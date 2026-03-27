import Foundation

/// Computed target window positions for IDE and Chrome.
public struct WindowLayout: Equatable, Sendable {
    public let ideFrame: CGRect
    public let chromeFrame: CGRect

    public init(ideFrame: CGRect, chromeFrame: CGRect) {
        self.ideFrame = ideFrame
        self.chromeFrame = chromeFrame
    }
}

/// Pure geometry engine for computing window positions.
///
/// All coordinates use NSScreen coordinate space: origin at bottom-left of primary display,
/// Y increases upward. No side effects, no AppKit dependency.
public struct WindowLayoutEngine {

    private init() {}

    /// Computes target window frames for the given screen and configuration.
    ///
    /// - Parameters:
    ///   - screenVisibleFrame: The monitor's visible frame (minus dock/menu bar) in NSScreen coordinates.
    ///   - screenPhysicalWidthInches: Physical width of the monitor in inches (for maxWindowWidth conversion).
    ///   - screenMode: Detected screen mode (small or wide).
    ///   - config: Layout configuration with positioning parameters.
    /// - Returns: Target frames for IDE and Chrome windows.
    public static func computeLayout(
        screenVisibleFrame: CGRect,
        screenPhysicalWidthInches: Double,
        screenMode: ScreenMode,
        config: LayoutConfig
    ) -> WindowLayout {
        switch screenMode {
        case .small:
            return computeSmallLayout(screenVisibleFrame: screenVisibleFrame)
        case .wide:
            return computeWideLayout(
                screenVisibleFrame: screenVisibleFrame,
                screenPhysicalWidthInches: screenPhysicalWidthInches,
                config: config
            )
        }
    }

    /// Clamps a saved window frame to fit within the current screen bounds.
    ///
    /// If the frame exceeds the screen dimensions, it is shrunk to fit and centered.
    /// If it extends past any edge, it is shifted to stay within bounds.
    ///
    /// - Parameters:
    ///   - frame: The saved window frame to validate.
    ///   - screenVisibleFrame: The current screen's visible bounds.
    /// - Returns: A frame that fits within the screen.
    public static func clampToScreen(frame: CGRect, screenVisibleFrame: CGRect) -> CGRect {
        var width = frame.width
        var height = frame.height

        // Shrink to fit if oversized
        if width > screenVisibleFrame.width {
            width = screenVisibleFrame.width
        }
        if height > screenVisibleFrame.height {
            height = screenVisibleFrame.height
        }

        // If we had to shrink, center on screen
        let wasResized = width != frame.width || height != frame.height
        var x: CGFloat
        var y: CGFloat

        if wasResized {
            x = screenVisibleFrame.midX - width / 2
            y = screenVisibleFrame.midY - height / 2
        } else {
            x = frame.origin.x
            y = frame.origin.y
        }

        // Clamp edges to screen bounds
        if x < screenVisibleFrame.minX {
            x = screenVisibleFrame.minX
        }
        if x + width > screenVisibleFrame.maxX {
            x = screenVisibleFrame.maxX - width
        }
        if y < screenVisibleFrame.minY {
            y = screenVisibleFrame.minY
        }
        if y + height > screenVisibleFrame.maxY {
            y = screenVisibleFrame.maxY - height
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Small Screen Mode

    private static func computeSmallLayout(screenVisibleFrame: CGRect) -> WindowLayout {
        WindowLayout(
            ideFrame: screenVisibleFrame,
            chromeFrame: screenVisibleFrame
        )
    }

    // MARK: - Wide Screen Mode

    private static func computeWideLayout(
        screenVisibleFrame: CGRect,
        screenPhysicalWidthInches: Double,
        config: LayoutConfig
    ) -> WindowLayout {
        let screenWidth = screenVisibleFrame.width
        let screenHeight = screenVisibleFrame.height

        // Window height (percentage of screen height, top-aligned)
        let windowHeight = screenHeight * CGFloat(config.windowHeight) / 100.0
        // Top-aligned in NSScreen Y-up coordinates
        let windowY = screenVisibleFrame.maxY - windowHeight

        // Points per inch for this screen
        let pointsPerInch = screenWidth / CGFloat(screenPhysicalWidthInches)

        // Max window width in points (capped at half the screen)
        let maxWindowWidthPoints = CGFloat(config.maxWindowWidth) * pointsPerInch
        var windowWidth = min(screenWidth * 0.5, maxWindowWidthPoints)

        // Gap calculation
        let maxGapPoints = screenWidth * CGFloat(config.maxGap) / 100.0
        let remainingAfterWindows = screenWidth - 2 * windowWidth
        var gap = min(maxGapPoints, max(0, remainingAfterWindows))

        // If gap < 0 (windows + gap exceed screen), shrink windows to fit with gap = 0
        if remainingAfterWindows < 0 {
            windowWidth = screenWidth / 2
            gap = 0
        }

        // Compute X positions
        let leftX: CGFloat
        let rightX: CGFloat

        switch config.justification {
        case .right:
            rightX = screenVisibleFrame.maxX - windowWidth
            leftX = rightX - gap - windowWidth
        case .left:
            leftX = screenVisibleFrame.minX
            rightX = leftX + windowWidth + gap
        }

        // Assign IDE and Chrome based on idePosition
        let ideX: CGFloat
        let chromeX: CGFloat

        switch config.idePosition {
        case .left:
            ideX = leftX
            chromeX = rightX
        case .right:
            ideX = rightX
            chromeX = leftX
        }

        let ideFrame = CGRect(x: ideX, y: windowY, width: windowWidth, height: windowHeight)
        let chromeFrame = CGRect(x: chromeX, y: windowY, width: windowWidth, height: windowHeight)

        return WindowLayout(ideFrame: ideFrame, chromeFrame: chromeFrame)
    }
}
