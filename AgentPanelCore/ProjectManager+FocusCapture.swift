import Foundation

extension ProjectManager {
    // MARK: - Focus Capture/Restore (for Switcher UX)

    /// Captures the currently focused window for later restoration.
    ///
    /// Retries once after a short delay on transient failures (e.g., race during
    /// workspace transitions), but not when the circuit breaker is open.
    public func captureCurrentFocus() -> CapturedFocus? {
        let result = aerospace.focusedWindow()
        switch result {
        case .success(let window):
            return finishCapture(window)
        case .failure(let error):
            guard !error.isBreakerOpen else {
                logEvent("focus.capture.failed", level: .info, message: error.message)
                return nil
            }
            // Only retry off the main thread — Thread.sleep would block UI.
            guard !Thread.isMainThread else {
                logEvent("focus.capture.failed", level: .warn, message: error.message,
                         context: ["retry_skipped": "main_thread"])
                return nil
            }
            // Single retry after a short delay for transient failures.
            Thread.sleep(forTimeInterval: 0.15)
            switch aerospace.focusedWindow() {
            case .success(let window):
                logEvent("focus.capture.retried", context: ["window_id": "\(window.windowId)"])
                return finishCapture(window)
            case .failure(let retryError):
                logEvent("focus.capture.failed", level: retryError.isBreakerOpen ? .info : .warn, message: retryError.message)
                return nil
            }
        }
    }

    private func finishCapture(_ window: ApWindow) -> CapturedFocus {
        let captured = CapturedFocus(windowId: window.windowId, appBundleId: window.appBundleId, workspace: window.workspace)
        updateMostRecentNonProjectFocus(captured)
        logEvent("focus.captured", context: [
            "window_id": "\(captured.windowId)",
            "app_bundle_id": captured.appBundleId,
            "workspace": captured.workspace
        ])
        return captured
    }

    /// Restores focus to a previously captured window.
    @discardableResult
    public func restoreFocus(_ focus: CapturedFocus) -> Bool {
        focusWindow(windowId: focus.windowId)
    }

    /// Focuses a workspace by name.
    ///
    /// Uses `summon-workspace` (preferred, pulls workspace to current monitor) with
    /// fallback to `workspace` (switches to workspace wherever it is).
    ///
    /// - Parameter name: Workspace name to focus.
    /// - Returns: True if the workspace was focused successfully.
    @discardableResult
    public func focusWorkspace(name: String) -> Bool {
        switch aerospace.focusWorkspace(name: name) {
        case .failure(let error):
            logEvent("focus.workspace.failed", level: error.isBreakerOpen ? .info : .warn, message: error.message, context: ["workspace": name])
            return false
        case .success:
            logEvent("focus.workspace.succeeded", context: ["workspace": name])
            return true
        }
    }

    /// Focuses a window by its AeroSpace window ID.
    @discardableResult
    public func focusWindow(windowId: Int) -> Bool {
        switch aerospace.focusWindow(windowId: windowId) {
        case .failure(let error):
            logEvent("focus.restore.failed", level: error.isBreakerOpen ? .info : .warn, message: error.message, context: ["window_id": "\(windowId)"])
            return false
        case .success:
            logEvent("focus.restored", context: ["window_id": "\(windowId)"])
            return true
        }
    }

