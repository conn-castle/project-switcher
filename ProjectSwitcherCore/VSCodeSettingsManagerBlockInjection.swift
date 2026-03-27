import Foundation

extension PsVSCodeSettingsManager {
    /// Start marker for the project-switcher settings block.
    static let startMarker = "// >>> project-switcher"
    /// End marker for the project-switcher settings block.
    static let endMarker = "// <<< project-switcher"
    /// Start marker for the legacy agent-panel settings block.
    private static let legacyStartMarker = "// >>> agent-panel"
    /// End marker for the legacy agent-panel settings block.
    private static let legacyEndMarker = "// <<< agent-panel"
    private static let markerPairs: [(start: String, end: String)] = [
        (start: startMarker, end: endMarker),
        (start: legacyStartMarker, end: legacyEndMarker)
    ]

    /// Injects or replaces the project-switcher block at the top of a JSONC settings file.
    ///
    /// The block is inserted right after the opening `{`. If an existing project-switcher
    /// block is found, it is replaced. When a color is configured, the block includes
    /// a `workbench.colorCustomizations` anchor so Peacock writes its colors in-place
    /// (inside the project-switcher block, safe from agent-layer's `al sync`). Existing
    /// Peacock-written color customizations are preserved across re-injections.
    /// Trailing commas are added only when content follows the block.
    ///
    /// - Parameters:
    ///   - content: Existing file content (JSONC).
    ///   - identifier: Project identifier for the `PS:<id>` window title.
    ///   - color: Optional project color string (named or hex) for VS Code color customizations.
    /// - Returns: Updated file content with the project-switcher block injected, or an error
    ///   if the content has no opening `{`.
    static func injectBlock(into content: String, identifier: String, color: String? = nil) -> Result<String, PsCoreError> {
        if let markerError = validateMarkers(in: content) {
            return .failure(markerError)
        }

        // Extract existing colorCustomizations before removing the block.
        let existingColorCustomizations = Self.extractColorCustomizations(from: content)

        // Remove existing block if present.
        let cleaned = removeExistingBlock(from: content)

        // Find the first `{`.
        guard let braceIndex = cleaned.firstIndex(of: "{") else {
            return .failure(PsCoreError(message: "Cannot inject settings block: content has no opening '{'."))
        }

        // Determine whether content follows the block (for trailing-comma decisions).
        let afterBrace = cleaned.index(after: braceIndex)
        let before = String(cleaned[cleaned.startIndex..<afterBrace])
        let after = String(cleaned[afterBrace...])
        let trimmedAfter = after.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContentAfter = trimmedAfter != "}"

        let windowTitle = "\(PsIdeToken.prefix)\(identifier) - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}"

        // Build property lines without trailing commas.
        var properties: [String] = [
            "  \"window.title\": \"\(windowTitle)\""
        ]

        // Add Peacock color and colorCustomizations anchor when a valid color is provided.
        // The colorCustomizations key acts as an in-place anchor so Peacock writes its
        // colors inside the project-switcher block (safe from agent-layer's al sync).
        if let color, let hex = VSCodeColorPalette.peacockColorHex(for: color) {
            properties.append("  \"peacock.color\": \"\(hex)\"")
            properties.append("  \"peacock.remoteColor\": \"\(hex)\"")
            let colorValue = existingColorCustomizations ?? "{}"
            properties.append("  \"workbench.colorCustomizations\": \(colorValue)")
        }

        // Add commas: all non-last properties always get one;
        // the last property gets one only if there is content after the block.
        for i in 0..<properties.count {
            let isLast = (i == properties.count - 1)
            if !isLast || hasContentAfter {
                properties[i] = appendCommaToLastLine(of: properties[i])
            }
        }

        var blockLines = [
            "  \(startMarker)",
            "  // Managed by ProjectSwitcher. Do not edit this block manually.",
        ]
        blockLines.append(contentsOf: properties)
        blockLines.append("  \(endMarker)")

        let block = blockLines.joined(separator: "\n")

        if !hasContentAfter {
            return .success("\(before)\n\(block)\n}")
        }

        return .success("\(before)\n\(block)\n\(after.drop(while: { $0 == "\n" || $0 == "\r" }))")
    }

