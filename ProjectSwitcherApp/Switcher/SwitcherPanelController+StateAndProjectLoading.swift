import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - State Management

    /// Resets query, rows, and status labels.
    func resetState(initialQuery: String) {
        allProjects = []
        searchField.stringValue = initialQuery
        searchField.isEnabled = true
        searchField.isEditable = true
        configErrorMessage = nil
        filteredProjects = []
        rows = []
        activeProjectId = nil
        openIds = []
        tableView.isEnabled = true
        lastSelectedRowIndex = -1
        lastFilterQuery = initialQuery
        lastStatusMessage = nil
        lastStatusLevel = nil
        cancelPendingFilterWorkItem()
        workspaceRetryCoordinator.cancelRetry()
        tableView.reloadData()
        tableView.deselectAll(nil)
        clearStatus()
        updateFooterHints()
    }

    /// Shows the panel and focuses the search field.
    ///
    /// The panel uses `.nonactivatingPanel` style mask which allows it to receive keyboard
    /// input without activating the owning app. This prevents workspace switching when the
    /// switcher is invoked from a different workspace. The system handles keyboard focus
    /// via "key focus theft" - the panel becomes key while the previous app remains active.
    func showPanel() {
        applyChromeColors()
        updatePanelSizeForCurrentRows()
        centerPanelOnActiveDisplay()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    /// Re-applies dynamic layer colors for the current effective appearance.
    /// Called on show and should be called on appearance changes.
    private func applyChromeColors() {
        guard let vfx = visualEffectView else { return }

        vfx.effectiveAppearance.performAsCurrentDrawingAppearance {
            vfx.layer?.backgroundColor =
                NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
            vfx.layer?.borderColor =
                NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }
    }

    // MARK: - Project Loading

    /// Reads current config-file fingerprint from disk metadata.
    private func currentConfigFingerprint() -> SwitcherConfigFingerprint? {
        let configPath = dataPaths.configFile.path
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: configPath) else {
            return nil
        }
        return SwitcherConfigFingerprint.from(fileAttributes: fileAttributes)
    }

    /// Applies a config snapshot to controller state and user-visible status.
    private func applyConfigSnapshot(_ snapshot: SwitcherConfigSnapshot, source: String) {
        allProjects = snapshot.projects
        configErrorMessage = snapshot.errorMessage
        filteredProjects = []

        if let errorMessage = snapshot.errorMessage {
            setStatus(message: "Config error: \(errorMessage)", level: .error)
            session.logEvent(
                event: "switcher.config.failed",
                level: .error,
                message: errorMessage,
                context: ["source": source]
            )
            onProjectOperationFailed?(ErrorContext(
                category: .configuration,
                message: errorMessage,
                trigger: source == "cache" ? "configCache" : "configLoad"
            ))
            return
        }

        if let warningTitle = snapshot.warningTitle {
            setStatus(message: "Config warning: \(warningTitle)", level: .warning)
        } else {
            clearStatus()
        }
        session.logConfigLoaded(projectCount: snapshot.projects.count)
    }

    /// Loads projects from config and returns a snapshot for cache reuse.
    @discardableResult
    private func loadProjects() -> SwitcherConfigSnapshot {
        switch projectManager.loadConfig() {
        case .failure(let error):
            let snapshot = SwitcherConfigSnapshot(
                projects: [],
                warningTitle: nil,
                errorMessage: configLoadErrorMessage(error)
            )
            applyConfigSnapshot(snapshot, source: "load")
            return snapshot

        case .success(let success):
            let snapshot = SwitcherConfigSnapshot(
                projects: success.config.projects,
                warningTitle: success.warnings.first?.title,
                errorMessage: nil
            )
            applyConfigSnapshot(snapshot, source: "load")
            return snapshot
        }
    }

    /// Uses cached config snapshot when possible, otherwise reloads from disk.
    func loadOrReuseProjectsForShow() {
        let currentFingerprint = currentConfigFingerprint()
        let shouldReload = SwitcherConfigReloadPolicy.shouldReload(
            previous: cachedConfigFingerprint,
            current: currentFingerprint
        )

        if !shouldReload, let cachedConfigSnapshot, cachedConfigSnapshot.errorMessage == nil {
            session.logEvent(event: "switcher.config.cache_hit")
            applyConfigSnapshot(cachedConfigSnapshot, source: "cache")
            return
        }

        let cacheMissReason: String
        if shouldReload {
            cacheMissReason = "fingerprint_changed"
        } else if cachedConfigSnapshot == nil {
            cacheMissReason = "snapshot_missing"
        } else {
            cacheMissReason = "cached_error_snapshot"
        }

        session.logEvent(
            event: "switcher.config.cache_miss",
            context: ["reason": cacheMissReason]
        )
        let loadedSnapshot = loadProjects()
        cachedConfigSnapshot = loadedSnapshot
        // Re-read after load in case load path created a starter config file.
        cachedConfigFingerprint = currentConfigFingerprint()
    }

    /// Seeds workspace state from pre-captured focus before first render.
    ///
    /// This avoids a two-phase visual update where the initial list is rendered with
    /// no active project and then immediately re-rendered after async workspace lookup.
    func seedWorkspaceStateFromCapturedFocus(_ focus: CapturedFocus?) {
        guard let focus,
              let activeProjectId = WorkspaceRouting.projectId(fromWorkspace: focus.workspace) else {
            return
        }
        self.activeProjectId = activeProjectId
        openIds.insert(activeProjectId)
    }

    /// Applies a workspace-state snapshot and returns true when state changed.
    ///
    /// - Parameter state: Snapshot from `ProjectManager.workspaceState()`.
    /// - Returns: True when active/open project state changed.
    @discardableResult
    func applyWorkspaceState(_ state: ProjectWorkspaceState) -> Bool {
        let didChange = activeProjectId != state.activeProjectId || openIds != state.openProjectIds
        activeProjectId = state.activeProjectId
        openIds = state.openProjectIds
        return didChange
    }

    /// Refreshes focused/open project workspace state for row grouping and close affordances.
    ///
    /// Runs workspace queries on a background queue to avoid blocking the main thread
    /// (AeroSpace CLI calls have a 5-second timeout). Results are applied to the UI on
    /// the main thread, and filtering is re-applied only when the state actually changed.
    ///
    /// - Parameter retryOnFailure: When true, schedules a repeating timer to retry workspace
    ///   state queries. Used during `show()` to auto-recover when the AeroSpace circuit breaker
    ///   is open and background recovery is in progress.
    /// - Parameter preferredSelectionKey: Row key to preserve as the selected row when
    ///   re-applying the filter after a state change. Pass `nil` for no preference.
    /// - Parameter useDefaultSelection: When true, falls back to the default selection
    ///   strategy if the preferred key is not found. Pass `false` to preserve the current
    ///   selection when workspace state is unchanged.
    func refreshWorkspaceState(
        retryOnFailure: Bool = false,
        preferredSelectionKey: String? = nil,
        useDefaultSelection: Bool = true
    ) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let result = self.projectManager.workspaceState()
            DispatchQueue.main.async {
                var shouldReapplyFilter = false
                switch result {
                case .success(let state):
                    shouldReapplyFilter = self.applyWorkspaceState(state)
                case .failure(let error):
                    shouldReapplyFilter = self.activeProjectId != nil || !self.openIds.isEmpty
                    self.activeProjectId = nil
                    self.openIds = []
                    if retryOnFailure {
                        self.setStatus(message: "Recovering AeroSpace\u{2026}", level: .info)
                        self.workspaceRetryCoordinator.scheduleRetry()
                    } else {
                        self.setStatus(
                            message: "Workspace state unavailable: \(error.userFacingMessage)",
                            level: .warning
                        )
                    }
                    self.session.logEvent(
                        event: "switcher.workspace_state.failed",
                        level: Self.workspaceStateFailureLogLevel(for: error, retryOnFailure: retryOnFailure),
                        message: "\(error)"
                    )
                    self.onProjectOperationFailed?(ErrorContext(
                        category: .command,
                        message: "\(error)",
                        trigger: "workspaceQuery"
                    ))
                }
                if shouldReapplyFilter {
                    self.applyFilter(
                        query: self.searchField.stringValue,
                        preferredSelectionKey: preferredSelectionKey,
                        useDefaultSelection: useDefaultSelection
                    )
                }
            }
        }
    }

    /// Returns the log level for workspace-state failures.
    ///
    /// Circuit-breaker-open failures are expected while recovery is in progress and are
    /// logged as info to avoid warning storms from repeated retry ticks.
    static func workspaceStateFailureLogLevel(for error: ProjectError, retryOnFailure: Bool) -> LogLevel {
        guard retryOnFailure else {
            return .warn
        }
        guard case .aeroSpaceError(let detail) = error else {
            return .warn
        }
        // Delegate to PsCoreError.isBreakerOpen to avoid duplicating the sentinel string.
        return PsCoreError(category: .command, message: detail).isBreakerOpen ? .info : .warn
    }

    /// Converts ConfigLoadError to a user-friendly message.
    private func configLoadErrorMessage(_ error: ConfigLoadError) -> String {
        switch error {
        case .fileNotFound(let path):
            return "Config file not found at \(path)"
        case .readFailed(let path, let detail):
            return "Could not read config at \(path): \(detail)"
        case .parseFailed(let detail):
            return "Config parse error: \(detail)"
        case .validationFailed(let findings):
            let firstFail = findings.first { $0.severity == .fail }
            return firstFail?.title ?? "Config validation failed"
        }
    }

}