    /// Focuses a window and polls until focus is stable.
    ///
    /// Re-asserts focus if macOS steals it during the polling window.
    ///
    /// - Parameters:
    ///   - windowId: AeroSpace window ID to focus.
    ///   - timeout: Maximum time to wait for stable focus.
    ///   - pollInterval: Interval between focus checks.
    /// - Returns: True if focus is stable within the timeout.
    @discardableResult
    public func focusWindowStable(
        windowId: Int,
        timeout: TimeInterval = 10.0,
        pollInterval: TimeInterval = 0.1
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            if isFocusedWindow(windowId: windowId) {
                return true
            }

            // Re-assert focus (macOS can steal it briefly during Space/app switches)
            _ = aerospace.focusWindow(windowId: windowId)

            // Re-check immediately so short timeouts don't miss a successful re-assert.
            if isFocusedWindow(windowId: windowId) {
                return true
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }

            let sleepInterval = min(pollInterval, remaining)
            if sleepInterval <= 0 {
                await Task.yield()
                continue
            }

            try? await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
        }
    }

    /// Synchronous variant of `focusWindowStable` for non-async callers.
    ///
    /// Must be called off the main thread (blocks while polling).
    @discardableResult
    func focusWindowStableSync(
        windowId: Int,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) -> Bool {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            if isFocusedWindow(windowId: windowId) {
                return true
            }

            _ = aerospace.focusWindow(windowId: windowId)

            // Re-check immediately so short timeouts don't miss a successful re-assert.
            if isFocusedWindow(windowId: windowId) {
                return true
            }

            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }

            Thread.sleep(forTimeInterval: min(pollInterval, remaining))
        }
    }

    private func isFocusedWindow(windowId: Int) -> Bool {
        switch aerospace.focusedWindow() {
        case .success(let focused):
            return focused.windowId == windowId
        case .failure:
            return false
        }
    }

    /// Recovers the focused window if it is off-screen or oversized.
    ///
    /// Non-fatal: logs the outcome but never fails the calling focus operation.
    /// Requires both `windowPositioner` and `mainScreenVisibleFrame` to be set.
    func recoverFocusedWindowIfNeeded(bundleId: String) {
        guard let windowPositioner,
              let screenFrame = mainScreenVisibleFrame?() else { return }
        switch windowPositioner.recoverFocusedWindow(bundleId: bundleId, screenVisibleFrame: screenFrame) {
        case .success(.recovered):
            logEvent("focus.recovery.recovered", context: ["bundle_id": bundleId])
        case .success(.unchanged), .success(.notFound):
            break
        case .failure(let error):
            logEvent("focus.recovery.failed", level: .warn, message: error.message, context: ["bundle_id": bundleId])
        }
    }

    func updateMostRecentNonProjectFocus(_ focus: CapturedFocus) {
        guard !focus.workspace.hasPrefix(Self.workspacePrefix) else { return }
        let entry = FocusHistoryEntry(focus: focus, capturedAt: Date())
        withState {
            mostRecentNonProjectFocus = entry
            focusRestoreRetryAttemptsByWindowId[focus.windowId] = 0
        }
        persistFocusHistory()
    }

    func pushNonProjectFocusForExit(_ focus: CapturedFocus) {
        guard !focus.workspace.hasPrefix(Self.workspacePrefix) else { return }
        let entry = FocusHistoryEntry(focus: focus, capturedAt: Date())
        let snapshot = withState {
            focusStack.push(entry)
            mostRecentNonProjectFocus = entry
            focusRestoreRetryAttemptsByWindowId[focus.windowId] = 0
            return FocusHistorySnapshot(
                stackCount: focusStack.count,
                recentWindowId: mostRecentNonProjectFocus?.windowId
            )
        }
        persistFocusHistory()
        let context = focusHistoryContext(
            windowId: focus.windowId,
            workspace: focus.workspace,
            appBundleId: focus.appBundleId,
            snapshot: snapshot
        )
        logEvent("focus.history.push", context: context.isEmpty ? nil : context)
    }

    func invalidateFocusHistory(windowId: Int, reason: String) {
        let snapshot = withState {
            focusStack.remove(windowId: windowId)
            if mostRecentNonProjectFocus?.windowId == windowId {
                mostRecentNonProjectFocus = nil
            }
            focusRestoreRetryAttemptsByWindowId.removeValue(forKey: windowId)
            return FocusHistorySnapshot(
                stackCount: focusStack.count,
                recentWindowId: mostRecentNonProjectFocus?.windowId
            )
        }
        persistFocusHistory()
        let context = focusHistoryContext(
            windowId: windowId,
            reason: reason,
            snapshot: snapshot
        )
        logEvent("focus.history.invalidate", context: context.isEmpty ? nil : context)
    }

    func popNextFocusStackEntry() -> (FocusHistoryEntry, FocusHistorySnapshot)? {
        let result = withState {
            guard let entry = focusStack.pop() else { return nil as (FocusHistoryEntry, FocusHistorySnapshot)? }
            let snapshot = FocusHistorySnapshot(
                stackCount: focusStack.count,
                recentWindowId: mostRecentNonProjectFocus?.windowId
            )
            return (entry, snapshot)
        }
        if result != nil {
            persistFocusHistory()
        }
        return result
    }

    func listAllWindowsById() -> [Int: ApWindow]? {
        switch aerospace.listAllWindows() {
        case .failure(let error):
            logEvent("focus.window_lookup.failed", level: error.isBreakerOpen ? .info : .warn, message: error.message)
            return nil
        case .success(let windows):
            var lookup: [Int: ApWindow] = [:]
            lookup.reserveCapacity(windows.count)
            for window in windows {
                lookup[window.windowId] = window
            }
            return lookup
        }
    }

    func updateMostRecentNonProjectFocus(
        windowId: Int,
        destinationWorkspace: String,
        windowLookup: [Int: ApWindow]
    ) {
        guard let window = windowLookup[windowId],
              !destinationWorkspace.hasPrefix(Self.workspacePrefix) else { return }
        // `windowLookup` reflects pre-move workspace membership. After a successful move,
        // we intentionally trust `destinationWorkspace` as the authoritative workspace.
        let focus = CapturedFocus(
            windowId: window.windowId,
            appBundleId: window.appBundleId,
            workspace: destinationWorkspace
        )
        updateMostRecentNonProjectFocus(focus)
    }
}
