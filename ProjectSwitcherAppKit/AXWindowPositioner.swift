import AppKit
import ProjectSwitcherCore
import os

/// AX API-based window positioning implementation.
///
/// Resolves windows by bundle ID + title token (`PS:<projectId>`), reads/writes
/// window frames via Accessibility APIs, and handles NSScreen-to-AX coordinate conversion.
///
/// All public API frames use NSScreen coordinate space (origin bottom-left, Y up).
/// AX coordinate conversion is handled internally.
public struct AXWindowPositioner: WindowPositioning {
    static let logger = Logger(subsystem: "com.projectswitcher", category: "AXWindowPositioner")

    /// Safety ceiling per AX element. Normal calls complete in 1–5ms.
    static let axTimeoutSeconds: Float = 0.5

    public init() {}

    // MARK: - Error Factories

    /// Creates a structured error for a token-miss during window lookup.
    static func windowTokenNotFoundError(bundleId: String, token: String) -> PsCoreError {
        PsCoreError(
            category: .window,
            message: "No window found with token '\(token)' for \(bundleId)",
            reason: .windowTokenNotFound
        )
    }

    /// Creates a structured error for a confirmed zero-window inventory result.
    static func windowInventoryEmptyError(bundleId: String) -> PsCoreError {
        PsCoreError(
            category: .window,
            message: "No windows found for \(bundleId) (0 windows enumerated)",
            reason: .windowInventoryEmpty
        )
    }

    /// Creates an enumeration error, preserving whether Accessibility reported a
    /// transient `cannotComplete` response so callers can retry it safely.
    static func windowEnumerationError(bundleId: String, axError: AXError) -> PsCoreError {
        PsCoreError(
            category: .window,
            message: "Failed to enumerate windows for \(bundleId)",
            detail: "AX error: \(axError.rawValue) (may indicate missing Accessibility permission)",
            reason: axError == .cannotComplete ? .windowEnumerationIncomplete : nil
        )
    }

    // MARK: - WindowPositioning Protocol

    public func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.get_frame_total bundleId=\(bundleId) projectId=\(projectId) elapsed=\(String(format: "%.1f", ms))ms")
            if ms > 100 { Self.logger.warning("ax.get_frame_total SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }
        }

        let token = "PS:\(projectId)"

        let matches: [AXUIElement]
        switch findMatchingWindows(bundleId: bundleId, token: token) {
        case .success(let windows):
            matches = windows
        case .failure(let error):
            return .failure(error)
        }

        guard let primary = matches.first else {
            return .failure(Self.windowTokenNotFoundError(bundleId: bundleId, token: token))
        }

        return readFrameNSScreen(element: primary, bundleId: bundleId)
    }

    public func setWindowFrames(
        bundleId: String,
        projectId: String,
        primaryFrame: CGRect,
        cascadeOffsetPoints: CGFloat
    ) -> Result<WindowPositionResult, PsCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.set_frames_total bundleId=\(bundleId) projectId=\(projectId) elapsed=\(String(format: "%.1f", ms))ms")
            if ms > 100 { Self.logger.warning("ax.set_frames_total SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }
        }

        let token = "PS:\(projectId)"

        let matches: [AXUIElement]
        switch findMatchingWindows(bundleId: bundleId, token: token) {
        case .success(let windows):
            matches = windows
        case .failure(let error):
            return .failure(error)
        }

        guard !matches.isEmpty else {
            return .failure(Self.windowTokenNotFoundError(bundleId: bundleId, token: token))
        }

        // Screen-selection heuristic: find which screen contains the target midpoint
        // so cascading windows are clamped to the correct display. This intentionally
        // uses a simple midpoint containment test (not the area-based threshold used
        // by recovery) because we need a single best-match screen, not a go/no-go decision.
        let screenFrame = NSScreen.screens.first {
            $0.visibleFrame.contains(CGPoint(x: primaryFrame.midX, y: primaryFrame.midY))
        }?.visibleFrame

        var positioned = 0
        var lastError: PsCoreError?
        var failures: [String] = []
        for (index, element) in matches.enumerated() {
            let offset = CGFloat(index) * cascadeOffsetPoints
            var frame = CGRect(
                x: primaryFrame.origin.x + offset,
                y: primaryFrame.origin.y - offset, // Down in NSScreen = lower Y
                width: primaryFrame.width,
                height: primaryFrame.height
            )

            // Clamp cascade frames to screen bounds to prevent off-screen windows
            if let screenFrame {
                frame = clampFrameToScreen(frame: frame, screenVisibleFrame: screenFrame)
            }

            switch writeFrameNSScreen(element: element, frame: frame, bundleId: bundleId) {
            case .success:
                positioned += 1
            case .failure(let error):
                lastError = error
                failures.append("window[\(index)]: \(error.message)")
                Self.logger.warning("Failed to set frame for match \(index) of \(bundleId): \(error.message)")
            }
        }

        if positioned == 0, let error = lastError {
            return .failure(error)
        }

        return .success(WindowPositionResult(positioned: positioned, matched: matches.count, failures: failures))
    }

