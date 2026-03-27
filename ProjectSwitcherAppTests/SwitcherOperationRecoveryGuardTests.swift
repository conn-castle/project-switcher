import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

@MainActor
final class SwitcherOperationRecoveryGuardTests: XCTestCase {

    private func makeProjectManager(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger,
        fileSystem: CoordinatorTestInMemoryFileSystem = CoordinatorTestInMemoryFileSystem()
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

    private func makeOperationCoordinator(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger
    ) -> (SwitcherOperationCoordinator, ProjectManager) {
        let fileSystem = CoordinatorTestInMemoryFileSystem()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let session = SwitcherSession(logger: logger)
        session.begin(origin: .hotkey)
        let coordinator = SwitcherOperationCoordinator(projectManager: manager, session: session)
        return (coordinator, manager)
    }

    // MARK: - handleRecoverProjectFromShortcut

    func testHandleRecoverProjectFromShortcutWithNilFocusSetsStatusAndBeeps() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        var statusMessages: [(String, StatusLevel)] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: nil)

        // Should set warning status.
        let warningStatuses = statusMessages.filter { $0.1 == .warning }
        XCTAssertFalse(warningStatuses.isEmpty, "Expected a warning status when capturedFocus is nil")
        XCTAssertTrue(warningStatuses.first?.0.contains("unavailable") == true)

