import Foundation

extension ProjectManager {
    // MARK: - Private Helpers

    /// Returns a ProjectSwitcher project ID from a workspace name.
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
        var attemptCount = 0

        // AeroSpace recovery can consume the entire nominal polling window. Always
        // allow a second focus/verification cycle so a command that recovers the
        // daemon near the deadline can actually apply and verify the requested focus.
        while attemptCount < 2 || Date() < deadline {
            attemptCount += 1
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
    func findWindowByToken(appBundleId: String, projectId: String) -> PsWindow? {
        let windows: [PsWindow]
        switch aerospace.listWindowsForApp(bundleId: appBundleId) {
        case .success(let result):
            windows = result
        case .failure(let error):
            logEvent("window_lookup.list_failed", level: .warn,
                     message: error.message,
                     context: ["app_bundle_id": appBundleId, "project_id": projectId])
            return nil
        }
        return windows.first {
            PsIdeToken.matches(windowTitle: $0.windowTitle, projectId: projectId)
        }
    }

    /// Polls for a tagged window to appear after launch.
    func pollForWindowByToken(
        appBundleId: String,
        projectId: String,
        windowLabel: String,
        newWindowBaselineIds: Set<Int>? = nil
    ) async -> Result<PsWindow, ProjectError> {
        let deadline = Date().addingTimeInterval(windowPollTimeout)
        let fallbackEligibleAt = Date().addingTimeInterval(min(0.5, windowPollTimeout / 2))

        while Date() < deadline {
            switch aerospace.listWindowsForApp(bundleId: appBundleId) {
            case .success(let windows):
                if let window = windows.first(where: {
                    PsIdeToken.matches(windowTitle: $0.windowTitle, projectId: projectId)
                }) {
                    return .success(window)
                }

                // Prefer the authoritative title token for a brief grace period.
                // This prevents an unrelated Chrome popup created concurrently from
                // being adopted before the launched window's title has propagated.
                if Date() >= fallbackEligibleAt, let baselineIds = newWindowBaselineIds {
                    let newWindows = windows.filter { !baselineIds.contains($0.windowId) }
                    if newWindows.count == 1, let newWindow = newWindows.first {
                        logEvent("window_lookup.new_window_fallback", level: .warn, context: [
                            "app_bundle_id": appBundleId,
                            "project_id": projectId,
                            "window_id": "\(newWindow.windowId)"
                        ])
                        return .success(newWindow)
                    }
                }
            case .failure(let error):
                logEvent("window_lookup.list_failed", level: .warn,
                         message: error.message,
                         context: ["app_bundle_id": appBundleId, "project_id": projectId])
            }
            try? await Task.sleep(nanoseconds: UInt64(windowPollInterval * 1_000_000_000))
        }

        return .failure(.windowNotFound(detail: "\(windowLabel) window did not appear within timeout"))
    }

    /// Polls until the IDE is in the target workspace and reports whether optional Chrome arrived.
    func pollForWindowsInWorkspace(chromeWindowId: Int?, ideWindowId: Int, workspace: String) async -> Result<Bool, ProjectError> {
        let deadline = Date().addingTimeInterval(windowPollTimeout)
        var loggedQueryFailure = false
        var ideArrived = false
        var optionalChromeDeadline: Date?

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
                ideArrived = ideArrived || windowIds.contains(ideWindowId)
                let chromeArrived = chromeWindowId.map(windowIds.contains) ?? true
                if ideArrived && chromeArrived {
                    logEvent("select.windows_verified_in_workspace", context: ["workspace": workspace])
                    return .success(true)
                }
                if ideArrived, chromeWindowId != nil {
                    if optionalChromeDeadline == nil {
                        optionalChromeDeadline = Date().addingTimeInterval(min(0.5, windowPollTimeout / 2))
                    } else if let optionalChromeDeadline, Date() >= optionalChromeDeadline {
                        return .success(false)
                    }
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(windowPollInterval * 1_000_000_000))
        }

        if ideArrived {
            return .success(false)
        }
        return .failure(.aeroSpaceError(detail: "IDE window did not arrive in workspace within timeout"))
    }

}
