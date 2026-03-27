import XCTest
@testable import ProjectSwitcherCore

final class AeroSpaceFallbackDecisionTests: XCTestCase {

    func testFallbackDecisionIsFalseWhenPrimaryCommandSucceeds() {
        let primary = Result<PsCommandResult, PsCoreError>.success(
            PsCommandResult(exitCode: 0, stdout: "", stderr: "")
        )

        XCTAssertFalse(PsAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsTrueWhenOutputContainsUnknownOption() {
        let primary = Result<PsCommandResult, PsCoreError>.success(
            PsCommandResult(exitCode: 2, stdout: "", stderr: "error: unknown option '--focus-follows-window'")
        )

        XCTAssertTrue(PsAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsTrueWhenOutputContainsUnrecognizedCommand() {
        let primary = Result<PsCommandResult, PsCoreError>.success(
            PsCommandResult(exitCode: 1, stdout: "", stderr: "unrecognized command: summon-workspace")
        )

        XCTAssertTrue(PsAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsTrueWhenMandatoryOptionNotSpecified() {
        let primary = Result<PsCommandResult, PsCoreError>.success(
            PsCommandResult(exitCode: 1, stdout: "", stderr: "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")
        )

        XCTAssertTrue(PsAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsFalseForNonZeroExitWithoutCompatibilityIndicator() {
        let primary = Result<PsCommandResult, PsCoreError>.success(
            PsCommandResult(exitCode: 1, stdout: "", stderr: "workspace 'ps-test' not found")
        )

        XCTAssertFalse(PsAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }

    func testFallbackDecisionIsFalseWhenPrimaryCommandFailsToRun() {
        let primary = Result<PsCommandResult, PsCoreError>.failure(
            PsCoreError(message: "Executable not found: aerospace")
        )

        XCTAssertFalse(PsAeroSpace.shouldAttemptCompatibilityFallback(primary))
    }
}
