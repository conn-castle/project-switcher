import XCTest

@testable import ProjectSwitcherCore

extension WindowCyclerTests {

    // MARK: - Session Commit/Cancel

    func testCommitSelectionFocusesSelectedWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.commitSelection(session: session)
        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [2])
    }

    func testCommitSelectionFailsWhenFocusFails() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows
        stub.focusWindowResult = .failure(PsCoreError(message: "focus failed"))

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.commitSelection(session: session)
        if case .success = result { XCTFail("Expected failure") }
    }

    func testCancelSelectionRestoresInitialWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.cancelSession(session: session)
        if case .failure(let error) = result { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(stub.focusWindowCalls, [1])
    }

    func testCancelSelectionFailsWhenFocusFails() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows
        stub.focusWindowResult = .failure(PsCoreError(message: "focus failed"))

        let cycler = makeCycler(stub: stub)
        guard case .success(let session?) = cycler.startSession(direction: .next) else {
            XCTFail("Expected non-nil session")
            return
        }

        let result = cycler.cancelSession(session: session)
        if case .success = result { XCTFail("Expected failure") }
    }

    // MARK: - cycleFocus returns candidate

    func testCycleFocusReturnsFocusedCandidate() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        guard case .success(let candidate?) = result else {
            XCTFail("Expected non-nil candidate")
            return
        }
        XCTAssertEqual(candidate.windowId, 2)
        XCTAssertEqual(candidate.appBundleId, "com.test.app2")
        XCTAssertEqual(candidate.windowTitle, "Window 2")
    }

    func testCycleFocusReturnsNilWhenSingleWindow() {
        let stub = StubAeroSpace()
        let windows = [makeWindow(id: 1)]
        stub.focusedWindowResult = .success(windows[0])
        stub.windowsByWorkspace["ps-test"] = windows

        let cycler = makeCycler(stub: stub)
        let result = cycler.cycleFocus(direction: .next)

        guard case .success(let candidate) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(candidate, "Should return nil when no cycling occurred")
    }
}
