import Foundation
import XCTest
@testable import ProjectSwitcherCore

/// Tests for ProjectManager.moveWindowToProject().
final class ProjectManagerMoveWindowTests: XCTestCase {

    // MARK: - Test Doubles

    private struct NoopLogger: ProjectSwitcherLogging {
        func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
            .success(())
        }
    }

    private struct NoopIdeLauncher: IdeLauncherProviding {
        func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> { .success(()) }
    }

    private struct NoopChromeLauncher: ChromeLauncherProviding {
        func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> { .success(()) }
    }

    private struct NoopTabCapture: ChromeTabCapturing {
        func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> { .success([]) }
    }

    private struct NoopGitRemoteResolver: GitRemoteResolving {
        func resolve(projectPath: String) -> String? { nil }
    }

    private final class MoveAeroSpaceStub: AeroSpaceProviding {
        var moveResult: Result<Void, PsCoreError> = .success(())
        var moveWindowCalls: [(workspace: String, windowId: Int, focusFollows: Bool)] = []
        var workspaces: [String] = []
        var windowsByWorkspace: [String: [PsWindow]] = [:]
        var failingWorkspaces: Set<String> = []
        var listAllWindowsResultOverride: Result<[PsWindow], PsCoreError>?

        func getWorkspaces() -> Result<[String], PsCoreError> { .success(workspaces) }
        func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(true) }
        func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
        func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { .success([]) }
        func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
        func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
        func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
            if failingWorkspaces.contains(workspace) {
                return .failure(PsCoreError(message: "listing failed for \(workspace)"))
            }
            return .success(windowsByWorkspace[workspace] ?? [])
        }
        func listAllWindows() -> Result<[PsWindow], PsCoreError> {
            if let result = listAllWindowsResultOverride {
                return result
            }
            var windows: [PsWindow] = []
            var seenWindowIds: Set<Int> = []
            for list in windowsByWorkspace.values {
                for window in list where !seenWindowIds.contains(window.windowId) {
                    seenWindowIds.insert(window.windowId)
                    windows.append(window)
                }
            }
            return .success(windows)
        }
        func focusedWindow() -> Result<PsWindow, PsCoreError> { .failure(PsCoreError(message: "no focus")) }
        func focusWindow(windowId: Int) -> Result<Void, PsCoreError> { .success(()) }
        func focusWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }

        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> {
            moveWindowCalls.append((workspace, windowId, focusFollows))
            return moveResult
        }
    }

    // MARK: - Helpers

    private func makeProjectManager(aerospace: MoveAeroSpaceStub = MoveAeroSpaceStub()) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-move-recency-\(UUID().uuidString).json")
        let focusHistoryFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-move-focus-\(UUID().uuidString).json")
        let chromeTabsDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-move-tabs-\(UUID().uuidString)", isDirectory: true)
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: NoopIdeLauncher(),
            agentLayerIdeLauncher: NoopIdeLauncher(),
            chromeLauncher: NoopChromeLauncher(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: NoopTabCapture(),
            gitRemoteResolver: NoopGitRemoteResolver(),
            logger: NoopLogger(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath
        )
    }

    private func makeTestConfig(projectIds: [String] = ["myproject"]) -> Config {
        let projects = projectIds.map { id in
            ProjectConfig(
                id: id,
                name: id.capitalized,
                path: "/tmp/\(id)",
                color: "#FF0000",
                useAgentLayer: false
            )
        }
        return Config(projects: projects)
    }

    // MARK: - Tests

    func testMoveWindowToProject_success() {
        let aerospace = MoveAeroSpaceStub()
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig(projectIds: ["myproject"]))

        let result = pm.moveWindowToProject(windowId: 42, projectId: "myproject")

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls.count, 1)
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "ps-myproject")
        XCTAssertEqual(aerospace.moveWindowCalls[0].windowId, 42)
        XCTAssertFalse(aerospace.moveWindowCalls[0].focusFollows)
    }

    func testMoveWindowToProject_configNotLoaded() {
        let pm = makeProjectManager()
        // Don't load config

        let result = pm.moveWindowToProject(windowId: 42, projectId: "myproject")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .configNotLoaded)
    }

    func testMoveWindowToProject_projectNotFound() {
        let pm = makeProjectManager()
        pm.loadTestConfig(makeTestConfig(projectIds: ["other"]))

        let result = pm.moveWindowToProject(windowId: 42, projectId: "nonexistent")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .projectNotFound(projectId: "nonexistent"))
    }

    func testMoveWindowToProject_aeroSpaceError() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.moveResult = .failure(PsCoreError(message: "move rejected"))
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig(projectIds: ["myproject"]))

        let result = pm.moveWindowToProject(windowId: 42, projectId: "myproject")

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .aeroSpaceError(detail: "move rejected"))
    }

    func testMoveWindowToProject_correctWorkspacePrefix() {
        let aerospace = MoveAeroSpaceStub()
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig(projectIds: ["my-fancy-project"]))

        _ = pm.moveWindowToProject(windowId: 1, projectId: "my-fancy-project")

        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "ps-my-fancy-project")
    }

    // MARK: - moveWindowFromProject Tests

    func testMoveWindowFromProject_noWorkspaces_fallsBackToDefault() {
        let aerospace = MoveAeroSpaceStub()
        // No workspaces configured — should fall back to WorkspaceRouting.fallbackWorkspace
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls.count, 1)
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, WorkspaceRouting.fallbackWorkspace)
        XCTAssertEqual(aerospace.moveWindowCalls[0].windowId, 99)
        XCTAssertFalse(aerospace.moveWindowCalls[0].focusFollows)
    }

    func testMoveWindowFromProject_prefersNonProjectWorkspaceWithWindows() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["ps-myproject", "main", "empty-ws"]
        aerospace.windowsByWorkspace["main"] = [
            PsWindow(windowId: 50, appBundleId: "com.test.app", workspace: "main", windowTitle: "Existing Window")
        ]
        // "empty-ws" has no windows

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "main",
                       "Should target non-project workspace with windows")
    }

    func testMoveWindowFromProject_onlyProjectWorkspaces_fallsBackToDefault() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["ps-proj1", "ps-proj2"]
        aerospace.windowsByWorkspace["ps-proj1"] = [
            PsWindow(windowId: 50, appBundleId: "com.test.app", workspace: "ps-proj1", windowTitle: "W")
        ]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, WorkspaceRouting.fallbackWorkspace,
                       "Should fall back to default when only project workspaces exist")
    }

    func testMoveWindowFromProject_failedListingExcludesWorkspaceFromCandidates() {
        let aerospace = MoveAeroSpaceStub()
        // "broken-ws" is listed but its window listing fails; "healthy-ws" succeeds
        aerospace.workspaces = ["broken-ws", "healthy-ws"]
        aerospace.failingWorkspaces = ["broken-ws"]
        aerospace.windowsByWorkspace["healthy-ws"] = [
            PsWindow(windowId: 50, appBundleId: "com.test.app", workspace: "healthy-ws", windowTitle: "W")
        ]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, "healthy-ws",
                       "Should skip workspace with failed listing and use healthy candidate")
    }

    func testMoveWindowFromProject_fastPathCandidateWithFailedListingFallsBackToHealthyWorkspace() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["broken-ws", "healthy-ws"]
        aerospace.failingWorkspaces = ["broken-ws"]
        aerospace.windowsByWorkspace["broken-ws"] = [
            PsWindow(windowId: 61, appBundleId: "com.test.app", workspace: "broken-ws", windowTitle: "Broken")
        ]
        aerospace.windowsByWorkspace["healthy-ws"] = [
            PsWindow(windowId: 62, appBundleId: "com.test.app", workspace: "healthy-ws", windowTitle: "Healthy")
        ]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(
            aerospace.moveWindowCalls[0].workspace,
            "healthy-ws",
            "Fast-path candidate should be validated; failed listing must fall back to healthy workspace"
        )
    }

    func testMoveWindowFromProject_listAllWindowsFailureFallsBackToPerWorkspaceSelection() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["broken-ws", "healthy-ws"]
        aerospace.failingWorkspaces = ["broken-ws"]
        aerospace.listAllWindowsResultOverride = .failure(PsCoreError(message: "listAllWindows unavailable"))
        aerospace.windowsByWorkspace["healthy-ws"] = [
            PsWindow(windowId: 50, appBundleId: "com.test.app", workspace: "healthy-ws", windowTitle: "W")
        ]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(
            aerospace.moveWindowCalls[0].workspace,
            "healthy-ws",
            "Should fall back to per-workspace selection when listAllWindows fails"
        )
    }

    func testMoveWindowFromProject_allNonProjectListingsFail_fallsBackToDefault() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.workspaces = ["broken-ws"]
        aerospace.failingWorkspaces = ["broken-ws"]

        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .success = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(aerospace.moveWindowCalls[0].workspace, WorkspaceRouting.fallbackWorkspace,
                       "Should fall back to default when all non-project workspace listings fail")
    }

    func testMoveWindowFromProject_configNotLoaded() {
        let pm = makeProjectManager()

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .configNotLoaded)
    }

    func testMoveWindowFromProject_aeroSpaceError() {
        let aerospace = MoveAeroSpaceStub()
        aerospace.moveResult = .failure(PsCoreError(message: "move failed"))
        let pm = makeProjectManager(aerospace: aerospace)
        pm.loadTestConfig(makeTestConfig())

        let result = pm.moveWindowFromProject(windowId: 99)

        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertEqual(error, .aeroSpaceError(detail: "move failed"))
    }
}
