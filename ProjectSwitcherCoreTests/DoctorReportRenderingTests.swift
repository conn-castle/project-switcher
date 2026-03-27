import XCTest
@testable import ProjectSwitcherCore

final class DoctorReportRenderingTests: XCTestCase {

    func testOverallSeverityReturnsFailWhenAnyFindingFails() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .pass, title: "Pass"),
                DoctorFinding(severity: .warn, title: "Warn"),
                DoctorFinding(severity: .fail, title: "Fail")
            ]
        )

        XCTAssertEqual(report.overallSeverity, .fail)
        XCTAssertTrue(report.hasFailures)
    }

    func testOverallSeverityReturnsWarnWhenNoFailuresExist() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .pass, title: "Pass"),
                DoctorFinding(severity: .warn, title: "Warn")
            ]
        )

        XCTAssertEqual(report.overallSeverity, .warn)
        XCTAssertFalse(report.hasFailures)
    }

    func testOverallSeverityReturnsPassWhenFindingsAreEmpty() {
        let report = DoctorReport(metadata: makeMetadata(), findings: [])

        XCTAssertEqual(report.overallSeverity, .pass)
        XCTAssertFalse(report.hasFailures)
    }

    func testRenderedSortsFindingsBySeverityWithStableOrder() {
        let metadata = makeMetadata(aerospaceApp: "NOT FOUND", aerospaceCli: "NOT FOUND")

        let findings: [DoctorFinding] = [
            DoctorFinding(severity: .pass, title: "Pass A"),
            DoctorFinding(severity: .fail, title: "Fail A"),
            DoctorFinding(severity: .warn, title: "Warn A"),
            DoctorFinding(severity: .fail, title: "Fail B"),
            DoctorFinding(severity: .pass, title: "Pass B")
        ]

        let report = DoctorReport(metadata: metadata, findings: findings)
        let rendered = report.rendered()

        let lines = rendered.split(separator: "\n").map(String.init)
        let findingLines = lines.filter { $0.hasPrefix("FAIL  ") || $0.hasPrefix("WARN  ") || $0.hasPrefix("PASS  ") }

        XCTAssertEqual(findingLines, [
            "FAIL  Fail A",
            "FAIL  Fail B",
            "WARN  Warn A",
            "PASS  Pass A",
            "PASS  Pass B"
        ])
    }

    func testRenderedIncludesSummaryCounts() {
        let metadata = makeMetadata()

        let findings: [DoctorFinding] = [
            DoctorFinding(severity: .pass, title: "Pass A"),
            DoctorFinding(severity: .warn, title: "Warn A"),
            DoctorFinding(severity: .fail, title: "Fail A")
        ]

        let report = DoctorReport(metadata: metadata, findings: findings)
        let rendered = report.rendered()

        XCTAssertTrue(rendered.contains("Summary: 1 PASS, 1 WARN, 1 FAIL"))
    }

    func testRenderedIncludesSnippetAsTomlBlock() {
        let metadata = makeMetadata()

        let finding = DoctorFinding(
            severity: .fail,
            title: "Config invalid",
            detail: "Bad value",
            fix: "Fix the config",
            snippet: "value = \"ok\""
        )

        let report = DoctorReport(metadata: metadata, findings: [finding])
        let rendered = report.rendered()

        XCTAssertTrue(rendered.contains("Snippet:"))
        XCTAssertTrue(rendered.contains("```toml"))
        XCTAssertTrue(rendered.contains("value = \"ok\""))
        XCTAssertTrue(rendered.contains("```"))
    }

    func testRenderedIncludesBodyLinesWhenTitleEmpty() {
        let metadata = makeMetadata()

        let finding = DoctorFinding(
            severity: .pass,
            title: "",
            bodyLines: ["Raw line 1", "Raw line 2"]
        )

        let report = DoctorReport(metadata: metadata, findings: [finding])
        let rendered = report.rendered()

        XCTAssertTrue(rendered.contains("Raw line 1"))
        XCTAssertTrue(rendered.contains("Raw line 2"))
    }

    // MARK: - Colorized rendering tests

    func testRenderedWithColorizeWrapsFailInRedAnsi() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [DoctorFinding(severity: .fail, title: "Something broke")]
        )

        let rendered = report.rendered(colorize: true)

        XCTAssertTrue(rendered.contains("\u{1b}[31mFAIL\u{1b}[0m  Something broke"))
    }

    func testRenderedWithColorizeWrapsWarnInYellowAnsi() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [DoctorFinding(severity: .warn, title: "Heads up")]
        )

        let rendered = report.rendered(colorize: true)

        XCTAssertTrue(rendered.contains("\u{1b}[33mWARN\u{1b}[0m  Heads up"))
    }

    func testRenderedWithColorizeWrapsPassInGreenAnsi() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [DoctorFinding(severity: .pass, title: "All good")]
        )

        let rendered = report.rendered(colorize: true)

        XCTAssertTrue(rendered.contains("\u{1b}[32mPASS\u{1b}[0m  All good"))
    }

    func testRenderedWithColorizeColorizeSummaryLine() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .pass, title: "OK"),
                DoctorFinding(severity: .warn, title: "Hmm"),
                DoctorFinding(severity: .fail, title: "Bad")
            ]
        )

        let rendered = report.rendered(colorize: true)

        XCTAssertTrue(rendered.contains("1 \u{1b}[32mPASS\u{1b}[0m"))
        XCTAssertTrue(rendered.contains("1 \u{1b}[33mWARN\u{1b}[0m"))
        XCTAssertTrue(rendered.contains("1 \u{1b}[31mFAIL\u{1b}[0m"))
    }

    func testRenderedWithoutColorizeHasNoAnsiCodes() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .pass, title: "OK"),
                DoctorFinding(severity: .warn, title: "Hmm"),
                DoctorFinding(severity: .fail, title: "Bad")
            ]
        )

        let rendered = report.rendered(colorize: false)

        XCTAssertFalse(rendered.contains("\u{1b}["))
    }

    func testRenderedDefaultIsNotColorized() {
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [DoctorFinding(severity: .fail, title: "Bad")]
        )

        let rendered = report.rendered()

        XCTAssertFalse(rendered.contains("\u{1b}["))
        XCTAssertTrue(rendered.contains("FAIL  Bad"))
    }

    func testRenderedWithColorizeEmptyFindingsShowsGreenPass() {
        let report = DoctorReport(metadata: makeMetadata(), findings: [])

        let rendered = report.rendered(colorize: true)

        XCTAssertTrue(rendered.contains("\u{1b}[32mPASS\u{1b}[0m  no issues found"))
    }

    private func makeMetadata(
        aerospaceApp: String = "AVAILABLE",
        aerospaceCli: String = "AVAILABLE"
    ) -> DoctorMetadata {
        DoctorMetadata(
            timestamp: "2024-01-01T00:00:00.000Z",
            projectSwitcherVersion: "dev",
            macOSVersion: "macOS 15.7 (Test)",
            aerospaceApp: aerospaceApp,
            aerospaceCli: aerospaceCli,
            errorContext: nil,
            durationMs: 0,
            sectionTimings: [:]
        )
    }
}
