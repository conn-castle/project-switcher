import XCTest

@testable import ProjectSwitcherCore

extension WindowRecoveryManagerTests {
    // MARK: - AeroSpace Tree-Node Error Recovery Tests

    // MARK: isAeroSpaceTreeNodeError detection

    func testIsAeroSpaceTreeNodeError_detailContainsAlreadyUnbound() {
        let error = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 42 failed with exit code 1.",
            detail: "AppBundle.MacWindow is already unbound."
        )
        XCTAssertTrue(error.isAeroSpaceTreeNodeError)
    }

    func testIsAeroSpaceTreeNodeError_nilDetail_returnsFalse() {
        let error = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 42 failed with exit code 1."
        )
        XCTAssertFalse(error.isAeroSpaceTreeNodeError)
    }

    func testIsAeroSpaceTreeNodeError_unrelatedDetail_returnsFalse() {
        let error = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 42 failed with exit code 1.",
            detail: "Unknown window id"
        )
        XCTAssertFalse(error.isAeroSpaceTreeNodeError)
    }

    // MARK: Pre-recovery reloadConfig

    func testRecoverWorkspace_callsReloadConfigBeforeWorkspaceFocus() async {
        let aerospace = StubAeroSpace()
        aerospace.windowsByWorkspace["ps-test"] = .success([])
        let manager = makeManager(aerospace: aerospace)

        _ = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        XCTAssertGreaterThanOrEqual(aerospace.reloadConfigCalls, 1,
                                    "reloadConfig should be called before workspace focus")
        // Verify ordering: reloadConfig must appear before the first focusWorkspace in the call trace.
        let reloadIndex = aerospace.callTrace.firstIndex(of: .reloadConfig)
        let firstFocusWsIndex = aerospace.callTrace.firstIndex(of: .focusWorkspace("ps-test"))
        XCTAssertNotNil(reloadIndex, "reloadConfig should be recorded in callTrace")
        XCTAssertNotNil(firstFocusWsIndex, "focusWorkspace should be recorded in callTrace")
        if let ri = reloadIndex, let fi = firstFocusWsIndex {
            XCTAssertTrue(ri < fi, "reloadConfig (index \(ri)) must precede focusWorkspace (index \(fi))")
        }
    }

    func testRecoverWorkspace_reloadConfigFailure_continuesRecovery() async {
        let aerospace = StubAeroSpace()
        aerospace.reloadConfigResult = .failure(PsCoreError(message: "reload failed"))
        let window = makeWindow(id: 1, title: "Test")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Test"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        // Recovery should succeed despite reload failure
        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsRecovered, 1)
    }

    // MARK: Tree-node error → retry + AX fallback (recoverWorkspaceWindows)

    func testRecoverWorkspace_treeNodeFocusError_retriesAfterReload() async {
        let aerospace = StubAeroSpace()
        let treeNodeError = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 1 failed with exit code 1.",
            detail: "AppBundle.MacWindow is already unbound."
        )
        let window = makeWindow(id: 1, title: "Stale Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])
        // First focus fails with tree-node error, second succeeds (after reload)
        aerospace.focusWindowSequences[1] = [.failure(treeNodeError), .success(())]

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Stale Window"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsRecovered, 1)
        // reloadConfig called: once in focusWorkspaceForRecovery + once for the tree-node retry
        XCTAssertGreaterThanOrEqual(aerospace.reloadConfigCalls, 2)
        // focusWindow called twice for window 1 (initial fail + retry)
        XCTAssertEqual(aerospace.focusWindowCalls.filter { $0 == 1 }.count, 2)
        // AX recovery should still run after successful retry
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }

    func testRecoverWorkspace_treeNodeFocusError_retryFails_fallsToAXRecovery() async {
        let aerospace = StubAeroSpace()
        let treeNodeError = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 1 failed with exit code 1.",
            detail: "AppBundle.MacWindow is already unbound."
        )
        let window = makeWindow(id: 1, title: "Stale Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])
        // Both focus attempts fail with tree-node error
        aerospace.focusWindowSequences[1] = [.failure(treeNodeError), .failure(treeNodeError)]

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Stale Window"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        // AX recovery should still run even when both focus attempts fail
        XCTAssertEqual(positioner.recoverCalls.count, 1,
                       "AX recovery should be attempted even after tree-node focus failure")
        XCTAssertEqual(recovery.windowsRecovered, 1)
    }

    func testRecoverWorkspace_nonTreeNodeFocusError_doesNotRetry() async {
        let aerospace = StubAeroSpace()
        let normalError = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 1 failed with exit code 1.",
            detail: "Unknown window id"
        )
        let window = makeWindow(id: 1, title: "Test")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])
        aerospace.focusWindowResult = .failure(normalError)

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        // Non-tree-node errors should NOT attempt AX recovery
        XCTAssertEqual(positioner.recoverCalls.count, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("Focus failed"))
        // Only the pre-recovery reload; no retry reload
        XCTAssertEqual(aerospace.reloadConfigCalls, 1)
    }

    // MARK: Tree-node error → retry + AX fallback (recoverCurrentWindow)

    func testRecoverCurrentWindow_treeNodeFocusError_retriesAndRecovers() {
        let aerospace = StubAeroSpace()
        let treeNodeError = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 7 failed with exit code 1.",
            detail: "AppBundle.MacWindow is already unbound."
        )
        let targetWindow = makeWindow(id: 7, bundleId: "com.test.target", workspace: "ps-test", title: "Target")
        aerospace.windowsByWorkspace["ps-test"] = .success([targetWindow])
        // First focus fails with tree-node error, second succeeds
        aerospace.focusWindowSequences[7] = [.failure(treeNodeError), .success(())]

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Target"] = .success(.recovered)
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        guard case .success(let outcome) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(outcome, .recovered)
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }

    func testRecoverCurrentWindow_treeNodeFocusError_retryFails_fallsToAXRecovery() {
        let aerospace = StubAeroSpace()
        let treeNodeError = PsCoreError(
            category: .command,
            message: "aerospace focus --window-id 7 failed with exit code 1.",
            detail: "AppBundle.MacWindow is already unbound."
        )
        let targetWindow = makeWindow(id: 7, bundleId: "com.test.target", workspace: "ps-test", title: "Target")
        aerospace.windowsByWorkspace["ps-test"] = .success([targetWindow])
        aerospace.focusWindowSequences[7] = [.failure(treeNodeError), .failure(treeNodeError)]

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Target"] = .success(.recovered)
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        // Should fall through to AX recovery when retry also fails
        guard case .success(let outcome) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(outcome, .recovered)
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }
}
