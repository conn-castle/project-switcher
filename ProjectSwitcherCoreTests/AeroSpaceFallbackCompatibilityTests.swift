import XCTest
@testable import ProjectSwitcherCore

// MARK: - checkCompatibility

final class AeroSpaceCompatibilityTests: XCTestCase {
    func testCheckCompatibilitySucceedsWhenAllFlagsPresent() {
        let runner = FallbackMockCommandRunner()
        // Use keyed results: concurrent execution means FIFO order is non-deterministic
        runner.keyedResults = [
            "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "--all --focused --format", stderr: "")),
            "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(PsCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 6)
    }

    func testCheckCompatibilityAcceptsFlagsFromStdoutAndStderr() {
        let runner = FallbackMockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "--all --focused --format")),
            "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "--monitor", stderr: "--workspace --focused --app-bundle-id --format")),
            "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(PsCommandResult(exitCode: 0, stdout: "--window-id --boundaries dfs-next", stderr: "--boundaries-action dfs-prev")),
            "close": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 6)
    }

    func testCheckCompatibilityFailsWhenFlagsMissing() {
        let runner = FallbackMockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "--all", stderr: "")),
            "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "focus": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "close": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.checkCompatibility()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .validation)
            XCTAssertEqual(error.message, "AeroSpace CLI compatibility check failed.")
            XCTAssertNotNil(error.detail)
        }
    }

    func testCheckCompatibilityFailsWhenHelpCommandRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "--all --focused --format", stderr: "")),
            "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(PsCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isFailure)
        if case .failure(let error) = result {
            XCTAssertTrue(error.detail?.contains("aerospace close --help failed: runner failed") ?? false)
        }
    }

    func testCheckCompatibilityFailsWhenHelpCommandExitsNonZero() {
        let runner = FallbackMockCommandRunner()
        runner.keyedResults = [
            "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "--all --focused --format", stderr: "")),
            "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(PsCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(PsCommandResult(exitCode: 2, stdout: "", stderr: "unknown option"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.checkCompatibility()

        XCTAssertTrue(result.isFailure)
        if case .failure(let error) = result {
            XCTAssertTrue(error.detail?.contains("aerospace close --help failed") ?? false)
        }
    }

    func testCheckCompatibilityFailureDetailIsSorted() {
        let runner = FallbackMockCommandRunner()
        // Two commands fail: "close" (alphabetically first) and "list-workspaces"
        runner.keyedResults = [
            "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "--all", stderr: "")),
            "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
            "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
            "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
            "focus": .success(PsCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
            "close": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.checkCompatibility()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            let lines = error.detail?.components(separatedBy: "\n") ?? []
            XCTAssertEqual(lines.count, 2)
            // Sorted: "close" before "list-workspaces"
            XCTAssertTrue(lines[0].contains("close"), "First failure should be 'close' (alphabetical)")
            XCTAssertTrue(lines[1].contains("list-workspaces"), "Second failure should be 'list-workspaces' (alphabetical)")
        }
    }

    func testCheckCompatibilityConcurrentCallsAreAllRecorded() {
        // Run compatibility check multiple times to exercise thread-safety
        for _ in 0..<10 {
            let runner = FallbackMockCommandRunner()
            runner.keyedResults = [
                "list-workspaces": .success(PsCommandResult(exitCode: 0, stdout: "--all --focused --format", stderr: "")),
                "list-windows": .success(PsCommandResult(exitCode: 0, stdout: "--monitor --workspace --focused --app-bundle-id --format", stderr: "")),
                "summon-workspace": .success(PsCommandResult(exitCode: 0, stdout: "ok", stderr: "")),
                "move-node-to-workspace": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: "")),
                "focus": .success(PsCommandResult(exitCode: 0, stdout: "--window-id --boundaries --boundaries-action dfs-next dfs-prev", stderr: "")),
                "close": .success(PsCommandResult(exitCode: 0, stdout: "--window-id", stderr: ""))
            ]
            let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

            let result = aero.checkCompatibility()

            XCTAssertTrue(result.isSuccess, "Iteration should succeed")
            // All 6 commands should be recorded regardless of execution order
            XCTAssertEqual(runner.calls.count, 6, "All 6 help checks should be recorded")
            let commands = Set(runner.calls.map { $0.arguments.first ?? "" })
            XCTAssertEqual(commands, [
                "list-workspaces", "list-windows", "summon-workspace",
                "move-node-to-workspace", "focus", "close"
            ], "All 6 unique commands should appear")
        }
    }
}
