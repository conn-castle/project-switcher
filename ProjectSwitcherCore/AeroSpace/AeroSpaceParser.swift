import Foundation

/// Pure parsing functions for AeroSpace CLI output.
///
/// Parses the `||`-delimited output format produced by `aerospace list-windows --format`
/// and `aerospace list-workspaces --format` into typed model objects.
enum AeroSpaceParser {

    /// Parses window summaries from formatted AeroSpace output.
    ///
    /// Expected format: `<window-id>||<app-bundle-id>||<workspace>||<window-title>`
    /// where fields are separated by `||` (double pipe).
    ///
    /// - Parameter output: Output from `aerospace list-windows --format`.
    /// - Returns: Parsed window summaries or an error.
    static func parseWindowSummaries(output: String) -> Result<[PsWindow], PsCoreError> {
        let lines = output.split(whereSeparator: \.isNewline)
        var windows: [PsWindow] = []
        windows.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            guard let firstSeparator = trimmed.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }

            let idPart = String(trimmed[..<firstSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let windowId = Int(idPart) else {
                return .failure(parseError(
                    "Window id was not an integer.",
                    detail: "Got: \(idPart)"
                ))
            }

            let remainder = trimmed[firstSeparator.upperBound...]
            guard let secondSeparator = remainder.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }

            let appBundleId = String(remainder[..<secondSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let remainderAfterBundle = remainder[secondSeparator.upperBound...]
            guard let thirdSeparator = remainderAfterBundle.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected aerospace output format.",
                    detail: "Expected '<window-id>||<app-bundle-id>||<workspace>||<window-title>', got: \(trimmed)"
                ))
            }
            let workspace = String(remainderAfterBundle[..<thirdSeparator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let titlePart = remainderAfterBundle[thirdSeparator.upperBound...]
            let windowTitle = String(titlePart).trimmingCharacters(in: .whitespacesAndNewlines)

            windows.append(
                PsWindow(
                    windowId: windowId,
                    appBundleId: appBundleId,
                    workspace: workspace,
                    windowTitle: windowTitle
                )
            )
        }

        return .success(windows)
    }

    /// Parses workspace summaries from formatted AeroSpace output.
    ///
    /// Expected format: `<workspace>||<is-focused>`
    /// where fields are separated by `||` (double pipe), and focus values are `true` or `false`.
    ///
    /// - Parameter output: Output from `aerospace list-workspaces --all --format`.
    /// - Returns: Parsed workspace summaries or an error.
    static func parseWorkspaceSummaries(output: String) -> Result<[PsWorkspaceSummary], PsCoreError> {
        let lines = output.split(whereSeparator: \.isNewline)
        var workspaces: [PsWorkspaceSummary] = []
        workspaces.reserveCapacity(lines.count)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            guard let separator = trimmed.range(of: "||") else {
                return .failure(parseError(
                    "Unexpected workspace summary format.",
                    detail: "Expected '<workspace>||<is-focused>', got: \(trimmed)"
                ))
            }

            let workspace = String(trimmed[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let focusToken = String(trimmed[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let isFocused: Bool
            switch focusToken {
            case "true":
                isFocused = true
            case "false":
                isFocused = false
            default:
                return .failure(parseError(
                    "Unexpected workspace focus value.",
                    detail: "Expected 'true' or 'false', got: \(focusToken)"
                ))
            }

            workspaces.append(PsWorkspaceSummary(workspace: workspace, isFocused: isFocused))
        }

        return .success(workspaces)
    }
}
