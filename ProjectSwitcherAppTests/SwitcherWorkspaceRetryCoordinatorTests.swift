//
//  SwitcherCoordinatorTests.swift
//  ProjectSwitcherAppTests
//
//  Tests for SwitcherWorkspaceRetryCoordinator and SwitcherOperationCoordinator.
//  Validates retry logic, session guards, operation callbacks, and guard resets.
//

import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

// MARK: - SwitcherWorkspaceRetryCoordinator Tests

final class SwitcherWorkspaceRetryCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeProjectManager(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger,
        fileSystem: CoordinatorTestInMemoryFileSystem
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: "/recency.json", isDirectory: false)
        let focusHistoryFilePath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: CoordinatorTestIdeLauncherStub(),
            agentLayerIdeLauncher: CoordinatorTestIdeLauncherStub(),
            chromeLauncher: CoordinatorTestChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: CoordinatorTestTabCaptureStub(),
            gitRemoteResolver: CoordinatorTestGitRemoteStub(),
            logger: logger,
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            fileSystem: fileSystem,
            windowPollTimeout: 0.5,
            windowPollInterval: 0.05
        )
    }

    /// Fast retry interval for tests — avoids multi-second real-timer waits.
    private static let testRetryInterval: TimeInterval = 0.05

    private func makeRetryCoordinator(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger
    ) -> (SwitcherWorkspaceRetryCoordinator, SwitcherSession) {
        let fileSystem = CoordinatorTestInMemoryFileSystem()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        let session = SwitcherSession(logger: logger)
        session.begin(origin: .hotkey)
        let coordinator = SwitcherWorkspaceRetryCoordinator(
            projectManager: manager,
            session: session,
            retryIntervalSeconds: Self.testRetryInterval
        )
        return (coordinator, session)
    }

    private func waitForMainQueueDrain(description: String) {
        let drained = expectation(description: description)
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 1.0)
    }

    // MARK: - Tests

    func testScheduleRetryTriggersOnRetrySucceededWhenWorkspaceStateSucceeds() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
        ])

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        let succeededExpectation = expectation(description: "onRetrySucceeded called")
        coordinator.onRetrySucceeded = { state in
            XCTAssertEqual(state.activeProjectId, "test")
            XCTAssertTrue(state.openProjectIds.contains("test"))
            succeededExpectation.fulfill()
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not be called when workspace state succeeds")
        }

        coordinator.scheduleRetry()

        waitForExpectations(timeout: 2.0)
    }

    func testCancelRetryPreventsCallbacksFromInFlightTickQueuedAfterCancel() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
        ])
        let inFlightTickStarted = expectation(description: "in-flight tick started")
        let inFlightTickReturned = expectation(description: "in-flight tick returned")
        let allowWorkspaceStateReturn = DispatchSemaphore(value: 0)
        aerospace.onListWorkspacesWithFocus = {
            inFlightTickStarted.fulfill()
        }
        aerospace.onListWorkspacesWithFocusReturn = {
            inFlightTickReturned.fulfill()
        }
        aerospace.listWorkspacesWithFocusWaitSemaphore = allowWorkspaceStateReturn

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        coordinator.onRetrySucceeded = { _ in
            XCTFail("onRetrySucceeded should not be called for stale tick queued after cancelRetry")
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not be called for stale tick queued after cancelRetry")
        }

        coordinator.scheduleRetry()
        wait(for: [inFlightTickStarted], timeout: 2.0)
        coordinator.cancelRetry()
        allowWorkspaceStateReturn.signal()
        wait(for: [inFlightTickReturned], timeout: 2.0)
        waitForMainQueueDrain(description: "stale queued tick drained")

        let retryOutcomeLogs = logger.entriesSnapshot().filter {
            $0.event == "switcher.workspace_retry.succeeded" || $0.event == "switcher.workspace_retry.exhausted"
        }
        XCTAssertTrue(retryOutcomeLogs.isEmpty, "No retry outcomes should fire after cancel, got: \(retryOutcomeLogs.map(\.event))")
    }

    func testCancelRetryForTeardownFromBackgroundThreadPreventsCallbacksFromInFlightTickQueuedAfterCancel() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
        ])
        let inFlightTickStarted = expectation(description: "in-flight tick started")
        let inFlightTickReturned = expectation(description: "in-flight tick returned")
        let cancelCompleted = expectation(description: "background cancel completed")
        let allowWorkspaceStateReturn = DispatchSemaphore(value: 0)
        aerospace.onListWorkspacesWithFocus = {
            inFlightTickStarted.fulfill()
        }
        aerospace.onListWorkspacesWithFocusReturn = {
            inFlightTickReturned.fulfill()
        }
        aerospace.listWorkspacesWithFocusWaitSemaphore = allowWorkspaceStateReturn

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        coordinator.onRetrySucceeded = { _ in
            XCTFail("onRetrySucceeded should not be called for stale tick queued after background cancelRetry")
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not be called for stale tick queued after background cancelRetry")
        }

        coordinator.scheduleRetry()
        wait(for: [inFlightTickStarted], timeout: 2.0)
        DispatchQueue.global(qos: .userInitiated).async {
            coordinator.cancelRetryForTeardown()
            cancelCompleted.fulfill()
        }
        wait(for: [cancelCompleted], timeout: 2.0)
        allowWorkspaceStateReturn.signal()
        wait(for: [inFlightTickReturned], timeout: 2.0)
        waitForMainQueueDrain(description: "background-cancel stale queued tick drained")

        let retryOutcomeLogs = logger.entriesSnapshot().filter {
            $0.event == "switcher.workspace_retry.succeeded" || $0.event == "switcher.workspace_retry.exhausted"
        }
        XCTAssertTrue(
            retryOutcomeLogs.isEmpty,
            "No retry outcomes should fire after background cancel, got: \(retryOutcomeLogs.map(\.event))"
        )
    }

    func testRetryExhaustedAfterMaxAttempts() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        // Always fail workspace state queries so retries accumulate.
        aerospace.workspacesWithFocusResult = .failure(PsCoreError(message: "circuit breaker open"))

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)

        let exhaustedExpectation = expectation(description: "onRetryExhausted called")
        coordinator.onRetrySucceeded = { _ in
            XCTFail("onRetrySucceeded should not be called when all retries fail")
        }
        coordinator.onRetryExhausted = { error in
            if case .aeroSpaceError(let detail) = error {
                XCTAssertTrue(detail.contains("circuit breaker open"))
            } else {
                XCTFail("Expected aeroSpaceError, got \(error)")
            }
            exhaustedExpectation.fulfill()
        }

        coordinator.scheduleRetry()

        // maxAttempts=5, interval=0.05s — completes in ~0.25s.
        waitForExpectations(timeout: 2.0)

        // Verify log entries confirm exhaustion.
        let exhaustedLogs = logger.entriesSnapshot().filter { $0.event == "switcher.workspace_retry.exhausted" }
        XCTAssertEqual(exhaustedLogs.count, 1)
    }

    func testStaleSessionTimerIsIgnored() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
        ])
        let staleTickStarted = expectation(description: "stale tick started")
        let staleTickReturned = expectation(description: "stale tick returned")
        staleTickStarted.assertForOverFulfill = false
        staleTickReturned.assertForOverFulfill = false
        let allowWorkspaceStateReturn = DispatchSemaphore(value: 0)
        aerospace.onListWorkspacesWithFocus = {
            staleTickStarted.fulfill()
        }
        aerospace.onListWorkspacesWithFocusReturn = {
            staleTickReturned.fulfill()
        }
        aerospace.listWorkspacesWithFocusWaitSemaphore = allowWorkspaceStateReturn

        let (coordinator, session) = makeRetryCoordinator(aerospace: aerospace, logger: logger)
        defer {
            coordinator.cancelRetry()
            aerospace.listWorkspacesWithFocusWaitSemaphore = nil
            allowWorkspaceStateReturn.signal()
        }

        coordinator.onRetrySucceeded = { _ in
            XCTFail("onRetrySucceeded should not fire for a stale session timer")
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not fire for a stale session timer")
        }

        coordinator.scheduleRetry()
        wait(for: [staleTickStarted], timeout: 2.0)

        // Simulate session change: end the current session and begin a new one.
        // This changes session.sessionId, making the timer's captured sessionId stale.
        session.end(reason: .toggle)
        session.begin(origin: .hotkey)
        allowWorkspaceStateReturn.signal()
        wait(for: [staleTickReturned], timeout: 2.0)
        waitForMainQueueDrain(description: "stale session callback drained")

        let retryOutcomeLogs = logger.entriesSnapshot().filter {
            $0.event == "switcher.workspace_retry.succeeded" || $0.event == "switcher.workspace_retry.exhausted"
        }
        XCTAssertTrue(retryOutcomeLogs.isEmpty, "No retry outcomes should fire for stale session, got: \(retryOutcomeLogs.map(\.event))")
    }

    func testScheduleRetryResetsCountOnReSchedule() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let firstTickStarted = expectation(description: "first generation tick started")
        let firstTickReturned = expectation(description: "first generation tick returned")
        let rescheduledTickStarted = expectation(description: "rescheduled generation tick started")
        let rescheduledTickReturned = expectation(description: "rescheduled generation tick returned")
        let firstPendingLogged = expectation(description: "first generation pending logged")
        let allowWorkspaceStateReturn = DispatchSemaphore(value: 0)
        let tickStateLock = NSLock()
        var nextTickIndex = 0
        var pendingTickIndices: [Int] = []

        // First: fail, then switch to success after a short delay.
        aerospace.workspacesWithFocusResult = .failure(PsCoreError(message: "transient"))
        aerospace.onListWorkspacesWithFocus = {
            let tickIndex = { () -> Int in
                tickStateLock.lock()
                defer { tickStateLock.unlock() }
                nextTickIndex += 1
                pendingTickIndices.append(nextTickIndex)
                return nextTickIndex
            }()
            if tickIndex == 1 {
                firstTickStarted.fulfill()
            } else if tickIndex == 2 {
                rescheduledTickStarted.fulfill()
            }
        }
        aerospace.onListWorkspacesWithFocusReturn = {
            let tickIndex = { () -> Int? in
                tickStateLock.lock()
                defer { tickStateLock.unlock() }
                guard !pendingTickIndices.isEmpty else { return nil }
                return pendingTickIndices.removeFirst()
            }()
            if tickIndex == 1 {
                firstTickReturned.fulfill()
            } else if tickIndex == 2 {
                rescheduledTickReturned.fulfill()
            }
        }
        aerospace.listWorkspacesWithFocusWaitSemaphore = allowWorkspaceStateReturn

        let (coordinator, _) = makeRetryCoordinator(aerospace: aerospace, logger: logger)
        var rescheduled = false
        logger.onLog = { entry in
            if entry.event == "switcher.workspace_retry.pending",
               entry.context?["attempt"] == "1",
               !rescheduled {
                rescheduled = true
                firstPendingLogged.fulfill()
                aerospace.workspacesWithFocusResult = .success([
                    PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
                ])
                coordinator.scheduleRetry()
            }
        }

        let rescheduledExpectation = expectation(description: "rescheduled retry succeeds")
        coordinator.onRetrySucceeded = { state in
            XCTAssertEqual(state.activeProjectId, "test")
            rescheduledExpectation.fulfill()
        }
        coordinator.onRetryExhausted = { _ in
            XCTFail("onRetryExhausted should not fire when rescheduled retry succeeds")
        }

        coordinator.scheduleRetry()
        wait(for: [firstTickStarted], timeout: 2.0)
        allowWorkspaceStateReturn.signal()
        wait(for: [firstTickReturned, firstPendingLogged, rescheduledTickStarted], timeout: 2.0)
        allowWorkspaceStateReturn.signal()
        wait(for: [rescheduledTickReturned, rescheduledExpectation], timeout: 2.0)

        let entries = logger.entriesSnapshot()
        let succeededEntries = entries.filter { $0.event == "switcher.workspace_retry.succeeded" }
        XCTAssertEqual(succeededEntries.count, 1, "Reschedule flow should produce exactly one success event")
        XCTAssertEqual(
            succeededEntries.first?.context?["attempt"],
            "1",
            "Rescheduled retry should reset attempt numbering to 1"
        )
    }

    func testWorkspaceStateFailureLogLevelUsesInfoForBreakerOpen() {
        let level = SwitcherPanelController.workspaceStateFailureLogLevel(
            for: .aeroSpaceError(detail: "AeroSpace is unresponsive (circuit breaker open)."),
            retryOnFailure: true
        )
        XCTAssertEqual(level, .info)
    }

    func testWorkspaceStateFailureLogLevelUsesWarnForNonBreakerErrors() {
        let aerospaceLevel = SwitcherPanelController.workspaceStateFailureLogLevel(
            for: .aeroSpaceError(detail: "aerospace list-workspaces failed with exit code 1."),
            retryOnFailure: true
        )
        XCTAssertEqual(aerospaceLevel, .warn)

        let configLevel = SwitcherPanelController.workspaceStateFailureLogLevel(
            for: .configNotLoaded,
            retryOnFailure: true
        )
        XCTAssertEqual(configLevel, .warn)
    }

    func testWorkspaceStateFailureLogLevelUsesWarnForBreakerOpenWhenRetryDisabled() {
        let level = SwitcherPanelController.workspaceStateFailureLogLevel(
            for: .aeroSpaceError(detail: "AeroSpace is unresponsive (circuit breaker open)."),
            retryOnFailure: false
        )
        XCTAssertEqual(level, .warn)
    }
}
