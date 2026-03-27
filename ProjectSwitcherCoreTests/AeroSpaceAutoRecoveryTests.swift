import XCTest
@testable import ProjectSwitcherCore

// MARK: - Auto-Recovery Integration Tests

final class AeroSpaceAutoRecoveryTests: XCTestCase {
    private let mainThreadFailFastUpperBoundSeconds: TimeInterval = 2.5

    /// When breaker is open and process is dead, recovery should restart AeroSpace and retry.
    func testAutoRecoveryWhenProcessDeadSkipsTerminateAndRestarts() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        breaker.recordTimeout()

        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // open -a AeroSpace
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // aerospace list-workspaces --focused (readiness)
            .success(PsCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: "")) // retried getWorkspaces
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)

        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after dead-process recovery, got: \(result)")
        }

        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10),
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("aerospace", ["list-workspaces", "--all"], timeoutSeconds: 5)
            ]
        )
        XCTAssertEqual(breaker.currentState, .closed)
    }

    /// Readiness probe timeouts during start must not trigger nested recovery attempts.
    func testAutoRecoveryReadinessTimeoutDoesNotReenterRecovery() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        breaker.recordTimeout()

        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // open -a AeroSpace
            .failure(CircuitBreakerRecoveryTestValues.timeoutError(command: "aerospace --help")), // readiness probe #1
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // readiness probe #2
            .success(PsCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: "")) // retried getWorkspaces
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)

        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after readiness-timeout retry, got: \(result)")
        }

        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10),
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("aerospace", ["list-workspaces", "--all"], timeoutSeconds: 5)
            ]
        )
        XCTAssertEqual(breaker.currentState, .closed)
        XCTAssertFalse(breaker.isRecoveryInProgress)
    }

    /// When processChecker is nil, no recovery is attempted.
    func testNoRecoveryWhenProcessCheckerIsNil() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        breaker.recordTimeout()

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker
        )

        let result = aero.getWorkspaces()
        assertBreakerOpenFailure(result)

        XCTAssertTrue(runner.calls.isEmpty)
    }

    /// Running + responsive should skip termination and restart.
    func testAutoRecoveryRunningButResponsiveDoesNotTerminateProcess() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // aerospace list-workspaces --focused probe
            .success(PsCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: "")) // retried getWorkspaces
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)

        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after responsive-process recovery, got: \(result)")
        }

        XCTAssertEqual(processChecker.terminateCalls, 0, "Responsive process should not be terminated")
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("aerospace", ["list-workspaces", "--all"], timeoutSeconds: 5)
            ]
        )
        XCTAssertEqual(breaker.currentState, .closed)
    }

    /// Running + unresponsive should terminate, then restart, then retry.
    func testAutoRecoveryRunningAndUnresponsiveTerminatesThenRestarts() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .failure(CircuitBreakerRecoveryTestValues.timeoutError(command: "aerospace list-workspaces --focused")), // aerospace list-workspaces --focused probe
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // open -a AeroSpace
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // aerospace list-workspaces --focused (readiness)
            .success(PsCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: "")) // retried getWorkspaces
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)

        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after unresponsive-process recovery, got: \(result)")
        }

        XCTAssertEqual(processChecker.terminateCalls, 1, "Unresponsive process should be terminated")
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertEqual(processChecker.terminateBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10),
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("aerospace", ["list-workspaces", "--all"], timeoutSeconds: 5)
            ]
        )
        XCTAssertEqual(breaker.currentState, .closed)
    }

    /// Running + unresponsive must fail fast when checker cannot terminate.
    func testAutoRecoveryRunningAndUnresponsiveWithoutTerminatorFailsWithDetail() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerQueryOnlyProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .failure(CircuitBreakerRecoveryTestValues.timeoutError(command: "aerospace list-workspaces --focused"))
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)
        assertBreakerOpenFailure(result)
        if case .failure(let error) = result {
            XCTAssertEqual(
                error.detail,
                CircuitBreakerRecoveryTestValues.terminateUnsupportedDetail
            )
        }

        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        assertCommandSequence(
            runner,
            equals: [commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)]
        )
        if case .open = breaker.currentState {
            // Expected: missing terminate capability keeps breaker open for fail-fast behavior.
        } else {
            XCTFail("Expected breaker to remain open when terminate capability is unavailable")
        }
        XCTAssertFalse(breaker.isRecoveryInProgress)
    }

    /// Legacy timeout-message probe failures should still trigger terminate/restart recovery.
    func testAutoRecoveryLegacyTimeoutProbeStillTerminatesThenRestarts() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .failure(PsCoreError(message: "Command timed out after 2.0s: aerospace list-workspaces --focused")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: ""))
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)

        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after legacy-timeout recovery, got: \(result)")
        }

        XCTAssertEqual(processChecker.terminateCalls, 1)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertEqual(processChecker.terminateBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10),
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("aerospace", ["list-workspaces", "--all"], timeoutSeconds: 5)
            ]
        )
        XCTAssertEqual(breaker.currentState, .closed)
    }

    /// Terminate failure should fail recovery and must not restart.
    func testAutoRecoveryTerminateFailureReturnsBreakerErrorAndSkipsRestart() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(
            isRunning: true,
            terminateResult: false
        )

        breaker.recordTimeout()

        runner.results = [
            .failure(CircuitBreakerRecoveryTestValues.timeoutError(command: "aerospace list-workspaces --focused")) // aerospace list-workspaces --focused probe
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)
        assertBreakerOpenFailure(result)
        if case .failure(let error) = result {
            XCTAssertEqual(
                error.detail,
                CircuitBreakerRecoveryTestValues.terminateFailedDetail
            )
        }

        XCTAssertEqual(processChecker.terminateCalls, 1)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertEqual(processChecker.terminateBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)]
        )
        if case .open = breaker.currentState {
            // Expected: failed terminate keeps breaker open for fail-fast behavior.
        } else {
            XCTFail("Expected breaker to remain open after terminate failure")
        }
        XCTAssertFalse(breaker.isRecoveryInProgress)
    }

    /// Non-timeout probe failures must fail recovery without terminating the process.
    func testAutoRecoveryNonTimeoutProbeFailureSkipsTerminateAndReturnsDetail() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .failure(PsCoreError(message: "Executable not found: aerospace")) // aerospace list-workspaces --focused probe
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)
        assertBreakerOpenFailure(result)
        if case .failure(let error) = result {
            XCTAssertEqual(
                error.detail,
                CircuitBreakerRecoveryTestValues.nonTimeoutProbeFailureDetail
            )
        }

        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)]
        )
        if case .open = breaker.currentState {
            // Expected: failed recovery keeps breaker open for fail-fast behavior.
        } else {
            XCTFail("Expected breaker to remain open after non-timeout probe failure")
        }
        XCTAssertFalse(breaker.isRecoveryInProgress)
    }

    /// Non-zero probe exits must fail recovery without terminating the process.
    func testAutoRecoveryNonZeroProbeExitSkipsTerminateAndReturnsDetail() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .success(PsCommandResult(exitCode: 3, stdout: "", stderr: "socket unavailable")) // aerospace list-workspaces --focused probe
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)
        assertBreakerOpenFailure(result)
        if case .failure(let error) = result {
            XCTAssertEqual(
                error.detail,
                CircuitBreakerRecoveryTestValues.nonZeroProbeExitDetail(exitCode: 3)
            )
        }

        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)]
        )
        if case .open = breaker.currentState {
            // Expected: failed recovery keeps breaker open for fail-fast behavior.
        } else {
            XCTFail("Expected breaker to remain open after non-zero probe exit")
        }
        XCTAssertFalse(breaker.isRecoveryInProgress)
    }

    /// When start() fails during recovery, return breaker error and keep retry budget.
    func testRecoveryFailureFallsBackToBreakerError() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        breaker.recordTimeout()

        runner.results = [
            .failure(PsCoreError(message: "Executable not found: open"))
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let result = runGetWorkspacesOffMain(aero)
        assertBreakerOpenFailure(result)

        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10)
            ]
        )
        XCTAssertTrue(breaker.shouldAttemptRecovery())
    }

    /// Main-thread callers should fail fast while background recovery completes.
    func testMainThreadRecoveryFailsFastAndRecoversAsync() {
        XCTAssertTrue(Thread.isMainThread, "This test must execute on the main thread.")

        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        breaker.recordTimeout()

        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // open -a AeroSpace
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")) // aerospace list-workspaces --focused (readiness)
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let startedAt = Date()
        let result = aero.getWorkspaces()
        assertFailFastLatency(Date().timeIntervalSince(startedAt))
        assertBreakerOpenFailure(result)

        waitUntil(description: "main-thread async recovery completes") {
            breaker.currentState == .closed &&
                !breaker.isRecoveryInProgress &&
                runner.calls.count == 2
        }

        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10),
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)
            ]
        )
    }

    /// Main-thread callers should fail fast while async recovery handles start() failure.
    func testMainThreadRecoveryFailsFastWhenAsyncStartFails() {
        XCTAssertTrue(Thread.isMainThread, "This test must execute on the main thread.")

        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        breaker.recordTimeout()

        runner.results = [
            .failure(PsCoreError(message: "Executable not found: open"))
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let startedAt = Date()
        let result = aero.getWorkspaces()
        assertFailFastLatency(Date().timeIntervalSince(startedAt))
        assertBreakerOpenFailure(result)

        waitUntil(description: "main-thread async start-failure recovery completes") {
            !breaker.isRecoveryInProgress && runner.calls.count == 1
        }

        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10)
            ]
        )
        if case .open = breaker.currentState {
            // Expected: failed background start keeps breaker open for fail-fast behavior.
        } else {
            XCTFail("Expected breaker to remain open after async start failure")
        }
    }

    /// Main-thread hung-process recovery should terminate in background before restart.
    func testMainThreadRecoveryTerminatesHungProcessAsync() {
        XCTAssertTrue(Thread.isMainThread, "This test must execute on the main thread.")

        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .failure(CircuitBreakerRecoveryTestValues.timeoutError(command: "aerospace list-workspaces --focused")), // aerospace list-workspaces --focused probe
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")), // open -a AeroSpace
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")) // aerospace list-workspaces --focused (readiness)
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let startedAt = Date()
        let result = aero.getWorkspaces()
        assertFailFastLatency(Date().timeIntervalSince(startedAt))
        assertBreakerOpenFailure(result)

        waitUntil(description: "main-thread hung-process recovery completes") {
            breaker.currentState == .closed &&
                !breaker.isRecoveryInProgress &&
                processChecker.terminateCalls == 1 &&
                runner.calls.count == 3
        }

        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertEqual(processChecker.terminateBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2),
                commandCall("open", ["-a", "AeroSpace"], timeoutSeconds: 10),
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)
            ]
        )
    }

    /// Main-thread responsive-process recovery should close breaker without restart.
    func testMainThreadRecoveryResponsiveProcessClosesBreaker() {
        XCTAssertTrue(Thread.isMainThread, "This test must execute on the main thread.")

        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: true)

        breaker.recordTimeout()

        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")) // aerospace list-workspaces --focused probe
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let startedAt = Date()
        let result = aero.getWorkspaces()
        assertFailFastLatency(Date().timeIntervalSince(startedAt))
        assertBreakerOpenFailure(result)

        waitUntil(description: "main-thread responsive-process recovery completes") {
            breaker.currentState == .closed &&
                !breaker.isRecoveryInProgress &&
                runner.calls.count == 1
        }

        XCTAssertEqual(processChecker.terminateCalls, 0, "Responsive process should not be terminated")
        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)
            ]
        )
    }

    /// Main-thread recovery should fail fast when terminate fails and skip restart.
    func testMainThreadRecoveryTerminateFailureFailsFastAndSkipsRestart() {
        XCTAssertTrue(Thread.isMainThread, "This test must execute on the main thread.")

        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(
            isRunning: true,
            terminateResult: false
        )

        breaker.recordTimeout()

        runner.results = [
            .failure(CircuitBreakerRecoveryTestValues.timeoutError(command: "aerospace list-workspaces --focused")) // aerospace list-workspaces --focused probe
        ]

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        let startedAt = Date()
        let result = aero.getWorkspaces()
        assertFailFastLatency(Date().timeIntervalSince(startedAt))
        assertBreakerOpenFailure(result)

        waitUntil(description: "main-thread terminate-failure recovery completes") {
            !breaker.isRecoveryInProgress &&
                processChecker.terminateCalls == 1 &&
                runner.calls.count == 1
        }

        XCTAssertEqual(processChecker.isApplicationRunningBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertEqual(processChecker.terminateBundleIdentifiers, [PsAeroSpace.bundleIdentifier])
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        assertCommandSequence(
            runner,
            equals: [
                commandCall("aerospace", ["list-workspaces", "--focused"], timeoutSeconds: 2)
            ]
        )
        if case .open = breaker.currentState {
            // Expected: failed terminate keeps breaker open for fail-fast behavior.
        } else {
            XCTFail("Expected breaker to remain open after terminate failure")
        }
    }

    /// After maxRecoveryAttempts failed recoveries, no more attempts are made.
    func testRecoveryExhaustedAfterMaxAttempts() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        for _ in 0..<AeroSpaceCircuitBreaker.maxRecoveryAttempts {
            breaker.recordTimeout()
            _ = breaker.beginRecovery()
            breaker.endRecovery(success: false)
        }

        breaker.recordTimeout()

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker
        )

        let result = aero.getWorkspaces()
        assertBreakerOpenFailure(result)

        XCTAssertTrue(runner.calls.isEmpty)
    }

    /// Breaker-open calls should fail fast when recovery is already in progress.
    func testRecoveryBlockedWhenAlreadyInProgressReturnsBreakerOpenWithoutNewAttempt() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)
        let processChecker = CircuitBreakerMockProcessChecker(isRunning: false)

        breaker.recordTimeout()
        XCTAssertTrue(breaker.beginRecovery())

        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            processChecker: processChecker
        )

        let result = runGetWorkspacesOffMain(aero)
        assertBreakerOpenFailure(result)

        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(processChecker.isApplicationRunningBundleIdentifiers.isEmpty)
        XCTAssertTrue(processChecker.terminateBundleIdentifiers.isEmpty)
        XCTAssertEqual(processChecker.terminateCalls, 0)
        XCTAssertTrue(processChecker.invalidBundleIdentifiers.isEmpty)
        XCTAssertTrue(breaker.isRecoveryInProgress)
        XCTAssertFalse(breaker.shouldAttemptRecovery())

        breaker.endRecovery(success: false)
        XCTAssertTrue(
            breaker.shouldAttemptRecovery(),
            "Recovery should become eligible again after current attempt ends (not exhausted)."
        )
    }

    // MARK: - Helpers

    private func runGetWorkspacesOffMain(
        _ aero: PsAeroSpace,
        timeout: TimeInterval = 5
    ) -> Result<[String], PsCoreError> {
        let completed = expectation(description: "off-main getWorkspaces completes")
        var result: Result<[String], PsCoreError>?

        DispatchQueue.global(qos: .userInitiated).async {
            result = aero.getWorkspaces()
            completed.fulfill()
        }

        wait(for: [completed], timeout: timeout)
        guard let result else {
            XCTFail("Expected off-main getWorkspaces to produce a result")
            return .failure(PsCoreError(message: "off-main test harness did not capture a result"))
        }
        return result
    }

    private func waitUntil(
        description: String,
        timeout: TimeInterval = 5.0,
        condition: @escaping () -> Bool
    ) {
        let predicate = NSPredicate { _, _ in condition() }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: NSObject())
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Timed out waiting for \(description)")
    }

    private func assertCommandSequence(
        _ runner: CircuitBreakerMockCommandRunner,
        equals expected: [CircuitBreakerMockCommandRunner.Call],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(runner.calls, expected, file: file, line: line)
    }

    private func commandCall(
        _ executable: String,
        _ arguments: [String],
        timeoutSeconds: TimeInterval?
    ) -> CircuitBreakerMockCommandRunner.Call {
        CircuitBreakerMockCommandRunner.Call(
            executable: executable,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func assertFailFastLatency(
        _ elapsedSeconds: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThan(
            elapsedSeconds,
            mainThreadFailFastUpperBoundSeconds,
            "Expected main-thread recovery to fail fast (<\(mainThreadFailFastUpperBoundSeconds)s), but took \(elapsedSeconds)s.",
            file: file,
            line: line
        )
    }

    private func assertBreakerOpenFailure(
        _ result: Result<[String], PsCoreError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error) = result else {
            XCTFail("Expected circuit-breaker-open failure, got success.", file: file, line: line)
            return
        }
        XCTAssertEqual(error.reason, .circuitBreakerOpen, file: file, line: line)
        XCTAssertTrue(error.isBreakerOpen, file: file, line: line)
    }
}
