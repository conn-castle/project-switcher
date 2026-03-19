import Foundation

extension ProjectManager {
    /// Moves a window to the specified project's workspace.
    /// - Parameters:
    ///   - windowId: AeroSpace window ID of the window to move.
    ///   - projectId: Target project ID (workspace will be `ap-<projectId>`).
    /// - Returns: Success or error.
    public func moveWindowToProject(windowId: Int, projectId: String) -> Result<Void, ProjectError> {
        let configSnapshot = withState { config }
        guard let configSnapshot else {
            return .failure(.configNotLoaded)
        }
        guard configSnapshot.projects.contains(where: { $0.id == projectId }) else {
            return .failure(.projectNotFound(projectId: projectId))
        }
        let targetWorkspace = Self.workspacePrefix + projectId
        switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: windowId, focusFollows: false) {
        case .success:
            invalidateFocusHistory(windowId: windowId, reason: "moved_to_project")
            logEvent("move_window.completed", context: [
                "window_id": "\(windowId)",
                "project_id": projectId,
                "workspace": targetWorkspace
            ])
            return .success(())
        case .failure(let error):
            logEvent("move_window.failed", level: .error, message: error.message, context: [
                "window_id": "\(windowId)",
                "project_id": projectId
            ])
            return .failure(.aeroSpaceError(detail: error.message))
        }
    }

    /// Moves a window out of its project workspace to the preferred non-project workspace.
    ///
    /// Destination is selected via ``WorkspaceRouting/preferredNonProjectWorkspace(from:hasWindows:)``
    /// which prefers a non-project workspace that already has windows, falling back to
    /// ``WorkspaceRouting/fallbackWorkspace`` when no candidate exists.
    ///
    /// - Parameter windowId: AeroSpace window ID of the window to move.
    /// - Returns: Success or error.
    public func moveWindowFromProject(windowId: Int) -> Result<Void, ProjectError> {
        let configSnapshot = withState { config }
        guard configSnapshot != nil else {
            return .failure(.configNotLoaded)
        }

        let windowLookup = listAllWindowsById()

        // Select destination using canonical non-project workspace strategy.
        // Fast path: derive workspaces-with-windows from a single listAllWindows call,
        // then validate the chosen destination via per-workspace listing.
        // Fallback: if either global lookup or destination validation fails, use
        // per-workspace listings and exclude failures.
        let destination: String
        if case .success(let workspaces) = aerospace.getWorkspaces() {
            if let windowLookup {
                destination = preferredNonProjectWorkspaceFromLookup(
                    workspaces: workspaces,
                    windowLookup: windowLookup
                )
            } else {
                destination = preferredNonProjectWorkspaceByListing(workspaces)
            }
        } else {
            destination = WorkspaceRouting.fallbackWorkspace
        }

        switch aerospace.moveWindowToWorkspace(workspace: destination, windowId: windowId, focusFollows: false) {
        case .success:
            if let windowLookup {
                updateMostRecentNonProjectFocus(
                    windowId: windowId,
                    destinationWorkspace: destination,
                    windowLookup: windowLookup
                )
            }
            logEvent("move_window_from_project.completed", context: [
                "window_id": "\(windowId)",
                "destination": destination
            ])
            return .success(())
        case .failure(let error):
            logEvent("move_window_from_project.failed", level: .error, message: error.message, context: [
                "window_id": "\(windowId)",
                "destination": destination
            ])
            return .failure(.aeroSpaceError(detail: error.message))
        }
    }

    private func preferredNonProjectWorkspaceFromLookup(
        workspaces: [String],
        windowLookup: [Int: ApWindow]
    ) -> String {
        var workspacesWithWindows: Set<String> = []
        for window in windowLookup.values {
            workspacesWithWindows.insert(window.workspace)
        }
        let hasNonProjectWorkspaceWithWindows = workspaces.contains {
            !$0.hasPrefix(Self.workspacePrefix) && workspacesWithWindows.contains($0)
        }
        guard hasNonProjectWorkspaceWithWindows else {
            return preferredNonProjectWorkspaceByListing(workspaces)
        }

        let candidate = WorkspaceRouting.preferredNonProjectWorkspace(
            from: workspaces,
            hasWindows: { workspacesWithWindows.contains($0) }
        )
        guard case .success(let candidateWindows) = aerospace.listWindowsWorkspace(workspace: candidate),
              !candidateWindows.isEmpty else {
            return preferredNonProjectWorkspaceByListing(workspaces)
        }
        return candidate
    }

    private func preferredNonProjectWorkspaceByListing(_ workspaces: [String]) -> String {
        var queriedWorkspaces: [String] = []
        var workspacesWithWindows: Set<String> = []
        for ws in workspaces {
            if case .success(let windows) = aerospace.listWindowsWorkspace(workspace: ws) {
                queriedWorkspaces.append(ws)
                if !windows.isEmpty {
                    workspacesWithWindows.insert(ws)
                }
            }
        }
        return WorkspaceRouting.preferredNonProjectWorkspace(
            from: queriedWorkspaces,
            hasWindows: { workspacesWithWindows.contains($0) }
        )
    }

    /// Exits to the last non-project window without closing the project.
    public func exitToNonProjectWindow() async -> Result<Void, ProjectError> {
        let state: ProjectWorkspaceState
        switch workspaceState() {
        case .failure(let error):
            return .failure(error)
        case .success(let snapshot):
            state = snapshot
        }

        guard let activeProjectId = state.activeProjectId else {
            logEvent("exit.no_active_project", level: .warn)
            return .failure(.noActiveProject)
        }

        // Capture window positions before exiting (non-fatal)
        await captureWindowPositions(projectId: activeProjectId)

        let restoredFocus = restoreNonProjectFocus(windowLookup: listAllWindowsById())

        if let focus = restoredFocus {
            logEvent("exit.focus_restored", context: [
                "window_id": "\(focus.windowId)",
                "workspace": focus.workspace
            ])
            logEvent("exit.completed")
            return .success(())
        } else if let ws = fallbackToNonProjectWorkspace() {
            logEvent("exit.focus_fallback_workspace", context: ["workspace": ws])
            logEvent("exit.completed")
            return .success(())
        } else {
            logEvent("exit.no_previous_window", level: .warn)
            return .failure(.noPreviousWindow)
        }
    }

    /// Falls back to focusing a non-project workspace when the focus stack is exhausted.
    ///
    /// Strategy (priority order):
    /// 1. Focus a concrete window in the first non-project workspace that has windows.
    /// 2. Focus any non-project workspace (even if empty) to leave project space.
    /// 3. Focus the canonical fallback workspace ("1") as a last resort.
    ///
    /// - Returns: The workspace name that was focused, or nil if all attempts failed.
    func fallbackToNonProjectWorkspace() -> String? {
        guard case .success(let workspaces) = aerospace.listWorkspacesWithFocus() else {
            // AeroSpace unreachable — try the canonical fallback workspace directly.
            if focusWorkspace(name: WorkspaceRouting.fallbackWorkspace) {
                return WorkspaceRouting.fallbackWorkspace
            }
            return nil
        }
        let nonProjectWorkspaces = workspaces.filter { !$0.workspace.hasPrefix(Self.workspacePrefix) }

        // 1. Prefer the first non-project workspace where we can actually focus a window.
        for candidate in nonProjectWorkspaces {
            guard case .success(let windows) = aerospace.listWindowsWorkspace(workspace: candidate.workspace),
                  !windows.isEmpty else { continue }
            guard focusWorkspace(name: candidate.workspace) else { continue }
            guard let focused = focusFirstWindow(windows) else { continue }
            recoverFocusedWindowIfNeeded(bundleId: focused.appBundleId)
            updateMostRecentNonProjectFocus(focused)
            return candidate.workspace
        }

        // 2. Focus any non-project workspace (even empty) to leave project space.
        for candidate in nonProjectWorkspaces {
            if focusWorkspace(name: candidate.workspace) {
                return candidate.workspace
            }
        }

        // 3. Last resort: focus the canonical fallback workspace.
        if focusWorkspace(name: WorkspaceRouting.fallbackWorkspace) {
            return WorkspaceRouting.fallbackWorkspace
        }

        return nil
    }

    /// Focuses the first focusable window from a candidate list.
    ///
    /// - Parameter windows: Candidate windows to attempt, in priority order.
    /// - Returns: Captured focus for the window that was focused, or nil if none can be focused.
    private func focusFirstWindow(_ windows: [ApWindow]) -> CapturedFocus? {
        for window in windows {
            if focusWindow(windowId: window.windowId) {
                return CapturedFocus(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: window.workspace
                )
            }
        }
        return nil
    }

}