    public func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, PsCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.get_fallback_frame bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms")
        }

        switch findFocusedOrOnlyWindow(bundleId: bundleId) {
        case .success(let match):
            Self.logger.info("ax.fallback_resolved bundleId=\(bundleId) windowCount=\(match.windowCount)")
            return readFrameNSScreen(element: match.element, bundleId: bundleId)
        case .failure(let error):
            return .failure(error)
        }
    }

    public func setFallbackWindowFrames(
        bundleId: String,
        primaryFrame: CGRect,
        cascadeOffsetPoints: CGFloat
    ) -> Result<WindowPositionResult, PsCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.set_fallback_frames bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms")
        }

        let element: AXUIElement
        switch findFocusedOrOnlyWindow(bundleId: bundleId) {
        case .success(let match):
            element = match.element
            Self.logger.info("ax.fallback_set_resolved bundleId=\(bundleId) windowCount=\(match.windowCount)")
        case .failure(let error):
            return .failure(error)
        }

        switch writeFrameNSScreen(element: element, frame: primaryFrame, bundleId: bundleId) {
        case .success:
            return .success(WindowPositionResult(positioned: 1, matched: 1))
        case .failure(let error):
            return .failure(error)
        }
    }

    public func isAccessibilityTrusted() -> Bool {
        let t0 = CFAbsoluteTimeGetCurrent()
        let trusted = AXIsProcessTrusted()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.is_trusted elapsed=\(String(format: "%.1f", ms))ms result=\(trusted)")
        return trusted
    }

    public func promptForAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Self.logger.debug("ax.prompt_accessibility result=\(trusted)")
        return trusted
    }

    public func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.recover_window bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms")
        }

        // Prefer the app's focused window (set by AeroSpace focus before this call),
        // falling back to title enumeration if the focused window title doesn't match.
        let element: AXUIElement
        switch findFocusedOrTitledWindow(bundleId: bundleId, title: windowTitle) {
        case .success(let match):
            guard let match else {
                return .success(.notFound)
            }
            element = match
        case .failure(let error):
            return .failure(error)
        }

        return recoverElement(element, bundleId: bundleId, screenVisibleFrame: screenVisibleFrame)
    }

    public func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            Self.logger.debug("ax.recover_focused_window bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms")
        }

        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else {
            return .success(.notFound)
        }

        // Get the app's AX focused window (set by AeroSpace before this call).
        for app in apps.sorted(by: { $0.processIdentifier < $1.processIdentifier }) {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, Self.axTimeoutSeconds)

            var focusedValue: AnyObject?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedValue)
            if result == .success,
               let ref = focusedValue,
               CFGetTypeID(ref) == AXUIElementGetTypeID() {
                let element = ref as! AXUIElement
                AXUIElementSetMessagingTimeout(element, Self.axTimeoutSeconds)
                return recoverElement(element, bundleId: bundleId, screenVisibleFrame: screenVisibleFrame)
            }
        }

        return .success(.notFound)
    }

    // MARK: - Private Recovery

    /// Recovers a single AX element: reads its frame, shrinks if oversized, and centers
    /// on screen if off-screen. Returns `.unchanged` if the window already fits.
    private func recoverElement(
        _ element: AXUIElement,
        bundleId: String,
        screenVisibleFrame: CGRect
    ) -> Result<RecoveryOutcome, PsCoreError> {
        let currentFrame: CGRect
        switch readFrameNSScreen(element: element, bundleId: bundleId) {
        case .success(let frame):
            currentFrame = frame
        case .failure(let error):
            return .failure(error)
        }

        let recoveryScreenVisibleFrame = Self.selectRecoveryScreenVisibleFrame(
            currentFrame: currentFrame,
            fallbackScreenVisibleFrame: screenVisibleFrame,
            availableScreenFrames: NSScreen.screens.map(\.visibleFrame)
        )

        guard let recoveredFrame = Self.computeRecoveredFrame(
            currentFrame: currentFrame,
            screenVisibleFrame: recoveryScreenVisibleFrame
        ) else {
            return .success(.unchanged)
        }

        switch writeFrameNSScreen(element: element, frame: recoveredFrame, bundleId: bundleId) {
        case .success:
            return .success(.recovered)
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Fraction of window area that must be off-screen to trigger recovery.
    /// A 10% threshold catches partially-visible windows where the midpoint is
    /// still on-screen but significant content is clipped.
    static let offscreenRecoveryThreshold: CGFloat = 0.10

    /// Returns the fraction of a window's area that lies outside the given screen frame.
    ///
    /// - Returns: A value in `[0, 1]`, or `nil` if the window has zero area
    ///   (either dimension is zero).
    static func offscreenCoverage(windowFrame: CGRect, screenFrame: CGRect) -> CGFloat? {
        let standardized = windowFrame.standardized
        let windowArea = standardized.width * standardized.height
        guard windowArea > 0 else { return nil }
        let onScreenArea = intersectionArea(screenFrame, standardized)
        return (windowArea - onScreenArea) / windowArea
    }

    /// Returns a recovered frame (shrunk to fit, centered) if the window is off-screen
    /// or oversized. Returns `nil` if the window already fits.
    static func computeRecoveredFrame(
        currentFrame: CGRect,
        screenVisibleFrame: CGRect
    ) -> CGRect? {
        let needsShrinkWidth = currentFrame.width > screenVisibleFrame.width
        let needsShrinkHeight = currentFrame.height > screenVisibleFrame.height

        let isOffScreen: Bool
        if let coverage = offscreenCoverage(windowFrame: currentFrame, screenFrame: screenVisibleFrame) {
            isOffScreen = coverage > offscreenRecoveryThreshold
        } else {
            // Zero-area window — not recoverable.
            isOffScreen = false
        }

        guard needsShrinkWidth || needsShrinkHeight || isOffScreen else {
            return nil
        }

        let width = needsShrinkWidth ? screenVisibleFrame.width : currentFrame.width
        let height = needsShrinkHeight ? screenVisibleFrame.height : currentFrame.height

        return CGRect(
            x: screenVisibleFrame.minX + (screenVisibleFrame.width - width) / 2,
            y: screenVisibleFrame.minY + (screenVisibleFrame.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// Picks the most appropriate screen frame for recovery in multi-display setups.
    ///
    /// Selection order:
    /// 1) screen containing the window midpoint,
    /// 2) screen with largest intersection area,
    /// 3) nearest screen center by midpoint distance,
    /// 4) fallback screen if no screens are available.
    static func selectRecoveryScreenVisibleFrame(
        currentFrame: CGRect,
        fallbackScreenVisibleFrame: CGRect,
        availableScreenFrames: [CGRect]
    ) -> CGRect {
        guard !availableScreenFrames.isEmpty else {
            return fallbackScreenVisibleFrame
        }

        let midpoint = CGPoint(x: currentFrame.midX, y: currentFrame.midY)

        if let containing = availableScreenFrames.first(where: { $0.contains(midpoint) }) {
            return containing
        }

        if let bestIntersection = availableScreenFrames
            .map({ (frame: $0, area: intersectionArea($0, currentFrame)) })
            .max(by: { $0.area < $1.area }),
           bestIntersection.area > 0 {
            return bestIntersection.frame
        }

        if let nearest = availableScreenFrames.min(by: {
            squaredDistance(from: midpoint, to: CGPoint(x: $0.midX, y: $0.midY)) <
                squaredDistance(from: midpoint, to: CGPoint(x: $1.midX, y: $1.midY))
        }) {
            return nearest
        }

        return fallbackScreenVisibleFrame
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return max(intersection.width, 0) * max(intersection.height, 0)
    }

    private static func squaredDistance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = from.x - to.x
        let dy = from.y - to.y
        return dx * dx + dy * dy
    }

}
