import Foundation

@testable import AgentPanelCore
// MARK: - Test Doubles

final class FocusAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<ApWindow, ApCoreError> = .failure(ApCoreError(category: .command, message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[ApWorkspaceSummary], ApCoreError> = .success([])
    var focusedWindowIds: [Int] = []
    var listAllWindowsResultOverride: Result<[ApWindow], ApCoreError>?
    /// Callback invoked on each `focusWindow()` call — used to modify stub state during focus stabilization.
    var onFocusWindowAttempt: ((Int) -> Void)?

    /// Windows returned by `listWindowsForApp(bundleId:)`, keyed by bundle ID.
    var windowsByBundleId: [String: [ApWindow]] = [:]

    /// Windows returned by `listWindowsWorkspace(workspace:)`, keyed by workspace name.
    var windowsByWorkspace: [String: [ApWindow]] = [:]

    func getWorkspaces() -> Result<[String], ApCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], ApCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByBundleId[bundleId] ?? [])
    }
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }
    func listAllWindows() -> Result<[ApWindow], ApCoreError> {
        if let override = listAllWindowsResultOverride {
            return override
        }
        var windows: [ApWindow] = []
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
    private func windowById(_ windowId: Int) -> ApWindow? {
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
    func focusedWindow() -> Result<ApWindow, ApCoreError> { focusedWindowResult }
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
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
        return .failure(ApCoreError(category: .command, message: "window \(windowId) not found"))
    }
    private(set) var focusedWorkspaces: [String] = []
    var focusWorkspaceResult: Result<Void, ApCoreError> = .success(())

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, ApCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }
}

final class FocusIdeLauncherStub: IdeLauncherProviding {
    var result: Result<Void, ApCoreError> = .success(())
    private(set) var called = false
    /// Optional callback invoked on launch — used to inject windows into AeroSpace stub.
    var onLaunch: ((String) -> Void)?

    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, ApCoreError> {
        called = true
        onLaunch?(identifier)
        return result
    }
}

struct FocusChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> { .success(()) }
}

final class FocusChromeLauncherRecordingStub: ChromeLauncherProviding {
    private(set) var calls: [(identifier: String, initialURLs: [String])] = []
    var onLaunch: ((String) -> Void)?

    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, ApCoreError> {
        calls.append((identifier: identifier, initialURLs: initialURLs))
        onLaunch?(identifier)
        return .success(())
    }
}

final class FocusTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], ApCoreError> { .success([]) }
}

struct FocusGitRemoteStub: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

struct FocusLoggerStub: AgentPanelLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> { .success(()) }
}

final class FocusWindowPositionerStub: WindowPositioning {
    private(set) var recoverFocusedCalls: [(bundleId: String, screenFrame: CGRect)] = []
    var recoverFocusedResult: Result<RecoveryOutcome, ApCoreError> = .success(.unchanged)

    func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> {
        recoverFocusedCalls.append((bundleId, screenVisibleFrame))
        return recoverFocusedResult
    }

    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, ApCoreError> {
        .failure(ApCoreError(category: .window, message: "stub"))
    }
    func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, ApCoreError> {
        .failure(ApCoreError(category: .window, message: "stub"))
    }
    func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, ApCoreError> { .success(.unchanged) }
    func isAccessibilityTrusted() -> Bool { true }
    func promptForAccessibility() -> Bool { true }
}
