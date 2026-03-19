import XCTest

@testable import AgentPanelCore

extension ProjectManagerFocusTests {
    // MARK: - Close restores focus from stack

    func testCloseProjectRestoresFocusFromStack() async {
        let aero = FocusAeroSpaceStub()
        aero.focusedWindowResult = .success(ApWindow(
            windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari"
        ))
        aero.focusWindowSuccessIds = [99]
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let captured = manager.captureCurrentFocus()!
        XCTAssertEqual(captured.windowId, 99)
        XCTAssertEqual(captured.workspace, "main")

        manager.pushFocusForTest(captured)
        aero.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        switch await manager.closeProject(projectId: "test") {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }

        XCTAssertTrue(aero.focusedWindowIds.contains(99), "Should have focused window 99")
    }

    // MARK: - Close with stale focus exhausts gracefully

    func testCloseProjectSkipsStaleFocus() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = []

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let staleFocus = CapturedFocus(windowId: 42, appBundleId: "com.gone.App", workspace: "main")
        manager.pushFocusForTest(staleFocus)

        switch await manager.closeProject(projectId: "test") {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    func testCloseProjectRestoresFromHistoryWhenWindowLookupFails() async {
        let aero = FocusAeroSpaceStub()
        aero.listAllWindowsResultOverride = .failure(ApCoreError(message: "listAllWindows failed"))
        aero.focusWindowSuccessIds = [99]
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        switch await manager.closeProject(projectId: "test") {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Should restore from persisted history without window lookup")
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    func testCloseProjectUsesMostRecentNonProjectFocusWhenStackEmpty() async {
        let aero = FocusAeroSpaceStub()
        aero.focusedWindowResult = .success(
            ApWindow(windowId: 777, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")
        )
        aero.focusWindowSuccessIds = [777]
        registerWindow(aero: aero, windowId: 777, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        XCTAssertEqual(manager.captureCurrentFocus()?.windowId, 777)
        aero.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        switch await manager.closeProject(projectId: "test") {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(777), "Should restore most recent non-project window")
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Exit restores focus from stack

    func testExitToNonProjectRestoresFocusFromStack() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99]
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99))
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    func testExitToNonProjectRestoresFromHistoryWhenWindowLookupFails() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99]
        aero.listAllWindowsResultOverride = .failure(ApCoreError(message: "listAllWindows failed"))
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99))
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    func testExitToNonProjectUsesMostRecentFocusWithoutLookupWhenStackEmpty() async {
        let aero = FocusAeroSpaceStub()
        aero.listAllWindowsResultOverride = .failure(ApCoreError(message: "listAllWindows failed"))
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        aero.focusedWindowResult = .success(
            ApWindow(windowId: 321, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")
        )
        aero.focusWindowSuccessIds = [321]
        registerWindow(aero: aero, windowId: 321, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        XCTAssertEqual(manager.captureCurrentFocus()?.windowId, 321)
        aero.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(321))
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    func testExitToNonProjectPreservesStackCandidateWhenFocusUnstable() async {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        // Disable workspace fallback so the retry path is exercised.
        aero.focusWorkspaceResult = .failure(ApCoreError(category: .command, message: "no workspace"))
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        // First attempt fails to stabilize and should preserve the entry for retry.
        aero.focusWindowSuccessIds = []
        let firstResult = await manager.exitToNonProjectWindow()
        if case .success = firstResult {
            XCTFail("Expected noPreviousWindow when focus cannot stabilize")
        }

        // Second attempt succeeds and should still restore from history.
        aero.focusWindowSuccessIds = [99]
        aero.focusWorkspaceResult = .success(())
        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99))
        case .failure(let error):
            XCTFail("Expected success after retry but got: \(error)")
        }
    }

    func testExitToNonProjectDoesNotRetryMostRecentInSameInvocationAfterStackFailure() async {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        // Disable workspace fallback so the retry path is exercised.
        aero.focusWorkspaceResult = .failure(ApCoreError(category: .command, message: "no workspace"))
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(
            aerospace: aero,
            windowPollTimeout: 0.05,
            windowPollInterval: 0.01
        )
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)
        aero.focusWindowSuccessIds = []

        let firstResult = await manager.exitToNonProjectWindow()
        if case .success = firstResult {
            XCTFail("Expected noPreviousWindow when focus cannot stabilize")
        }
        let secondResult = await manager.exitToNonProjectWindow()
        if case .success = secondResult {
            XCTFail("Expected noPreviousWindow when focus cannot stabilize")
        }

        aero.focusWindowSuccessIds = [99]
        aero.focusWorkspaceResult = .success(())
        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Candidate should remain retriable after two failed invocations")
        case .failure(let error):
            XCTFail("Expected success after bounded retries but got: \(error)")
        }
    }

    func testExitToNonProjectRestoresFocusWhenReassertSucceedsNearTimeoutBoundary() async {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(
            aerospace: aero,
            windowPollTimeout: 0.01,
            windowPollInterval: 1.0
        )
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)
        aero.focusWindowSuccessIds = [99]

        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99))
        case .failure(let error):
            XCTFail("Expected success when focus stabilizes immediately after re-assert, got: \(error)")
        }
    }

    func testExitToNonProjectRetryLimitEventuallyInvalidatesUnstableCandidate() async {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        // Disable workspace fallback so the retry limit path is exercised.
        aero.focusWorkspaceResult = .failure(ApCoreError(category: .command, message: "no workspace"))
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(
            aerospace: aero,
            windowPollTimeout: 0.05,
            windowPollInterval: 0.01
        )
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)
        aero.focusWindowSuccessIds = []

        for _ in 0..<3 {
            let failure = await manager.exitToNonProjectWindow()
            guard case .failure(let error) = failure else {
                XCTFail("Expected noPreviousWindow while focus remains unstable")
                return
            }
            XCTAssertEqual(error, .noPreviousWindow)
        }

        aero.focusWindowSuccessIds = [99]
        let result = await manager.exitToNonProjectWindow()
        guard case .failure(let error) = result else {
            XCTFail("Expected retry limit to invalidate unstable candidate")
            return
        }
        XCTAssertEqual(error, .noPreviousWindow)
    }

}
