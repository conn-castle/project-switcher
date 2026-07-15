import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

// MARK: - SwitcherOperationCoordinator Tests

@MainActor
final class SwitcherOperationCoordinatorTests: XCTestCase {

    // MARK: - Helpers

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

    // MARK: - handleProjectSelection

    func testHandleProjectSelectionSetsIsActivatingThenResetsOnSuccess() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "alpha"
        let workspace = "ps-\(projectId)"
        let chromeWindow = PsWindow(
            windowId: 100,
            appBundleId: PsChromeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "PS:\(projectId) - Chrome"
        )
        let ideWindow = PsWindow(
            windowId: 101,
            appBundleId: PsVSCodeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "PS:\(projectId) - VS Code"
        )

        aerospace.windowsByBundleId[PsChromeLauncher.bundleId] = [chromeWindow]
        aerospace.windowsByBundleId[PsVSCodeLauncher.bundleId] = [ideWindow]
        aerospace.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
        aerospace.focusedWindowResult = .success(ideWindow)
        aerospace.focusWindowSuccessIds = [ideWindow.windowId]
        aerospace.allWindows = [chromeWindow, ideWindow]

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        var controlsEnabledHistory: [Bool] = []
        var controlsEnabledOnMainThread: [Bool] = []
        coordinator.onSetControlsEnabled = { enabled in
            controlsEnabledHistory.append(enabled)
            controlsEnabledOnMainThread.append(Thread.isMainThread)
        }

        var dismissReason: SwitcherDismissReason?
        var dismissOnMainThread = false
        coordinator.onDismiss = { reason in
            dismissReason = reason
            dismissOnMainThread = Thread.isMainThread
        }

        var focusedIdeWindowId: Int?
        var focusIdeOnMainThread = false
        coordinator.onFocusIdeWindow = { windowId in
            focusedIdeWindowId = windowId
            focusIdeOnMainThread = Thread.isMainThread
        }

