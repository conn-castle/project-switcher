import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherCore

// MARK: - Test Doubles

/// Minimal WindowPositioning stub for RecoveryOperationCoordinator tests.
/// Returns predictable results without AX calls.
private final class RecoveryTestWindowPositioner: WindowPositioning {
    var defaultRecoverResult: Result<RecoveryOutcome, PsCoreError> = .success(.recovered)

    func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
        defaultRecoverResult
    }

    func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
        defaultRecoverResult
    }

    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError> {
        .failure(PsCoreError(message: "not implemented"))
    }

    func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
        .success(WindowPositionResult(positioned: 1, matched: 1))
    }

    func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, PsCoreError> {
        .failure(PsCoreError(message: "not implemented"))
    }

    func setFallbackWindowFrames(bundleId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
        .failure(PsCoreError(message: "not implemented"))
    }

    func isAccessibilityTrusted() -> Bool { true }
    func promptForAccessibility() -> Bool { true }
}

// MARK: - Tests

@MainActor
final class RecoveryOperationCoordinatorTests: XCTestCase {

    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private func makeCoordinator(
        aerospace: CoordinatorTestAeroSpaceStub = CoordinatorTestAeroSpaceStub(),
        positioner: RecoveryTestWindowPositioner = RecoveryTestWindowPositioner(),
        layoutConfig: LayoutConfig? = nil
    ) -> RecoveryOperationCoordinator {
        let logger = CoordinatorTestRecordingLogger()
        return RecoveryOperationCoordinator(
            logger: logger,
            makeRecoveryManager: { screenFrame, config in
                WindowRecoveryManager(
                    aerospace: aerospace,
                    windowPositioner: positioner,
                    screenVisibleFrame: screenFrame,
                    logger: logger,
                    layoutConfig: config ?? LayoutConfig()
                )
            },
            currentLayoutConfig: { layoutConfig }
        )
    }

    // MARK: - recoverCurrentWindow

    func testRecoverCurrentWindowCallsCallbackOnMainThread() {
        let aerospace = CoordinatorTestAeroSpaceStub()
        let window = PsWindow(windowId: 7, appBundleId: "com.test.app", workspace: "ps-test", windowTitle: "Test")
        aerospace.windowsByWorkspace["ps-test"] = [window]
        aerospace.focusedWindowResult = .success(window)
        aerospace.focusWindowSuccessIds = [7]

        let coordinator = makeCoordinator(aerospace: aerospace)

        var callbackOnMainThread = false
        var receivedResult: Result<RecoveryOutcome, PsCoreError>?
        var receivedWindowId: Int?
        var receivedWorkspace: String?

        let completionExpectation = expectation(description: "current window recovery completes")
        coordinator.onCurrentWindowRecovered = { result, windowId, workspace in
            callbackOnMainThread = Thread.isMainThread
            receivedResult = result
            receivedWindowId = windowId
            receivedWorkspace = workspace
            completionExpectation.fulfill()
        }

        coordinator.recoverCurrentWindow(windowId: 7, workspace: "ps-test", screenFrame: screenFrame)

        wait(for: [completionExpectation], timeout: 5.0)

        XCTAssertTrue(callbackOnMainThread, "onCurrentWindowRecovered must run on main thread")
        XCTAssertEqual(receivedWindowId, 7)
        XCTAssertEqual(receivedWorkspace, "ps-test")
        if case .success(let outcome) = receivedResult {
            XCTAssertEqual(outcome, .recovered)
        } else {
            XCTFail("Expected success result")
        }
    }

    func testRecoverCurrentWindowFailureCallsCallbackOnMainThread() {
        let aerospace = CoordinatorTestAeroSpaceStub()
        // Empty workspace — window not found triggers failure.
        aerospace.windowsByWorkspace["ps-test"] = []

        let coordinator = makeCoordinator(aerospace: aerospace)

        var callbackOnMainThread = false
        var receivedResult: Result<RecoveryOutcome, PsCoreError>?

        let completionExpectation = expectation(description: "current window recovery fails")
        coordinator.onCurrentWindowRecovered = { result, _, _ in
            callbackOnMainThread = Thread.isMainThread
            receivedResult = result
            completionExpectation.fulfill()
        }

        coordinator.recoverCurrentWindow(windowId: 99, workspace: "ps-test", screenFrame: screenFrame)

        wait(for: [completionExpectation], timeout: 5.0)

        XCTAssertTrue(callbackOnMainThread, "onCurrentWindowRecovered must run on main thread on failure")
        if case .failure = receivedResult {
            // Expected
        } else {
            XCTFail("Expected failure result")
        }
    }

