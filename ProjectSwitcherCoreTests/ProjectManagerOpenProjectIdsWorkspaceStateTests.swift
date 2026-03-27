import Foundation
import XCTest
@testable import ProjectSwitcherCore

final class ProjectManagerWorkspaceStateTests: XCTestCase {

    func testWorkspaceStateReturnsOpenProjectIdsAndActiveProjectId() {
        let aerospace = WorkspaceStateAeroSpaceStub(
            listWorkspacesWithFocusResult: .success([
                PsWorkspaceSummary(workspace: "main", isFocused: false),
                PsWorkspaceSummary(workspace: "ps-alpha", isFocused: false),
                PsWorkspaceSummary(workspace: "ps-beta", isFocused: true),
                PsWorkspaceSummary(workspace: "ps-alpha", isFocused: false)
            ])
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.workspaceState() {
        case .success(let state):
            XCTAssertEqual(state.activeProjectId, "beta")
            XCTAssertEqual(state.openProjectIds, Set(["alpha", "beta"]))
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWorkspaceStateIgnoresFocusedNonProjectWorkspace() {
        let aerospace = WorkspaceStateAeroSpaceStub(
            listWorkspacesWithFocusResult: .success([
                PsWorkspaceSummary(workspace: "main", isFocused: true),
                PsWorkspaceSummary(workspace: "ps-alpha", isFocused: false)
            ])
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.workspaceState() {
        case .success(let state):
            XCTAssertNil(state.activeProjectId)
            XCTAssertEqual(state.openProjectIds, Set(["alpha"]))
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWorkspaceStateReturnsAeroSpaceFailureWhenWorkspaceQueryFails() {
        let aerospace = WorkspaceStateAeroSpaceStub(
            listWorkspacesWithFocusResult: .failure(PsCoreError(message: "workspace query failed"))
        )
        let manager = makeManager(aerospace: aerospace)

        switch manager.workspaceState() {
        case .success(let state):
            XCTFail("Expected failure, got state: \(state)")
        case .failure(let error):
            XCTAssertEqual(error, .aeroSpaceError(detail: "workspace query failed"))
        }
    }

    private func makeManager(aerospace: WorkspaceStateAeroSpaceStub) -> ProjectManager {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyFilePath = tempDir
            .appendingPathComponent("pm-workspace-state-\(UUID().uuidString).json")
        let focusHistoryFilePath = tempDir
            .appendingPathComponent("pm-workspace-focus-\(UUID().uuidString).json")
        let chromeTabsDir = tempDir.appendingPathComponent("chrome-tabs-\(UUID().uuidString)", isDirectory: true)
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: WorkspaceStateIdeLauncherStub(),
            agentLayerIdeLauncher: WorkspaceStateIdeLauncherStub(),
            chromeLauncher: WorkspaceStateChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: WorkspaceStateTabCaptureStub(),
            gitRemoteResolver: WorkspaceStateGitRemoteStub(),
            logger: WorkspaceStateLoggerStub(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath
        )
    }
}
