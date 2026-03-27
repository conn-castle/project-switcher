import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

@MainActor
final class SwitcherFocusFlowTests: XCTestCase {
    func testExitToPreviousRestoresFocusAndLogsSuccess() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

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

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: nonProjectWindow.windowId,
            appBundleId: nonProjectWindow.appBundleId,
            workspace: nonProjectWindow.workspace
        ))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_enableBackActionRow()

        let expectation = expectation(description: "exit succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.exit_to_previous.succeeded" {
                expectation.fulfill()
            }
        }

        controller.testing_handleExitToNonProject()
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertTrue(aerospace.focusedWindowIds.contains(nonProjectWindow.windowId))
    }

    // MARK: - Pre-Entry Focus Restoration on Close

    func testCloseProjectRestoresPreEntryFocusFromNonProject() async {
        // Safari focused → activate Project A → close Project A → restores Safari
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        let safariWindow = PsWindow(
            windowId: 42,
            appBundleId: "com.apple.Safari",
            workspace: "main",
            windowTitle: "Safari"
        )
        aerospace.allWindows = [safariWindow]
        aerospace.focusWindowSuccessIds = [safariWindow.windowId]

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Simulate: Safari was focused when user opened switcher and selected Project A
        manager.setPreEntryFocusForTest(
            projectId: projectId,
            focus: CapturedFocus(windowId: safariWindow.windowId, appBundleId: safariWindow.appBundleId, workspace: safariWindow.workspace)
        )

        let result = await manager.closeProject(projectId: projectId)
        XCTAssertNotNil(try? result.get())

        // Safari window should have been focused
        XCTAssertTrue(aerospace.focusedWindowIds.contains(safariWindow.windowId))
        // Pre-entry restore log should appear
        XCTAssertTrue(logger.entries.contains { $0.event == "project_manager.close.focus_restored_pre_entry" })
    }

    func testCloseProjectRestoresPreEntryFocusCrossProject() async {
        // Project A focused → activate Project B → close Project B → restores Project A's window
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectA = "alpha"
        let projectB = "beta"
        let projectAWindow = PsWindow(
            windowId: 101,
            appBundleId: "com.microsoft.VSCode",
            workspace: "ps-\(projectA)",
            windowTitle: "VS Code - Alpha"
        )
        aerospace.allWindows = [projectAWindow]
        aerospace.focusWindowSuccessIds = [projectAWindow.windowId]

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [
                ProjectConfig(id: projectA, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false),
                ProjectConfig(id: projectB, name: "Beta", path: "/tmp/beta", color: "green", useAgentLayer: false)
            ],
            chrome: ChromeConfig()
        ))

        // Simulate: Project A's window was focused when user switched to Project B
        manager.setPreEntryFocusForTest(
            projectId: projectB,
            focus: CapturedFocus(windowId: projectAWindow.windowId, appBundleId: projectAWindow.appBundleId, workspace: projectAWindow.workspace)
        )

        let result = await manager.closeProject(projectId: projectB)
        XCTAssertNotNil(try? result.get())

        // Project A's window should have been focused
        XCTAssertTrue(aerospace.focusedWindowIds.contains(projectAWindow.windowId))
        XCTAssertTrue(logger.entries.contains { $0.event == "project_manager.close.focus_restored_pre_entry" })
    }

    func testCloseProjectFallsBackToStackWhenPreEntryWindowGone() async {
        // Pre-entry window closed/invalid → falls back to existing stack behavior
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        let terminalWindow = PsWindow(
            windowId: 55,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        // Only terminal window exists; Safari (pre-entry) window is gone
        aerospace.allWindows = [terminalWindow]
        aerospace.focusWindowSuccessIds = [terminalWindow.windowId]

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Pre-entry points to Safari window (id=42) which no longer exists
        manager.setPreEntryFocusForTest(
            projectId: projectId,
            focus: CapturedFocus(windowId: 42, appBundleId: "com.apple.Safari", workspace: "main")
        )
        // Push Terminal to the focus stack as fallback
        manager.pushFocusForTest(CapturedFocus(
            windowId: terminalWindow.windowId,
            appBundleId: terminalWindow.appBundleId,
            workspace: terminalWindow.workspace
        ))

        let result = await manager.closeProject(projectId: projectId)
        XCTAssertNotNil(try? result.get())

        // Should fall back to Terminal from the focus stack
        XCTAssertTrue(aerospace.focusedWindowIds.contains(terminalWindow.windowId))
        // Pre-entry restore should NOT appear (it failed silently)
        XCTAssertFalse(logger.entries.contains { $0.event == "project_manager.close.focus_restored_pre_entry" })
    }

    func testCloseProjectWithNoPreEntryUsesStack() async {
        // No pre-entry focus stored → falls back to stack as before
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        let terminalWindow = PsWindow(
            windowId: 55,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.allWindows = [terminalWindow]
        aerospace.focusWindowSuccessIds = [terminalWindow.windowId]
        aerospace.focusedWindowResult = .failure(PsCoreError(message: "no focus"))

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Only the stack has a focus entry — no preEntryFocus for this project
        manager.pushFocusForTest(CapturedFocus(
            windowId: terminalWindow.windowId,
            appBundleId: terminalWindow.appBundleId,
            workspace: terminalWindow.workspace
        ))

        let result = await manager.closeProject(projectId: projectId)
        XCTAssertNotNil(try? result.get())

        XCTAssertTrue(aerospace.focusedWindowIds.contains(terminalWindow.windowId))
        XCTAssertFalse(logger.entries.contains { $0.event == "project_manager.close.focus_restored_pre_entry" })
    }

    func testCloseProjectSkipsPreEntryFocusFromSameWorkspace() async {
        // Pre-entry snapshot from the workspace being closed should be ignored.
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        let closingWorkspace = "ps-\(projectId)"
        let staleProjectWindow = PsWindow(
            windowId: 77,
            appBundleId: "com.microsoft.VSCode",
            workspace: closingWorkspace,
            windowTitle: "VS Code - Alpha"
        )
        let fallbackWindow = PsWindow(
            windowId: 55,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )

        aerospace.allWindows = [staleProjectWindow, fallbackWindow]
        aerospace.focusWindowSuccessIds = [staleProjectWindow.windowId, fallbackWindow.windowId]

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        manager.setPreEntryFocusForTest(
            projectId: projectId,
            focus: CapturedFocus(
                windowId: staleProjectWindow.windowId,
                appBundleId: staleProjectWindow.appBundleId,
                workspace: staleProjectWindow.workspace
            )
        )
        manager.pushFocusForTest(CapturedFocus(
            windowId: fallbackWindow.windowId,
            appBundleId: fallbackWindow.appBundleId,
            workspace: fallbackWindow.workspace
        ))

        let result = await manager.closeProject(projectId: projectId)
        XCTAssertNotNil(try? result.get())

        XCTAssertFalse(aerospace.focusedWindowIds.contains(staleProjectWindow.windowId))
        XCTAssertTrue(aerospace.focusedWindowIds.contains(fallbackWindow.windowId))
        XCTAssertTrue(logger.entries.contains { $0.event == "project_manager.close.pre_entry_focus_skipped_same_workspace" })
    }

    func testSelectProjectStoresPreEntryFocus() async {
        // Verifies that selectProject stores the pre-captured focus in preEntryFocus
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        let workspace = "ps-\(projectId)"
        let safariFocus = CapturedFocus(windowId: 42, appBundleId: "com.apple.Safari", workspace: "main")

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

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        _ = await manager.selectProject(projectId: projectId, preCapturedFocus: safariFocus)

        // Verify pre-entry focus was logged
        XCTAssertTrue(logger.entries.contains { $0.event == "project_manager.focus.pre_entry_stored" })
    }

    func testCloseProjectRefreshesCapturedFocus() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "test"
        let refreshedWindow = PsWindow(
            windowId: 55,
            appBundleId: "com.apple.Terminal",
            workspace: "main",
            windowTitle: "Terminal"
        )
        aerospace.focusedWindowResult = .success(refreshedWindow)
        aerospace.allWindows = [refreshedWindow]
        aerospace.focusWindowSuccessIds = [refreshedWindow.windowId]

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 1, appBundleId: "com.apple.Safari", workspace: "main"))

        let expectation = expectation(description: "close succeeds")
        logger.onLog = { entry in
            if entry.event == "switcher.close_project.succeeded" {
                expectation.fulfill()
            }
        }

        controller.testing_performCloseProject(
            projectId: projectId,
            projectName: "Test",
            source: "test",
            selectedRowAtRequestTime: 0
        )

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(controller.testing_capturedFocus?.windowId, refreshedWindow.windowId)
        XCTAssertEqual(controller.testing_capturedFocus?.appBundleId, refreshedWindow.appBundleId)
        XCTAssertEqual(controller.testing_capturedFocus?.workspace, refreshedWindow.workspace)
    }

    func testProjectSelectionFocusesIdeWindow() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

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

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "main"))

        let expectation = expectation(description: "project selection completes")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                expectation.fulfill()
            }
        }

        controller.testing_handleProjectSelection(project)
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertTrue(aerospace.focusedWindowIds.contains(ideWindow.windowId))
    }

    func testProjectSelectionProceedsWithoutCapturedFocus() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

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

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        // Explicitly do NOT set capturedFocus — it remains nil

        let expectation = expectation(description: "project selection completes without captured focus")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                expectation.fulfill()
            }
        }

        controller.testing_handleProjectSelection(project)
        await fulfillment(of: [expectation], timeout: 2.0)

        let warnEntries = logger.entriesSnapshot().filter { $0.event == "switcher.project.selection_without_focus" }
        XCTAssertEqual(warnEntries.count, 1, "Expected warn log for selection without captured focus")
        XCTAssertTrue(aerospace.focusedWindowIds.contains(ideWindow.windowId))
    }

    func testShowDoesNotReapplyFilterWhenWorkspaceStateIsUnchanged() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-\(projectId)", isFocused: true)
        ])

        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        let config = Config(projects: [project], chrome: ChromeConfig())
        let manager = makeProjectManager(
            aerospace: aerospace,
            logger: logger,
            fileSystem: fileSystem,
            configLoader: { .success(ConfigLoadSuccess(config: config)) }
        )
        manager.loadTestConfig(config)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.show(
            origin: .hotkey,
            previousApp: nil,
            capturedFocus: CapturedFocus(
                windowId: 101,
                appBundleId: PsVSCodeLauncher.bundleId,
                workspace: "ps-\(projectId)"
            )
        )
        // Order out immediately so the panel doesn't steal keyboard focus during the wait.
        controller.testing_orderOutPanel()

        try? await Task.sleep(nanoseconds: 300_000_000)

        let filterAppliedCount = logger.entriesSnapshot().filter { $0.event == "switcher.filter.applied" }.count
        XCTAssertEqual(filterAppliedCount, 1, "Expected one initial filter pass when workspace state is unchanged.")

        controller.dismiss(reason: .toggle)
    }

    func testShowAlwaysStartsWithEmptyQuery() {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

        let projectId = "alpha"
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-\(projectId)", isFocused: true)
        ])

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)

        // First show: type a query, then dismiss.
        controller.show(origin: .hotkey)
        controller.testing_setSearchFieldValue("some query")
        controller.dismiss(reason: .toggle)

        // Second show: query must be empty regardless of how quickly we reopen.
        controller.show(origin: .hotkey)

        XCTAssertEqual(
            controller.testing_searchFieldValue,
            "",
            "Switcher must start with an empty search field on every launch."
        )

        controller.dismiss(reason: .toggle)
    }

    // MARK: - Dismissal focus-safety (selection success path)

    func testProjectSelectionDismissesAndFocusesIde() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

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

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "main"))

        let expectation = expectation(description: "IDE focused after selection")
        logger.onLog = { entry in
            if entry.event == "switcher.ide.focused" {
                expectation.fulfill()
            }
        }

        controller.testing_handleProjectSelection(project)
        await fulfillment(of: [expectation], timeout: 2.0)

        // After IDE focus, dismiss must have already happened (dismiss is called before
        // focusIdeWindow in handleProjectSelection success path). Verify state:
        XCTAssertNil(controller.testing_capturedFocus, "Dismiss should have cleared captured focus")
        XCTAssertTrue(aerospace.focusedWindowIds.contains(ideWindow.windowId), "IDE window should be focused")
    }

    func testProjectSelectionDoesNotTripDismissReentrancy() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()

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

        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)
        let project = ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        manager.loadTestConfig(Config(projects: [project], chrome: ChromeConfig()))

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "main"))

        let expectation = expectation(description: "project selection completes")
        logger.onLog = { entry in
            if entry.event == "project_manager.select.completed" {
                expectation.fulfill()
            }
        }

        controller.testing_handleProjectSelection(project)
        await fulfillment(of: [expectation], timeout: 2.0)

        // No re-entrancy warnings should have been logged
        let reentrantEntries = logger.entriesSnapshot().filter { $0.event == "switcher.dismiss.reentrant_blocked" }
        XCTAssertTrue(reentrantEntries.isEmpty, "Selection success path should not trigger re-entrant dismiss")
    }

    func testRecoverProjectShortcutInvokesRecoverCallbackWithCapturedFocus() {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        let focus = CapturedFocus(windowId: 77, appBundleId: "com.apple.Terminal", workspace: "ps-test")
        controller.testing_setCapturedFocus(focus)

        var callbackFocus: CapturedFocus?
        controller.onRecoverProjectRequested = { capturedFocus, completion in
            callbackFocus = capturedFocus
            completion(.success(RecoveryResult(windowsProcessed: 2, windowsRecovered: 1, errors: [])))
        }

        controller.testing_handleRecoverProjectFromShortcut()

        XCTAssertEqual(callbackFocus, focus)
    }

    func testFooterHintsIncludeRecoverProjectWhenShortcutIsAvailable() {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test"))
        controller.onRecoverProjectRequested = { _, completion in
            completion(.success(RecoveryResult(windowsProcessed: 0, windowsRecovered: 0, errors: [])))
        }

        controller.testing_updateFooterHints()

        XCTAssertTrue(controller.testing_footerHints.contains("⌘R Recover Project"))
    }

    func testRecoverProjectShortcutIsSingleFlight() {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test"))

        var invocationCount = 0
        var pendingCompletion: ((Result<RecoveryResult, PsCoreError>) -> Void)?
        controller.onRecoverProjectRequested = { _, completion in
            invocationCount += 1
            pendingCompletion = completion
        }

        controller.testing_handleRecoverProjectFromShortcut()
        controller.testing_handleRecoverProjectFromShortcut()

        XCTAssertEqual(invocationCount, 1, "Recover Project should not run concurrently from repeated keybind presses")

        pendingCompletion?(.success(RecoveryResult(windowsProcessed: 1, windowsRecovered: 1, errors: [])))
    }

    func testRecoverProjectShortcutRestoresSearchFieldInputFocus() async {
        let logger = RecordingLogger()
        let fileSystem = InMemoryFileSystem()
        let aerospace = TestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger, fileSystem: fileSystem)

        let controller = SwitcherPanelController(logger: logger, projectManager: manager)
        controller.testing_setCapturedFocus(
            CapturedFocus(windowId: 7, appBundleId: "com.apple.Terminal", workspace: "ps-test")
        )

        var pendingCompletion: ((Result<RecoveryResult, PsCoreError>) -> Void)?
        controller.onRecoverProjectRequested = { _, completion in
            pendingCompletion = completion
        }

        controller.testing_showPanelForFocusAssertions()
        _ = controller.testing_makeSearchFieldFirstResponder()
        XCTAssertTrue(
            controller.testing_makeTableViewFirstResponder(),
            "Precondition failed: expected table view to become first responder."
        )
        XCTAssertFalse(
            controller.testing_searchFieldHasInputFocus,
            "Precondition failed: search field should not have input focus before recovery completion."
        )

        controller.testing_handleRecoverProjectFromShortcut()
        pendingCompletion?(.success(RecoveryResult(windowsProcessed: 1, windowsRecovered: 1, errors: [])))

        let completionApplied = expectation(description: "recover completion applied on main queue")
        DispatchQueue.main.async {
            completionApplied.fulfill()
        }
        await fulfillment(of: [completionApplied], timeout: 1.0)

        XCTAssertTrue(
            controller.testing_searchFieldHasInputFocus,
            "Recover completion should restore search field input focus so Escape keeps dismissing."
        )

        controller.dismiss(reason: .toggle)
    }

    func testRecoveryScreenSelectionUsesContainingSecondaryScreen() {
        let primaryScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondaryScreen = CGRect(x: 1600, y: 0, width: 1440, height: 900)
        let windowFrame = CGRect(x: 1800, y: 120, width: 700, height: 500)

        let selected = AXWindowPositioner.selectRecoveryScreenVisibleFrame(
            currentFrame: windowFrame,
            fallbackScreenVisibleFrame: primaryScreen,
            availableScreenFrames: [primaryScreen, secondaryScreen]
        )

        XCTAssertEqual(selected, secondaryScreen)
        XCTAssertNil(
            AXWindowPositioner.computeRecoveredFrame(
                currentFrame: windowFrame,
                screenVisibleFrame: selected
            )
        )
    }

    func testRecoveryScreenSelectionUsesLargestIntersectionWhenMidpointInGap() {
        let primaryScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondaryScreen = CGRect(x: 1600, y: 0, width: 1440, height: 900)
        let windowFrame = CGRect(x: 1200, y: 120, width: 600, height: 500)

        let selected = AXWindowPositioner.selectRecoveryScreenVisibleFrame(
            currentFrame: windowFrame,
            fallbackScreenVisibleFrame: primaryScreen,
            availableScreenFrames: [primaryScreen, secondaryScreen]
        )

        XCTAssertEqual(selected, primaryScreen)
    }

    func testRecoveryScreenSelectionUsesNearestScreenWhenNoIntersection() {
        let primaryScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondaryScreen = CGRect(x: 1600, y: 0, width: 1440, height: 900)
        let windowFrame = CGRect(x: 1450, y: 120, width: 100, height: 500)

        let selected = AXWindowPositioner.selectRecoveryScreenVisibleFrame(
            currentFrame: windowFrame,
            fallbackScreenVisibleFrame: secondaryScreen,
            availableScreenFrames: [primaryScreen, secondaryScreen]
        )

        XCTAssertEqual(selected, primaryScreen)
    }

    func testRecoveryScreenSelectionFallsBackWhenNoScreensAvailable() {
        let secondaryScreen = CGRect(x: 1600, y: 0, width: 1440, height: 900)
        let windowFrame = CGRect(x: 1800, y: 120, width: 700, height: 500)

        let selected = AXWindowPositioner.selectRecoveryScreenVisibleFrame(
            currentFrame: windowFrame,
            fallbackScreenVisibleFrame: secondaryScreen,
            availableScreenFrames: []
        )

        XCTAssertEqual(selected, secondaryScreen)
    }

    // MARK: - Offscreen Coverage Tests

    func testOffscreenCoverageZeroSizeWindowReturnsNil() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let zeroWidth = CGRect(x: 100, y: 100, width: 0, height: 500)
        XCTAssertNil(AXWindowPositioner.offscreenCoverage(windowFrame: zeroWidth, screenFrame: screen))

        let zeroHeight = CGRect(x: 100, y: 100, width: 500, height: 0)
        XCTAssertNil(AXWindowPositioner.offscreenCoverage(windowFrame: zeroHeight, screenFrame: screen))

        let zeroBoth = CGRect(x: 100, y: 100, width: 0, height: 0)
        XCTAssertNil(AXWindowPositioner.offscreenCoverage(windowFrame: zeroBoth, screenFrame: screen))
    }

    func testOffscreenCoverageFullyOnScreenIsZero() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 100, y: 100, width: 500, height: 400)
        let coverage = AXWindowPositioner.offscreenCoverage(windowFrame: window, screenFrame: screen)
        XCTAssertEqual(coverage, 0)
    }

    func testOffscreenCoverageFullyOffScreenIsOne() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 2000, y: 2000, width: 500, height: 400)
        let coverage = AXWindowPositioner.offscreenCoverage(windowFrame: window, screenFrame: screen)
        XCTAssertEqual(coverage, 1.0)
    }

    func testOffscreenCoveragePartiallyOffUnder10PercentNoRecovery() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        // Window: 100x100, only 5px off the right edge → 5% offscreen
        let window = CGRect(x: 905, y: 450, width: 100, height: 100)
        let coverage = AXWindowPositioner.offscreenCoverage(windowFrame: window, screenFrame: screen)!
        XCTAssertLessThan(coverage, AXWindowPositioner.offscreenRecoveryThreshold)

        // computeRecoveredFrame should return nil (no recovery needed)
        XCTAssertNil(AXWindowPositioner.computeRecoveredFrame(currentFrame: window, screenVisibleFrame: screen))
    }

    func testOffscreenCoveragePartiallyOffOver10PercentTriggersRecovery() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        // Window: 100x100, 20px off the right edge → 20% offscreen
        let window = CGRect(x: 920, y: 450, width: 100, height: 100)
        let coverage = AXWindowPositioner.offscreenCoverage(windowFrame: window, screenFrame: screen)!
        XCTAssertGreaterThan(coverage, AXWindowPositioner.offscreenRecoveryThreshold)

        // computeRecoveredFrame should return a frame (recovery needed)
        XCTAssertNotNil(AXWindowPositioner.computeRecoveredFrame(currentFrame: window, screenVisibleFrame: screen))
    }

    func testOffscreenCoverageExactlyAtBoundary() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        // Window: 100x100, exactly 10px off the right edge → exactly 10% offscreen
        let window = CGRect(x: 910, y: 450, width: 100, height: 100)
        let coverage = AXWindowPositioner.offscreenCoverage(windowFrame: window, screenFrame: screen)!
        XCTAssertEqual(coverage, 0.10, accuracy: 0.001)

        // At exactly 10%, threshold is > 10%, so no recovery
        XCTAssertNil(AXWindowPositioner.computeRecoveredFrame(currentFrame: window, screenVisibleFrame: screen))
    }

    func testOffscreenCoverageWindowExactlyAtScreenEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        // Window perfectly flush with right edge
        let window = CGRect(x: 900, y: 450, width: 100, height: 100)
        let coverage = AXWindowPositioner.offscreenCoverage(windowFrame: window, screenFrame: screen)!
        XCTAssertEqual(coverage, 0)
        XCTAssertNil(AXWindowPositioner.computeRecoveredFrame(currentFrame: window, screenVisibleFrame: screen))
    }

    func testComputeRecoveredFrameZeroSizeWindowReturnsNil() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 2000, y: 2000, width: 0, height: 0)
        // Zero-area window is not recoverable
        XCTAssertNil(AXWindowPositioner.computeRecoveredFrame(currentFrame: window, screenVisibleFrame: screen))
    }

    // MARK: - Multi-Display Coordinate Conversion Tests

    func testAXToNSScreenPrimaryDisplayRegression() {
        // Single primary display: 2560x1440
        let screens = [CGRect(x: 0, y: 0, width: 2560, height: 1440)]
        // Window at AX (100, 200) size (800, 600)
        // nsY = 1440 - 200 - 600 = 640
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 100, y: 200),
            axSize: CGSize(width: 800, height: 600),
            screenFrames: screens
        )
        XCTAssertEqual(result, CGRect(x: 100, y: 640, width: 800, height: 600))
    }

    func testAXToNSScreenSecondaryToRight() {
        // Primary 2560x1440, secondary 1920x1080 to the right
        let screens = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        ]
        // Window on secondary at AX (2700, 100) size (800, 600)
        // nsY = 1440 - 100 - 600 = 740
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 2700, y: 100),
            axSize: CGSize(width: 800, height: 600),
            screenFrames: screens
        )
        XCTAssertEqual(result, CGRect(x: 2700, y: 740, width: 800, height: 600))
        // Center should be on the secondary screen
        let center = CGPoint(x: result!.midX, y: result!.midY)
        XCTAssertTrue(AXWindowPositioner.isPointOnScreen(center, screenFrames: screens))
    }

    func testAXToNSScreenSecondaryAboveNegativeAXY() {
        // Primary 2560x1440, secondary 1920x1080 above
        // NSScreen: secondary at (0, 1440, 1920, 1080) — above means higher Y
        let screens = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 0, y: 1440, width: 1920, height: 1080)
        ]
        // In AX space, "above" = negative Y. Secondary top at axY = -1080.
        // Window at AX (100, -800) size (800, 600): fully on secondary
        // nsY = 1440 - (-800) - 600 = 1640
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 100, y: -800),
            axSize: CGSize(width: 800, height: 600),
            screenFrames: screens
        )
        XCTAssertEqual(result, CGRect(x: 100, y: 1640, width: 800, height: 600))
        // Center at (500, 1940) should be on secondary (y: 1440 to 2520)
        let center = CGPoint(x: result!.midX, y: result!.midY)
        XCTAssertTrue(AXWindowPositioner.isPointOnScreen(center, screenFrames: screens))
    }

    func testAXToNSScreenSecondaryBelowNegativeNSScreenY() {
        // Primary 2560x1440, secondary 1920x1080 below
        // NSScreen: secondary at (0, -1080, 1920, 1080)
        let screens = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        ]
        // In AX space, "below" = Y > primaryHeight. Secondary top at axY = 1440.
        // Window at AX (100, 1500) size (800, 600)
        // nsY = 1440 - 1500 - 600 = -660
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 100, y: 1500),
            axSize: CGSize(width: 800, height: 600),
            screenFrames: screens
        )
        XCTAssertEqual(result, CGRect(x: 100, y: -660, width: 800, height: 600))
        // Center at (500, -360) should be on secondary (y: -1080 to 0)
        let center = CGPoint(x: result!.midX, y: result!.midY)
        XCTAssertTrue(AXWindowPositioner.isPointOnScreen(center, screenFrames: screens))
    }

    func testAXToNSScreenDifferentHeightDisplays() {
        // Primary 2560x1440, secondary 1920x1080 to the right, bottom-aligned
        let screens = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        ]
        // Window near bottom of secondary at AX (2700, 900) size (400, 400)
        // nsY = 1440 - 900 - 400 = 140
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 2700, y: 900),
            axSize: CGSize(width: 400, height: 400),
            screenFrames: screens
        )
        XCTAssertEqual(result, CGRect(x: 2700, y: 140, width: 400, height: 400))
        let center = CGPoint(x: result!.midX, y: result!.midY)
        XCTAssertTrue(AXWindowPositioner.isPointOnScreen(center, screenFrames: screens))
    }

    func testAXToNSScreenNoPrimaryReturnsNil() {
        // No screen at origin (0,0) — edge case during display reconfiguration
        let screens = [CGRect(x: 1920, y: 0, width: 1920, height: 1080)]
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 2000, y: 100),
            axSize: CGSize(width: 800, height: 600),
            screenFrames: screens
        )
        XCTAssertNil(result)
    }

    func testAXToNSScreenEmptyScreenListReturnsNil() {
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 100, y: 100),
            axSize: CGSize(width: 800, height: 600),
            screenFrames: []
        )
        XCTAssertNil(result)
    }

    func testAXToNSScreenWindowOffAllScreens() {
        // Gap between two screens — window in empty space
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 3000, y: 0, width: 1920, height: 1080)
        ]
        // Window at AX (2000, 100) — in the gap between screens
        // Conversion still works (global formula), but center is off-screen
        let result = AXWindowPositioner.axFrameToNSScreen(
            axPosition: CGPoint(x: 2000, y: 100),
            axSize: CGSize(width: 800, height: 600),
            screenFrames: screens
        )
        XCTAssertNotNil(result)
        let center = CGPoint(x: result!.midX, y: result!.midY)
        XCTAssertFalse(AXWindowPositioner.isPointOnScreen(center, screenFrames: screens))
    }

    func testNSScreenToAXRoundTrip() {
        let screens = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        ]
        let originalAXPos = CGPoint(x: 2700, y: 300)
        let originalSize = CGSize(width: 800, height: 600)

        // AX → NSScreen → AX should round-trip
        let nsFrame = AXWindowPositioner.axFrameToNSScreen(
            axPosition: originalAXPos,
            axSize: originalSize,
            screenFrames: screens
        )!
        let ax = AXWindowPositioner.nsScreenFrameToAX(
            frame: nsFrame,
            screenFrames: screens
        )!
        XCTAssertEqual(ax.position.x, originalAXPos.x, accuracy: 0.001)
        XCTAssertEqual(ax.position.y, originalAXPos.y, accuracy: 0.001)
        XCTAssertEqual(ax.size.width, originalSize.width, accuracy: 0.001)
        XCTAssertEqual(ax.size.height, originalSize.height, accuracy: 0.001)
    }

    func testNSScreenToAXRoundTripNegativeY() {
        // Round-trip with a window on a display below primary (negative NSScreen Y)
        let screens = [
            CGRect(x: 0, y: 0, width: 2560, height: 1440),
            CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        ]
        let originalAXPos = CGPoint(x: 100, y: 1600)
        let originalSize = CGSize(width: 800, height: 600)

        let nsFrame = AXWindowPositioner.axFrameToNSScreen(
            axPosition: originalAXPos,
            axSize: originalSize,
            screenFrames: screens
        )!
        let ax = AXWindowPositioner.nsScreenFrameToAX(
            frame: nsFrame,
            screenFrames: screens
        )!
        XCTAssertEqual(ax.position.x, originalAXPos.x, accuracy: 0.001)
        XCTAssertEqual(ax.position.y, originalAXPos.y, accuracy: 0.001)
    }

    func testNSScreenToAXNoPrimaryReturnsNil() {
        let screens = [CGRect(x: 1920, y: 0, width: 1920, height: 1080)]
        let result = AXWindowPositioner.nsScreenFrameToAX(
            frame: CGRect(x: 2000, y: 100, width: 800, height: 600),
            screenFrames: screens
        )
        XCTAssertNil(result)
    }

    func testIsPointOnScreenFindsCorrectDisplay() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        ]
        // Point on primary
        XCTAssertTrue(AXWindowPositioner.isPointOnScreen(CGPoint(x: 500, y: 500), screenFrames: screens))
        // Point on secondary
        XCTAssertTrue(AXWindowPositioner.isPointOnScreen(CGPoint(x: 2500, y: 500), screenFrames: screens))
    }

    func testIsPointOnScreenDetectsGapBetweenDisplays() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 3000, y: 0, width: 1920, height: 1080)
        ]
        // Point in gap between screens
        XCTAssertFalse(AXWindowPositioner.isPointOnScreen(CGPoint(x: 2500, y: 500), screenFrames: screens))
        // Point above all screens
        XCTAssertFalse(AXWindowPositioner.isPointOnScreen(CGPoint(x: 500, y: 1500), screenFrames: screens))
    }

    private func makeProjectManager(
        aerospace: TestAeroSpaceStub,
        logger: RecordingLogger,
        fileSystem: InMemoryFileSystem,
        configLoader: (() -> Result<ConfigLoadSuccess, ConfigLoadError>)? = nil
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: "/recency.json", isDirectory: false)
        let focusHistoryFilePath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: TestIdeLauncherStub(),
            agentLayerIdeLauncher: TestIdeLauncherStub(),
            chromeLauncher: TestChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: TestTabCaptureStub(),
            gitRemoteResolver: TestGitRemoteStub(),
            logger: logger,
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            configLoader: configLoader ?? { Config.loadDefault() },
            fileSystem: fileSystem,
            windowPollTimeout: 0.5,
            windowPollInterval: 0.05
        )
    }
}

