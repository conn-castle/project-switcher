import Foundation

/// Parsed `[layout]` configuration section for window positioning.
///
/// All fields have documented defaults applied when omitted from config.
/// Invalid values produce FAIL findings and cause config load to fail (no per-field fallback).
public struct LayoutConfig: Equatable, Sendable {
    /// Physical screen width in inches below which small screen mode is used.
    /// Screens >= this threshold use wide mode. Must be > 0.
    public let smallScreenThreshold: Double

    /// Window height as percentage of screen height in wide mode (1–100).
    public let windowHeight: Int

    /// Maximum window width in inches in wide mode. Must be > 0.
    public let maxWindowWidth: Double

    /// IDE window position in wide mode: "left" or "right".
    public let idePosition: IdePosition

    /// Window pair anchored to screen edge: "left" or "right".
    public let justification: Justification

    /// Maximum gap between windows as percentage of screen width (0–100).
    public let maxGap: Int

    /// IDE position options.
    public enum IdePosition: String, Equatable, Sendable, CaseIterable {
        case left
        case right
    }

    /// Window pair justification options.
    public enum Justification: String, Equatable, Sendable, CaseIterable {
        case left
        case right
    }

    public init(
        smallScreenThreshold: Double = Defaults.smallScreenThreshold,
        windowHeight: Int = Defaults.windowHeight,
        maxWindowWidth: Double = Defaults.maxWindowWidth,
        idePosition: IdePosition = Defaults.idePosition,
        justification: Justification = Defaults.justification,
        maxGap: Int = Defaults.maxGap
    ) {
        self.smallScreenThreshold = smallScreenThreshold
        self.windowHeight = windowHeight
        self.maxWindowWidth = maxWindowWidth
        self.idePosition = idePosition
        self.justification = justification
        self.maxGap = maxGap
    }

    /// Default values for layout configuration.
    public enum Defaults {
        public static let smallScreenThreshold: Double = 24
        public static let windowHeight: Int = 90
        public static let maxWindowWidth: Double = 18
        public static let idePosition: IdePosition = .left
        public static let justification: Justification = .right
        public static let maxGap: Int = 10
    }
}
