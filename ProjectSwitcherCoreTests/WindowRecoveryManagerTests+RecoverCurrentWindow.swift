import XCTest

@testable import ProjectSwitcherCore

extension WindowRecoveryManagerTests {
    // MARK: - recoverCurrentWindow Tests

    func testRecoverCurrentWindow_recovered_focusesWindowAndRestoresOriginalFocus() {
        let aerospace = StubAeroSpace()
        let originalFocus = makeWindow(id: 42, workspace: "2", title: "Original Focus")
        aerospace.focusedWindowResult = .success(originalFocus)
        let targetWindow = makeWindow(id: 7, bundleId: "com.test.target", workspace: "ps-test", title: "Target Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([targetWindow])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Target Window"] = .success(.recovered)
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        guard case .success(let outcome) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        XCTAssertEqual(outcome, .recovered)
        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(positioner.recoverCalls[0].bundleId, "com.test.target")
        XCTAssertEqual(positioner.recoverCalls[0].windowTitle, "Target Window")
        XCTAssertEqual(aerospace.focusWindowCalls, [7, 42], "Should focus target window, then restore original focus")
        XCTAssertEqual(
            Array(aerospace.callTrace.prefix(3)),
            [.reloadConfig, .focusWorkspace("ps-test"), .focusWindow(7)]
        )
        XCTAssertEqual(
            Array(aerospace.callTrace.suffix(2)),
            [.focusWorkspace("2"), .focusWindow(42)]
        )
    }

    func testRecoverCurrentWindow_workspaceListFailure_returnsError() {
        let aerospace = StubAeroSpace()
        aerospace.windowsByWorkspace["ps-test"] = .failure(PsCoreError(message: "workspace gone"))
        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("workspace gone"))
        XCTAssertTrue(positioner.recoverCalls.isEmpty, "Recovery should not run when workspace listing fails")
    }

    func testRecoverCurrentWindow_windowNotFound_returnsError() {
        let aerospace = StubAeroSpace()
        aerospace.windowsByWorkspace["ps-test"] = .success([makeWindow(id: 1, workspace: "ps-test", title: "Other Window")])
        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("not found"))
        XCTAssertTrue(positioner.recoverCalls.isEmpty, "Recovery should not run when target window is missing")
    }

    func testRecoverCurrentWindow_focusFailure_returnsError() {
        let aerospace = StubAeroSpace()
        let targetWindow = makeWindow(id: 7, bundleId: "com.test.target", workspace: "ps-test", title: "Target Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([targetWindow])
        aerospace.focusWindowResult = .failure(PsCoreError(message: "focus denied"))
        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("focus denied"))
        XCTAssertTrue(positioner.recoverCalls.isEmpty, "Recovery should not run when focusing target window fails")
    }

    func testRecoverCurrentWindow_focusWorkspaceFailure_returnsErrorBeforeWindowFocus() {
        let aerospace = StubAeroSpace()
        aerospace.focusWorkspaceResult = .failure(PsCoreError(message: "workspace focus denied"))
        let targetWindow = makeWindow(id: 7, bundleId: "com.test.target", workspace: "ps-test", title: "Target Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([targetWindow])

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("workspace focus denied"))
        XCTAssertEqual(aerospace.callTrace, [.reloadConfig, .focusWorkspace("ps-test")])
        XCTAssertEqual(aerospace.focusWindowCalls, [])
        XCTAssertTrue(positioner.recoverCalls.isEmpty)
    }

    func testRecoverCurrentWindow_positionerNotFound_returnsError() {
        let aerospace = StubAeroSpace()
        let targetWindow = makeWindow(id: 7, bundleId: "com.test.target", workspace: "ps-test", title: "Target Window")
        aerospace.windowsByWorkspace["ps-test"] = .success([targetWindow])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Target Window"] = .success(.notFound)
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = manager.recoverCurrentWindow(windowId: 7, workspace: "ps-test")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(error.message.contains("not found"))
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }

}
