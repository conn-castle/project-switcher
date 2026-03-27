import XCTest

@testable import ProjectSwitcherAppKit

final class AppKitRunningApplicationCheckerTests: XCTestCase {
    func testIsApplicationRunningReturnsFalseForNonExistentBundleId() {
        let checker = makeChecker(
            runningApplications: { _ in [] },
            clock: TestClock()
        )
        XCTAssertFalse(checker.isApplicationRunning(bundleIdentifier: "com.projectswitcher.tests.nonexistent.bundle"))
    }

    /// Terminating a process that isn't running should return true (vacuously successful).
    func testTerminateApplicationReturnsTrueForNonExistentBundleId() {
        let checker = makeChecker(
            runningApplications: { _ in [] },
            clock: TestClock()
        )
        XCTAssertTrue(checker.terminateApplication(bundleIdentifier: "com.projectswitcher.tests.nonexistent.bundle"))
    }

    func testTerminateApplicationGracefulSuccessSkipsForceTerminate() {
        let bundleIdentifier = "com.projectswitcher.tests.graceful"
        let state = RunningState(isRunning: true)
        let clock = TestClock()
        let app = StubRunningApplication(
            onTerminate: { state.isRunning = false }
        )
        let checker = makeChecker(
            bundleIdentifier: bundleIdentifier,
            state: state,
            app: app,
            clock: clock
        )

        XCTAssertTrue(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceTerminateCalls, 0)
        XCTAssertLessThan(clock.elapsedSeconds, 0.25)
    }

    func testTerminateApplicationForceFallbackSucceeds() {
        let bundleIdentifier = "com.projectswitcher.tests.force_success"
        let state = RunningState(isRunning: true)
        let clock = TestClock()
        let app = StubRunningApplication(
            onForceTerminate: { state.isRunning = false }
        )
        let checker = makeChecker(
            bundleIdentifier: bundleIdentifier,
            state: state,
            app: app,
            clock: clock
        )

        XCTAssertTrue(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceTerminateCalls, 1)
        XCTAssertGreaterThanOrEqual(clock.elapsedSeconds, 3.0)
        XCTAssertLessThan(clock.elapsedSeconds, 3.25)
    }

    func testTerminateApplicationSkipsGracefulWaitWhenNoTerminateRequestAccepted() {
        let bundleIdentifier = "com.projectswitcher.tests.skip_graceful_wait"
        let state = RunningState(isRunning: true)
        let clock = TestClock()
        let app = StubRunningApplication(
            terminateResult: false,
            onForceTerminate: { state.isRunning = false }
        )
        let checker = makeChecker(
            bundleIdentifier: bundleIdentifier,
            state: state,
            app: app,
            clock: clock
        )

        XCTAssertTrue(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceTerminateCalls, 1)
        XCTAssertLessThan(clock.elapsedSeconds, 0.25)
    }

    func testTerminateApplicationSkipsForceWaitWhenNoForceRequestAccepted() {
        let bundleIdentifier = "com.projectswitcher.tests.skip_force_wait"
        let state = RunningState(isRunning: true)
        let clock = TestClock()
        let app = StubRunningApplication(
            forceTerminateResult: false
        )
        let checker = makeChecker(
            bundleIdentifier: bundleIdentifier,
            state: state,
            app: app,
            clock: clock
        )

        XCTAssertFalse(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceTerminateCalls, 1)
        XCTAssertGreaterThanOrEqual(clock.elapsedSeconds, 3.5)
        XCTAssertLessThan(clock.elapsedSeconds, 3.75)
    }

    func testTerminateApplicationSettleWaitCanObserveLateExitAfterRejectedForce() {
        let bundleIdentifier = "com.projectswitcher.tests.rejected_force_late_exit"
        let clock = TestClock()
        let app = StubRunningApplication(
            terminateResult: true,
            forceTerminateResult: false
        )

        let checker = makeChecker(
            runningApplications: { requestedBundleIdentifier in
                guard requestedBundleIdentifier == bundleIdentifier else { return [] }
                return clock.elapsedSeconds < 3.25 ? [app] : []
            },
            clock: clock
        )

        XCTAssertTrue(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceTerminateCalls, 1)
        XCTAssertGreaterThanOrEqual(clock.elapsedSeconds, 3.25)
        XCTAssertLessThan(clock.elapsedSeconds, 3.75)
    }

    func testTerminateApplicationBothRejectedNoExitReturnsFalseAfterSettleOnly() {
        let bundleIdentifier = "com.projectswitcher.tests.both_rejected"
        let state = RunningState(isRunning: true)
        let clock = TestClock()
        let app = StubRunningApplication(
            terminateResult: false,
            forceTerminateResult: false
        )
        let checker = makeChecker(
            bundleIdentifier: bundleIdentifier,
            state: state,
            app: app,
            clock: clock
        )

        XCTAssertFalse(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceTerminateCalls, 1)
        // Only the 0.5s settle wait is paid (graceful was skipped because terminate was rejected)
        XCTAssertGreaterThanOrEqual(clock.elapsedSeconds, 0.5)
        XCTAssertLessThan(clock.elapsedSeconds, 0.75)
    }

