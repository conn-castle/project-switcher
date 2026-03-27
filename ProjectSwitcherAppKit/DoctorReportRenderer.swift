//
//  DoctorReportRenderer.swift
//  ProjectSwitcherAppKit
//
//  Builds an NSAttributedString from a DoctorReport with explicit, contrast-safe
//  colors so Doctor output remains readable across build configurations.
//

import AppKit

import ProjectSwitcherCore

/// Explicit Doctor report colors for a specific appearance mode.
///
/// Using concrete RGB colors avoids release-only rendering differences observed with
/// dynamic semantic colors in `NSTextView` rich text.
public struct DoctorReportPalette {
    /// Scroll/report background color.
    public let reportBackgroundColor: NSColor
    /// Primary text color for titles and finding headings.
    public let primaryTextColor: NSColor
    /// Secondary text color for metadata and detail lines.
    public let secondaryTextColor: NSColor
    /// Summary label text color.
    public let summaryTextColor: NSColor
    /// Snippet text color.
    public let snippetTextColor: NSColor
    /// Snippet background color.
    public let snippetBackgroundColor: NSColor
    /// FAIL severity color.
    public let failSeverityColor: NSColor
    /// WARN severity color.
    public let warnSeverityColor: NSColor
    /// PASS severity color.
    public let passSeverityColor: NSColor
}

/// Produces rich-text (NSAttributedString) renderings of Doctor reports.
///
/// Mirrors the structure of `DoctorReport.rendered()` but uses a deterministic,
/// explicit color palette and typographic hierarchy.
public enum DoctorReportRenderer {

