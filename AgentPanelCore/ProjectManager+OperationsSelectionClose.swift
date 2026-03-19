import Foundation

extension ProjectManager {
    // MARK: - Project Operations

    /// Activates a project by ID (sequential flow).
    ///
    /// Runs the full activation sequence matching the proven shell-script order exactly:
    /// 1. Look up project in config
    /// 2. Store pre-captured focus (for later exit)
    /// 3. Find or launch Chrome (do NOT move yet)
    /// 4. Find or launch VS Code (do NOT move yet)
    /// 5. Move Chrome to workspace (no focus follow)
    /// 6. Move VS Code to workspace (with focus follow)
    /// 7. Verify both windows arrived in workspace
    /// 8. Focus workspace (poll until confirmed)
    /// 9. Focus IDE window + verify stability
    ///
    /// The order is critical: both windows must exist before any moves happen.
    /// Moving Chrome before VS Code is launched can cause VS Code to open on
    /// a different macOS Space.
    ///
    /// - Parameters:
    ///   - projectId: The project ID to activate.
    ///   - preCapturedFocus: Focus state captured before showing UI, used for restoring
    ///     focus when exiting the project later.
    /// - Returns: Activation success (IDE window ID + optional tab restore warning) or error.
    public func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<ProjectActivationSuccess, ProjectError> {
        await selectProject(projectId: projectId, preCapturedFocus: preCapturedFocus as CapturedFocus?)
    }

    /// Activates a project with optional pre-captured focus.
    ///
    /// When `preCapturedFocus` is nil (e.g., focus capture failed before switcher opened),
    /// activation proceeds normally but no new focus entry is pushed to history.
    /// Exit/close can still restore from existing focus history; if none is restorable,
    /// workspace routing fallback is used.
    ///
    /// - Parameters:
    ///   - projectId: The project ID to activate.
    ///   - preCapturedFocus: Focus state captured before showing UI, or nil if capture failed.
    /// - Returns: Activation success (IDE window ID + optional tab restore warning) or error.
    public func selectProject(projectId: String, preCapturedFocus: CapturedFocus?) async -> Result<ProjectActivationSuccess, ProjectError> {
        let configSnapshot = withState { config }
        guard let configSnapshot else {
            return .failure(.configNotLoaded)
        }

        guard let project = configSnapshot.projects.first(where: { $0.id == projectId }) else {
            logEvent("select.project_not_found", level: .warn, context: ["project_id": projectId])
            return .failure(.projectNotFound(projectId: projectId))
        }

        let targetWorkspace = Self.workspacePrefix + projectId

        if let preCapturedFocus {
            // Push pre-captured focus for "exit project space" restoration.
            // Only push if the user is coming from outside project space.
            // Project-to-project switches (ap-* workspace) are not recorded.
            if !preCapturedFocus.workspace.hasPrefix(Self.workspacePrefix) {
                pushNonProjectFocusForExit(preCapturedFocus)
            } else {
                logEvent("focus.push_skipped_project_workspace", context: [
                    "workspace": preCapturedFocus.workspace,
                    "window_id": "\(preCapturedFocus.windowId)"
                ])
            }

            // Capture window positions for the source project before switching away.
            // Only when coming from another project workspace (ap-*).
            if let sourceProjectId = Self.projectId(fromWorkspace: preCapturedFocus.workspace) {
                await captureWindowPositions(projectId: sourceProjectId)
            }
        } else {
            logEvent("select.no_prefocus", level: .warn, context: [
                "project_id": projectId,
                "detail": "Focus capture failed before switcher; restore will use workspace routing"
            ])
        }

        // --- Phase 1: Find or launch all windows (no moves yet) ---

        let chromeWindow: ApWindow
        var chromeFreshlyLaunched = false
        var tabRestoreWarning: String?

        // Check for existing Chrome window first (avoids resolving URLs when not needed)
        if let existingWindow = findWindowByToken(appBundleId: ApChromeLauncher.bundleId, projectId: projectId) {
            logEvent(Self.activationWindowEventName(source: "chrome", action: "found"), context: ["window_id": "\(existingWindow.windowId)"])
            chromeWindow = existingWindow
        } else {
            // Chrome needs a fresh launch — resolve URLs now
            let chromeInitialURLs = resolveInitialURLs(project: project, projectId: projectId)

            switch await findOrLaunchWindow(
                appBundleId: ApChromeLauncher.bundleId,
                projectId: projectId,
                launchAction: { self.chromeLauncher.openNewWindow(identifier: projectId, initialURLs: chromeInitialURLs) },
                windowLabel: "Chrome",
                eventSource: "chrome"
            ) {
            case .failure(let error):
                // If launch-with-tabs failed and we had tabs, retry without tabs
                if !chromeInitialURLs.isEmpty {
                    logEvent("select.chrome_tab_launch_failed", level: .warn, message: "\(error)")
                    switch await findOrLaunchWindow(
                        appBundleId: ApChromeLauncher.bundleId,
                        projectId: projectId,
                        launchAction: { self.chromeLauncher.openNewWindow(identifier: projectId, initialURLs: []) },
                        windowLabel: "Chrome",
                        eventSource: "chrome"
                    ) {
                    case .failure(let fallbackError):
                        return .failure(fallbackError)
                    case .success(let outcome):
                        chromeWindow = outcome.window
                        chromeFreshlyLaunched = outcome.wasLaunched
                        tabRestoreWarning = "Chrome launched without tabs (tab restore failed)"
                    }
                } else {
                    return .failure(error)
                }
            case .success(let outcome):
                chromeWindow = outcome.window
                chromeFreshlyLaunched = outcome.wasLaunched
            }
        }

        let ideWindow: ApWindow
        let selectedIdeLauncher = project.useAgentLayer ? agentLayerIdeLauncher : ideLauncher
        switch await findOrLaunchWindow(
            appBundleId: ApVSCodeLauncher.bundleId,
            projectId: projectId,
            launchAction: {
                selectedIdeLauncher.openNewWindow(
                    identifier: projectId,
                    projectPath: project.path,
                    remoteAuthority: project.remote,
                    color: project.color
                )
            },
            windowLabel: "VS Code",
            eventSource: "vscode"
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let outcome):
            ideWindow = outcome.window
        }

