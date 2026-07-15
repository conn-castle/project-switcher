import AppKit
import ProjectSwitcherCore
import os

extension AXWindowPositioner {
    // MARK: - AX Window Resolution

    /// Finds the target window for recovery, preferring the app's focused window.
    ///
    /// Strategy: First checks the app's focused window (set by AeroSpace focus before this call).
    /// If its title matches, uses it directly (avoids duplicate-title ambiguity). Falls back to
    /// title enumeration if the focused window doesn't match or isn't available.
    /// Returns `.success(nil)` if no matching window is found (not an error).
    func findFocusedOrTitledWindow(bundleId: String, title: String) -> Result<AXUIElement?, PsCoreError> {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else {
            return .success(nil) // App not running — not an error for recovery
        }

        let sortedPids = apps.map { $0.processIdentifier }.sorted()
        var lastEnumerationError: AXError?
        var anyEnumerationSucceeded = false

        // Phase 1: Check the app's focused window (most likely the one AeroSpace just focused)
        for pid in sortedPids {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var focusedValue: AnyObject?
            let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
            if focusResult == .success, let focusedRef = focusedValue, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
                let focusedWindow = focusedRef as! AXUIElement
                AXUIElementSetMessagingTimeout(focusedWindow, Self.axTimeoutSeconds)
                if let focusedTitle = readTitle(element: focusedWindow, bundleId: bundleId), focusedTitle == title {
                    return .success(focusedWindow)
                }
            }
        }

        // Phase 2: Fall back to title enumeration (focused window didn't match)
        for pid in sortedPids {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var windowsValue: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)

            guard result == .success, let windows = windowsValue as? [AXUIElement] else {
                lastEnumerationError = result
                continue
            }

