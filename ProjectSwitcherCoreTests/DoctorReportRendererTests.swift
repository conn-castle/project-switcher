import AppKit
import XCTest

@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

final class DoctorReportRendererTests: XCTestCase {

    func testPaletteMaintainsHighContrastInLightAppearance() {
        let palette = DoctorReportRenderer.palette(for: NSAppearance(named: .aqua))

        XCTAssertGreaterThanOrEqual(
            contrastRatio(palette.primaryTextColor, palette.reportBackgroundColor),
            7.0,
            "Primary text contrast must stay high in light mode"
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio(palette.secondaryTextColor, palette.reportBackgroundColor),
            4.5,
            "Secondary text contrast must stay readable in light mode"
        )
    }

    func testPaletteMaintainsHighContrastInDarkAppearance() {
        let palette = DoctorReportRenderer.palette(for: NSAppearance(named: .darkAqua))

        XCTAssertGreaterThanOrEqual(
            contrastRatio(palette.primaryTextColor, palette.reportBackgroundColor),
            7.0,
            "Primary text contrast must stay high in dark mode"
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio(palette.secondaryTextColor, palette.reportBackgroundColor),
            4.5,
            "Secondary text contrast must stay readable in dark mode"
        )
    }

    func testRenderUsesPaletteColorsForTitleAndSeverity() {
        let report = DoctorReport(
            metadata: DoctorMetadata(
                timestamp: "2026-02-21T00:00:00Z",
                projectSwitcherVersion: "0.1.8",
                macOSVersion: "Version 26.2",
                aerospaceApp: "/Applications/AeroSpace.app",
                aerospaceCli: "AVAILABLE",
                errorContext: nil,
                durationMs: 42,
                sectionTimings: [:]
            ),
            findings: [
                DoctorFinding(severity: .pass, title: "All good")
            ]
        )

        let appearance = NSAppearance(named: .aqua)
        let palette = DoctorReportRenderer.palette(for: appearance)
        let rendered = DoctorReportRenderer.render(report, appearance: appearance)

        let titleRange = (rendered.string as NSString).range(of: "ProjectSwitcher Doctor Report")
        XCTAssertNotEqual(titleRange.location, NSNotFound)

        let titleColor = rendered.attribute(
            NSAttributedString.Key.foregroundColor,
            at: titleRange.location,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertTrue(colorsMatch(titleColor, palette.primaryTextColor))

        let passRange = (rendered.string as NSString).range(of: "PASS")
        XCTAssertNotEqual(passRange.location, NSNotFound)

        let passColor = rendered.attribute(
            NSAttributedString.Key.foregroundColor,
            at: passRange.location,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertTrue(colorsMatch(passColor, palette.passSeverityColor))
    }

    private func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor, tolerance: CGFloat = 0.01) -> Bool {
        guard let lhs else { return false }
        let l = toRGB(lhs)
        let r = toRGB(rhs)
        return abs(l.red - r.red) <= tolerance &&
            abs(l.green - r.green) <= tolerance &&
            abs(l.blue - r.blue) <= tolerance &&
            abs(l.alpha - r.alpha) <= tolerance
    }

    private func contrastRatio(_ first: NSColor, _ second: NSColor) -> Double {
        let l1 = relativeLuminance(first)
        let l2 = relativeLuminance(second)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> Double {
        let rgb = toRGB(color)
        let r = linearized(Double(rgb.red))
        let g = linearized(Double(rgb.green))
        let b = linearized(Double(rgb.blue))
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func linearized(_ component: Double) -> Double {
        if component <= 0.03928 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }

    private func toRGB(_ color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let resolved = color.usingColorSpace(.extendedSRGB) ?? color
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent, resolved.alphaComponent)
    }
}