    /// Finds the line indices of the project-switcher block markers within an array of lines.
    ///
    /// - Parameter lines: Lines of the settings file.
    /// - Returns: A tuple of `(startMarker, endMarker)` line indices, or `nil` if markers
    ///   are missing or in the wrong order.
    private static func findBlockMarkers(
        in lines: [String],
        startMarker: String,
        endMarker: String
    ) -> (startMarker: Int, endMarker: Int)? {
        guard let startIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == startMarker }),
              let endIndex = lines[lines.index(after: startIndex)...].firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == endMarker
              }),
              endIndex > startIndex else {
            return nil
        }
        return (startIndex, endIndex)
    }

    private static func findBlockMarkers(in lines: [String]) -> (startMarker: Int, endMarker: Int)? {
        for pair in markerPairs {
            if let markers = findBlockMarkers(in: lines, startMarker: pair.start, endMarker: pair.end) {
                return markers
            }
        }
        return nil
    }

    /// Removes an existing project-switcher block (markers + content between them) from the content.
    ///
    /// If the start marker exists but the end marker is missing (unbalanced markers),
    /// returns the content unchanged to prevent data loss.
    private static func removeExistingBlock(from content: String) -> String {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var removedAnyBlock = false

        while let markers = findBlockMarkers(in: lines) {
            let before = Array(lines[..<markers.startMarker])
            let after = Array(lines[lines.index(after: markers.endMarker)...])
            lines = before + after
            removedAnyBlock = true
        }

        guard removedAnyBlock else { return content }
        return lines.joined(separator: "\n")
    }

    /// Extracts the `workbench.colorCustomizations` JSON object value from an existing
    /// project-switcher block, preserving Peacock-written color customizations across re-injections.
    ///
    /// - Parameter content: Full JSONC settings file content.
    /// - Returns: The raw JSON object text (e.g., `{}` or multi-line `{ ... }`), or `nil`
    ///   if no `workbench.colorCustomizations` key exists within the block.
    static func extractColorCustomizations(from content: String) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let markers = findBlockMarkers(in: lines),
              markers.endMarker > markers.startMarker + 1 else {
            return nil
        }

        let blockLines = Array(lines[(markers.startMarker + 1)..<markers.endMarker])
        let blockText = blockLines.joined(separator: "\n")
        let key = "\"workbench.colorCustomizations\""
        guard let keyRange = blockText.range(of: key) else { return nil }

        // Find the colon after the key, then the opening brace of the JSON object value.
        let afterKey = blockText[keyRange.upperBound...]
        guard let colonIndex = afterKey.firstIndex(of: ":") else { return nil }
        let afterColon = blockText[blockText.index(after: colonIndex)...]
        guard let openBrace = afterColon.firstIndex(of: "{") else { return nil }

        // Match braces to find the corresponding closing }.
        var depth = 0
        for index in blockText[openBrace...].indices {
            let char = blockText[index]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(blockText[openBrace...index])
                }
            }
        }

        return nil
    }

    /// Appends a comma after the last line of a potentially multi-line property string.
    ///
    /// For single-line properties this simply appends `,`. For multi-line values
    /// (e.g., `workbench.colorCustomizations` with Peacock content) the comma is
    /// placed after the closing `}` on the final line.
    private static func appendCommaToLastLine(of text: String) -> String {
        if let lastNewline = text.lastIndex(of: "\n") {
            let prefix = text[text.startIndex...lastNewline]
            let lastLine = text[text.index(after: lastNewline)...]
            return "\(prefix)\(lastLine),"
        }
        return "\(text),"
    }

    private static func validateMarkers(in content: String) -> PsCoreError? {
        for pair in markerPairs {
            let hasStart = content.contains(pair.start)
            let hasEnd = content.contains(pair.end)
            if hasStart != hasEnd {
                return PsCoreError(
                    category: .validation,
                    message: """
                    Cannot inject settings block: unbalanced managed markers in settings.json.
                    Expected both markers:
                    \(pair.start)
                    \(pair.end)
                    Fix the file manually, then retry.
                    """
                )
            }
        }
        return nil
    }
}
