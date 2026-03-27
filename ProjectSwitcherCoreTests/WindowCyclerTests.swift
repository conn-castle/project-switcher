import XCTest

@testable import ProjectSwitcherCore

final class WindowCyclerTests: XCTestCase {

    // MARK: - Test Stub

    final class StubAeroSpace: AeroSpaceProviding {
        var focusedWindowResult: Result<PsWindow, PsCoreError> = .failure(PsCoreError(message: "no focus"))
        var windowsByWorkspace: [String: [PsWindow]] = [:]
        var listWorkspaceResultOverride: Result<[PsWindow], PsCoreError>?
        var focusWindowCalls: [Int] = []
        var focusWindowResult: Result<Void, PsCoreError> = .success(())

        func focusedWindow() -> Result<PsWindow, PsCoreError> { focusedWindowResult }

        func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
            if let override = listWorkspaceResultOverride {
                return override
            }
            return .success(windowsByWorkspace[workspace] ?? [])
        }

        func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
            focusWindowCalls.append(windowId)
            return focusWindowResult
        }

        // Unused stubs required by protocol
        func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
        func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
        func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
        func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { .success([]) }
        func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
        func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
        func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }
        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
        func focusWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
    }

    // MARK: - Helpers

    func makeWindow(id: Int, workspace: String = "ps-test") -> PsWindow {
        PsWindow(windowId: id, appBundleId: "com.test.app\(id)", workspace: workspace, windowTitle: "Window \(id)")
    }

    func makeCycler(stub: StubAeroSpace) -> WindowCycler {
        WindowCycler(aerospace: stub)
    }

    // MARK: - Next Direction

    func testCycleFocusNextWrapsAround() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[2]) // focused on last
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [1]) // wraps to first
    }

    func testCycleFocusNextMiddle() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[1]) // focused on #2
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [3]) // moves to #3
    }

    // MARK: - Previous Direction

    func testCycleFocusPreviousWrapsAround() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0]) // focused on first
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .previous)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [3]) // wraps to last
    }

    func testCycleFocusPreviousMiddle() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[1]) // focused on #2
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .previous)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [1]) // moves to #1
    }

    // MARK: - Edge Cases

    func testCycleFocusSkipsSingleWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(stub.focusWindowCalls.isEmpty)
    }

    func testCycleFocusSkipsNoWindows() {
        let stub = StubAeroSpace()
        let focused = makeWindow(id: 1)
        stub.focusedWindowResult = .success(focused)
        stub.windowsByWorkspace["ps-test"] = []

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(stub.focusWindowCalls.isEmpty)
    }

    func testCycleFocusHandlesFocusedNotInList() {
        let stub = StubAeroSpace()
        let focused = makeWindow(id: 99) // not in the workspace list
        stub.focusedWindowResult = .success(focused)
        stub.windowsByWorkspace["ps-test"] = [makeWindow(id: 1), makeWindow(id: 2)]

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(stub.focusWindowCalls.isEmpty)
    }

    // MARK: - Error Propagation

    func testCycleFocusFailsWhenFocusedWindowFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .failure(PsCoreError(message: "no focused window"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    func testCycleFocusFailsWhenFocusWindowFails() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows
        stub.focusWindowResult = .failure(PsCoreError(message: "focus failed"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    func testCycleFocusFailsWhenListWorkspaceFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 1))
        stub.listWorkspaceResultOverride = .failure(PsCoreError(message: "workspace list failed"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    // MARK: - Session Start

    func testStartSessionSelectsNextCandidate() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session?) = result else {
            XCTFail("Expected non-nil session")
            return
        }

        XCTAssertEqual(session.initialWindowId, 1)
        XCTAssertEqual(session.selectedCandidate.windowId, 2)
        XCTAssertEqual(session.candidates.map(\.windowId), [1, 2, 3])
    }

    func testStartSessionSelectsPreviousCandidate() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .previous)

        guard case .success(let session?) = result else {
            XCTFail("Expected non-nil session")
            return
        }

        XCTAssertEqual(session.initialWindowId, 1)
        XCTAssertEqual(session.selectedCandidate.windowId, 3)
    }

    func testStartSessionReturnsNilForSingleWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(session)
    }

    func testStartSessionReturnsNilForNoWindows() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 1))
        stub.windowsByWorkspace["ps-test"] = []

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(session)
    }

    func testStartSessionReturnsNilWhenFocusedNotInList() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 99))
        stub.windowsByWorkspace["ps-test"] = [makeWindow(id: 1), makeWindow(id: 2)]

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        guard case .success(let session) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(session)
    }

    func testStartSessionFailsWhenFocusedWindowFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .failure(PsCoreError(message: "no focused window"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    func testStartSessionFailsWhenListWorkspaceFails() {
        let stub = StubAeroSpace()
        stub.focusedWindowResult = .success(makeWindow(id: 1))
        stub.listWorkspaceResultOverride = .failure(PsCoreError(message: "workspace list failed"))

        let cycler = makeCycler(stub: stub)
        let result = cycler.startSession(direction: .next)

        if case .success = result { XCTFail("Expected failure") }
    }

    // MARK: - Session Advance

    func testAdvanceSelectionWrapsNext() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let initial?) = cycler.startSession(direction: .previous) else {
            XCTFail("Expected non-nil session")
            return
        }
        XCTAssertEqual(initial.selectedCandidate.windowId, 3)

        let advanced = cycler.advanceSelection(session: initial, direction: .next)
        XCTAssertEqual(advanced.selectedCandidate.windowId, 1)
    }

    func testAdvanceSelectionWrapsPrevious() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let initial?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }
        XCTAssertEqual(initial.selectedCandidate.windowId, 2)

        let advanced = cycler.advanceSelection(session: initial, direction: .previous)
        XCTAssertEqual(advanced.selectedCandidate.windowId, 1)
    }

}
