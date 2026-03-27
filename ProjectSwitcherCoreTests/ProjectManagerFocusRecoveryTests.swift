import XCTest

@testable import ProjectSwitcherCore
// MARK: - Focus Recovery Tests

final class ProjectManagerFocusRecoveryTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Recovery called after focus restore

    func testExitRestoresFocusAndCallsRecovery() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99]
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let positioner = FocusWindowPositionerStub()
        let manager = makeFocusManager(
            aerospace: aero,
            windowPositioner: positioner,
            mainScreenVisibleFrame: { [screenFrame] in screenFrame }
        )
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertEqual(positioner.recoverFocusedCalls.count, 1)
            XCTAssertEqual(positioner.recoverFocusedCalls.first?.bundleId, "com.apple.Safari")
            XCTAssertEqual(positioner.recoverFocusedCalls.first?.screenFrame, screenFrame)
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Recovery failure does not affect focus restore

    func testRecoveryFailureDoesNotBlockFocusRestore() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99]
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let positioner = FocusWindowPositionerStub()
        positioner.recoverFocusedResult = .failure(PsCoreError(category: .window, message: "AX error"))

        let manager = makeFocusManager(
            aerospace: aero,
            windowPositioner: positioner,
            mainScreenVisibleFrame: { [screenFrame] in screenFrame }
        )
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertTrue(aero.focusedWindowIds.contains(99), "Focus restore should succeed even when recovery fails")
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Recovery skipped when no positioner

    func testRecoverySkippedWhenNoPositioner() async {
        let aero = FocusAeroSpaceStub()
        aero.focusWindowSuccessIds = [99]
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true)
        ])
        registerWindow(aero: aero, windowId: 99, appBundleId: "com.apple.Safari", workspace: "main", windowTitle: "Safari")

        let manager = makeFocusManager(aerospace: aero)
        loadTestConfig(manager: manager)

        let focus = CapturedFocus(windowId: 99, appBundleId: "com.apple.Safari", workspace: "main")
        manager.pushFocusForTest(focus)

        // Should succeed without crash — no positioner configured
        switch await manager.exitToNonProjectWindow() {
        case .success:
            break
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Recovery called during fallback

    func testFallbackToNonProjectWorkspaceCallsRecovery() async {
        let aero = FocusAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true),
            PsWorkspaceSummary(workspace: "main", isFocused: false)
        ])
        aero.windowsByWorkspace["main"] = [
            PsWindow(windowId: 55, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")
        ]
        aero.focusWindowSuccessIds = [55]

        let positioner = FocusWindowPositionerStub()
        let manager = makeFocusManager(
            aerospace: aero,
            windowPositioner: positioner,
            mainScreenVisibleFrame: { [screenFrame] in screenFrame }
        )
        loadTestConfig(manager: manager)

        // No focus stack entries → falls back to non-project workspace
        switch await manager.exitToNonProjectWindow() {
        case .success:
            XCTAssertEqual(positioner.recoverFocusedCalls.count, 1)
            XCTAssertEqual(positioner.recoverFocusedCalls.first?.bundleId, "com.apple.Terminal")
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }
    }

    // MARK: - Helpers

    private func registerWindow(
        aero: FocusAeroSpaceStub,
        windowId: Int,
        appBundleId: String,
        workspace: String,
        windowTitle: String = "Window"
    ) {
        let window = PsWindow(
            windowId: windowId,
            appBundleId: appBundleId,
            workspace: workspace,
            windowTitle: windowTitle
        )
        aero.windowsByWorkspace[workspace, default: []].append(window)
        aero.windowsByBundleId[appBundleId, default: []].append(window)
    }

    private func makeFocusManager(
        aerospace: FocusAeroSpaceStub = FocusAeroSpaceStub(),
        windowPositioner: WindowPositioning? = nil,
        mainScreenVisibleFrame: (() -> CGRect?)? = nil
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-recovery-recency-\(UUID().uuidString).json")
        let focusHistoryFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-recovery-history-\(UUID().uuidString).json")
        let chromeTabsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-recovery-tabs-\(UUID().uuidString)", isDirectory: true)
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: FocusIdeLauncherStub(),
            agentLayerIdeLauncher: FocusIdeLauncherStub(),
            chromeLauncher: FocusChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: FocusTabCaptureStub(),
            gitRemoteResolver: FocusGitRemoteStub(),
            logger: FocusLoggerStub(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            windowPositioner: windowPositioner,
            mainScreenVisibleFrame: mainScreenVisibleFrame,
            windowPollTimeout: 10.0,
            windowPollInterval: 0.1
        )
    }

    private func loadTestConfig(manager: ProjectManager) {
        _ = manager.loadConfig()
    }
}
