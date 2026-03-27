import XCTest
@testable import ProjectSwitcherCore

// MARK: - Windows parsing

final class AeroSpaceWindowsTests: XCTestCase {
    func testFocusedWindowSucceedsWhenExactlyOneFocusedWindow() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "42||app||main||title\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusedWindow()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let window):
            XCTAssertEqual(window.windowId, 42)
        }
    }

    func testFocusedWindowFailsWhenZeroWindowsFocused() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusedWindow()

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsFocusedMonitorFailsOnParseError() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "not a window line\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        XCTAssertTrue(result.isFailure)
    }

    func testFocusWindowRejectsNonPositiveWindowId() {
        let runner = FallbackMockCommandRunner()
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWindow(windowId: 0)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testFocusWindowReturnsFailureWhenRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWindow(windowId: 42)

        XCTAssertTrue(result.isFailure)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["focus", "--window-id", "42"])
    }

    func testFocusWindowReturnsFailureOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 7, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWindow(windowId: 42)

        XCTAssertTrue(result.isFailure)
    }

    func testFocusWindowSucceedsOnZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusWindow(windowId: 42)

        XCTAssertTrue(result.isSuccess)
    }

    func testFocusedWindowPropagatesRunnerFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusedWindow()

        XCTAssertTrue(result.isFailure)
    }

    func testFocusedWindowFailsWhenFocusedQueryExitsNonZero() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 3, stdout: "", stderr: "focused query failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.focusedWindow()

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsFocusedMonitorFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 9, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsOnFocusedMonitorFailsWhenRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsOnFocusedMonitorFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 4, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsOnFocusedMonitor(appBundleId: "com.app")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsWorkspaceFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 5, stdout: "", stderr: "bad"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsWorkspace(workspace: "main")

        XCTAssertTrue(result.isFailure)
    }

    func testListWindowsFocusedMonitorSkipsEmptyOutputLines() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "\n42||app||main||title\n\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
            XCTAssertEqual(windows.first?.windowId, 42)
        }
    }

    func testListWindowsFocusedMonitorFailsWhenWindowIdIsNotInteger() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "abc||app||main||title\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listWindowsFocusedMonitor()

        XCTAssertTrue(result.isFailure)
    }
}

final class AeroSpaceFocusedMonitorConvenienceTests: XCTestCase {

    func testListVSCodeWindowsOnFocusedMonitorUsesBundleIdFilter() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "1||com.microsoft.VSCode||main||title\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listVSCodeWindowsOnFocusedMonitor()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--app-bundle-id"))
        XCTAssertTrue(runner.calls[0].arguments.contains("com.microsoft.VSCode"))
    }

    func testListChromeWindowsOnFocusedMonitorUsesBundleIdFilter() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "2||com.google.Chrome||main||title\n", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listChromeWindowsOnFocusedMonitor()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertTrue(runner.calls[0].arguments.contains("--app-bundle-id"))
        XCTAssertTrue(runner.calls[0].arguments.contains("com.google.Chrome"))
    }
}

final class AeroSpaceListAllWindowsTests: XCTestCase {
    func testListAllWindowsPropagatesWorkspaceQueryFailure() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "list-workspaces failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listAllWindows()

        XCTAssertTrue(result.isFailure)
    }

    func testListAllWindowsSkipsWorkspaceFailuresAndAggregatesSuccessfulResults() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // getWorkspaces
            .success(PsCommandResult(exitCode: 0, stdout: "main\nps-two\n", stderr: "")),
            // listWindowsWorkspace(main)
            .success(PsCommandResult(exitCode: 0, stdout: "1||com.app||main||one\n", stderr: "")),
            // listWindowsWorkspace(ps-two) fails and should be skipped
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "workspace unavailable"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.listAllWindows()

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let windows):
            XCTAssertEqual(windows.count, 1)
            XCTAssertEqual(windows[0].workspace, "main")
        }
    }
}
