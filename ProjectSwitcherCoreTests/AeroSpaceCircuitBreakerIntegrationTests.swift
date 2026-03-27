import XCTest
@testable import ProjectSwitcherCore

final class AeroSpaceCircuitBreakerIntegrationTests: XCTestCase {

    func testTimeoutTripsCircuitBreaker() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call times out
        runner.results = [
            .failure(
                CircuitBreakerRecoveryTestValues.timeoutError(
                    command: "aerospace list-workspaces --all",
                    timeoutSeconds: 5
                )
            )
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker
        )

        let result1 = aero.getWorkspaces()
        if case .failure = result1 {} else {
            XCTFail("Expected failure from timeout")
        }

        // Second call should fail fast without hitting the runner
        runner.results = []
        let result2 = aero.getWorkspaces()
        assertBreakerOpenFailure(result2)

        // Runner should only have been called once (the first timeout)
        XCTAssertEqual(runner.calls.count, 1)
    }

    func testNonTimeoutErrorDoesNotTripBreaker() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call fails but not a timeout
        runner.results = [
            .failure(PsCoreError(message: "Executable not found: aerospace")),
            // Second call succeeds
            .success(PsCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: ""))
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker
        )

        let result1 = aero.getWorkspaces()
        if case .failure = result1 {} else {
            XCTFail("Expected failure")
        }

        // Breaker should still be closed, second call goes through
        let result2 = aero.getWorkspaces()
        if case .success(let workspaces) = result2 {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success on second call")
        }
        XCTAssertEqual(runner.calls.count, 2)
    }

    func testLegacyTimeoutMessageStillTripsBreaker() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // Legacy fixture without structured reason should still trip via message fallback.
        runner.results = [
            .failure(PsCoreError(message: "Command timed out after 5.0s: aerospace list-workspaces --all"))
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker
        )

        _ = aero.getWorkspaces()
        XCTAssertFalse(breaker.shouldAllow())
    }

    func testSuccessAfterCooldownResetsBreaker() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 0.05)

        // Timeout trips the breaker
        runner.results = [
            .failure(
                CircuitBreakerRecoveryTestValues.timeoutError(
                    command: "aerospace list-workspaces --all",
                    timeoutSeconds: 5
                )
            )
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker
        )

        _ = aero.getWorkspaces()
        XCTAssertFalse(breaker.shouldAllow())

        // Wait for cooldown
        Thread.sleep(forTimeInterval: 0.1)

        // Next call should go through and succeed
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "ws-1\n", stderr: ""))
        ]
        let result = aero.getWorkspaces()
        if case .success(let workspaces) = result {
            XCTAssertEqual(workspaces, ["ws-1"])
        } else {
            XCTFail("Expected success after cooldown")
        }

        XCTAssertEqual(breaker.currentState, .closed)
    }

    func testStartResetsCircuitBreaker() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // Trip the breaker
        breaker.recordTimeout()
        XCTAssertFalse(breaker.shouldAllow())

        // Simulate start(): open -a AeroSpace succeeds, then isCliAvailable probe succeeds
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),  // open -a AeroSpace
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))   // aerospace --help (readiness)
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            startupTimeoutSeconds: 1.0,
            readinessCheckInterval: 0.05
        )

        // start() runs on a background thread (guard !Thread.isMainThread)
        let expectation = expectation(description: "start completes")
        var startResult: Result<Void, PsCoreError>?
        DispatchQueue.global().async {
            startResult = aero.start()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)

        if case .success = startResult {} else {
            XCTFail("Expected start to succeed, got: \(String(describing: startResult))")
        }

        // Breaker should be closed after start
        XCTAssertTrue(breaker.shouldAllow())
    }

    func testStartReadinessTimeoutTripsBreakerWhenNotRecovering() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .failure(CircuitBreakerRecoveryTestValues.timeoutError(command: "aerospace --help"))
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker,
            startupTimeoutSeconds: 0.3,
            readinessCheckInterval: 0.1
        )

        let completed = expectation(description: "start completes off-main")
        var result: Result<Void, PsCoreError>?
        DispatchQueue.global(qos: .userInitiated).async {
            result = aero.start()
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5)

        guard case .failure = result else {
            XCTFail("Expected start readiness timeout failure, got: \(String(describing: result))")
            return
        }
        XCTAssertFalse(breaker.shouldAllow(), "Readiness timeout should trip the breaker outside recovery")
        XCTAssertEqual(
            runner.calls,
            [
                CircuitBreakerMockCommandRunner.Call(
                    executable: "open",
                    arguments: ["-a", "AeroSpace"],
                    timeoutSeconds: 10
                ),
                CircuitBreakerMockCommandRunner.Call(
                    executable: "aerospace",
                    arguments: ["--help"],
                    timeoutSeconds: 2
                )
            ],
            "start() should issue exactly open + one readiness probe command before failing fast."
        )
    }

    func testCascadePreventionMultipleMethods() {
        let runner = CircuitBreakerMockCommandRunner()
        let breaker = AeroSpaceCircuitBreaker(cooldownSeconds: 60)

        // First call times out
        runner.results = [
            .failure(
                CircuitBreakerRecoveryTestValues.timeoutError(
                    command: "aerospace list-workspaces --focused",
                    timeoutSeconds: 5
                )
            )
        ]
        let aero = PsAeroSpace(
            commandRunner: runner,
            appDiscovery: CircuitBreakerStubAppDiscovery(),
            circuitBreaker: breaker
        )

        // Trip the breaker via listWorkspacesFocused
        _ = aero.listWorkspacesFocused()

        // All subsequent methods should fail fast without hitting the runner
        runner.results = []

        let r1 = aero.getWorkspaces()
        let r2 = aero.listWindowsFocusedMonitor()
        let r3 = aero.focusWorkspace(name: "test")
        let r4 = aero.isCliAvailable()

        assertBreakerOpenFailure(r1)
        assertBreakerOpenFailure(r2)
        assertBreakerOpenFailure(r3)

        XCTAssertFalse(r4) // isCliAvailable returns false, doesn't expose error

        // Only 1 actual command was sent to the runner
        XCTAssertEqual(runner.calls.count, 1)
    }

    private func assertBreakerOpenFailure<T>(
        _ result: Result<T, PsCoreError>,
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
