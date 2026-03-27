import Foundation
import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerFocusTests {
    // MARK: - Helpers

    func testProject(id: String = "test") -> ProjectConfig {
        ProjectConfig(
            id: id,
            name: id.capitalized,
            path: "/\(id)",
            color: "blue",
            useAgentLayer: false,
            chromePinnedTabs: [],
            chromeDefaultTabs: []
        )
    }

    func loadTestConfig(manager: ProjectManager, projects: [ProjectConfig]? = nil) {
        let config = Config(
            projects: projects ?? [testProject()],
            chrome: ChromeConfig(pinnedTabs: [])
        )
        manager.loadTestConfig(config)
    }

    func makeFocusManager(
        aerospace: FocusAeroSpaceStub = FocusAeroSpaceStub(),
        ideLauncher: IdeLauncherProviding = FocusIdeLauncherStub(),
        chromeLauncher: ChromeLauncherProviding = FocusChromeLauncherStub(),
        preloadedFocusHistoryState: FocusHistoryState? = nil,
        windowPositioner: WindowPositioning? = nil,
        mainScreenVisibleFrame: (() -> CGRect?)? = nil,
        windowPollTimeout: TimeInterval = 0.5,
        windowPollInterval: TimeInterval = 0.05
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-recency-\(UUID().uuidString).json")
        let focusHistoryFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-history-\(UUID().uuidString).json")
        let chromeTabsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-tabs-\(UUID().uuidString)", isDirectory: true)
        if let preloadedFocusHistoryState {
            let store = FocusHistoryStore(
                fileURL: focusHistoryFilePath,
                maxAge: 7 * 24 * 60 * 60,
                maxEntries: 20
            )
            switch store.save(state: preloadedFocusHistoryState) {
            case .success:
                break
            case .failure(let error):
                XCTFail("Failed to preload focus history state: \(error)")
            }
        }
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: ideLauncher,
            agentLayerIdeLauncher: ideLauncher,
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: FocusTabCaptureStub(),
            gitRemoteResolver: FocusGitRemoteStub(),
            logger: FocusLoggerStub(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            windowPositioner: windowPositioner,
            mainScreenVisibleFrame: mainScreenVisibleFrame,
            windowPollTimeout: windowPollTimeout,
            windowPollInterval: windowPollInterval
        )
    }

    func makeFocusManagerWithSeparateLaunchers(
        aerospace: FocusAeroSpaceStub = FocusAeroSpaceStub(),
        ideLauncher: IdeLauncherProviding = FocusIdeLauncherStub(),
        agentLayerIdeLauncher: IdeLauncherProviding = FocusIdeLauncherStub(),
        chromeLauncher: ChromeLauncherProviding = FocusChromeLauncherStub(),
        preloadedFocusHistoryState: FocusHistoryState? = nil,
        windowPollTimeout: TimeInterval = 0.5,
        windowPollInterval: TimeInterval = 0.05
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-recency-\(UUID().uuidString).json")
        let focusHistoryFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-history-\(UUID().uuidString).json")
        let chromeTabsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-focus-tabs-\(UUID().uuidString)", isDirectory: true)
        if let preloadedFocusHistoryState {
            let store = FocusHistoryStore(
                fileURL: focusHistoryFilePath,
                maxAge: 7 * 24 * 60 * 60,
                maxEntries: 20
            )
            switch store.save(state: preloadedFocusHistoryState) {
            case .success:
                break
            case .failure(let error):
                XCTFail("Failed to preload focus history state: \(error)")
            }
        }
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: ideLauncher,
            agentLayerIdeLauncher: agentLayerIdeLauncher,
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: FocusTabCaptureStub(),
            gitRemoteResolver: FocusGitRemoteStub(),
            logger: FocusLoggerStub(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            windowPollTimeout: windowPollTimeout,
            windowPollInterval: windowPollInterval
        )
    }

    func registerWindow(
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

    /// Configures AeroSpace stub with Chrome window only (no VS Code).
    ///
    /// Used by launcher-selection tests where VS Code must be launched (not pre-existing).
    /// Sets up Chrome, workspace focus, and focus stability for the IDE window (101).
    func configureForActivationChromeOnly(
        aero: FocusAeroSpaceStub,
        projectId: String,
        chromeWindowId: Int = 100,
        ideWindowId: Int = 101
    ) {
        let workspace = "ps-\(projectId)"
        let chromeWindow = PsWindow(
            windowId: chromeWindowId, appBundleId: "com.google.Chrome",
            workspace: workspace, windowTitle: "PS:\(projectId) - Chrome"
        )
        let ideWindow = PsWindow(
            windowId: ideWindowId, appBundleId: "com.microsoft.VSCode",
            workspace: workspace, windowTitle: "PS:\(projectId) - VS Code"
        )

        // Chrome exists; VS Code does NOT (launcher must create it via onLaunch callback)
        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow]
        aero.focusWindowSuccessIds.formUnion([chromeWindowId, ideWindowId])
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
    }

    /// Configures the AeroSpace stub for a successful selectProject activation.
    ///
    /// Sets up tagged Chrome/VS Code windows already in the target workspace,
    /// workspace focus, and focus stability — so selectProject completes the full
    /// activation sequence without launching or moving windows.
    func configureForActivation(
        aero: FocusAeroSpaceStub,
        projectId: String,
        chromeWindowId: Int = 100,
        ideWindowId: Int = 101
    ) {
        let workspace = "ps-\(projectId)"
        let chromeWindow = PsWindow(
            windowId: chromeWindowId, appBundleId: "com.google.Chrome",
            workspace: workspace, windowTitle: "PS:\(projectId) - Chrome"
        )
        let ideWindow = PsWindow(
            windowId: ideWindowId, appBundleId: "com.microsoft.VSCode",
            workspace: workspace, windowTitle: "PS:\(projectId) - VS Code"
        )

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowSuccessIds.formUnion([chromeWindowId, ideWindowId])
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
    }
}
