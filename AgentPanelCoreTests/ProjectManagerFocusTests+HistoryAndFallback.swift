import XCTest

@testable import AgentPanelCore

extension ProjectManagerFocusTests {
    // MARK: - Activation failure does not rollback push (via selectProject)

    func testActivationFailureDoesNotRollbackPush() async {
        let aero = FocusAeroSpaceStub()
        // Chrome exists but VS Code does not — IDE launch will fail
        let chromeWindow = ApWindow(
            windowId: 100, appBundleId: "com.google.Chrome",
            workspace: "ap-test", windowTitle: "AP:test - Chrome"
        )
        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.focusWindowSuccessIds = [99]
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let failingIde = FocusIdeLauncherStub()
        failingIde.result = .failure(ApCoreError(category: .command, message: "IDE launch failed"))

        let manager = makeFocusManager(aerospace: aero, ideLauncher: failingIde)
        loadTestConfig(manager: manager)

        // selectProject pushes preCapturedFocus BEFORE attempting window launch
        let preFocus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        let result = await manager.selectProject(projectId: "test", preCapturedFocus: preFocus)

        // Activation should fail (IDE launch failed)
        switch result {
        case .success:
            XCTFail("Expected activation failure")
        case .failure(let error):
            XCTAssertEqual(error, .ideLaunchFailed(detail: "VS Code launch failed: IDE launch failed"))
        }

        // Push should still be on the stack — verify by closing the project
        switch await manager.closeProject(projectId: "test") {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Focus should have been restored from stack despite activation failure")
        case .failure(let error):
            XCTFail("Expected close success but got: \(error)")
        }
    }

    // MARK: - selectProject pushes non-project focus (happy path via selectProject)

    func testSelectProjectPushesNonProjectFocus() async {
        let aero = FocusAeroSpaceStub()
        configureForActivation(aero: aero, projectId: "test")
        aero.focusWindowSuccessIds.insert(99) // for close restoration
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // selectProject with non-project preCapturedFocus should push it
        let preFocus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        let result = await manager.selectProject(projectId: "test", preCapturedFocus: preFocus)
        switch result {
        case .failure(let error):
            XCTFail("Expected activation success but got: \(error)")
            return
        case .success:
            break
        }

        // Close should restore window 99 (pushed by the real selectProject path)
        switch await manager.closeProject(projectId: "test") {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Should restore window 99 pushed by selectProject")
        case .failure(let error):
            XCTFail("Expected close success but got: \(error)")
        }
    }

    // MARK: - Move window updates focus history

