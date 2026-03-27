import Foundation

/// Screen mode determined by the physical width of the display.
///
/// - `small`: Screen narrower than the configured threshold (default < 24").
///   Both IDE and Chrome are maximized to fill the screen (stacked).
/// - `wide`: Screen at or above the threshold.
///   IDE and Chrome are positioned side-by-side with configurable dimensions.
public enum ScreenMode: String, Codable, Equatable, Sendable, CaseIterable {
    case small
    case wide
}
