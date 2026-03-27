import Foundation
import XCTest
@testable import ProjectSwitcherCore

final class ProjectManagerCoverageTests: XCTestCase {
    private struct NoopLogger: ProjectSwitcherLogging {
        func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
            .success(())
        }
    }

    private struct NoopTabCapture: ChromeTabCapturing {
        func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> { .success([]) }
    }

    private struct NoopGitRemoteResolver: GitRemoteResolving {
        func resolve(projectPath: String) -> String? { nil }
    }

    private struct NoopIdeLauncher: IdeLauncherProviding {
        func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> { .success(()) }
    }

    private final class ChromeLauncherFailingOnTabsStub: ChromeLauncherProviding {
        func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> {
            if initialURLs.isEmpty {
                return .success(())
            }
            return .failure(PsCoreError(message: "simulated tab launch failure"))
        }
    }

    private final class SequencedAeroSpaceStub: AeroSpaceProviding {
        var workspacesWithFocusSequence: [Result<[PsWorkspaceSummary], PsCoreError>] = []
        private var workspacesWithFocusIdx: Int = 0

        var windowsWorkspaceSequence: [Result<[PsWindow], PsCoreError>] = []
        private var windowsWorkspaceIdx: Int = 0

        var windowsForAppSequences: [String: [[PsWindow]]] = [:]
        private var windowsForAppIdx: [String: Int] = [:]

        var focusedWindowSequence: [Result<PsWindow, PsCoreError>] = []
        private var focusedWindowIdx: Int = 0

        private(set) var focusedWorkspaces: [String] = []
        private(set) var focusedWindowIds: [Int] = []

        var focusWindowSuccessIds: Set<Int> = []

        func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
        func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
        func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }

        func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> {
            defer { workspacesWithFocusIdx += 1 }
            guard !workspacesWithFocusSequence.isEmpty else { return .success([]) }
            let idx = min(workspacesWithFocusIdx, workspacesWithFocusSequence.count - 1)
            return workspacesWithFocusSequence[idx]
        }

        func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }

        func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> {
            let seq = windowsForAppSequences[bundleId] ?? []
            let idx = windowsForAppIdx[bundleId] ?? 0
            windowsForAppIdx[bundleId] = idx + 1
            guard !seq.isEmpty else { return .success([]) }
            let effectiveIdx = min(idx, seq.count - 1)
            return .success(seq[effectiveIdx])
        }

        func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
            defer { windowsWorkspaceIdx += 1 }
            guard !windowsWorkspaceSequence.isEmpty else { return .success([]) }
            let idx = min(windowsWorkspaceIdx, windowsWorkspaceSequence.count - 1)
            return windowsWorkspaceSequence[idx]
        }
        func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }

        func focusedWindow() -> Result<PsWindow, PsCoreError> {
            defer { focusedWindowIdx += 1 }
            guard !focusedWindowSequence.isEmpty else { return .failure(PsCoreError(message: "no focused window configured")) }
            let idx = min(focusedWindowIdx, focusedWindowSequence.count - 1)
            return focusedWindowSequence[idx]
        }

        func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
            focusedWindowIds.append(windowId)
            if focusWindowSuccessIds.contains(windowId) {
                return .success(())
            }
            return .failure(PsCoreError(message: "window not found"))
        }

        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }

        func focusWorkspace(name: String) -> Result<Void, PsCoreError> {
            focusedWorkspaces.append(name)
            return .success(())
        }
    }

    private func makeManager(
        aerospace: SequencedAeroSpaceStub,
        chromeLauncher: ChromeLauncherProviding,
        recencyFilePath: URL
    ) -> ProjectManager {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let chromeTabsDir = tmp.appendingPathComponent("pm-coverage-tabs-\(UUID().uuidString)", isDirectory: true)
        let focusHistoryFilePath = tmp.appendingPathComponent("pm-coverage-focus-\(UUID().uuidString).json")
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: NoopIdeLauncher(),
            agentLayerIdeLauncher: NoopIdeLauncher(),
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: NoopTabCapture(),
            gitRemoteResolver: NoopGitRemoteResolver(),
            logger: NoopLogger(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath
        )
    }

    private func loadConfig(manager: ProjectManager, project: ProjectConfig, chrome: ChromeConfig = ChromeConfig()) {
        manager.loadTestConfig(Config(projects: [project], chrome: chrome))
    }

    func testSelectProjectPollsUntilWindowsArriveAndWorkspaceIsFocused() async {
        let projectId = "alpha"
        let workspace = "ps-\(projectId)"

        let chromeWindow = PsWindow(
            windowId: 100,
            appBundleId: "com.google.Chrome",
            workspace: workspace,
            windowTitle: "PS:\(projectId) - Chrome"
        )
        let ideWindow = PsWindow(
            windowId: 101,
            appBundleId: "com.microsoft.VSCode",
            workspace: workspace,
            windowTitle: "PS:\(projectId) - VS Code"
        )

        let aerospace = SequencedAeroSpaceStub()
        aerospace.windowsForAppSequences = [
            "com.google.Chrome": [[chromeWindow]],
            "com.microsoft.VSCode": [[ideWindow]]
        ]
        aerospace.windowsWorkspaceSequence = [
            .failure(PsCoreError(message: "workspace not queryable yet")),
            .success([chromeWindow, ideWindow])
        ]
        aerospace.workspacesWithFocusSequence = [
            .success([PsWorkspaceSummary(workspace: workspace, isFocused: false)]),
            .success([PsWorkspaceSummary(workspace: workspace, isFocused: true)])
        ]
        aerospace.focusedWindowSequence = [.success(ideWindow)]
        aerospace.focusWindowSuccessIds = [101]

        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-coverage-recency-\(UUID().uuidString).json")
        let manager = makeManager(aerospace: aerospace, chromeLauncher: ChromeLauncherFailingOnTabsStub(), recencyFilePath: recencyFilePath)
        loadConfig(
            manager: manager,
            project: ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)
        )

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let success):
            XCTAssertEqual(success.ideWindowId, 101)
        }
        XCTAssertTrue(aerospace.focusedWorkspaces.contains(workspace), "Should attempt to focus workspace while polling")
        XCTAssertTrue(aerospace.focusedWorkspaces.allSatisfy { $0 == workspace }, "All focus attempts should target the same workspace")
    }

    func testSelectProjectRetriesChromeLaunchWithoutTabsWhenTabLaunchFailsAndPollsForWindow() async {
        let projectId = "beta"
        let workspace = "ps-\(projectId)"

        let chromeWindow = PsWindow(
            windowId: 200,
            appBundleId: "com.google.Chrome",
            workspace: workspace,
            windowTitle: "PS:\(projectId) - Chrome"
        )
        let ideWindow = PsWindow(
            windowId: 201,
            appBundleId: "com.microsoft.VSCode",
            workspace: workspace,
            windowTitle: "PS:\(projectId) - VS Code"
        )

        let aerospace = SequencedAeroSpaceStub()
        // Chrome: not found on initial lookup; first poll misses; second poll finds.
        aerospace.windowsForAppSequences = [
            "com.google.Chrome": [[], [], [chromeWindow]],
            "com.microsoft.VSCode": [[ideWindow]]
        ]
        aerospace.windowsWorkspaceSequence = [.success([chromeWindow, ideWindow])]
        aerospace.workspacesWithFocusSequence = [.success([PsWorkspaceSummary(workspace: workspace, isFocused: true)])]
        aerospace.focusedWindowSequence = [.success(ideWindow)]
        aerospace.focusWindowSuccessIds = [201]

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir.appendingPathComponent("pm-coverage-recency-\(UUID().uuidString).json")
        let manager = makeManager(aerospace: aerospace, chromeLauncher: ChromeLauncherFailingOnTabsStub(), recencyFilePath: recencyFilePath)
        loadConfig(
            manager: manager,
            project: ProjectConfig(id: projectId, name: "Beta", path: "/tmp/beta", color: "blue", useAgentLayer: false),
            chrome: ChromeConfig(defaultTabs: ["https://example.com"])
        )

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        case .success(let success):
            XCTAssertEqual(success.ideWindowId, 201)
            XCTAssertEqual(success.tabRestoreWarning, "Chrome launched without tabs (tab restore failed)")
        }
    }

    func testSelectProjectRecencyDirectoryCreateFailureDoesNotFailActivation() async throws {
        let projectId = "gamma"
        let workspace = "ps-\(projectId)"

        let chromeWindow = PsWindow(windowId: 300, appBundleId: "com.google.Chrome", workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 301, appBundleId: "com.microsoft.VSCode", workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")

        let aerospace = SequencedAeroSpaceStub()
        aerospace.windowsForAppSequences = [
            "com.google.Chrome": [[chromeWindow]],
            "com.microsoft.VSCode": [[ideWindow]]
        ]
        aerospace.windowsWorkspaceSequence = [.success([chromeWindow, ideWindow])]
        aerospace.workspacesWithFocusSequence = [.success([PsWorkspaceSummary(workspace: workspace, isFocused: true)])]
        aerospace.focusedWindowSequence = [.success(ideWindow)]
        aerospace.focusWindowSuccessIds = [301]

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let notADirectory = tmp.appendingPathComponent("notadir")
        try Data("x".utf8).write(to: notADirectory, options: .atomic)
        let recencyFilePath = notADirectory.appendingPathComponent("recency.json")

        let manager = makeManager(aerospace: aerospace, chromeLauncher: ChromeLauncherFailingOnTabsStub(), recencyFilePath: recencyFilePath)
        loadConfig(
            manager: manager,
            project: ProjectConfig(id: projectId, name: "Gamma", path: "/tmp/gamma", color: "blue", useAgentLayer: false)
        )

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result {
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testSelectProjectRecencyWriteFailureDoesNotFailActivation() async throws {
        let projectId = "delta"
        let workspace = "ps-\(projectId)"

        let chromeWindow = PsWindow(windowId: 400, appBundleId: "com.google.Chrome", workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 401, appBundleId: "com.microsoft.VSCode", workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")

        let aerospace = SequencedAeroSpaceStub()
        aerospace.windowsForAppSequences = [
            "com.google.Chrome": [[chromeWindow]],
            "com.microsoft.VSCode": [[ideWindow]]
        ]
        aerospace.windowsWorkspaceSequence = [.success([chromeWindow, ideWindow])]
        aerospace.workspacesWithFocusSequence = [.success([PsWorkspaceSummary(workspace: workspace, isFocused: true)])]
        aerospace.focusedWindowSequence = [.success(ideWindow)]
        aerospace.focusWindowSuccessIds = [401]

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        // Point recencyFilePath at a directory so `data.write(to:)` fails.
        let recencyFilePath = tmp

        let manager = makeManager(aerospace: aerospace, chromeLauncher: ChromeLauncherFailingOnTabsStub(), recencyFilePath: recencyFilePath)
        loadConfig(
            manager: manager,
            project: ProjectConfig(id: projectId, name: "Delta", path: "/tmp/delta", color: "blue", useAgentLayer: false)
        )

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result {
            XCTFail("Expected success, got error: \(error)")
        }
    }
}
