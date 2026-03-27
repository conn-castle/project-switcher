import XCTest
@testable import ProjectSwitcherCore

// MARK: - installViaHomebrew

final class AeroSpaceInstallViaHomebrewTests: XCTestCase {
    func testInstallViaHomebrewSucceedsOnZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.installViaHomebrew()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "brew")
    }

    func testInstallViaHomebrewFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "boom"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.installViaHomebrew()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .command)
            XCTAssertTrue(error.message.contains("brew install --cask nikitabobko/tap/aerospace failed"))
        }
    }

    func testInstallViaHomebrewFailsWhenRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.installViaHomebrew()

        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - reloadConfig

final class AeroSpaceReloadConfigTests: XCTestCase {
    func testReloadConfigSucceedsOnZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.reloadConfig()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].arguments, ["reload-config"])
    }

    func testReloadConfigFailsOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "nope"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.reloadConfig()

        XCTAssertTrue(result.isFailure)
    }

    func testReloadConfigFailsWhenRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "runner failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.reloadConfig()

        XCTAssertTrue(result.isFailure)
    }
}

// MARK: - start

final class AeroSpaceStartTests: XCTestCase {
    func testStartFailsOnMainThread() {
        let runner = FallbackMockCommandRunner()
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let result = aero.start()

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .command)
            XCTAssertEqual(error.message, "AeroSpace start must run off the main thread.")
        }
        XCTAssertEqual(runner.calls.count, 0)
    }

    func testStartReturnsFailureWhenOpenCommandFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "open failed"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, PsCoreError>?
        var ranOnMainThread: Bool?
        DispatchQueue.global(qos: .userInitiated).async {
            ranOnMainThread = Thread.isMainThread
            result = aero.start()
            semaphore.signal()
        }
        let wait = semaphore.wait(timeout: .now() + 5)
        XCTAssertNotEqual(wait, .timedOut)
        XCTAssertEqual(ranOnMainThread, false)

        XCTAssertTrue(result?.isFailure ?? false)
        XCTAssertEqual(runner.calls.first?.executable, "open")
    }

    func testStartReturnsFailureOnNonZeroOpenExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "cannot open"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, PsCoreError>?
        var ranOnMainThread: Bool?
        DispatchQueue.global(qos: .userInitiated).async {
            ranOnMainThread = Thread.isMainThread
            result = aero.start()
            semaphore.signal()
        }
        let wait = semaphore.wait(timeout: .now() + 5)
        XCTAssertNotEqual(wait, .timedOut)
        XCTAssertEqual(ranOnMainThread, false)

        XCTAssertTrue(result?.isFailure ?? false)
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "open")
    }

    func testStartWaitsForReadinessAndSucceeds() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            // open -a AeroSpace succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            // aerospace --help not ready
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "")),
            // aerospace --help ready
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: FallbackStubAppDiscovery(),
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, PsCoreError>?
        var ranOnMainThread: Bool?
        DispatchQueue.global(qos: .userInitiated).async {
            ranOnMainThread = Thread.isMainThread
            result = aero.start()
            semaphore.signal()
        }
        let wait = semaphore.wait(timeout: .now() + 2)
        XCTAssertNotEqual(wait, .timedOut)
        XCTAssertEqual(ranOnMainThread, false)

        XCTAssertTrue(result?.isSuccess ?? false)
        XCTAssertEqual(runner.calls.count, 3)
        XCTAssertEqual(runner.calls[0].executable, "open")
        XCTAssertEqual(runner.calls[1].executable, "aerospace")
        XCTAssertEqual(runner.calls[2].executable, "aerospace")
    }

    func testStartReturnsFailureWhenReadinessTimesOut() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: FallbackStubAppDiscovery(),
            startupTimeoutSeconds: 0.1,
            readinessCheckInterval: 0.02
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Void, PsCoreError>?
        DispatchQueue.global(qos: .userInitiated).async {
            result = aero.start()
            semaphore.signal()
        }

        let wait = semaphore.wait(timeout: .now() + 2)
        XCTAssertNotEqual(wait, .timedOut)
        switch result {
        case .success:
            XCTFail("Expected startup timeout failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("did not become ready"))
        case .none:
            XCTFail("Expected result")
        }
    }
}

// MARK: - isCliAvailable

final class AeroSpaceCliAvailabilityTests: XCTestCase {
    func testIsCliAvailableFalseWhenRunnerFails() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "no aerospace"))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        XCTAssertFalse(aero.isCliAvailable())
    }

    func testIsCliAvailableFalseOnNonZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        XCTAssertFalse(aero.isCliAvailable())
    }

    func testIsCliAvailableTrueOnZeroExit() {
        let runner = FallbackMockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "usage", stderr: ""))
        ]
        let aero = PsAeroSpace(commandRunner: runner, appDiscovery: FallbackStubAppDiscovery())

        XCTAssertTrue(aero.isCliAvailable())
    }
}

