import Foundation

@testable import ProjectSwitcherCore
// MARK: - Test Doubles

final class FocusAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<PsWindow, PsCoreError> = .failure(PsCoreError(category: .command, message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[PsWorkspaceSummary], PsCoreError> = .success([])
    var focusedWindowIds: [Int] = []
    var listAllWindowsResultOverride: Result<[PsWindow], PsCoreError>?
    /// Callback invoked on each `focusWindow()` call — used to modify stub state during focus stabilization.
    var onFocusWindowAttempt: ((Int) -> Void)?

    /// Windows returned by `listWindowsForApp(bundleId:)`, keyed by bundle ID.
    var windowsByBundleId: [String: [PsWindow]] = [:]

    /// Windows returned by `listWindowsWorkspace(workspace:)`, keyed by workspace name.
    var windowsByWorkspace: [String: [PsWindow]] = [:]

    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> {
        .success(windowsByBundleId[bundleId] ?? [])
    }
    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> {
        if let override = listAllWindowsResultOverride {
            return override
        }
        var windows: [PsWindow] = []
        var seenIds: Set<Int> = []

        for list in windowsByWorkspace.values {
            for window in list where !seenIds.contains(window.windowId) {
                seenIds.insert(window.windowId)
                windows.append(window)
            }
        }
        for list in windowsByBundleId.values {
            for window in list where !seenIds.contains(window.windowId) {
                seenIds.insert(window.windowId)
                windows.append(window)
            }
        }

        return .success(windows)
    }
    private func windowById(_ windowId: Int) -> PsWindow? {
        for list in windowsByWorkspace.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        for list in windowsByBundleId.values {
            if let match = list.first(where: { $0.windowId == windowId }) {
                return match
            }
        }
        return nil
    }
    func focusedWindow() -> Result<PsWindow, PsCoreError> { focusedWindowResult }
    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
        focusedWindowIds.append(windowId)
        onFocusWindowAttempt?(windowId)
        if focusWindowSuccessIds.contains(windowId) {
            if case .success(let focused) = focusedWindowResult, focused.windowId == windowId {
                return .success(())
            }
            if let match = windowById(windowId) {
                focusedWindowResult = .success(match)
            }
            return .success(())
        }
        return .failure(PsCoreError(category: .command, message: "window \(windowId) not found"))
    }
    private(set) var focusedWorkspaces: [String] = []
    var focusWorkspaceResult: Result<Void, PsCoreError> = .success(())

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, PsCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }
}

final class FocusIdeLauncherStub: IdeLauncherProviding {
    var result: Result<Void, PsCoreError> = .success(())
    private(set) var called = false
    /// Optional callback invoked on launch — used to inject windows into AeroSpace stub.
    var onLaunch: ((String) -> Void)?

    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> {
        called = true
        onLaunch?(identifier)
        return result
    }
}

struct FocusChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> { .success(()) }
}

final class FocusChromeLauncherRecordingStub: ChromeLauncherProviding {
    private(set) var calls: [(identifier: String, initialURLs: [String])] = []
    var onLaunch: ((String) -> Void)?

    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> {
        calls.append((identifier: identifier, initialURLs: initialURLs))
        onLaunch?(identifier)
        return .success(())
    }
}

final class FocusTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> { .success([]) }
}

struct FocusGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

struct FocusLoggerStub: ProjectSwitcherLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> { .success(()) }
}

final class FocusWindowPositionerStub: WindowPositioning {
    private(set) var recoverFocusedCalls: [(bundleId: String, screenFrame: CGRect)] = []
    var recoverFocusedResult: Result<RecoveryOutcome, PsCoreError> = .success(.unchanged)

    func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
        recoverFocusedCalls.append((bundleId, screenVisibleFrame))
        return recoverFocusedResult
    }

    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError> {
        .failure(PsCoreError(category: .window, message: "stub"))
    }
    func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
        .failure(PsCoreError(category: .window, message: "stub"))
    }
    func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> { .success(.unchanged) }
    func isAccessibilityTrusted() -> Bool { true }
    func promptForAccessibility() -> Bool { true }
}