        // Should log the skip event.
        let skipLogs = logger.entriesSnapshot().filter { $0.event == "switcher.recover_project.skipped" }
        XCTAssertEqual(skipLogs.count, 1)
    }

    func testHandleRecoverProjectFromShortcutWithoutCallbackSetsStatusAndBeeps() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test")
        // Do NOT set onRecoverProjectRequested — it remains nil.

        var statusMessages: [(String, StatusLevel)] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)

        let warningStatuses = statusMessages.filter { $0.1 == .warning }
        XCTAssertFalse(warningStatuses.isEmpty)
        XCTAssertTrue(warningStatuses.first?.0.contains("not available") == true)

        XCTAssertFalse(coordinator.isRecoveringProject, "Guard should not be set when callback is not wired")
    }

    func testHandleRecoverProjectFromShortcutGuardsAgainstConcurrentRecovery() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test")

        var invocationCount = 0
        var pendingCompletion: ((Result<RecoveryResult, PsCoreError>) -> Void)?
        coordinator.onRecoverProjectRequested = { _, completion in
            invocationCount += 1
            pendingCompletion = completion
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)
        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)

        XCTAssertEqual(invocationCount, 1, "Recovery should be single-flight")
        XCTAssertTrue(coordinator.isRecoveringProject)

        // Complete recovery.
        pendingCompletion?(.success(RecoveryResult(windowsProcessed: 1, windowsRecovered: 1, errors: [])))
    }

    // MARK: - handleRecoverProjectFromShortcut (main-thread delivery)

    func testHandleRecoverProjectSuccessCallsCallbacksOnMainThread() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test")

        var controlsEnabledHistory: [Bool] = []
        var controlsEnabledOnMainThread: [Bool] = []
        coordinator.onSetControlsEnabled = { enabled in
            controlsEnabledHistory.append(enabled)
            controlsEnabledOnMainThread.append(Thread.isMainThread)
        }

        var statusMessages: [(String, StatusLevel)] = []
        var statusOnMainThread: [Bool] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
            statusOnMainThread.append(Thread.isMainThread)
        }

        var searchFieldFocusRestored = false
        var searchFieldFocusOnMainThread = false
        let completionExpectation = expectation(description: "recovery completes")
        coordinator.onRestoreSearchFieldFocus = {
            searchFieldFocusRestored = true
            searchFieldFocusOnMainThread = Thread.isMainThread
            completionExpectation.fulfill()
        }

        coordinator.onRecoverProjectRequested = { _, completion in
            // Simulate async completion from a background queue.
            DispatchQueue.global(qos: .userInitiated).async {
                completion(.success(RecoveryResult(windowsProcessed: 3, windowsRecovered: 3, errors: [])))
            }
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)

        wait(for: [completionExpectation], timeout: 5.0)

        // Guard should be reset.
        XCTAssertFalse(coordinator.isRecoveringProject)

        // Controls should have been disabled then re-enabled.
        XCTAssertEqual(controlsEnabledHistory, [false, true])

        // Status should report success.
        let infoStatuses = statusMessages.filter { $0.1 == .info }
        XCTAssertTrue(infoStatuses.contains(where: { $0.0.contains("Recovered 3 of 3") }))

        // Search field focus should be restored.
        XCTAssertTrue(searchFieldFocusRestored)

        // All callbacks should have run on the main thread.
        XCTAssertTrue(controlsEnabledOnMainThread.allSatisfy { $0 }, "onSetControlsEnabled must run on main thread")
        XCTAssertTrue(statusOnMainThread.allSatisfy { $0 }, "onSetStatus must run on main thread")
        XCTAssertTrue(searchFieldFocusOnMainThread, "onRestoreSearchFieldFocus must run on main thread")
    }

    func testHandleRecoverProjectFailureCallsCallbacksOnMainThread() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test")

        var statusOnMainThread: [Bool] = []
        coordinator.onSetStatus = { _, _ in
            statusOnMainThread.append(Thread.isMainThread)
        }

        var operationFailedOnMainThread = false
        coordinator.onOperationFailed = { _ in
            operationFailedOnMainThread = Thread.isMainThread
        }

        var controlsEnabledOnMainThread: [Bool] = []
        coordinator.onSetControlsEnabled = { _ in
            controlsEnabledOnMainThread.append(Thread.isMainThread)
        }

        var searchFieldFocusOnMainThread = false
        let completionExpectation = expectation(description: "recovery fails")
        coordinator.onRestoreSearchFieldFocus = {
            searchFieldFocusOnMainThread = Thread.isMainThread
            completionExpectation.fulfill()
        }

        coordinator.onRecoverProjectRequested = { _, completion in
            DispatchQueue.global(qos: .userInitiated).async {
                completion(.failure(PsCoreError(category: .command, message: "AeroSpace unavailable")))
            }
        }

        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)

        wait(for: [completionExpectation], timeout: 5.0)

        // Guard should be reset.
        XCTAssertFalse(coordinator.isRecoveringProject)

        // All callbacks should have run on the main thread.
        XCTAssertTrue(controlsEnabledOnMainThread.allSatisfy { $0 }, "onSetControlsEnabled must run on main thread")
        XCTAssertTrue(statusOnMainThread.allSatisfy { $0 }, "onSetStatus must run on main thread")
        XCTAssertTrue(operationFailedOnMainThread, "onOperationFailed must run on main thread")
        XCTAssertTrue(searchFieldFocusOnMainThread, "onRestoreSearchFieldFocus must run on main thread")
    }

    // MARK: - resetGuards

    func testResetGuardsClearsAllGuardFlags() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        // Manually verify the guards are initially false.
        XCTAssertFalse(coordinator.isActivating)
        XCTAssertFalse(coordinator.isExitingToNonProject)
        XCTAssertFalse(coordinator.isRecoveringProject)

        // Set up the recover callback so we can trigger the guard.
        let focus = CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test")
        coordinator.onRecoverProjectRequested = { _, _ in
            // Don't complete — leave the guard set.
        }

        // Trigger isRecoveringProject.
        coordinator.handleRecoverProjectFromShortcut(capturedFocus: focus)
        XCTAssertTrue(coordinator.isRecoveringProject)

        // resetGuards should clear all flags.
        coordinator.resetGuards()

        XCTAssertFalse(coordinator.isActivating)
        XCTAssertFalse(coordinator.isExitingToNonProject)
        XCTAssertFalse(coordinator.isRecoveringProject)
    }

}