        let capturedFocus = CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "main")

        // isActivating should be false before selection.
        XCTAssertFalse(coordinator.isActivating)

        let completionExpectation = expectation(description: "project selection completes")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                completionExpectation.fulfill()
            }
        }

        coordinator.handleProjectSelection(project, capturedFocus: capturedFocus)

        // isActivating should be true immediately after calling handleProjectSelection.
        XCTAssertTrue(coordinator.isActivating)

        await fulfillment(of: [completionExpectation], timeout: 5.0)

        // After completion, isActivating should be reset to false.
        XCTAssertFalse(coordinator.isActivating)

        // Controls should have been disabled then re-enabled.
        XCTAssertEqual(controlsEnabledHistory, [false, true])

        // Dismiss should have been called with .projectSelected.
        XCTAssertEqual(dismissReason, .projectSelected)

        // IDE window should have been focused.
        XCTAssertEqual(focusedIdeWindowId, ideWindow.windowId)

        // All callbacks should have run on the main thread.
        XCTAssertTrue(controlsEnabledOnMainThread.allSatisfy { $0 }, "onSetControlsEnabled must run on main thread")
        XCTAssertTrue(dismissOnMainThread, "onDismiss must run on main thread")
        XCTAssertTrue(focusIdeOnMainThread, "onFocusIdeWindow must run on main thread")
    }

    func testHandleProjectSelectionReportsErrorAndCallsOnOperationFailedOnFailure() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(id: "bad", name: "Bad Project", path: "/tmp/bad", color: "red", useAgentLayer: false)
        // Load config WITHOUT the project to trigger projectNotFound.
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "other", name: "Other", path: "/tmp/other", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        var statusMessages: [(String, StatusLevel)] = []
        var statusOnMainThread: [Bool] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
            statusOnMainThread.append(Thread.isMainThread)
        }

        var operationFailedContext: ErrorContext?
        var operationFailedOnMainThread = false
        coordinator.onOperationFailed = { context in
            operationFailedContext = context
            operationFailedOnMainThread = Thread.isMainThread
        }

        var searchFieldFocusRestored = false
        var searchFieldFocusOnMainThread = false
        coordinator.onRestoreSearchFieldFocus = {
            searchFieldFocusRestored = true
            searchFieldFocusOnMainThread = Thread.isMainThread
        }

        var dismissCalled = false
        coordinator.onDismiss = { _ in
            dismissCalled = true
        }

        let failureExpectation = expectation(description: "project selection fails")
        logger.onLog = { entry in
            if entry.event == "switcher.project.activation_failed" {
                failureExpectation.fulfill()
            }
        }

        coordinator.handleProjectSelection(project, capturedFocus: nil)

        await fulfillment(of: [failureExpectation], timeout: 5.0)

        // isActivating should be reset after failure.
        XCTAssertFalse(coordinator.isActivating)

        // onOperationFailed should have been called.
        XCTAssertNotNil(operationFailedContext)
        XCTAssertEqual(operationFailedContext?.trigger, "activation")
        XCTAssertEqual(operationFailedContext?.category, .command)

        // Status should show an error.
        let errorStatuses = statusMessages.filter { $0.1 == .error }
        XCTAssertFalse(errorStatuses.isEmpty, "Expected at least one error status message")

        // Search field focus should be restored.
        XCTAssertTrue(searchFieldFocusRestored)

        // Dismiss should NOT have been called on failure.
        XCTAssertFalse(dismissCalled)

        // All callbacks should have run on the main thread.
        XCTAssertTrue(statusOnMainThread.allSatisfy { $0 }, "onSetStatus must run on main thread")
        XCTAssertTrue(operationFailedOnMainThread, "onOperationFailed must run on main thread")
        XCTAssertTrue(searchFieldFocusOnMainThread, "onRestoreSearchFieldFocus must run on main thread")
    }

    func testHandleProjectSelectionIgnoresDuplicateWhileActivationIsInProgress() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let workspaceQuerySemaphore = DispatchSemaphore(value: 0)
        aerospace.listWorkspacesWithFocusWaitSemaphore = workspaceQuerySemaphore

        let projectId = "alpha"
        let workspace = "ps-\(projectId)"
        let chromeWindow = PsWindow(
            windowId: 100,
            appBundleId: PsChromeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "PS:\(projectId) - Chrome"
        )
        let ideWindow = PsWindow(
            windowId: 101,
            appBundleId: PsVSCodeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "PS:\(projectId) - VS Code"
        )
        aerospace.windowsByBundleId[PsChromeLauncher.bundleId] = [chromeWindow]
        aerospace.windowsByBundleId[PsVSCodeLauncher.bundleId] = [ideWindow]
        aerospace.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
        aerospace.focusedWindowResult = .success(ideWindow)
        aerospace.focusWindowSuccessIds = [ideWindow.windowId]

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(
            id: projectId,
            name: "Alpha",
            path: "/tmp/alpha",
            color: "blue",
            useAgentLayer: false
        )
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let completion = expectation(description: "activation completes")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                completion.fulfill()
            }
        }

        coordinator.handleProjectSelection(project, capturedFocus: nil)
        coordinator.handleProjectSelection(project, capturedFocus: nil)

        XCTAssertEqual(
            logger.entriesSnapshot().filter { $0.event == "switcher.project.selected" }.count,
            1
        )
        XCTAssertEqual(
            logger.entriesSnapshot().filter { $0.event == "switcher.project.selection_skipped" }.count,
            1
        )

        workspaceQuerySemaphore.signal()
        await fulfillment(of: [completion], timeout: 5.0)
    }

    // MARK: - handleExitToNonProject

    func testPerformCloseProjectGuardsOperationUntilCloseCompletes() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let closeSemaphore = DispatchSemaphore(value: 0)
        aerospace.closeWorkspaceWaitSemaphore = closeSemaphore

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(
            id: "alpha",
            name: "Alpha",
            path: "/tmp/alpha",
            color: "blue",
            useAgentLayer: false
        )
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        var controlsEnabledHistory: [Bool] = []
        coordinator.onSetControlsEnabled = { controlsEnabledHistory.append($0) }
        let completionExpectation = expectation(description: "close completes")
        logger.onLog = { entry in
            if entry.event == "switcher.close_project.succeeded" {
                completionExpectation.fulfill()
            }
        }

        coordinator.performCloseProject(
            projectId: project.id,
            projectName: project.name,
            source: "test",
            fallbackSelectionKey: nil
        )

        XCTAssertTrue(coordinator.isClosingProject)
        XCTAssertEqual(controlsEnabledHistory, [false])

        closeSemaphore.signal()
        await fulfillment(of: [completionExpectation], timeout: 3.0)

        XCTAssertFalse(coordinator.isClosingProject)
        XCTAssertEqual(controlsEnabledHistory, [false, true])
    }

    func testHandleExitToNonProjectGuardsAgainstDoubleFire() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "test"
        let nonProjectWindow = PsWindow(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-\(projectId)", isFocused: true)
        ])
        aerospace.allWindows = [nonProjectWindow]
        aerospace.focusWindowSuccessIds = [nonProjectWindow.windowId]
        aerospace.focusedWindowResult = .failure(PsCoreError(message: "no focus"))

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: nonProjectWindow.windowId,
            appBundleId: nonProjectWindow.appBundleId,
            workspace: nonProjectWindow.workspace
        ))

        var dismissCallCount = 0
        coordinator.onDismiss = { _ in
            dismissCallCount += 1
        }

        let exitExpectation = expectation(description: "exit succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.exit_to_previous.succeeded" {
                exitExpectation.fulfill()
            }
        }

        // Fire twice before the first async operation completes.
        coordinator.handleExitToNonProject(fromShortcut: false, hasBackActionRow: true)
        coordinator.handleExitToNonProject(fromShortcut: false, hasBackActionRow: true)

        await fulfillment(of: [exitExpectation], timeout: 3.0)

        // Guard should prevent second invocation from running.
        XCTAssertEqual(dismissCallCount, 1, "handleExitToNonProject should guard against double-fire")
    }

    func testHandleExitToNonProjectCallsOnDismissOnSuccess() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "test"
        let nonProjectWindow = PsWindow(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-\(projectId)", isFocused: true)
        ])
        aerospace.allWindows = [nonProjectWindow]
        aerospace.focusWindowSuccessIds = [nonProjectWindow.windowId]
        aerospace.focusedWindowResult = .failure(PsCoreError(message: "no focus"))

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: nonProjectWindow.windowId,
            appBundleId: nonProjectWindow.appBundleId,
            workspace: nonProjectWindow.workspace
        ))

        var dismissReason: SwitcherDismissReason?
        var dismissOnMainThread = false
        coordinator.onDismiss = { reason in
            dismissReason = reason
            dismissOnMainThread = Thread.isMainThread
        }

        var controlsEnabledHistory: [Bool] = []
        var controlsEnabledOnMainThread: [Bool] = []
        coordinator.onSetControlsEnabled = { enabled in
            controlsEnabledHistory.append(enabled)
            controlsEnabledOnMainThread.append(Thread.isMainThread)
        }

        let exitExpectation = expectation(description: "exit to non-project succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.exit_to_previous.succeeded" {
                exitExpectation.fulfill()
            }
        }

        coordinator.handleExitToNonProject(fromShortcut: false, hasBackActionRow: true)

        await fulfillment(of: [exitExpectation], timeout: 3.0)

        XCTAssertEqual(dismissReason, .exitedToNonProject)
        XCTAssertEqual(controlsEnabledHistory, [false, true])
        XCTAssertFalse(coordinator.isExitingToNonProject, "Guard should be reset after completion")

        // All callbacks should have run on the main thread.
        XCTAssertTrue(controlsEnabledOnMainThread.allSatisfy { $0 }, "onSetControlsEnabled must run on main thread")
        XCTAssertTrue(dismissOnMainThread, "onDismiss must run on main thread")
    }

    // MARK: - performCloseProject

    func testPerformCloseProjectCallsCallbacksOnMainThreadOnSuccess() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let projectId = "closable"
        let workspace = "ps-\(projectId)"
        let ideWindow = PsWindow(
            windowId: 200,
            appBundleId: PsVSCodeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "PS:\(projectId) - VS Code"
        )
        let chromeWindow = PsWindow(
            windowId: 201,
            appBundleId: PsChromeLauncher.bundleId,
            workspace: workspace,
            windowTitle: "PS:\(projectId) - Chrome"
        )
        // After close, the focused window lands on a non-project window.
        let terminalWindow = PsWindow(
            windowId: 300,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )

        aerospace.windowsByWorkspace[workspace] = [ideWindow, chromeWindow]
        aerospace.windowsByBundleId[PsVSCodeLauncher.bundleId] = [ideWindow]
        aerospace.windowsByBundleId[PsChromeLauncher.bundleId] = [chromeWindow]
        aerospace.allWindows = [ideWindow, chromeWindow, terminalWindow]
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true),
            PsWorkspaceSummary(workspace: "main", isFocused: false)
        ])
        aerospace.focusedWindowResult = .success(terminalWindow)
        aerospace.focusWindowSuccessIds = [terminalWindow.windowId]

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        let project = ProjectConfig(id: projectId, name: "Closable", path: "/tmp/closable", color: "green", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        var statusMessages: [(String, StatusLevel)] = []
        var statusOnMainThread: [Bool] = []
        coordinator.onSetStatus = { message, level in
            statusMessages.append((message, level))
            statusOnMainThread.append(Thread.isMainThread)
        }

        var refreshCalled = false
        var refreshOnMainThread = false
        coordinator.onRefreshWorkspaceAndFilter = { _, _ in
            refreshCalled = true
            refreshOnMainThread = Thread.isMainThread
        }

        var updatedCapturedFocusCalled = false
        var updateCapturedFocusOnMainThread = false
        coordinator.onUpdateCapturedFocus = { _ in
            updatedCapturedFocusCalled = true
            updateCapturedFocusOnMainThread = Thread.isMainThread
        }

        let closeExpectation = expectation(description: "close project completes")
        logger.onLog = { entry in
            if entry.event == "switcher.close_project.succeeded" {
                closeExpectation.fulfill()
            }
        }

        coordinator.performCloseProject(
            projectId: projectId,
            projectName: "Closable",
            source: "test",
            fallbackSelectionKey: nil
        )

        await fulfillment(of: [closeExpectation], timeout: 5.0)

        // Callbacks should have been invoked.
        XCTAssertTrue(refreshCalled, "onRefreshWorkspaceAndFilter should be called on close success")
        XCTAssertTrue(updatedCapturedFocusCalled, "onUpdateCapturedFocus should be called on close success")
        XCTAssertFalse(statusMessages.isEmpty, "onSetStatus should be called")

        // All callbacks should have run on the main thread.
        XCTAssertTrue(statusOnMainThread.allSatisfy { $0 }, "onSetStatus must run on main thread")
        XCTAssertTrue(refreshOnMainThread, "onRefreshWorkspaceAndFilter must run on main thread")
        XCTAssertTrue(updateCapturedFocusOnMainThread, "onUpdateCapturedFocus must run on main thread")
    }

    func testPerformCloseProjectCallsCallbacksOnMainThreadOnFailure() async {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        let (coordinator, manager) = makeOperationCoordinator(aerospace: aerospace, logger: logger)
        // Load config WITHOUT the target project to trigger failure.
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "other", name: "Other", path: "/tmp/other", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        var statusOnMainThread: [Bool] = []
        coordinator.onSetStatus = { _, _ in
            statusOnMainThread.append(Thread.isMainThread)
        }

        var operationFailedOnMainThread = false
        coordinator.onOperationFailed = { _ in
            operationFailedOnMainThread = Thread.isMainThread
        }

        let failExpectation = expectation(description: "close project fails")
        logger.onLog = { entry in
            if entry.event == "switcher.close_project.failed" {
                failExpectation.fulfill()
            }
        }

        coordinator.performCloseProject(
            projectId: "nonexistent",
            projectName: "Nonexistent",
            source: "test",
            fallbackSelectionKey: nil
        )

        await fulfillment(of: [failExpectation], timeout: 5.0)

        // Callbacks should have run on the main thread.
        XCTAssertTrue(statusOnMainThread.allSatisfy { $0 }, "onSetStatus must run on main thread")
        XCTAssertTrue(operationFailedOnMainThread, "onOperationFailed must run on main thread")
    }

    // MARK: - handleExitToNonProject (continued)

    func testHandleExitToNonProjectBeepsWhenNoBackActionRowFromShortcut() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let (coordinator, _) = makeOperationCoordinator(aerospace: aerospace, logger: logger)

        var dismissCalled = false
        coordinator.onDismiss = { _ in
            dismissCalled = true
        }

        // No back action row and from shortcut: should beep and return immediately.
        coordinator.handleExitToNonProject(fromShortcut: true, hasBackActionRow: false)

        XCTAssertFalse(dismissCalled)
        XCTAssertFalse(coordinator.isExitingToNonProject, "Guard should not be set when hasBackActionRow is false")
    }

}
