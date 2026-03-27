import XCTest
@testable import ProjectSwitcherCore

final class AeroSpaceHealthWrapperTests: XCTestCase {

    func testHealthInstallViaHomebrewReturnsTrueOnSuccess() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        XCTAssertTrue(aero.healthInstallViaHomebrew())
        XCTAssertEqual(runner.calls.first?.executable, "brew")
    }

    func testHealthInstallViaHomebrewReturnsFalseOnFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "brew failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        XCTAssertFalse(aero.healthInstallViaHomebrew())
    }

    func testHealthReloadConfigReturnsTrueOnSuccessAndFalseOnFailure() {
        do {
            let runner = FallbackMockCommandRunner()
            runner.results = [
                .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
            ]
            let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())
            XCTAssertTrue(aero.healthReloadConfig())
        }

        do {
            let runner = FallbackMockCommandRunner()
            runner.results = [
                .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "bad"))
            ]
            let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())
            XCTAssertFalse(aero.healthReloadConfig())
        }
    }

    func testHealthStartReturnsFalseOnMainThreadAndTrueOffMainThread() {
        do {
            let runner = FallbackMockCommandRunner()
            let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())
            XCTAssertFalse(aero.healthStart())
            XCTAssertEqual(runner.calls.count, 0)
        }

        do {
            let runner = FallbackMockCommandRunner()
            runner.results = [
                // open -a AeroSpace succeeds
                .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
                // aerospace --help ready
                .success(PsCommandResult(exitCode: 0, stdout: "usage", stderr: ""))
            ]
            let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

            let semaphore = DispatchSemaphore(value: 0)
            var value: Bool?
            DispatchQueue.global(qos: .userInitiated).async {
                value = aero.healthStart()
                semaphore.signal()
            }
            let wait = semaphore.wait(timeout: .now() + 5)
            XCTAssertNotEqual(wait, .timedOut)
            XCTAssertEqual(value, true)
        }
    }

    func testHealthCheckCompatibilityReturnsCliUnavailableWhenCliMissing() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "aerospace missing"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.healthCheckCompatibility()

        XCTAssertEqual(result, .cliUnavailable)
    }

    func testHealthCheckCompatibilityReturnsIncompatibleDetailWhenCompatibilityFails() {
        let runner = FallbackMockCommandRunner()
        runner.keyedResults = [
            "--help": .success(PsCommandResult(exitCode: 0, stdout: "usage", stderr: "")),
            "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "--all", stderr: "")),
            "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(PsCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.healthCheckCompatibility()

        switch result {
        case .incompatible(let detail):
            XCTAssertTrue(detail.contains("list-workspaces"))
        default:
            XCTFail("Expected incompatible result, got \(result)")
        }
    }
}

final class AeroSpaceWorkspacesWithFocusTests: XCTestCase {

    func testListWorkspacesWithFocusParsesSummaries() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "main||true\nps-one||false\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let summaries):
            XCTAssertEqual(summaries, [
                PsWorkspaceSummary(workspace: "main", isFocused: true),
                PsWorkspaceSummary(workspace: "ps-one", isFocused: false)
            ])
        }
    }

    func testListWorkspacesWithFocusSkipsEmptyLines() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "\nmain||true\n\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let summaries):
            XCTAssertEqual(summaries, [PsWorkspaceSummary(workspace: "main", isFocused: true)])
        }
    }

    func testListWorkspacesWithFocusFailsWhenSeparatorMissing() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "main true\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesWithFocusFailsOnInvalidFocusToken() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "main||maybe\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesWithFocusFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 2, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesWithFocusFailsWhenRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }
}

final class AeroSpaceWindowParsingErrorBranchTests: XCTestCase {

    func testListWindowsOnFocusedMonitorFailsWhenSecondSeparatorMissing() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "1||com.app\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsOnFocusedMonitorFailsWhenThirdSeparatorMissing() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "1||com.app||main\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
    }
}