    // MARK: - recoverWorkspaceWindows (callback)

    func testRecoverWorkspaceWindowsCallbackCallsCallbackOnMainThread() {
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.windowsByWorkspace["ps-test"] = []

        let coordinator = makeCoordinator(aerospace: aerospace)
        let focus = CapturedFocus(windowId: 7, appBundleId: "com.test.app", workspace: "ps-test")

        var callbackOnMainThread = false
        var receivedResult: Result<RecoveryResult, PsCoreError>?

        let completionExpectation = expectation(description: "workspace recovery completes")
        coordinator.onWorkspaceRecovered = { result, _ in
            callbackOnMainThread = Thread.isMainThread
            receivedResult = result
            completionExpectation.fulfill()
        }

        coordinator.recoverWorkspaceWindows(focus: focus, screenFrame: screenFrame)

        wait(for: [completionExpectation], timeout: 5.0)

        XCTAssertTrue(callbackOnMainThread, "onWorkspaceRecovered must run on main thread")
        if case .success = receivedResult {
            // Expected — empty workspace recovers 0 of 0 windows successfully
        } else {
            XCTFail("Expected success result, got \(String(describing: receivedResult))")
        }
    }

    // MARK: - recoverWorkspaceWindows (completion handler)

    func testRecoverWorkspaceWindowsCompletionCallsCompletionOnMainThread() {
        let aerospace = CoordinatorTestAeroSpaceStub()
        aerospace.windowsByWorkspace["ps-test"] = []

        let coordinator = makeCoordinator(aerospace: aerospace)
        let focus = CapturedFocus(windowId: 7, appBundleId: "com.test.app", workspace: "ps-test")

        var completionOnMainThread = false
        var receivedResult: Result<RecoveryResult, PsCoreError>?

        let completionExpectation = expectation(description: "workspace recovery completion handler fires")

        coordinator.recoverWorkspaceWindows(focus: focus, screenFrame: screenFrame) { result in
            completionOnMainThread = Thread.isMainThread
            receivedResult = result
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 5.0)

        XCTAssertTrue(completionOnMainThread, "completion handler must run on main thread")
        if case .success = receivedResult {
            // Expected
        } else {
            XCTFail("Expected success result")
        }
    }

    // MARK: - recoverAllWindows

    func testRecoverAllWindowsCallsCallbacksOnMainThread() {
        let aerospace = CoordinatorTestAeroSpaceStub()
        // Add one workspace with one window for a minimal recovery pass.
        let window = PsWindow(windowId: 10, appBundleId: "com.test.app", workspace: "main", windowTitle: "Test Window")
        aerospace.windowsByWorkspace["main"] = [window]
        aerospace.allWindows = [window]
        aerospace.focusedWindowResult = .success(window)
        aerospace.focusWindowSuccessIds = [window.windowId]

        let coordinator = makeCoordinator(aerospace: aerospace)

        var completionOnMainThread = false
        var progressOnMainThread: [Bool] = []
        var receivedResult: Result<RecoveryResult, PsCoreError>?

        let completionExpectation = expectation(description: "recover all completes")

        coordinator.onAllWindowsProgress = { _, _ in
            progressOnMainThread.append(Thread.isMainThread)
        }

        coordinator.onAllWindowsCompleted = { result in
            completionOnMainThread = Thread.isMainThread
            receivedResult = result
            completionExpectation.fulfill()
        }

        coordinator.recoverAllWindows(screenFrame: screenFrame)

        wait(for: [completionExpectation], timeout: 5.0)

        XCTAssertTrue(completionOnMainThread, "onAllWindowsCompleted must run on main thread")
        if !progressOnMainThread.isEmpty {
            XCTAssertTrue(progressOnMainThread.allSatisfy { $0 }, "onAllWindowsProgress must run on main thread")
        }
        if case .success = receivedResult {
            // Expected
        } else {
            XCTFail("Expected success result, got \(String(describing: receivedResult))")
        }
    }
}
