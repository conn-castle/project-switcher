import XCTest

@testable import ProjectSwitcherCore

extension WindowRecoveryManagerTests {
    // MARK: - recoverWorkspaceWindows Tests

    func testRecoverWorkspace_emptyWorkspace_succeeds() async {
        let aerospace = StubAeroSpace()
        aerospace.windowsByWorkspace["ps-test"] = .success([])
        let manager = makeManager(aerospace: aerospace)

        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 0)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertTrue(recovery.errors.isEmpty)
    }

    func testRecoverWorkspace_oversizedWindowRecovered() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Big Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])
        aerospace.focusedWindowResult = .success(window)

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Big Window"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 1)
        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(positioner.recoverCalls[0].bundleId, "com.test.app")
        XCTAssertEqual(positioner.recoverCalls[0].windowTitle, "Big Window")
    }

    func testRecoverWorkspace_normalWindowNotRecovered() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Normal Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.defaultRecoverResult = .success(.unchanged)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
    }

    func testRecoverWorkspace_axFailureRecordedAsError() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Broken Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Broken Window"] = .failure(PsCoreError(category: .window, message: "AX denied"))

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("AX denied"))
    }

    func testRecoverWorkspace_restoresFocusAfterRecovery() async {
        let aerospace = StubAeroSpace()
        let originalWindow = makeWindow(id: 42, workspace: "main", title: "My Window")
        aerospace.focusedWindowResult = .success(originalWindow)
        let otherWindow = makeWindow(id: 99, workspace: "ps-test", title: "Other")
        aerospace.windowsByWorkspace["ps-test"] = .success([otherWindow])

        let manager = makeManager(aerospace: aerospace)
        _ = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        XCTAssertEqual(
            Array(aerospace.callTrace.suffix(2)),
            [.focusWorkspace("main"), .focusWindow(42)]
        )
    }

    func testRecoverWorkspace_focusesWorkspaceBeforeWindowFocus() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Win1")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Win1"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        _ = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        // reloadConfig then workspace focus must happen to prevent cross-Space AeroSpace crashes.
        XCTAssertEqual(
            Array(aerospace.callTrace.prefix(3)),
            [.reloadConfig, .focusWorkspace("ps-test"), .focusWindow(1)]
        )
    }

    func testRecoverWorkspace_multipleWindows_allProcessed() async {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 1, title: "Win1")
        let w2 = makeWindow(id: 2, title: "Win2")
        let w3 = makeWindow(id: 3, title: "Win3")
        aerospace.windowsByWorkspace["ps-test"] = .success([w1, w2, w3])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Win1"] = .success(.recovered)
        positioner.recoverResults["Win2"] = .success(.unchanged)
        positioner.recoverResults["Win3"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 3)
        XCTAssertEqual(recovery.windowsRecovered, 2)
        XCTAssertEqual(positioner.recoverCalls.count, 3)
    }

    func testRecoverWorkspace_unknownWorkspace_succeedsWithZeroProcessed() async {
        let aerospace = StubAeroSpace()
        let manager = makeManager(aerospace: aerospace)
        let result = await manager.recoverWorkspaceWindows(workspace: "nonexistent")

        // Unknown workspace returns empty window list — success with 0 processed
        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 0)
    }

    func testRecoverWorkspace_listFailure_returnsError() async {
        let aerospace = StubAeroSpace()
        aerospace.windowsByWorkspace["ps-broken"] = .failure(PsCoreError(message: "workspace gone"))
        let manager = makeManager(aerospace: aerospace)

        let result = await manager.recoverWorkspaceWindows(workspace: "ps-broken")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("workspace gone"))
    }

    func testRecoverWorkspace_listFailure_restoresOriginalFocus() async {
        let aerospace = StubAeroSpace()
        let originalWindow = makeWindow(id: 42, workspace: "main", title: "Original")
        aerospace.focusedWindowResult = .success(originalWindow)
        aerospace.windowsByWorkspace["ps-broken"] = .failure(PsCoreError(message: "workspace gone"))
        let manager = makeManager(aerospace: aerospace)

        let result = await manager.recoverWorkspaceWindows(workspace: "ps-broken")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("workspace gone"))
        XCTAssertEqual(
            Array(aerospace.callTrace.suffix(2)),
            [.focusWorkspace("main"), .focusWindow(42)]
        )
    }

    func testRecoverWorkspace_focusWorkspaceFailure_returnsErrorBeforeWindowFocus() async {
        let aerospace = StubAeroSpace()
        aerospace.focusWorkspaceResult = .failure(PsCoreError(message: "workspace focus denied"))
        aerospace.windowsByWorkspace["ps-test"] = .success([makeWindow(id: 1, title: "Test")])
        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("workspace focus denied"))
        XCTAssertTrue(positioner.recoverCalls.isEmpty)
        XCTAssertEqual(aerospace.focusWindowCalls, [])
        XCTAssertEqual(aerospace.callTrace, [.reloadConfig, .focusWorkspace("ps-test")])
    }

    func testRecoverWorkspace_focusFailure_surfacedAsError() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Test")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])
        aerospace.focusWindowResult = .failure(PsCoreError(message: "focus denied"))

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("Focus failed"))
        // Recovery should NOT be called when focus fails
        XCTAssertEqual(positioner.recoverCalls.count, 0)
    }

    func testRecoverWorkspace_focusesEachWindowBeforeRecovery() async {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 10, title: "A")
        let w2 = makeWindow(id: 20, title: "B")
        aerospace.windowsByWorkspace["ps-test"] = .success([w1, w2])

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        _ = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        // Focus calls should include both window IDs (before each recovery)
        XCTAssertTrue(aerospace.focusWindowCalls.contains(10))
        XCTAssertTrue(aerospace.focusWindowCalls.contains(20))
        // Each focus should precede the corresponding recover call
        XCTAssertEqual(positioner.recoverCalls.count, 2)
    }

    func testRecoverWorkspace_notFoundSurfacedAsError() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, title: "Ghost")
        aerospace.windowsByWorkspace["ps-test"] = .success([window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Ghost"] = .success(.notFound)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: "ps-test")

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("not found"))
    }

}