    // MARK: - Design Tokens

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let metadataFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let severityFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private static let findingTitleFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private static let bodyFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let snippetFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let summaryFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    /// Returns the report color palette for the provided appearance.
    /// - Parameter appearance: Effective appearance from the Doctor window/text view.
    /// - Returns: Light or dark palette with explicit RGB colors.
    public static func palette(for appearance: NSAppearance?) -> DoctorReportPalette {
        if isDarkAppearance(appearance) {
            return DoctorReportPalette(
                reportBackgroundColor: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1.0),
                primaryTextColor: NSColor(srgbRed: 0.92, green: 0.93, blue: 0.94, alpha: 1.0),
                secondaryTextColor: NSColor(srgbRed: 0.73, green: 0.75, blue: 0.78, alpha: 1.0),
                summaryTextColor: NSColor(srgbRed: 0.92, green: 0.93, blue: 0.94, alpha: 1.0),
                snippetTextColor: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.92, alpha: 1.0),
                snippetBackgroundColor: NSColor(srgbRed: 0.19, green: 0.20, blue: 0.22, alpha: 1.0),
                failSeverityColor: NSColor(srgbRed: 1.00, green: 0.47, blue: 0.43, alpha: 1.0),
                warnSeverityColor: NSColor(srgbRed: 1.00, green: 0.73, blue: 0.30, alpha: 1.0),
                passSeverityColor: NSColor(srgbRed: 0.41, green: 0.88, blue: 0.52, alpha: 1.0)
            )
        }

        return DoctorReportPalette(
            reportBackgroundColor: NSColor(srgbRed: 0.985, green: 0.985, blue: 0.985, alpha: 1.0),
            primaryTextColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0),
            secondaryTextColor: NSColor(srgbRed: 0.34, green: 0.34, blue: 0.36, alpha: 1.0),
            summaryTextColor: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0),
            snippetTextColor: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1.0),
            snippetBackgroundColor: NSColor(srgbRed: 0.94, green: 0.94, blue: 0.95, alpha: 1.0),
            failSeverityColor: NSColor(srgbRed: 0.77, green: 0.16, blue: 0.12, alpha: 1.0),
            warnSeverityColor: NSColor(srgbRed: 0.74, green: 0.46, blue: 0.05, alpha: 1.0),
            passSeverityColor: NSColor(srgbRed: 0.12, green: 0.56, blue: 0.20, alpha: 1.0)
        )
    }

    /// Renders a Doctor report as an attributed string with severity labels.
    ///
    /// Same sort order and structure as `DoctorReport.rendered()`:
    /// title, metadata, findings sorted by severity (FAIL > WARN > PASS, stable),
    /// and a summary line with colored counts.
    ///
    /// - Parameters:
    ///   - report: The Doctor report to render.
    ///   - appearance: Optional effective appearance used to select a contrast-safe palette.
    /// - Returns: A styled attributed string suitable for display in an `NSTextView`.
    public static func render(_ report: DoctorReport, appearance: NSAppearance? = nil) -> NSAttributedString {
        let palette = palette(for: appearance)
        let result = NSMutableAttributedString()

        // Title
        appendLine(to: result, "ProjectSwitcher Doctor Report",
                   font: titleFont, color: palette.primaryTextColor)

        // Metadata
        let metadataLines = buildMetadataLines(report.metadata)
        for line in metadataLines {
            appendLine(to: result, line, font: metadataFont, color: palette.secondaryTextColor)
        }

        // Blank line before findings
        appendLine(to: result, "", color: palette.primaryTextColor)

        // Sort findings by severity (FAIL > WARN > PASS), stable by original index
        let sortedFindings = report.findings.enumerated().sorted { lhs, rhs in
            let leftOrder = lhs.element.severity.sortOrder
            let rightOrder = rhs.element.severity.sortOrder
            if leftOrder == rightOrder {
                return lhs.offset < rhs.offset
            }
            return leftOrder < rightOrder
        }.map { $0.element }

        // Findings
        if sortedFindings.isEmpty {
            appendSeverityLine(to: result, severity: .pass, text: "  no issues found", palette: palette)
        } else {
            for finding in sortedFindings {
                appendFinding(to: result, finding, palette: palette)
            }
        }

        // Summary
        let countedFindings = sortedFindings.filter { !$0.title.isEmpty }
        let passCount = countedFindings.filter { $0.severity == DoctorSeverity.pass }.count
        let warnCount = countedFindings.filter { $0.severity == DoctorSeverity.warn }.count
        let failCount = countedFindings.filter { $0.severity == DoctorSeverity.fail }.count

        appendLine(to: result, "", color: palette.primaryTextColor)
        appendSummaryLine(
            to: result,
            passCount: passCount,
            warnCount: warnCount,
            failCount: failCount,
            palette: palette
        )

        return result
    }

    // MARK: - Metadata

    private static func buildMetadataLines(_ metadata: DoctorMetadata) -> [String] {
        var lines: [String] = []
        lines.append("Timestamp: \(metadata.timestamp)")
        lines.append("ProjectSwitcher version: \(metadata.projectSwitcherVersion)")
        lines.append("macOS version: \(metadata.macOSVersion)")
        lines.append("AeroSpace app: \(metadata.aerospaceApp)")
        lines.append("aerospace CLI: \(metadata.aerospaceCli)")
        if let ctx = metadata.errorContext {
            lines.append("Triggered by: \(ctx.trigger) (\(ctx.category.rawValue)): \(ctx.message)")
        }
        lines.append("Duration: \(metadata.durationMs)ms")
        if !metadata.sectionTimings.isEmpty {
            let sortedSections = metadata.sectionTimings.sorted { $0.key < $1.key }
            let timingParts = sortedSections.map { "\($0.key)=\($0.value)ms" }
            lines.append("Sections: \(timingParts.joined(separator: ", "))")
        }
        return lines
    }

    // MARK: - Findings

    private static func appendFinding(
        to result: NSMutableAttributedString,
        _ finding: DoctorFinding,
        palette: DoctorReportPalette
    ) {
        if finding.title.isEmpty {
            // Findings with empty title: body lines only, no severity prefix
            for line in finding.bodyLines {
                appendLine(to: result, line, font: bodyFont, color: palette.secondaryTextColor)
            }
            return
        }

        // Severity label + title on same line
        appendSeverityLine(to: result, severity: finding.severity, text: "  \(finding.title)", palette: palette)

        // Body lines (indented detail/fix)
        for line in finding.bodyLines {
            appendLine(to: result, line, font: bodyFont, color: palette.secondaryTextColor)
        }

        // Code snippet with background tint (omit ``` fences)
        if let snippet = finding.snippet, !snippet.isEmpty {
            appendLine(to: result, "  Snippet:", font: bodyFont, color: palette.secondaryTextColor)
            for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
                appendSnippetLine(to: result, "  \(line)", palette: palette)
            }
        }
    }

    // MARK: - Summary

    private static func appendSummaryLine(
        to result: NSMutableAttributedString,
        passCount: Int,
        warnCount: Int,
        failCount: Int,
        palette: DoctorReportPalette
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: palette.summaryTextColor
        ]
        result.append(NSAttributedString(string: "Summary: ", attributes: attrs))

        let passAttrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: palette.passSeverityColor
        ]
        result.append(NSAttributedString(string: "\(passCount) PASS", attributes: passAttrs))

        result.append(NSAttributedString(string: ", ", attributes: attrs))

        let warnAttrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: palette.warnSeverityColor
        ]
        result.append(NSAttributedString(string: "\(warnCount) WARN", attributes: warnAttrs))

        result.append(NSAttributedString(string: ", ", attributes: attrs))

        let failAttrs: [NSAttributedString.Key: Any] = [
            .font: summaryFont,
            .foregroundColor: palette.failSeverityColor
        ]
        result.append(NSAttributedString(string: "\(failCount) FAIL", attributes: failAttrs))

        result.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    // MARK: - Line Helpers

    private static func appendLine(
        to result: NSMutableAttributedString,
        _ text: String,
        font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        color: NSColor
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        result.append(NSAttributedString(string: text + "\n", attributes: attrs))
    }

    private static func appendSeverityLine(
        to result: NSMutableAttributedString,
        severity: DoctorSeverity,
        text: String,
        palette: DoctorReportPalette
    ) {
        let severityColor = switch severity {
        case .fail: palette.failSeverityColor
        case .warn: palette.warnSeverityColor
        case .pass: palette.passSeverityColor
        }

        let severityAttrs: [NSAttributedString.Key: Any] = [
            .font: severityFont,
            .foregroundColor: severityColor
        ]
        result.append(NSAttributedString(string: severity.rawValue, attributes: severityAttrs))

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: findingTitleFont,
            .foregroundColor: palette.primaryTextColor
        ]
        result.append(NSAttributedString(string: text + "\n", attributes: titleAttrs))
    }

    private static func appendSnippetLine(
        to result: NSMutableAttributedString,
        _ text: String,
        palette: DoctorReportPalette
    ) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: snippetFont,
            .foregroundColor: palette.snippetTextColor,
            .backgroundColor: palette.snippetBackgroundColor
        ]
        result.append(NSAttributedString(string: text + "\n", attributes: attrs))
    }

    private static func isDarkAppearance(_ appearance: NSAppearance?) -> Bool {
        appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
