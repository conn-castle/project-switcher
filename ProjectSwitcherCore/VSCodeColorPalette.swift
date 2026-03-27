import Foundation

/// Resolves project colors to Peacock-compatible hex values for VS Code color differentiation.
///
/// The Peacock VS Code extension (`johnpapa.vscode-peacock`) reads a single `peacock.color`
/// key from `.vscode/settings.json` and applies it across the title bar, activity bar, and
/// status bar. This enum handles color resolution from named/hex strings to `#RRGGBB` format.
public enum VSCodeColorPalette {

    /// Resolves a project color string to a Peacock-compatible `#RRGGBB` hex value.
    ///
    /// - Parameter color: The project's color string (named or hex).
    /// - Returns: A `#RRGGBB` hex string, or `nil` if the color string cannot be resolved.
    public static func peacockColorHex(for color: String) -> String? {
        guard let rgb = ProjectColorPalette.resolve(color) else { return nil }
        return toHex(rgb)
    }

    // MARK: - Hex conversion

    /// Converts RGB components to a `#RRGGBB` hex string.
    public static func toHex(_ rgb: ProjectColorRGB) -> String {
        let r = Int(round(rgb.red * 255.0))
        let g = Int(round(rgb.green * 255.0))
        let b = Int(round(rgb.blue * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
