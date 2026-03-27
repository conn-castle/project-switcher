import XCTest
@testable import ProjectSwitcherCore

final class AeroSpaceAppPathTests: XCTestCase {
    func testAppPathPrefersLaunchServicesResult() {
        let discovery = FallbackStubBundleURLAppDiscovery(
            bundleURL: URL(fileURLWithPath: "/Applications/Custom/AeroSpace.app", isDirectory: true)
        )
        let fileSystem = FallbackStubLegacyDirectoryFileSystem(existingDirectories: [])
        let aero = PsAeroSpace(commandRunner: FallbackMockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertEqual(aero.appPath, "/Applications/Custom/AeroSpace.app")
    }

    func testAppPathFallsBackToLegacyDirectoryWhenLaunchServicesHasNoMatch() {
        let discovery = FallbackStubBundleURLAppDiscovery(bundleURL: nil)
        let fileSystem = FallbackStubLegacyDirectoryFileSystem(existingDirectories: ["/Applications/AeroSpace.app"])
        let aero = PsAeroSpace(commandRunner: FallbackMockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertEqual(aero.appPath, "/Applications/AeroSpace.app")
        XCTAssertTrue(aero.isAppInstalled())
    }

    func testAppPathReturnsNilWhenNoInstallLocationExists() {
        let discovery = FallbackStubBundleURLAppDiscovery(bundleURL: nil)
        let fileSystem = FallbackStubLegacyDirectoryFileSystem(existingDirectories: [])
        let aero = PsAeroSpace(commandRunner: FallbackMockCommandRunner(), appDiscovery: discovery, fileSystem: fileSystem)

        XCTAssertNil(aero.appPath)
        XCTAssertFalse(aero.isAppInstalled())
    }
}

// MARK: - focusWorkspace fallback

final class AeroSpaceFocusWorkspaceFallbackTests: XCTestCase {

    func testFocusWorkspaceSucceedsWithSummonWorkspace() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // summon-workspace succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ps-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ps-test"])
    }

    func testFocusWorkspaceFallsBackToWorkspaceOnIncompatibility() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // summon-workspace fails with compatibility error
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            // workspace fallback succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ps-test")

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ps-test"])
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ps-test"])
    }

    func testFocusWorkspaceDoesNotFallBackOnOperationalError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // summon-workspace fails with an operational error (not a compatibility issue)
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "workspace 'ps-test' not found"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
        // Should NOT have attempted the fallback
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["summon-workspace", "ps-test"])
    }

    func testFocusWorkspaceRejectsEmptyName() {
        let runner = FallbackMockCommandRunner()
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "   ")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testFocusWorkspaceFallbackPropagatesRunnerFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            .failure(PsCoreError(category: .command, message: "workspace command failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ps-test"])
    }

    func testFocusWorkspaceFallbackReturnsFailureOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "unknown command: summon-workspace")),
            .success(PsCommandResult(exitCode: 2, stdout: "", stderr: "workspace missing"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWorkspace(name: "ps-test")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertEqual(runner.calls[1].arguments, ["workspace", "ps-test"])
    }
}

// MARK: - listWindowsForApp fallback

final class AeroSpaceListWindowsFallbackTests: XCTestCase {

    func testListWindowsForAppSucceedsWithGlobalSearch() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // Global list-windows succeeds
            .success(PsCommandResult(
                exitCode: 0,
                stdout: "42||com.microsoft.VSCode||ps-test||PS:test - main.swift",
                stderr: ""
            ))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        switch result {
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
            XCTAssertEqual(windows[0].windowId, 42)
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }
        XCTAssertEqual(runner.calls.count, 1)
        // Global search: no --monitor flag
        XCTAssertFalse(runner.calls[0].arguments.contains("--monitor"))
    }

    func testListWindowsForAppFallsBackToFocusedMonitorOnIncompatibility() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // Global search fails — AeroSpace requires --monitor/--focused/--all/--workspace
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")),
            // Fallback to focused monitor succeeds
            .success(PsCommandResult(
                exitCode: 0,
                stdout: "42||com.microsoft.VSCode||ps-test||PS:test - main.swift",
                stderr: ""
            ))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        switch result {
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }
        XCTAssertEqual(runner.calls.count, 2)
        // Second call should include --monitor focused
        XCTAssertTrue(runner.calls[1].arguments.contains("--monitor"))
        XCTAssertTrue(runner.calls[1].arguments.contains("focused"))
    }

    func testListWindowsForAppDoesNotFallBackOnOperationalError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // Global search fails with an operational error
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "permission denied"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testListWindowsForAppPropagatesRunnerFailureWithoutFallback() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner unavailable"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsForApp(bundleId: "com.microsoft.VSCode")

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }
}

// MARK: - moveWindowToWorkspace fallback

final class AeroSpaceMoveWindowFallbackTests: XCTestCase {

    func testMoveWindowSucceedsWithFocusFollows() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // move-node-to-workspace --focus-follows-window succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowFallsBackToPlainMoveOnIncompatibility() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // --focus-follows-window not supported
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "unknown option '--focus-follows-window'")),
            // Plain move succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
        XCTAssertFalse(runner.calls[1].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowDoesNotFallBackOnOperationalError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // --focus-follows-window command fails with an operational error
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "window 42 not found"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isFailure)
        // Should NOT have attempted the fallback
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testMoveWindowWithoutFocusFollowsSkipsFallbackPath() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // Plain move succeeds (no --focus-follows-window attempted)
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertFalse(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowRejectsEmptyWorkspaceName() {
        let runner = FallbackMockCommandRunner()
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: " ", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testMoveWindowRejectsNonPositiveWindowId() {
        let runner = FallbackMockCommandRunner()
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 0, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testMoveWindowFocusFollowsPropagatesRunnerFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 42, focusFollows: true)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--focus-follows-window"))
    }

    func testMoveWindowWithoutFocusFollowsPropagatesRunnerFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testMoveWindowWithoutFocusFollowsFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 5, stdout: "", stderr: "bad move"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.moveWindowToWorkspace(workspace: "ps-test", windowId: 42, focusFollows: false)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
    }
}