            anyEnumerationSucceeded = true
            for window in windows {
                AXUIElementSetMessagingTimeout(window, Self.axTimeoutSeconds)
                if let windowTitle = readTitle(element: window, bundleId: bundleId), windowTitle == title {
                    return .success(window)
                }
            }
        }

        if !anyEnumerationSucceeded, let axError = lastEnumerationError {
            return .failure(Self.windowEnumerationError(bundleId: bundleId, axError: axError))
        }

        return .success(nil) // No matching window
    }

    /// Finds all AX windows matching the title token, sorted by title for stable ordering.
    ///
    /// If window enumeration fails for all PIDs (e.g., AX permission denied), returns `.failure`
    /// with the last AX error instead of an empty success.
    func findMatchingWindows(bundleId: String, token: String) -> Result<[AXUIElement], PsCoreError> {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else {
            return .failure(PsCoreError(
                category: .window,
                message: "No running application with bundle ID '\(bundleId)'"
            ))
        }

        // Sort PIDs ascending for deterministic order
        let sortedPids = apps.map { $0.processIdentifier }.sorted()

        var allMatches: [(title: String, element: AXUIElement, enumIndex: Int)] = []
        var lastEnumerationError: AXError?
        var anyEnumerationSucceeded = false
        var nextEnumIndex = 0

        for pid in sortedPids {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var windowsValue: AnyObject?
            let t0 = CFAbsoluteTimeGetCurrent()
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.enumerate_windows bundleId=\(bundleId) pid=\(pid) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
            if ms > 100 { Self.logger.warning("ax.enumerate_windows SLOW bundleId=\(bundleId) pid=\(pid) elapsed=\(String(format: "%.1f", ms))ms") }

            guard result == .success, let windows = windowsValue as? [AXUIElement] else {
                lastEnumerationError = result
                continue
            }

            anyEnumerationSucceeded = true
            for window in windows {
                AXUIElementSetMessagingTimeout(window, Self.axTimeoutSeconds)
                if let title = readTitle(element: window, bundleId: bundleId),
                   Self.matchesLeadingToken(title: title, token: token) {
                    allMatches.append((title: title, element: window, enumIndex: nextEnumIndex))
                }
                nextEnumIndex += 1
            }
        }

        // If no PID succeeded enumeration, surface the AX error rather than returning empty success
        if !anyEnumerationSucceeded, let axError = lastEnumerationError {
            return .failure(Self.windowEnumerationError(bundleId: bundleId, axError: axError))
        }

        // Sort by title for stable ordering; secondary sort by enumeration index.
        // NOTE: Apple does not formally document the ordering of kAXWindowsAttribute.
        // Empirically it follows a consistent order (stacking/creation) within an app session,
        // making enumeration index more stable than the previous CFHash approach (which operated
        // on freshly created opaque references with no stability guarantee). If users report
        // continued window-position flipping with duplicate titles, escalate to CGWindowID-based
        // identity (see ISSUES.md ax-tiebreak-residual).
        allMatches.sort {
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.enumIndex < $1.enumIndex
        }

        return .success(allMatches.map { $0.element })
    }

    /// Matches a leading token at an identifier boundary (`PS:foo` must not match `PS:foo-copy`).
    static func matchesLeadingToken(title: String, token: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(token) else { return false }
        let suffix = trimmed.dropFirst(token.count)
        return suffix.isEmpty || suffix.first?.isWhitespace == true
    }

    // MARK: - Fallback Window Resolution

    /// Finds an unambiguous window for the given app, ignoring token matching.
    ///
    /// Selection strategy:
    /// 1. If exactly one window exists across all app instances, use it.
    /// 2. If multiple windows exist, prefer the app's AX focused window.
    /// 3. If ambiguous (multiple windows, none focused), return `.failure` with inventory.
    ///
    /// Returns the resolved AXUIElement and the total window count for diagnostics.
    func findFocusedOrOnlyWindow(bundleId: String) -> Result<(element: AXUIElement, windowCount: Int, titles: [String]), PsCoreError> {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else {
            return .failure(PsCoreError(
                category: .window,
                message: "No running application with bundle ID '\(bundleId)'"
            ))
        }

        let sortedPids = apps.map { $0.processIdentifier }.sorted()
        var allWindows: [(title: String, element: AXUIElement)] = []
        var lastEnumerationError: AXError?
        var failedPids: [pid_t] = []

        for pid in sortedPids {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var windowsValue: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
            guard result == .success, let windows = windowsValue as? [AXUIElement] else {
                lastEnumerationError = result
                failedPids.append(pid)
                continue
            }

            for window in windows {
                AXUIElementSetMessagingTimeout(window, Self.axTimeoutSeconds)
                let title = readTitle(element: window, bundleId: bundleId) ?? "<untitled>"
                allWindows.append((title: title, element: window))
            }
        }

        if !failedPids.isEmpty {
            let pidList = failedPids.map(String.init).joined(separator: ", ")
            let axDetail = lastEnumerationError.map { "AX error: \($0.rawValue)" } ?? "unknown"
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to enumerate complete window inventory for \(bundleId); fallback requires complete inventory (failed PIDs: [\(pidList)])",
                detail: "\(axDetail) (may indicate missing Accessibility permission)"
            ))
        }

        let titles = allWindows.map { $0.title }

        guard !allWindows.isEmpty else {
            return .failure(Self.windowInventoryEmptyError(bundleId: bundleId))
        }

        // Unambiguous: exactly one window
        if allWindows.count == 1 {
            return .success((element: allWindows[0].element, windowCount: 1, titles: titles))
        }

        // Multiple windows: prefer the app's AX focused window
        for pid in sortedPids {
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var focusedValue: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
            if result == .success,
               let ref = focusedValue,
               CFGetTypeID(ref) == AXUIElementGetTypeID() {
                let element = ref as! AXUIElement
                AXUIElementSetMessagingTimeout(element, Self.axTimeoutSeconds)
                return .success((element: element, windowCount: allWindows.count, titles: titles))
            }
        }

        // Ambiguous: multiple windows, none focused
        let titleList = titles.joined(separator: ", ")
        return .failure(PsCoreError(
            category: .window,
            message: "Ambiguous: \(allWindows.count) windows found for \(bundleId), none focused. Titles: [\(titleList)]"
        ))
    }

    // MARK: - AX Attribute Read/Write

    private func readTitle(element: AXUIElement, bundleId: String) -> String? {
        var titleValue: AnyObject?
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.read_title bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.read_title SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else { return nil }
        return titleValue as? String
    }
}