        // --- Phase 2: Move windows to workspace (Chrome first, then VS Code) ---

        let chromeWindowId = chromeWindow.windowId
        let ideWindowId = ideWindow.windowId

        if chromeWindow.workspace != targetWorkspace {
            logEvent("select.chrome_moving", context: ["window_id": "\(chromeWindowId)", "workspace": targetWorkspace])
            switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: chromeWindowId, focusFollows: false) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.chrome_moved", context: ["workspace": targetWorkspace])
            }
        }

        if ideWindow.workspace != targetWorkspace {
            logEvent("select.vscode_moving", context: ["window_id": "\(ideWindowId)", "workspace": targetWorkspace, "focus_follows": "true"])
            switch aerospace.moveWindowToWorkspace(workspace: targetWorkspace, windowId: ideWindowId, focusFollows: true) {
            case .failure(let error):
                return .failure(.aeroSpaceError(detail: error.message))
            case .success:
                logEvent("select.vscode_moved", context: ["workspace": targetWorkspace])
            }
        }

        // --- Phase 3: Verify, focus workspace, focus IDE ---

        switch await pollForWindowsInWorkspace(
            chromeWindowId: chromeWindowId,
            ideWindowId: ideWindowId,
            workspace: targetWorkspace
        ) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        // Ensure moved project windows are removed from non-project focus history.
        invalidateFocusHistory(windowId: chromeWindowId, reason: "moved_to_project")
        invalidateFocusHistory(windowId: ideWindowId, reason: "moved_to_project")

        if !(await ensureWorkspaceFocused(name: targetWorkspace)) {
            let detail = "Workspace \(targetWorkspace) could not be focused within timeout"
            logEvent("select.workspace_focus_failed", level: .error, message: detail)
            return .failure(.aeroSpaceError(detail: detail))
        }

        _ = aerospace.focusWindow(windowId: ideWindowId)
        if !(await focusWindowStable(windowId: ideWindowId)) {
            let detail = "IDE window \(ideWindowId) could not be stably focused in workspace \(targetWorkspace)"
            logEvent("select.focus_unstable", level: .error, message: detail)
            return .failure(.focusUnstable(detail: detail))
        }

        if chromeFreshlyLaunched {
            logEvent("select.chrome_fresh_launch", context: ["project_id": projectId])
        }

        // Position windows (non-fatal)
        let layoutWarning = await positionWindows(projectId: projectId)

        // Store pre-entry focus for close-project restoration now that activation
        // succeeded. Stored here (not earlier) so failure paths never leave stale entries.
        if let preCapturedFocus {
            withState {
                preEntryFocus[projectId] = FocusHistoryEntry(focus: preCapturedFocus, capturedAt: Date())
            }
            logEvent("focus.pre_entry_stored", context: [
                "project_id": projectId,
                "source_window_id": "\(preCapturedFocus.windowId)",
                "source_workspace": preCapturedFocus.workspace
            ])
        }

        // Record activation
        recordActivation(projectId: projectId)
        logEvent("select.completed", context: ["project_id": projectId, "ide_window_id": "\(ideWindowId)"])

        return .success(ProjectActivationSuccess(
            ideWindowId: ideWindowId,
            tabRestoreWarning: tabRestoreWarning,
            layoutWarning: layoutWarning
        ))
    }

    /// Closes a project by ID and restores focus to non-project space.
    public func closeProject(projectId: String) async -> Result<ProjectCloseSuccess, ProjectError> {
        let configSnapshot = withState { config }
        guard let configSnapshot else {
            return .failure(.configNotLoaded)
        }

        guard configSnapshot.projects.contains(where: { $0.id == projectId }) else {
            return .failure(.projectNotFound(projectId: projectId))
        }

        // Capture Chrome tabs before closing (non-fatal)
        let tabCaptureWarning = performTabCapture(projectId: projectId)

        // Capture window positions before closing (non-fatal)
        await captureWindowPositions(projectId: projectId)

        let workspace = Self.workspacePrefix + projectId

        switch aerospace.closeWorkspace(name: workspace) {
        case .failure(let error):
            logEvent("close.failed", level: .error, context: [
                "project_id": projectId,
                "workspace": workspace,
                "error": error.message
            ])
            return .failure(.aeroSpaceError(detail: error.message))
        case .success:
            logEvent("close.workspace_closed", context: ["project_id": projectId])
        }

        // Flush stale tree nodes after closing the workspace. AeroSpace may leave
        // floating window nodes in an unbound state after workspace closure, causing
        // the subsequent focus command to crash in makeFloatingWindowsSeenAsTiling
        // with "MacWindow is already unbound". Reloading the config clears this state.
        if case .failure(let reloadError) = aerospace.reloadConfig() {
            logEvent("close.post_close_reload_failed", level: .warn,
                     message: reloadError.message,
                     context: ["project_id": projectId])
        }

        // Try restoring the focus that was active when this project was first entered.
        // This handles cross-project transitions (A→B→close B→restore A) that the
        // non-project focus stack cannot track.
        let preEntry: FocusHistoryEntry? = withState { preEntryFocus.removeValue(forKey: projectId) }
        let windowLookup = listAllWindowsById()
        var restoredFocus: CapturedFocus?

        if let preEntry {
            // Never restore to the workspace currently being closed.
            // This can happen if a stale/same-project pre-entry snapshot exists.
            if preEntry.focus.workspace == workspace {
                logEvent("close.pre_entry_focus_skipped_same_workspace", context: [
                    "project_id": projectId,
                    "workspace": workspace,
                    "window_id": "\(preEntry.focus.windowId)"
                ])
            } else if windowLookup == nil || windowLookup?[preEntry.focus.windowId] != nil {
                // Attempt restore even when lookup is unavailable (transient failure);
                // use lookup only as a validation step when present.
                switch aerospace.focusWindow(windowId: preEntry.focus.windowId) {
                case .success:
                    restoredFocus = preEntry.focus
                    logEvent("close.focus_restored_pre_entry", context: [
                        "project_id": projectId,
                        "window_id": "\(preEntry.focus.windowId)",
                        "app": preEntry.focus.appBundleId,
                        "source_workspace": preEntry.focus.workspace,
                        "lookup_available": "\(windowLookup != nil)"
                    ])
                case .failure(let error):
                    logEvent("close.pre_entry_focus_failed", level: .warn, message: error.message, context: [
                        "project_id": projectId,
                        "window_id": "\(preEntry.focus.windowId)",
                        "workspace": preEntry.focus.workspace
                    ])
                }
            } else {
                logEvent("close.pre_entry_focus_window_gone", context: [
                    "project_id": projectId,
                    "window_id": "\(preEntry.focus.windowId)"
                ])
            }
        }

        // Fall back to existing stack-based restoration if pre-entry didn't work.
        if restoredFocus == nil {
            restoredFocus = restoreNonProjectFocus(windowLookup: windowLookup)
        }

        if let focus = restoredFocus {
            logEvent("close.focus_restored", context: [
                "window_id": "\(focus.windowId)",
                "workspace": focus.workspace
            ])
        } else if let ws = fallbackToNonProjectWorkspace() {
            logEvent("close.focus_fallback_workspace", context: ["project_id": projectId, "workspace": ws])
        } else {
            logEvent("close.focus_restore_exhausted", level: .warn, context: ["project_id": projectId])
        }

        logEvent("close.completed", context: ["project_id": projectId])
        return .success(ProjectCloseSuccess(tabCaptureWarning: tabCaptureWarning))
    }

}
