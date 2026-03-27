import Foundation
@testable import ProjectSwitcherCore

final class WorkspaceStateAeroSpaceStub: AeroSpaceProviding {
    let listWorkspacesWithFocusResult: Result<[PsWorkspaceSummary], PsCoreError>

    init(listWorkspacesWithFocusResult: Result<[PsWorkspaceSummary], PsCoreError>) {
        self.listWorkspacesWithFocusResult = listWorkspacesWithFocusResult
    }

    func getWorkspaces() -> Result<[String], PsCoreError> {
        .success([])
    }

    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> {
        .success(false)
    }

    func listWorkspacesFocused() -> Result<[String], PsCoreError> {
        .success([])
    }

    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> {
        listWorkspacesWithFocusResult
    }

    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> {
        .success(())
    }

    func closeWorkspace(name: String) -> Result<Void, PsCoreError> {
        .success(())
    }

    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> {
        .success([])
    }

    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
        .success([])
    }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }

    func focusedWindow() -> Result<PsWindow, PsCoreError> {
        .failure(PsCoreError(message: "not used in this test"))
    }

    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
        .success(())
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> {
        .success(())
    }

    func focusWorkspace(name: String) -> Result<Void, PsCoreError> {
        .success(())
    }
}

struct WorkspaceStateIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> {
        .success(())
    }
}

struct WorkspaceStateChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> {
        .success(())
    }
}

struct WorkspaceStateTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> {
        .success([])
    }
}

struct WorkspaceStateGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? {
        nil
    }
}

struct WorkspaceStateLoggerStub: ProjectSwitcherLogging {
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        .success(())
    }
}


final class RecordingFocusAeroSpaceStub: AeroSpaceProviding {
    var focusWindowSuccessIds: Set<Int> = []
    private(set) var focusedWindowIds: [Int] = []

    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { .success([]) }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }
    func focusedWindow() -> Result<PsWindow, PsCoreError> { .failure(PsCoreError(message: "not used")) }

    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
        focusedWindowIds.append(windowId)
        if focusWindowSuccessIds.contains(windowId) {
            return .success(())
        }
        return .failure(PsCoreError(message: "window not found"))
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
}

final class AlwaysDifferentFocusAeroSpaceStub: AeroSpaceProviding {
    var focusWindowSuccessIds: Set<Int> = []
    private(set) var focusedWindowIds: [Int] = []

    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { .success([]) }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }

    func focusedWindow() -> Result<PsWindow, PsCoreError> {
        .success(PsWindow(windowId: 999, appBundleId: "other", workspace: "main", windowTitle: "Other"))
    }

    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
        focusedWindowIds.append(windowId)
        if focusWindowSuccessIds.contains(windowId) {
            return .success(())
        }
        return .failure(PsCoreError(message: "window not found"))
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
}
