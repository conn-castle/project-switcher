import XCTest
@testable import ProjectSwitcherCore

// MARK: - Workspaces parsing

final class AeroSpaceWorkspacesTests: XCTestCase {
    func testListWorkspacesFocusedParsesLines() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "main\n\n ps-one \n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesFocused()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let workspaces):
            XCTAssertEqual(workspaces, ["main", "ps-one"])
        }
    }

    func testListWorkspacesFocusedFailsWhenRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesFocused()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesFocusedFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 2, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesFocused()

        XCTAssertTrue(result.isFailure)
    }

    func testGetWorkspacesFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 2, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.getWorkspaces()

        XCTAssertTrue(result.isFailure)
    }

    func testListWorkspacesWithFocusParsesSummaries() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "ps-one||true\nps-two||false\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let summaries):
            XCTAssertEqual(summaries, [
                PsWorkspaceSummary(workspace: "ps-one", isFocused: true),
                PsWorkspaceSummary(workspace: "ps-two", isFocused: false)
            ])
        }
    }

    func testListWorkspacesWithFocusFailsOnParseError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "ps-one||maybe\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWorkspacesWithFocus()

        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - createWorkspace / closeWorkspace

final class AeroSpaceWorkspaceLifecycleTests: XCTestCase {
    func testCreateWorkspaceFailsOnEmptyName() {
        let runner = FallbackMockCommandRunner()
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.createWorkspace("   ")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testCreateWorkspaceFailsWhenAlreadyExists() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "ps-test\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.createWorkspace("ps-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testCreateWorkspaceSummonsWhenMissing() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // list-workspaces --all does not include ps-test
            .success(PsCommandResult(exitCode: 0, stdout: "main\n", stderr: "")),
            // summon-workspace succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.createWorkspace("ps-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["summon-workspace", "ps-test"])
    }

    func testCreateWorkspacePropagatesWorkspaceExistsFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // getWorkspaces runner failure
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.createWorkspace("ps-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["list-workspaces", "--all"])
    }

    func testCreateWorkspaceFailsWhenSummonWorkspaceRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // list-workspaces --all does not include ps-test
            .success(PsCommandResult(exitCode: 0, stdout: "main\n", stderr: "")),
            // summon-workspace runner fails
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.createWorkspace("ps-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["summon-workspace", "ps-test"])
    }

    func testCreateWorkspaceFailsWhenSummonWorkspaceNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // list-workspaces --all does not include ps-test
            .success(PsCommandResult(exitCode: 0, stdout: "main\n", stderr: "")),
            // summon-workspace returns non-zero
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.createWorkspace("ps-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
    }

    func testCloseWorkspaceAggregatesCloseFailures() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // list-windows in workspace returns 2 windows
            .success(PsCommandResult(exitCode: 0, stdout: "1||app||ps-test||t\n2||app||ps-test||t\n", stderr: "")),
            // close window 1 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // close window 2 fails
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "no")),
            // re-query: window 2 still present
            .success(PsCommandResult(exitCode: 0, stdout: "2||app||ps-test||t\n", stderr: "")),
            // retry close window 2 fails again
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "no"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
    }

    func testCloseWorkspaceFailsOnEmptyName() {
        let runner = FallbackMockCommandRunner()
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "   ")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testCloseWorkspaceFailsWhenListWindowsWorkspaceFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "list-windows failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testCloseWorkspaceSucceedsWhenNoWindowsInWorkspace() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testCloseWorkspaceSucceedsWhenAllWindowsClosed() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // list-windows in workspace returns 2 windows
            .success(PsCommandResult(exitCode: 0, stdout: "1||app||ps-test||t\n2||app||ps-test||t\n", stderr: "")),
            // close window 1 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // close window 2 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 3)
    }

    func testCloseWorkspaceFailsWhenParsedWindowIdIsNotPositive() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "0||app||ps-test||t\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
    }

    func testCloseWorkspaceAggregatesRunnerFailureFromCloseWindow() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "1||app||ps-test||t\n", stderr: "")),
            .failure(PsCoreError(category: .command, message: "close command failed")),
            // re-query: window 1 still present
            .success(PsCommandResult(exitCode: 0, stdout: "1||app||ps-test||t\n", stderr: "")),
            // retry close window 1 fails again
            .failure(PsCoreError(category: .command, message: "close command failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
        // 1 list-windows + 1 close attempt + 1 re-query + 1 retry close = 4 calls
        XCTAssertEqual(runner.calls.count, 4)
    }

    func testCloseWorkspaceRetriesTransientMissAndSucceeds() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // First list-windows: 3 windows
            .success(PsCommandResult(exitCode: 0, stdout: "1||app||ps-test||t\n2||app||ps-test||t\n3||app||ps-test||t\n", stderr: "")),
            // close window 1 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // close window 2 fails (transient)
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "window gone")),
            // close window 3 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // Re-query: window 2 is gone (only window 1 and 3 remain, already closed)
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isSuccess, "Should succeed when transient miss disappears on re-query")
        // 1 list + 3 close + 1 re-query = 5 calls
        XCTAssertEqual(runner.calls.count, 5)
    }

    func testCloseWorkspaceRetryFailsWithWindowIdsInError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // First list-windows: 3 windows
            .success(PsCommandResult(exitCode: 0, stdout: "1||app||ps-test||t\n2||app||ps-test||t\n3||app||ps-test||t\n", stderr: "")),
            // close window 1 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // close window 2 fails
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "stuck")),
            // close window 3 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // Re-query: window 2 is still present
            .success(PsCommandResult(exitCode: 0, stdout: "2||app||ps-test||t\n", stderr: "")),
            // Retry close window 2 fails again
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "still stuck")),
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("[2]"), "Error should include failing window ID 2, got: \(error.message)")
        }
        // 1 list + 3 close + 1 re-query + 1 retry close = 6 calls
        XCTAssertEqual(runner.calls.count, 6)
    }

    func testCloseWorkspaceReturnsOriginalErrorWhenReQueryFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // First list-windows: 2 windows
            .success(PsCommandResult(exitCode: 0, stdout: "1||app||ps-test||t\n2||app||ps-test||t\n", stderr: "")),
            // close window 1 fails
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "fail")),
            // close window 2 succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // Re-query fails (AeroSpace timeout/breaker)
            .failure(PsCoreError(category: .command, message: "aerospace timeout")),
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.closeWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("[1]"), "Error should include failing window ID 1, got: \(error.message)")
        }
        // 1 list + 2 close + 1 re-query = 4 calls
        XCTAssertEqual(runner.calls.count, 4)
    }
}
