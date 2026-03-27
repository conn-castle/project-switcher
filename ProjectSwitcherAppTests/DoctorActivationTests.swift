import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherCore

@MainActor
final class DoctorActivationTests: XCTestCase {

    // MARK: - skipActivation

    func testShowReportWithSkipActivationStillRendersReport() {
        let controller = DoctorWindowController()
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .pass, title: "All good")
            ]
        )

        // showReport with skipActivation: true should still store the report
        // and set up the window — it just skips NSApp.activate.
        controller.showReport(report, skipActivation: true)

        XCTAssertNotNil(controller.lastReport)
        XCTAssertEqual(controller.lastReport?.findings.count, 1)
    }

    func testShowLoadingWithSkipActivationDoesNotCrash() {
        let controller = DoctorWindowController()

        // showLoading with skipActivation: true should set up the window
        // and loading state without calling NSApp.activate.
        controller.showLoading(skipActivation: true)

        // Verify loading state was set (no report yet)
        XCTAssertNil(controller.lastReport)
    }

    func testShowReportWithoutSkipActivationStillRendersReport() {
        let controller = DoctorWindowController()
        let report = DoctorReport(
            metadata: makeMetadata(),
            findings: [
                DoctorFinding(severity: .fail, title: "Problem found")
            ]
        )

        // Default path (skipActivation: false) should also work correctly
        controller.showReport(report)

        XCTAssertNotNil(controller.lastReport)
        XCTAssertTrue(controller.lastReport?.hasFailures == true)
    }

    // MARK: - Helpers

    private func makeMetadata() -> DoctorMetadata {
        DoctorMetadata(
            timestamp: "2024-01-01T00:00:00.000Z",
            projectSwitcherVersion: "dev",
            macOSVersion: "macOS 15.7 (Test)",
            aerospaceApp: "AVAILABLE",
            aerospaceCli: "AVAILABLE",
            errorContext: nil,
            durationMs: 0,
            sectionTimings: [:]
        )
    }
}