    func testMoveWindowToProjectInvalidatesFocusHistory() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99]
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Push non-project window into history, then move it into project space.
        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)
        _ = manager.moveWindowToProject(windowId: 99, projectId: "test")

        // Exit should no longer restore the moved window. It succeeds via workspace
        // fallback, but the invalidated window must not be focused.
        let result = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success via workspace fallback, got \(error)")
        }
        XCTAssertFalse(aero.focusedWindowIds.contains(99), "Should not focus the moved window")
    }

    func testMoveWindowFromProjectUpdatesMostRecentNonProjectFocus() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [77]
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 77, appBundleId: "com.apple.Terminal", workspace: "1", windowTitle: "Terminal")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        _ = manager.moveWindowFromProject(windowId: 77)

        let result = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success but got: \(error)")
        }
        XCTAssertTrue(aero.focusedWindowIds.contains(77), "Should restore moved non-project window")
    }

    // MARK: - captureCurrentFocus carries workspace

    func testCapturedFocusCarriesWorkspace() {
        let aero = FocusAeroSpaceStub()
        aero.focusedWindowResult = .success(ApWindow(
            windowId: 7, appBundleId: "com.google.Chrome", workspace: "personal", windowTitle: "Google"
        ))

        let manager = makeFocusManager(aerospace: aero)

        let captured = manager.captureCurrentFocus()
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.windowId, 7)
        XCTAssertEqual(captured?.appBundleId, "com.google.Chrome")
        XCTAssertEqual(captured?.workspace, "personal")
    }

    // MARK: - Workspace fallback when focus stack exhausted

    func testCloseProjectFallsBackToNonProjectWorkspaceWhenStackEmpty() async {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Non-project workspaces available; no focus stack entries
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "1", isFocused: false),
            ApWorkspaceSummary(workspace: "personal", isFocused: false)
        ])
        let fallbackWindow = ApWindow(
            windowId: 401,
            appBundleId: "com.apple.Terminal",
            workspace: "1",
            windowTitle: "Terminal"
        )
        aero.windowsByWorkspace["1"] = [fallbackWindow]
        aero.focusWindowSuccessIds = [fallbackWindow.windowId]

        let result = await manager.closeProject(projectId: "test")

        if case .failure = result { XCTFail("Expected close to succeed") }
        XCTAssertEqual(aero.focusedWorkspaces.last, "1", "Should fall back to first non-project workspace")
        XCTAssertTrue(
            aero.focusedWindowIds.contains(fallbackWindow.windowId),
            "Workspace fallback should focus a concrete non-project window"
        )
    }

    func testCloseProjectFallsBackToCanonicalWorkspaceWhenOnlyProjectWorkspaces() async {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Only project workspaces — fallback to canonical workspace "1"
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "ap-other", isFocused: false)
        ])

        let result = await manager.closeProject(projectId: "test")

        // Close still succeeds (focus restoration is non-fatal)
        if case .failure = result { XCTFail("Expected close to succeed") }
        // Canonical fallback workspace should be focused to leave project space
        XCTAssertTrue(
            aero.focusedWorkspaces.contains(WorkspaceRouting.fallbackWorkspace),
            "Should fall back to canonical workspace when only project workspaces exist"
        )
    }

    func testExitFallsBackToNonProjectWorkspaceWhenStackEmpty() async {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Currently in a project workspace with non-project workspaces available
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true),
            ApWorkspaceSummary(workspace: "main", isFocused: false)
        ])
        let fallbackWindow = ApWindow(
            windowId: 402,
            appBundleId: "com.apple.Safari",
            workspace: "main",
            windowTitle: "Safari"
        )
        aero.windowsByWorkspace["main"] = [fallbackWindow]
        aero.focusWindowSuccessIds = [fallbackWindow.windowId]

        let result = await manager.exitToNonProjectWindow()

        if case .failure = result { XCTFail("Expected exit to succeed via workspace fallback") }
        XCTAssertEqual(aero.focusedWorkspaces.last, "main")
        XCTAssertTrue(
            aero.focusedWindowIds.contains(fallbackWindow.windowId),
            "Workspace fallback should focus a concrete non-project window"
        )
    }

    // MARK: - Window-gone invalidation after focus failure

    func testExitInvalidatesHistoryWhenWindowGoneAfterFocusFails() async {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        // Disable workspace fallback so we can observe the invalidation path.
        aero.focusWorkspaceResult = .failure(ApCoreError(category: .command, message: "no workspace"))
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")
        // Do NOT add 99 to focusWindowSuccessIds — focus will fail.

        // When focus is attempted, remove the window to simulate it closing.
        var removedWindow = false
        aero.onFocusWindowAttempt = { windowId in
            guard windowId == 99, !removedWindow else { return }
            removedWindow = true
            aero.windowsByWorkspace["main"]?.removeAll(where: { $0.windowId == 99 })
            aero.windowsByBundleId["com.apple.Safari"]?.removeAll(where: { $0.windowId == 99 })
        }

        let manager = makeFocusManager(aerospace: aero, windowPollTimeout: 0.15, windowPollInterval: 0.03)
        loadTestConfig(manager: manager)
        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        // First exit: focus fails → window is gone → entry invalidated → fallback disabled → failure.
        let result1 = await manager.exitToNonProjectWindow()
        if case .success = result1 { XCTFail("Expected failure (fallback disabled)") }

        // Clear tracking and re-enable workspace fallback.
        aero.focusedWindowIds.removeAll()
        aero.focusWorkspaceResult = .success(())

        // Second exit: the invalidated entry should NOT be re-attempted.
        let result2 = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result2 {
            XCTFail("Expected success via workspace fallback, got \(error)")
        }
        XCTAssertFalse(
            aero.focusedWindowIds.contains(99),
            "Window 99 should have been invalidated (not preserved for retry)"
        )
    }

    func testExitFallsBackToCanonicalWorkspaceWhenNoNonProjectWorkspace() async {
        let aero = FocusAeroSpaceStub()
        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        // Only project workspaces — fallback to canonical workspace "1"
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let result = await manager.exitToNonProjectWindow()

        if case .failure(let error) = result {
            XCTFail("Expected success via workspace fallback, got \(error)")
        }
        XCTAssertTrue(
            aero.focusedWorkspaces.contains(WorkspaceRouting.fallbackWorkspace),
            "Should fall back to canonical workspace when no non-project workspace exists"
        )
    }

}
