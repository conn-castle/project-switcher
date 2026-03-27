import Foundation

// MARK: - Config Write-Back

/// Targeted config.toml write-back for the `[app]` section.
///
/// Reads the existing file, finds or inserts the `[app]` section,
/// and sets `autoStartAtLogin` to the desired value.
/// Preserves all other content and comments.
public struct ConfigWriteBack {
    /// Sets `autoStartAtLogin` in the `[app]` section of the config file.
    /// - Parameters:
    ///   - value: The desired boolean value.
    ///   - fileURL: URL of the config.toml file.
    /// - Throws: If the file cannot be read or written.
    public static func setAutoStartAtLogin(
        _ value: Bool,
        in fileURL: URL
    ) throws {
        try setAutoStartAtLogin(value, in: fileURL, fileSystem: DefaultFileSystem())
    }

    /// Sets `autoStartAtLogin` in the `[app]` section of the config file.
    /// - Parameters:
    ///   - value: The desired boolean value.
    ///   - fileURL: URL of the config.toml file.
    ///   - fileSystem: File system abstraction for testability.
    /// - Throws: If the file cannot be read or written.
    static func setAutoStartAtLogin(
        _ value: Bool,
        in fileURL: URL,
        fileSystem: FileSystem
    ) throws {
        let data = try fileSystem.readFile(at: fileURL)
        guard let content = String(data: data, encoding: .utf8) else {
            throw PsCoreError(message: "Config file is not valid UTF-8")
        }

        let updated = updateAutoStartAtLogin(in: content, value: value)

        guard let newData = updated.data(using: .utf8) else {
            throw PsCoreError(message: "Failed to encode updated config as UTF-8")
        }
        try fileSystem.writeFile(at: fileURL, data: newData)
    }

    /// Pure-function core: updates `autoStartAtLogin` in the given TOML string.
    /// - Parameters:
    ///   - content: The existing config.toml content.
    ///   - value: The desired boolean value.
    /// - Returns: Updated config.toml content.
    static func updateAutoStartAtLogin(in content: String, value: Bool) -> String {
        let valueStr = value ? "true" : "false"
        var lines = content.components(separatedBy: "\n")

        // Find existing [app] section
        var appSectionIndex: Int?
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip inline comment (TOML allows `[app] # comment`)
            let beforeComment = trimmed.split(separator: "#", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? trimmed
            if beforeComment == "[app]" {
                appSectionIndex = i
                break
            }
        }

        if let sectionStart = appSectionIndex {
            // Look for existing autoStartAtLogin key within the section
            var keyIndex: Int?
            for i in (sectionStart + 1)..<lines.count {
                let trimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                // Stop at next section header (both [section] and [[array]])
                if trimmed.hasPrefix("[") {
                    break
                }
                if trimmed.hasPrefix("autoStartAtLogin"),
                   trimmed.count == "autoStartAtLogin".count
                       || trimmed[trimmed.index(trimmed.startIndex, offsetBy: "autoStartAtLogin".count)].isWhitespace
                       || trimmed[trimmed.index(trimmed.startIndex, offsetBy: "autoStartAtLogin".count)] == "=" {
                    keyIndex = i
                    break
                }
            }

            if let ki = keyIndex {
                lines[ki] = rewrittenAutoStartLine(from: lines[ki], valueString: valueStr)
            } else {
                lines.insert("autoStartAtLogin = \(valueStr)", at: sectionStart + 1)
            }
        } else {
            // No [app] section exists — append one
            // Ensure trailing newline before new section
            if let last = lines.last, !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("")
            }
            lines.append("[app]")
            lines.append("autoStartAtLogin = \(valueStr)")
        }

        return lines.joined(separator: "\n")
    }

    /// Rewrites an existing `autoStartAtLogin` line while preserving indentation and inline comments.
    /// - Parameters:
    ///   - originalLine: Existing line from config.toml.
    ///   - valueString: Target boolean literal (`true` or `false`).
    /// - Returns: Normalized key/value line with original indentation and trailing inline comment.
    private static func rewrittenAutoStartLine(from originalLine: String, valueString: String) -> String {
        let indentation = leadingWhitespace(in: originalLine)
        let trailingComment = trailingCommentSegment(in: originalLine)
        return "\(indentation)autoStartAtLogin = \(valueString)\(trailingComment)"
    }

    /// Extracts leading indentation (spaces/tabs) from a config line.
    /// - Parameter line: Config line.
    /// - Returns: Leading whitespace prefix.
    private static func leadingWhitespace(in line: String) -> String {
        String(line.prefix { $0 == " " || $0 == "\t" })
    }

    /// Returns the trailing inline comment segment, including spacing before `#`.
    ///
    /// Uses naive `#` detection (first occurrence). This is safe because this method
    /// is only called for `autoStartAtLogin` lines, which are boolean-valued and never
    /// contain `#` inside quoted strings. If extended to keys whose values may contain
    /// `#` (e.g., hex color strings), this must be replaced with TOML-aware parsing.
    ///
    /// - Parameter line: Config line.
    /// - Returns: Empty string when no inline comment exists.
    private static func trailingCommentSegment(in line: String) -> String {
        guard let commentStart = line.firstIndex(of: "#") else {
            return ""
        }

        let contentBeforeComment = line[..<commentStart]
        let trailingSpaceStart = contentBeforeComment.lastIndex(where: { !$0.isWhitespace })
            .map { line.index(after: $0) } ?? line.startIndex
        return String(line[trailingSpaceStart...])
    }
}