    func testTerminateApplicationForceFallbackFailureReturnsFalse() {
        let bundleIdentifier = "com.projectswitcher.tests.force_failure"
        let state = RunningState(isRunning: true)
        let clock = TestClock()
        let app = StubRunningApplication()
        let checker = makeChecker(
            bundleIdentifier: bundleIdentifier,
            state: state,
            app: app,
            clock: clock
        )

        XCTAssertFalse(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(app.terminateCalls, 1)
        XCTAssertEqual(app.forceTerminateCalls, 1)
        XCTAssertGreaterThanOrEqual(clock.elapsedSeconds, 5.0)
        XCTAssertLessThan(clock.elapsedSeconds, 5.25)
    }

    func testTerminateApplicationHandlesMultipleProcesses() {
        let bundleIdentifier = "com.projectswitcher.tests.multi"
        let gracefulState = RunningState(isRunning: true)
        let forceState = RunningState(isRunning: true)
        let clock = TestClock()

        let gracefulApp = StubRunningApplication(
            onTerminate: { gracefulState.isRunning = false }
        )
        let forceApp = StubRunningApplication(
            onForceTerminate: { forceState.isRunning = false }
        )

        let checker = makeChecker(
            runningApplications: { requestedBundleIdentifier in
                guard requestedBundleIdentifier == bundleIdentifier else { return [] }
                var apps: [any AppKitRunningApplication] = []
                if gracefulState.isRunning {
                    apps.append(gracefulApp)
                }
                if forceState.isRunning {
                    apps.append(forceApp)
                }
                return apps
            },
            clock: clock
        )

        XCTAssertTrue(checker.terminateApplication(bundleIdentifier: bundleIdentifier))
        XCTAssertEqual(gracefulApp.terminateCalls, 1)
        XCTAssertEqual(gracefulApp.forceTerminateCalls, 0)
        XCTAssertEqual(forceApp.terminateCalls, 1)
        XCTAssertEqual(forceApp.forceTerminateCalls, 1)
        XCTAssertGreaterThanOrEqual(clock.elapsedSeconds, 3.0)
        XCTAssertLessThan(clock.elapsedSeconds, 3.25)
    }

    private func makeChecker(
        bundleIdentifier: String,
        state: RunningState,
        app: StubRunningApplication,
        clock: TestClock
    ) -> AppKitRunningApplicationChecker {
        makeChecker(
            runningApplications: { requestedBundleIdentifier in
                guard requestedBundleIdentifier == bundleIdentifier else { return [] }
                return state.isRunning ? [app] : []
            },
            clock: clock
        )
    }

    private func makeChecker(
        runningApplications: @escaping (String) -> [any AppKitRunningApplication],
        clock: TestClock
    ) -> AppKitRunningApplicationChecker {
        AppKitRunningApplicationChecker(
            dependencies: AppKitRunningApplicationCheckerDependencies(
                runningApplications: runningApplications,
                now: { clock.now },
                sleep: { interval in
                    clock.advance(by: interval)
                }
            )
        )
    }
}

private final class RunningState {
    var isRunning: Bool

    init(isRunning: Bool) {
        self.isRunning = isRunning
    }
}

private final class TestClock {
    private(set) var now: Date = Date(timeIntervalSince1970: 0)
    private(set) var elapsedSeconds: TimeInterval = 0

    func advance(by seconds: TimeInterval) {
        elapsedSeconds += seconds
        now = now.addingTimeInterval(seconds)
    }
}

private final class StubRunningApplication: AppKitRunningApplication {
    private let terminateResult: Bool
    private let forceTerminateResult: Bool
    private let onTerminate: () -> Void
    private let onForceTerminate: () -> Void

    private(set) var terminateCalls: Int = 0
    private(set) var forceTerminateCalls: Int = 0

    init(
        terminateResult: Bool = true,
        forceTerminateResult: Bool = true,
        onTerminate: @escaping () -> Void = {},
        onForceTerminate: @escaping () -> Void = {}
    ) {
        self.terminateResult = terminateResult
        self.forceTerminateResult = forceTerminateResult
        self.onTerminate = onTerminate
        self.onForceTerminate = onForceTerminate
    }

    @discardableResult
    func terminate() -> Bool {
        terminateCalls += 1
        if terminateResult {
            onTerminate()
        }
        return terminateResult
    }

    @discardableResult
    func forceTerminate() -> Bool {
        forceTerminateCalls += 1
        if forceTerminateResult {
            onForceTerminate()
        }
        return forceTerminateResult
    }
}
