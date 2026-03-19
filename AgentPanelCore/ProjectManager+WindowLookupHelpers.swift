import Foundation

extension ProjectManager {
    // MARK: - Private Helpers

    /// Returns an AgentPanel project ID from a workspace name.
    /// Delegates to ``WorkspaceRouting/projectId(fromWorkspace:)``.
    /// - Parameter workspace: Raw AeroSpace workspace name.
    /// - Returns: Project ID when workspace uses the project prefix, otherwise nil.
    static func projectId(fromWorkspace workspace: String) -> String? {
        WorkspaceRouting.projectId(fromWorkspace: workspace)
    }

    /// Polls until the target workspace is confirmed focused via dual-signal verification.
    ///
    /// Always calls `focusWorkspace` (summon-workspace) before accepting verification,
    /// ensuring the workspace is pulled to the current monitor/desktop space.
    /// Verification requires both:
    /// - `listWorkspacesWithFocus` reporting the target workspace as focused, and
    /// - `focusedWindow().workspace` matching the target workspace.
    func ensureWorkspaceFocused(name: String) async -> Bool {
        let deadline = Date().addingTimeInterval(windowPollTimeout)

        while Date() < deadline {
            // Always attempt focus first (summon-workspace pulls workspace to current monitor)
            _ = aerospace.focusWorkspace(name: name)

            // Dual-signal verification:
            // Signal 1: workspace summary reports target as focused
            guard case .success(let workspaces) = aerospace.listWorkspacesWithFocus(),
                  workspaces.contains(where: { $0.workspace == name && $0.isFocused }) else {
                try? await Task.sleep(nanoseconds: UInt64(windowPollInterval * 1_000_000_000))
                continue
            }

            // Signal 2: focused window is in the target workspace
            if case .success(let focusedWin) = aerospace.focusedWindow(),
               focusedWin.workspace == name {
                logEvent("focus.workspace.verified", context: ["workspace": name])
                return true
            }

            try? await Task.sleep(nanoseconds: UInt64(windowPollInterval * 1_000_000_000))
        }

        logEvent("focus.workspace.timeout", level: .warn, context: [
            "workspace": name,
            "timeout_seconds": String(format: "%.1f", windowPollTimeout)
        ])
        return false
    }

    /// Finds a tagged window for the given app across all monitors.
    func findWindowByToken(appBundleId: String, projectId: String) -> ApWindow? {
        let windows: [ApWindow]
        switch aerospace.listWindowsForApp(bundleId: appBundleId) {
        case .success(let result):
            windows = result
        case .failure(let error):
            logEvent("window_lookup.list_failed", level: .warn,
                     message: error.message,
                     context: ["app_bundle_id": appBundleId, "project_id": projectId])
            return nil
        }
        let token = "\(ApIdeToken.prefix)\(projectId)"
        return windows.first { $0.windowTitle.contains(token) }
    }

    /// Polls for a tagged window to appear after launch.
    func pollForWindowByToken(
        appBundleId: String,
        projectId: String,
        windowLabel: String
    ) async -> Result<ApWindow, ProjectError> {
        let deadline = Date().addingTimeInterval(windowPollTimeout)

        while Date() < deadline {
            if let window = findWindowByToken(appBundleId: appBundleId, projectId: projectId) {
                return .success(window)
            }
            try? await Task.sleep(nanoseconds: UInt64(windowPollInterval * 1_000_000_000))
        }

        return .failure(.windowNotFound(detail: "\(windowLabel) window did not appear within timeout"))
    }

    /// Polls until both windows are in the target workspace.
    func pollForWindowsInWorkspace(chromeWindowId: Int, ideWindowId: Int, workspace: String) async -> Result<Void, ProjectError> {
        let deadline = Date().addingTimeInterval(windowPollTimeout)
        var loggedQueryFailure = false

        while Date() < deadline {
            switch aerospace.listWindowsWorkspace(workspace: workspace) {
            case .failure(let error):
                if !loggedQueryFailure {
                    logEvent("select.workspace_query_pending",
                             message: error.message,
                             context: ["workspace": workspace])
                    loggedQueryFailure = true
                }
            case .success(let windows):
                let windowIds = Set(windows.map { $0.windowId })
                if windowIds.contains(chromeWindowId) && windowIds.contains(ideWindowId) {
                    logEvent("select.windows_verified_in_workspace", context: ["workspace": workspace])
                    return .success(())
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(windowPollInterval * 1_000_000_000))
        }

        return .failure(.aeroSpaceError(detail: "Windows did not arrive in workspace within timeout"))
    }

}
