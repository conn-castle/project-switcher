import AppKit
import ProjectSwitcherCore
import os

extension AXWindowPositioner {
    func readFrameNSScreen(element: AXUIElement, bundleId: String) -> Result<CGRect, PsCoreError> {
        // Read AX position
        var posValue: AnyObject?
        let t0 = CFAbsoluteTimeGetCurrent()
        var result = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
        var ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.read_position bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.read_position SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to read window position for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        var axPosition = CGPoint.zero
        // posValue is AnyObject; verify it's an AXValue via CoreFoundation type ID
        guard let posObj = posValue, CFGetTypeID(posObj) == AXValueGetTypeID() else {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to read window position for \(bundleId)",
                detail: "AX returned unexpected type for position attribute"
            ))
        }
        let posAXValue = posObj as! AXValue
        if !AXValueGetValue(posAXValue, .cgPoint, &axPosition) {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to unpack window position for \(bundleId)"
            ))
        }

        // Read AX size
        var sizeValue: AnyObject?
        let t1 = CFAbsoluteTimeGetCurrent()
        result = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
        ms = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        Self.logger.debug("ax.read_size bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.read_size SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to read window size for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        var axSize = CGSize.zero
        guard let sizeObj = sizeValue, CFGetTypeID(sizeObj) == AXValueGetTypeID() else {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to read window size for \(bundleId)",
                detail: "AX returned unexpected type for size attribute"
            ))
        }
        let sizeAXValue = sizeObj as! AXValue
        if !AXValueGetValue(sizeAXValue, .cgSize, &axSize) {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to unpack window size for \(bundleId)"
            ))
        }

        // Convert AX → NSScreen
        let screenFrames = NSScreen.screens.map(\.frame)
        guard let nsFrame = Self.axFrameToNSScreen(
            axPosition: axPosition,
            axSize: axSize,
            screenFrames: screenFrames
        ) else {
            return .failure(PsCoreError(
                category: .system,
                message: "Cannot determine primary display",
                detail: "No NSScreen with origin (0,0) found"
            ))
        }

        // Diagnostic: warn if converted frame center is off all known screens
        let center = CGPoint(x: nsFrame.midX, y: nsFrame.midY)
        if !Self.isPointOnScreen(center, screenFrames: screenFrames) {
            Self.logger.warning("ax.read_frame_offscreen bundleId=\(bundleId) center=(\(String(format: "%.0f", center.x)), \(String(format: "%.0f", center.y)))")
        }

        return .success(nsFrame)
    }

    func writeFrameNSScreen(element: AXUIElement, frame: CGRect, bundleId: String) -> Result<Void, PsCoreError> {
        // Convert NSScreen → AX
        guard let ax = Self.nsScreenFrameToAX(
            frame: frame,
            screenFrames: NSScreen.screens.map(\.frame)
        ) else {
            return .failure(PsCoreError(
                category: .system,
                message: "Cannot determine primary display",
                detail: "No NSScreen with origin (0,0) found"
            ))
        }
        let axX = ax.position.x
        let axY = ax.position.y

        // Set AX position
        var axPosition = CGPoint(x: axX, y: axY)
        guard let positionValue = AXValueCreate(.cgPoint, &axPosition) else {
            return .failure(PsCoreError(category: .window, message: "Failed to create AX position value"))
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        var result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        var ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        Self.logger.debug("ax.set_position bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.set_position SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to set window position for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        // Set AX size
        var axSize = CGSize(width: frame.width, height: frame.height)
        guard let sizeValue = AXValueCreate(.cgSize, &axSize) else {
            return .failure(PsCoreError(category: .window, message: "Failed to create AX size value"))
        }

        let t1 = CFAbsoluteTimeGetCurrent()
        result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        ms = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        Self.logger.debug("ax.set_size bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms result=\(result.rawValue)")
        if ms > 100 { Self.logger.warning("ax.set_size SLOW bundleId=\(bundleId) elapsed=\(String(format: "%.1f", ms))ms") }

        guard result == .success else {
            return .failure(PsCoreError(
                category: .window,
                message: "Failed to set window size for \(bundleId)",
                detail: "AX error: \(result.rawValue)"
            ))
        }

        return .success(())
    }

    // MARK: - Coordinate Conversion

    /// Converts an AX-space position and size to an NSScreen-space frame.
    ///
    /// AX coordinate space: origin at top-left of primary display, Y increases downward.
    /// NSScreen coordinate space: origin at bottom-left of primary display, Y increases upward.
    /// Both are global coordinate spaces anchored to the primary display, so conversion
    /// uses only the primary screen height as the Y-axis flip point. This formula is correct
    /// for ALL displays, not just the primary.
    ///
    /// - Parameters:
    ///   - axPosition: Window top-left in AX coordinates.
    ///   - axSize: Window size.
    ///   - screenFrames: Available screen frames in NSScreen coordinates.
    /// - Returns: The window frame in NSScreen coordinates, or `nil` if the primary
    ///   screen (origin 0,0) cannot be found.
    static func axFrameToNSScreen(
        axPosition: CGPoint,
        axSize: CGSize,
        screenFrames: [CGRect]
    ) -> CGRect? {
        guard let primaryHeight = screenFrames.first(where: { $0.origin == .zero })?.height else {
            return nil
        }
        return CGRect(
            x: axPosition.x,
            y: primaryHeight - axPosition.y - axSize.height,
            width: axSize.width,
            height: axSize.height
        )
    }

    /// Converts an NSScreen-space frame to AX-space position and size.
    ///
    /// Inverse of ``axFrameToNSScreen(axPosition:axSize:screenFrames:)``.
    ///
    /// - Parameters:
    ///   - frame: Window frame in NSScreen coordinates (bottom-left origin).
    ///   - screenFrames: Available screen frames in NSScreen coordinates.
    /// - Returns: The AX position and size, or `nil` if the primary screen cannot be found.
    static func nsScreenFrameToAX(
        frame: CGRect,
        screenFrames: [CGRect]
    ) -> (position: CGPoint, size: CGSize)? {
        guard let primaryHeight = screenFrames.first(where: { $0.origin == .zero })?.height else {
            return nil
        }
        return (
            CGPoint(x: frame.origin.x, y: primaryHeight - frame.origin.y - frame.height),
            CGSize(width: frame.width, height: frame.height)
        )
    }

    /// Returns whether the given NSScreen-space point falls on any of the provided screen frames.
    static func isPointOnScreen(_ point: CGPoint, screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { $0.contains(point) }
    }

    // MARK: - Frame Clamping

    /// Clamps a frame to fit within the screen visible area.
    /// Shrinks if oversized, then shifts to ensure the frame stays on screen.
    func clampFrameToScreen(frame: CGRect, screenVisibleFrame: CGRect) -> CGRect {
        var width = min(frame.width, screenVisibleFrame.width)
        var height = min(frame.height, screenVisibleFrame.height)
        // Don't grow
        width = min(width, frame.width)
        height = min(height, frame.height)

        var x = frame.origin.x
        var y = frame.origin.y

        // Shift into bounds
        if x < screenVisibleFrame.minX { x = screenVisibleFrame.minX }
        if y < screenVisibleFrame.minY { y = screenVisibleFrame.minY }
        if x + width > screenVisibleFrame.maxX { x = screenVisibleFrame.maxX - width }
        if y + height > screenVisibleFrame.maxY { y = screenVisibleFrame.maxY - height }

        return CGRect(x: x, y: y, width: width, height: height)
    }
}