private struct LogEntryRecord: Equatable {
    let event: String
    let level: LogLevel
    let message: String?
    let context: [String: String]?
}

private final class RecordingLogger: ProjectSwitcherLogging {
    private let queue = DispatchQueue(label: "com.projectswitcher.tests.logger")
    private(set) var entries: [LogEntryRecord] = []
    var onLog: ((LogEntryRecord) -> Void)?

    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
        let entry = LogEntryRecord(event: event, level: level, message: message, context: context)
        queue.sync {
            entries.append(entry)
        }
        onLog?(entry)
        return .success(())
    }

    func entriesSnapshot() -> [LogEntryRecord] {
        queue.sync { entries }
    }
}

private final class TestAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<PsWindow, PsCoreError> = .failure(PsCoreError(message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[PsWorkspaceSummary], PsCoreError> = .success([])
    var focusWorkspaceResult: Result<Void, PsCoreError> = .success(())
    var windowsByBundleId: [String: [PsWindow]] = [:]
    var windowsByWorkspace: [String: [PsWindow]] = [:]
    var allWindows: [PsWindow] = []
    private(set) var focusedWindowIds: [Int] = []
    private(set) var focusedWorkspaces: [String] = []

    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }

    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> {
        .success(windowsByBundleId[bundleId] ?? [])
    }

    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }

    func listAllWindows() -> Result<[PsWindow], PsCoreError> {
        if !allWindows.isEmpty {
            return .success(allWindows)
        }
        var windows: [PsWindow] = []
        var seen: Set<Int> = []
        for list in windowsByWorkspace.values {
            for window in list where !seen.contains(window.windowId) {
                seen.insert(window.windowId)
                windows.append(window)
            }
        }
        for list in windowsByBundleId.values {
            for window in list where !seen.contains(window.windowId) {
                seen.insert(window.windowId)
                windows.append(window)
            }
        }
        return .success(windows)
    }

    func focusedWindow() -> Result<PsWindow, PsCoreError> { focusedWindowResult }

    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
        focusedWindowIds.append(windowId)
        guard focusWindowSuccessIds.contains(windowId) else {
            return .failure(PsCoreError(message: "window not found"))
        }
        if case .success(let focused) = focusedWindowResult, focused.windowId == windowId {
            return .success(())
        }
        if let match = windowById(windowId) {
            focusedWindowResult = .success(match)
        } else {
            focusedWindowResult = .success(PsWindow(
                windowId: windowId,
                appBundleId: "com.stub.app",
                workspace: "main",
                windowTitle: "Stub"
            ))
        }
        return .success(())
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> {
        updateWindowWorkspace(windowId: windowId, workspace: workspace)
        return .success(())
    }

    func focusWorkspace(name: String) -> Result<Void, PsCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }

    private func windowById(_ windowId: Int) -> PsWindow? {
        if !allWindows.isEmpty {
            return allWindows.first(where: { $0.windowId == windowId })
        }
        for list in windowsByWorkspace.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        for list in windowsByBundleId.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        return nil
    }

    private func updateWindowWorkspace(windowId: Int, workspace: String) {
        if !allWindows.isEmpty {
            for (index, window) in allWindows.enumerated() where window.windowId == windowId {
                allWindows[index] = PsWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                )
            }
            return
        }

        for (bundleId, list) in windowsByBundleId {
            for (index, window) in list.enumerated() where window.windowId == windowId {
                var updated = list
                updated[index] = PsWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                )
                windowsByBundleId[bundleId] = updated
            }
        }

        for (workspaceName, list) in windowsByWorkspace {
            if let index = list.firstIndex(where: { $0.windowId == windowId }) {
                var updated = list
                let window = updated.remove(at: index)
                windowsByWorkspace[workspaceName] = updated
                var targetList = windowsByWorkspace[workspace] ?? []
                targetList.append(PsWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                ))
                windowsByWorkspace[workspace] = targetList
                return
            }
        }
    }
}

private struct TestIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> {
        .success(())
    }
}

private struct TestChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> {
        .success(())
    }
}

private struct TestTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> { .success([]) }
}

private struct TestGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

private final class InMemoryFileSystem: FileSystem {
    private var storage: [URL: Data] = [:]
    private var directories: Set<URL> = []

    func fileExists(at url: URL) -> Bool { storage[url] != nil }
    func directoryExists(at url: URL) -> Bool { directories.contains(url) }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        guard let data = storage[url] else {
            throw NSError(domain: "InMemoryFileSystem", code: 1, userInfo: nil)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = storage[url] else {
            throw NSError(domain: "InMemoryFileSystem", code: 2, userInfo: nil)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        storage.removeValue(forKey: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        storage[destinationURL] = storage[sourceURL]
        storage.removeValue(forKey: sourceURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        let existing = storage[url] ?? Data()
        var updated = existing
        updated.append(data)
        storage[url] = updated
    }

    func writeFile(at url: URL, data: Data) throws {
        storage[url] = data
    }

    func contentsOfDirectory(at url: URL) throws -> [String] {
        storage.keys
            .filter { $0.deletingLastPathComponent() == url }
            .map { $0.lastPathComponent }
    }
}
