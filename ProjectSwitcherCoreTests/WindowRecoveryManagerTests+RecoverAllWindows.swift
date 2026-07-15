import XCTest

@testable import ProjectSwitcherCore

extension WindowRecoveryManagerTests {
    // MARK: - recoverAllWindows Tests

    func testRecoverAll_emptyWindowList_succeeds() async {
        let aerospace = StubAeroSpace()
        // No workspaces at all
        let manager = makeManager(aerospace: aerospace)

        var progressCalls: [(Int, Int)] = []
        let result = await manager.recoverAllWindows { current, total in
            progressCalls.append((current, total))
        }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 0)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertTrue(progressCalls.isEmpty)
    }

    func testRecoverAll_movesMisplacedProjectWindowsToProjectWorkspace() async {
        let aerospace = StubAeroSpace()
        let misplacedVSCode = makeWindow(
            id: 10,
            bundleId: "com.microsoft.VSCode",
            workspace: "2",
            title: "PS:foo - VS Code"
        )
        let misplacedChrome = makeWindow(
            id: 20,
            bundleId: "com.google.Chrome",
            workspace: "main",
            title: "PS:bar - Chrome"
        )
        let nonProject = makeWindow(
            id: 30,
            bundleId: "com.other.App",
            workspace: "2",
            title: "Notes"
        )
        setupWorkspaceWindows(aerospace, windows: [misplacedVSCode, misplacedChrome, nonProject])

        let manager = makeManager(aerospace: aerospace)
        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertEqual(aerospace.moveWindowCalls.count, 2)
        XCTAssertTrue(
            aerospace.moveWindowCalls.contains(where: { $0.windowId == 10 && $0.workspace == "ps-foo" }),
            "VS Code token window should be moved to its project workspace"
        )
        XCTAssertTrue(
            aerospace.moveWindowCalls.contains(where: { $0.windowId == 20 && $0.workspace == "ps-bar" }),
            "Chrome token window should be moved to its project workspace"
        )
    }

    func testRecoverAll_doesNotMoveNonProjectWindows() async {
        let aerospace = StubAeroSpace()
        let nonProjectWindow = makeWindow(
            id: 11,
            bundleId: "com.other.App",
            workspace: "2",
            title: "General Window"
        )
        setupWorkspaceWindows(aerospace, windows: [nonProjectWindow])

        let manager = makeManager(aerospace: aerospace)
        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertTrue(aerospace.moveWindowCalls.isEmpty, "Non-project windows should stay in-place")
    }

    func testRecoverAll_doesNotRouteWindowsWhenTokenIsNotLeadingPrefix() async {
        let aerospace = StubAeroSpace()
        let chromeWindowWithMidTitleToken = makeWindow(
            id: 13,
            bundleId: "com.google.Chrome",
            workspace: "2",
            title: "Sprint notes PS:foo - Chrome"
        )
        setupWorkspaceWindows(aerospace, windows: [chromeWindowWithMidTitleToken])

        let manager = makeManager(aerospace: aerospace)
        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertTrue(
            aerospace.moveWindowCalls.isEmpty,
            "Titles with a ProjectSwitcher token in the middle should not be treated as project-routable windows"
        )
    }

    func testRecoverAll_routesWindowWithLeadingWhitespaceInTokenizedTitle() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(
            id: 14,
            bundleId: "com.microsoft.VSCode",
            workspace: "2",
            title: "  PS:foo - VS Code"
        )
        setupWorkspaceWindows(aerospace, windows: [window])

        let manager = makeManager(aerospace: aerospace)
        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertEqual(aerospace.moveWindowCalls.count, 1)
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "ps-foo")
    }

    func testRecoverAll_doesNotRouteUnknownProjectIdWhenKnownProjectsProvided() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(
            id: 15,
            bundleId: "com.microsoft.VSCode",
            workspace: "2",
            title: "PS:unknown - VS Code"
        )
        setupWorkspaceWindows(aerospace, windows: [window])

        let manager = makeManager(aerospace: aerospace, knownProjectIds: ["foo", "bar"])
        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertTrue(
            aerospace.moveWindowCalls.isEmpty,
            "Unknown project IDs should not be routed to a project workspace"
        )
    }

    func testRecoverAll_keepsProjectWindowAlreadyInCorrectWorkspace() async {
        let aerospace = StubAeroSpace()
        let alreadyPlaced = makeWindow(
            id: 12,
            bundleId: "com.microsoft.VSCode",
            workspace: "ps-foo",
            title: "PS:foo - VS Code"
        )
        setupWorkspaceWindows(aerospace, windows: [alreadyPlaced])

        let manager = makeManager(aerospace: aerospace)
        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertTrue(aerospace.moveWindowCalls.isEmpty, "Window already in matching project workspace should not move")
    }

    func testRecoverAll_reportsProgressForEachWindow() async {
        let aerospace = StubAeroSpace()
        let windows = [
            makeWindow(id: 1, workspace: "ws1", title: "A"),
            makeWindow(id: 2, workspace: "ws1", title: "B"),
            makeWindow(id: 3, workspace: "ws1", title: "C")
        ]
        setupWorkspaceWindows(aerospace, windows: windows)

        let manager = makeManager(aerospace: aerospace)

        var progressCalls: [(Int, Int)] = []
        _ = await manager.recoverAllWindows { current, total in
            progressCalls.append((current, total))
        }

        XCTAssertEqual(progressCalls.count, 3)
        XCTAssertEqual(progressCalls[0].0, 1)
        XCTAssertEqual(progressCalls[0].1, 3)
        XCTAssertEqual(progressCalls[1].0, 2)
        XCTAssertEqual(progressCalls[1].1, 3)
        XCTAssertEqual(progressCalls[2].0, 3)
        XCTAssertEqual(progressCalls[2].1, 3)
    }

    func testRecoverAll_restoresOriginalFocus() async {
        let aerospace = StubAeroSpace()
        let original = makeWindow(id: 42, workspace: "ps-myproject", title: "My Window")
        aerospace.focusedWindowResult = .success(original)
        let other = makeWindow(id: 99, workspace: "2", title: "Other")
        setupWorkspaceWindows(aerospace, windows: [other])

        let manager = makeManager(aerospace: aerospace)
        _ = await manager.recoverAllWindows { _, _ in }

        // Should restore focus to original window after full recovery pass.
        XCTAssertEqual(aerospace.focusWindowCalls.last, 42)
        XCTAssertTrue(aerospace.focusWorkspaceCalls.contains("2"))
        XCTAssertEqual(
            Array(aerospace.callTrace.suffix(2)),
            [.focusWorkspace("ps-myproject"), .focusWindow(42)]
        )
    }

    func testRecoverAll_moveFailure_continuesAndRecordsError() async {
        let aerospace = StubAeroSpace()
        let windows = [
            makeWindow(
                id: 1,
                bundleId: "com.microsoft.VSCode",
                workspace: "ws1",
                title: "PS:foo - VS Code"
            ),
            makeWindow(id: 2, workspace: "ws1", title: "B")
        ]
        setupWorkspaceWindows(aerospace, windows: windows)
        aerospace.moveWindowResult = .failure(PsCoreError(message: "move failed"))

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        let result = await manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 2)
        XCTAssertTrue(recovery.errors.contains { $0.contains("move failed") })
        XCTAssertEqual(positioner.recoverCalls.count, 2, "Recovery should continue even when routing move fails")
    }

    func testRecoverAll_recoveredCountTracksActuallyResized() async {
        let aerospace = StubAeroSpace()
        let windows = [
            makeWindow(id: 1, workspace: "ws1", title: "Big"),
            makeWindow(id: 2, workspace: "ws1", title: "Small"),
            makeWindow(id: 3, workspace: "ws1", title: "Medium")
        ]
        setupWorkspaceWindows(aerospace, windows: windows)

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Big"] = .success(.recovered)
        positioner.recoverResults["Small"] = .success(.unchanged)
        positioner.recoverResults["Medium"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 3)
        XCTAssertEqual(recovery.windowsRecovered, 2)
    }

    func testRecoverAll_passesCorrectScreenFrame() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, workspace: "ws1", title: "Win")
        setupWorkspaceWindows(aerospace, windows: [window])

        let positioner = StubWindowPositioner()
        positioner.defaultRecoverResult = .success(.unchanged)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(positioner.recoverCalls[0].screenFrame, screenFrame)
    }

    func testRecoverAll_workspaceListFailure_surfacedAsError() async {
        let aerospace = StubAeroSpace()
        aerospace.workspaces = ["ws-ok", "ws-broken"]
        aerospace.windowsByWorkspace["ws-ok"] = .success([makeWindow(id: 1, workspace: "ws-ok", title: "OK")])
        aerospace.windowsByWorkspace["ws-broken"] = .failure(PsCoreError(message: "workspace gone"))

        let manager = makeManager(aerospace: aerospace)
        let result = await manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        // Should still process the window from ws-ok
        XCTAssertEqual(recovery.windowsProcessed, 1)
        // But also surface the workspace failure
        XCTAssertTrue(recovery.errors.contains { $0.contains("ws-broken") })
    }

    func testRecoverAll_workspaceRecoveryFailure_surfacesErrorAndStillCountsProgress() async {
        let aerospace = StubAeroSpace()
        // Initial listing succeeds on workspace "2".
        let misplaced = makeWindow(
            id: 7,
            bundleId: "com.microsoft.VSCode",
            workspace: "2",
            title: "PS:proj - VS Code"
        )
        aerospace.workspaces = ["2"]
        aerospace.windowsByWorkspace["2"] = .success([misplaced])
        // The routed destination workspace is explicitly broken during recovery.
        aerospace.windowsByWorkspace["ps-proj"] = .failure(PsCoreError(message: "workspace unavailable"))

        let manager = makeManager(aerospace: aerospace)
        var progressCalls: [(Int, Int)] = []
        let result = await manager.recoverAllWindows { current, total in
            progressCalls.append((current, total))
        }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertTrue(recovery.errors.contains { $0.contains("ps-proj") })
        XCTAssertTrue(recovery.errors.contains { $0.contains("workspace unavailable") })
        XCTAssertEqual(aerospace.moveWindowCalls.count, 1)
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "ps-proj")
        XCTAssertEqual(progressCalls.count, 1)
        XCTAssertEqual(progressCalls[0].0, 1)
        XCTAssertEqual(progressCalls[0].1, 1)
    }

    func testRecoverAll_notFoundSurfacedAsError() async {
        let aerospace = StubAeroSpace()
        let window = makeWindow(id: 1, workspace: "ws1", title: "Ghost")
        setupWorkspaceWindows(aerospace, windows: [window])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Ghost"] = .success(.notFound)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverAllWindows { _, _ in }

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 0)
        XCTAssertEqual(recovery.errors.count, 1)
        XCTAssertTrue(recovery.errors[0].contains("not found"))
    }

    func testRecoverAll_focusesEachWindowBeforeRecovery() async {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 10, workspace: "ws1", title: "A")
        let w2 = makeWindow(id: 20, workspace: "ws1", title: "B")
        setupWorkspaceWindows(aerospace, windows: [w1, w2])

        let positioner = StubWindowPositioner()
        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        _ = await manager.recoverAllWindows { _, _ in }

        // Focus calls include the per-window focus (before each recovery)
        XCTAssertTrue(aerospace.focusWindowCalls.contains(10))
        XCTAssertTrue(aerospace.focusWindowCalls.contains(20))
        XCTAssertEqual(positioner.recoverCalls.count, 2)
    }

}
