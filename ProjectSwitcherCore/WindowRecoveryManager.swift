import Foundation

/// Result of a window recovery operation.
public struct RecoveryResult: Equatable, Sendable {
    /// Number of windows checked during recovery.
    public let windowsProcessed: Int
    /// Number of windows that were actually resized or moved.
    public let windowsRecovered: Int
    /// Non-fatal error messages encountered during recovery.
    public let errors: [String]

    public init(windowsProcessed: Int, windowsRecovered: Int, errors: [String]) {
        self.windowsProcessed = windowsProcessed
        self.windowsRecovered = windowsRecovered
        self.errors = errors
    }
}

/// Handles window recovery operations: resize oversized windows and center them on screen.
/// For project workspaces (`ps-<projectId>`), an optional layout phase applies canonical IDE/Chrome layout first.
/// Not thread-safe; call from one queue.
public final class WindowRecoveryManager {
    private let aerospace: AeroSpaceProviding
    private let windowPositioner: WindowPositioning
    private let screenVisibleFrame: CGRect
    private let logger: ProjectSwitcherLogging
    private let screenModeDetector: ScreenModeDetecting?
    private let layoutConfig: LayoutConfig
    private let knownProjectIds: Set<String>?

    /// Creates a WindowRecoveryManager with production defaults for AeroSpace.
    /// - Parameters:
    ///   - windowPositioner: Window positioning provider for AX operations.
    ///   - screenVisibleFrame: The screen's visible frame (minus dock/menu bar) to clamp within.
    ///   - logger: Logger for structured event logging.
    ///   - processChecker: Process checker for AeroSpace auto-recovery. Pass nil to disable.
    ///   - screenModeDetector: Screen mode detector for layout-aware recovery. Pass nil to disable layout phase.
    ///   - layoutConfig: Layout configuration for computing canonical positions. Defaults to `LayoutConfig()`.
    ///   - knownProjectIds: Optional known project IDs. When provided, recover-all routing only
    ///     routes tokenized windows for these IDs; unknown IDs are treated as non-project windows.
    public init(
        windowPositioner: WindowPositioning,
        screenVisibleFrame: CGRect,
        logger: ProjectSwitcherLogging,
        processChecker: RunningApplicationChecking? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        layoutConfig: LayoutConfig = LayoutConfig(),
        knownProjectIds: Set<String>? = nil
    ) {
        self.aerospace = PsAeroSpace(processChecker: processChecker)
        self.windowPositioner = windowPositioner
        self.screenVisibleFrame = screenVisibleFrame
        self.logger = logger
        self.screenModeDetector = screenModeDetector
        self.layoutConfig = layoutConfig
        self.knownProjectIds = knownProjectIds
    }

    /// Creates a WindowRecoveryManager with injected dependencies (for testing).
    init(
        aerospace: AeroSpaceProviding,
        windowPositioner: WindowPositioning,
        screenVisibleFrame: CGRect,
        logger: ProjectSwitcherLogging,
        screenModeDetector: ScreenModeDetecting? = nil,
        layoutConfig: LayoutConfig = LayoutConfig(),
        knownProjectIds: Set<String>? = nil
    ) {
        self.aerospace = aerospace
        self.windowPositioner = windowPositioner
        self.screenVisibleFrame = screenVisibleFrame
        self.logger = logger
        self.screenModeDetector = screenModeDetector
        self.layoutConfig = layoutConfig
        self.knownProjectIds = knownProjectIds
    }

    /// Recovers all windows in the given workspace.
    /// Returns `.failure` when the workspace cannot be focused or listed.
    public func recoverWorkspaceWindows(workspace: String) async -> Result<RecoveryResult, PsCoreError> {
        logEvent("recover_workspace.started", context: ["workspace": workspace])

        let originalFocus = try? aerospace.focusedWindow().get()
        defer {
            restoreOriginalFocus(originalFocus, eventPrefix: "recover_workspace")
        }

        switch focusWorkspaceForRecovery(workspace: workspace, eventPrefix: "recover_workspace") {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        return await performWorkspaceRecovery(workspace: workspace)
    }

    /// Recovers the currently focused window in the given workspace.
    ///
    /// The target is resolved by window id from a workspace snapshot to avoid title-only ambiguity.
    /// Returns `.failure` if the workspace cannot be focused or listed, the target window is
    /// missing, or focus/AX recovery fails.
    public func recoverCurrentWindow(windowId: Int, workspace: String) -> Result<RecoveryOutcome, PsCoreError> {
        logEvent("recover_current_window.started", context: [
            "window_id": "\(windowId)",
            "workspace": workspace
        ])

        let originalFocus = try? aerospace.focusedWindow().get()
        defer {
            restoreOriginalFocus(originalFocus, eventPrefix: "recover_current_window")
        }

        switch focusWorkspaceForRecovery(workspace: workspace, eventPrefix: "recover_current_window") {
        case .success:
            break
        case .failure(let error):
            return .failure(error)
        }

        let windows: [PsWindow]
        switch aerospace.listWindowsWorkspace(workspace: workspace) {
        case .success(let result):
            windows = result
        case .failure(let error):
            logEvent("recover_current_window.list_failed", level: .error, message: error.message, context: [
                "workspace": workspace
            ])
            return .failure(error)
        }

        guard let targetWindow = windows.first(where: { $0.windowId == windowId }) else {
            let error = PsCoreError(
                category: .window,
                message: "Window \(windowId) not found in workspace '\(workspace)'."
            )
            logEvent("recover_current_window.not_found", level: .error, message: error.message, context: [
                "window_id": "\(windowId)",
                "workspace": workspace
            ])
            return .failure(error)
        }

        if case .failure(let error) = aerospace.focusWindow(windowId: windowId) {
            if error.isAeroSpaceTreeNodeError {
                logEvent("recover_current_window.tree_node_error", level: .warn,
                         message: "AeroSpace tree-node error for window \(windowId), retrying after reload",
                         context: ["window_id": "\(windowId)", "workspace": workspace])
                _ = aerospace.reloadConfig()
                if case .failure = aerospace.focusWindow(windowId: windowId) {
                    logEvent("recover_current_window.tree_node_retry_failed", level: .warn,
                             message: "Focus retry failed for window \(windowId), attempting AX-only recovery",
                             context: ["window_id": "\(windowId)", "workspace": workspace])
                }
                // Fall through to AX recovery regardless of retry outcome.
            } else {
                logEvent("recover_current_window.focus_failed", level: .error, message: error.message, context: [
                    "window_id": "\(windowId)",
                    "workspace": workspace
                ])
                return .failure(error)
            }
        }

        switch windowPositioner.recoverWindow(
            bundleId: targetWindow.appBundleId,
            windowTitle: targetWindow.windowTitle,
            screenVisibleFrame: screenVisibleFrame
        ) {
        case .success(.recovered):
            logEvent("recover_current_window.completed", context: [
                "window_id": "\(windowId)",
                "workspace": workspace,
                "outcome": "recovered"
            ])
            return .success(.recovered)
        case .success(.unchanged):
            logEvent("recover_current_window.completed", context: [
                "window_id": "\(windowId)",
                "workspace": workspace,
                "outcome": "unchanged"
            ])
            return .success(.unchanged)
        case .success(.notFound):
            let error = PsCoreError(
                category: .window,
                message: "Window not found for recovery: \(windowId) (\(targetWindow.windowTitle))."
            )
            logEvent("recover_current_window.not_found", level: .error, message: error.message, context: [
                "window_id": "\(windowId)",
                "workspace": workspace
            ])
            return .failure(error)
        case .failure(let error):
            logEvent("recover_current_window.failed", level: .error, message: error.message, context: [
                "window_id": "\(windowId)",
                "workspace": workspace
            ])
            return .failure(error)
        }
    }

    /// Recovers all windows across all workspaces.
    /// Windows tagged with `PS:<projectId>` are first routed to `ps-<projectId>` when needed.
    /// Recovery then runs for every workspace that contains snapshot windows, using layout-aware
    /// recovery for project workspaces and generic recovery for non-project workspaces.
    public func recoverAllWindows(
        progress: @escaping (_ current: Int, _ total: Int) -> Void
    ) async -> Result<RecoveryResult, PsCoreError> {
        logEvent("recover_all.started")

        let originalFocus = try? aerospace.focusedWindow().get()
        defer {
            restoreOriginalFocus(originalFocus, eventPrefix: "recover_all")
        }

        let workspaces: [String]
        switch aerospace.getWorkspaces() {
        case .success(let result):
            workspaces = result
        case .failure(let error):
            logEvent("recover_all.list_workspaces_failed", level: .error, message: error.message)
            return .failure(error)
        }

        var allWindows: [PsWindow] = []
        var errors: [String] = []

        for workspace in workspaces {
            switch aerospace.listWindowsWorkspace(workspace: workspace) {
            case .success(let windows):
                allWindows.append(contentsOf: windows)
            case .failure(let error):
                errors.append("Failed to list workspace \(workspace): \(error.message)")
                logEvent("recover_all.workspace_list_failed", level: .warn, message: error.message, context: ["workspace": workspace])
            }
        }

        let totalWindows = allWindows.count
        if totalWindows == 0 {
            let result = RecoveryResult(windowsProcessed: 0, windowsRecovered: 0, errors: errors)
            logEvent("recover_all.completed", context: [
                "processed": "0",
                "recovered": "0",
                "errors": "\(errors.count)"
            ])
            return .success(result)
        }

        var plannedWorkspaceWindowCounts: [String: Int] = [:]
        var recoveryWorkspaces: Set<String> = []

        for window in allWindows {
            let destinationWorkspace = intendedProjectWorkspace(for: window) ?? window.workspace
            var assignedWorkspace = window.workspace

            if destinationWorkspace != window.workspace {
                switch aerospace.moveWindowToWorkspace(workspace: destinationWorkspace, windowId: window.windowId, focusFollows: true) {
                case .success:
                    assignedWorkspace = destinationWorkspace
                case .failure(let error):
                    errors.append("Move failed for window \(window.windowId) (\(window.windowTitle)): \(error.message)")
                    logEvent(
                        "recover_all.move_failed",
                        level: .warn,
                        message: error.message,
                        context: [
                            "window_id": "\(window.windowId)",
                            "from_workspace": window.workspace,
                            "to_workspace": destinationWorkspace
                        ]
                    )
                }
            }

            plannedWorkspaceWindowCounts[assignedWorkspace, default: 0] += 1
            recoveryWorkspaces.insert(assignedWorkspace)
        }

        var progressProcessed = 0
        var recovered = 0

        for workspace in recoveryWorkspaces.sorted() {
            let plannedWindowCount = plannedWorkspaceWindowCounts[workspace] ?? 0

            // Focus the workspace once, then run recovery without the
            // save/restore wrapper that the public method adds.
            if case .failure(let focusError) = focusWorkspaceForRecovery(workspace: workspace, eventPrefix: "recover_all") {
                errors.append("Recovery failed for workspace \(workspace): \(focusError.message)")
                logEvent("recover_all.workspace_recover_failed", level: .warn, message: focusError.message, context: [
                    "workspace": workspace
                ])
            } else {
                switch await performWorkspaceRecovery(workspace: workspace) {
                case .success(let recovery):
                    recovered += recovery.windowsRecovered
                    errors.append(contentsOf: recovery.errors)
                case .failure(let error):
                    errors.append("Recovery failed for workspace \(workspace): \(error.message)")
                    logEvent("recover_all.workspace_recover_failed", level: .warn, message: error.message, context: [
                        "workspace": workspace
                    ])
                }
            }

            reportProgress(
                progress: progress,
                processed: &progressProcessed,
                increment: plannedWindowCount,
                total: totalWindows
            )
        }

        if progressProcessed < totalWindows {
            reportProgress(
                progress: progress,
                processed: &progressProcessed,
                increment: totalWindows - progressProcessed,
                total: totalWindows
            )
        }

        let result = RecoveryResult(
            windowsProcessed: totalWindows,
            windowsRecovered: recovered,
            errors: errors
        )

        logEvent("recover_all.completed", context: [
            "processed": "\(result.windowsProcessed)",
            "recovered": "\(result.windowsRecovered)",
            "errors": "\(result.errors.count)"
        ])

        return .success(result)
    }

    // MARK: - Private Helpers

    private func reportProgress(
        progress: @escaping (_ current: Int, _ total: Int) -> Void,
        processed: inout Int,
        increment: Int,
        total: Int
    ) {
        guard increment > 0 else { return }
        for _ in 0..<increment {
            processed += 1
            progress(min(processed, total), total)
        }
    }

    /// Core workspace recovery logic without focus save/restore.
    /// Caller is responsible for workspace focus and focus restoration.
    private func performWorkspaceRecovery(workspace: String) async -> Result<RecoveryResult, PsCoreError> {
        let windows: [PsWindow]
        switch aerospace.listWindowsWorkspace(workspace: workspace) {
        case .success(let result):
            windows = result
        case .failure(let error):
            logEvent("recover_workspace.list_failed", level: .error, message: error.message, context: ["workspace": workspace])
            return .failure(error)
        }

        var layoutRecovered = 0
        var layoutErrors: [String] = []
        var layoutHandledWindowIds: Set<Int> = []

        if let projectId = projectId(fromWorkspace: workspace), screenModeDetector != nil {
            let layoutResult = await recoverProjectWorkspaceLayout(projectId: projectId, workspaceWindows: windows)
            layoutRecovered = layoutResult.recovered
            layoutErrors = layoutResult.errors
            layoutHandledWindowIds = layoutResult.handledWindowIds
        }

        let genericWindows = windows.filter { !layoutHandledWindowIds.contains($0.windowId) }
        let genericResult = recoverWindows(genericWindows)

        let totalRecovered = layoutRecovered + genericResult.windowsRecovered
        let totalErrors = layoutErrors + genericResult.errors
        let result = RecoveryResult(
            windowsProcessed: windows.count,
            windowsRecovered: totalRecovered,
            errors: totalErrors
        )

        logEvent("recover_workspace.completed", context: [
            "workspace": workspace,
            "processed": "\(result.windowsProcessed)",
            "recovered": "\(result.windowsRecovered)",
            "errors": "\(result.errors.count)"
        ])

        return .success(result)
    }

    private func focusWorkspaceForRecovery(
        workspace: String,
        eventPrefix: String
    ) -> Result<Void, PsCoreError> {
        // Reload config before workspace focus to flush stale AeroSpace tree-node
        // state that can accumulate after monitor-configuration changes (e.g., undocking).
        // Without this, the subsequent focus command may hit the "already unbound" bug
        // inside AeroSpace's makeFloatingWindowsSeenAsTiling.
        if case .failure(let reloadError) = aerospace.reloadConfig() {
            logEvent(
                "\(eventPrefix).pre_recovery_reload_failed",
                level: .warn,
                message: reloadError.message,
                context: ["workspace": workspace]
            )
            // Non-fatal: continue with workspace focus even if reload fails.
        }

        // Switch to the target workspace before any per-window focus calls.
        // This prevents AeroSpace tree-node crashes when the current macOS Space
        // differs from the workspace's Space (aerospace#focus double-unbind bug).
        switch aerospace.focusWorkspace(name: workspace) {
        case .success:
            return .success(())
        case .failure(let error):
            logEvent(
                "\(eventPrefix).focus_workspace_failed",
                level: .error,
                message: error.message,
                context: ["workspace": workspace]
            )
            return .failure(error)
        }
    }

    private func restoreOriginalFocus(
        _ originalFocus: PsWindow?,
        eventPrefix: String
    ) {
        guard let originalFocus else { return }

        switch aerospace.focusWorkspace(name: originalFocus.workspace) {
        case .success:
            break
        case .failure(let error):
            logEvent(
                "\(eventPrefix).restore_workspace_failed",
                level: .warn,
                message: error.message,
                context: [
                    "workspace": originalFocus.workspace,
                    "window_id": "\(originalFocus.windowId)"
                ]
            )
            return
        }

        if case .failure(let error) = aerospace.focusWindow(windowId: originalFocus.windowId) {
            logEvent(
                "\(eventPrefix).restore_window_failed",
                level: .warn,
                message: error.message,
                context: [
                    "workspace": originalFocus.workspace,
                    "window_id": "\(originalFocus.windowId)"
                ]
            )
        }
    }

    private enum SingleRecoveryResult {
        case recovered
        case unchanged
        case notFound
        case error(String)
    }

    private func recoverSingleWindow(_ window: PsWindow) -> SingleRecoveryResult {
        if case .failure(let error) = aerospace.focusWindow(windowId: window.windowId) {
            if error.isAeroSpaceTreeNodeError {
                // AeroSpace tree-node bug (stale state after monitor change).
                // Reload config to flush stale nodes, then retry focus once.
                logEvent("recover_single.tree_node_error", level: .warn,
                         message: "AeroSpace tree-node error for window \(window.windowId), retrying after reload",
                         context: ["window_id": "\(window.windowId)"])
                _ = aerospace.reloadConfig()
                if case .failure = aerospace.focusWindow(windowId: window.windowId) {
                    // Retry failed — still attempt AX recovery without AeroSpace focus.
                    // The window is on screen; the positioner identifies it by bundleId + title.
                    logEvent("recover_single.tree_node_retry_failed", level: .warn,
                             message: "Focus retry failed for window \(window.windowId), attempting AX-only recovery",
                             context: ["window_id": "\(window.windowId)"])
                }
            } else {
                return .error("Focus failed for window \(window.windowId) (\(window.windowTitle)): \(error.message)")
            }
        }

        switch windowPositioner.recoverWindow(
            bundleId: window.appBundleId,
            windowTitle: window.windowTitle,
            screenVisibleFrame: screenVisibleFrame
        ) {
        case .success(.recovered): return .recovered
        case .success(.unchanged): return .unchanged
        case .success(.notFound): return .notFound
        case .failure(let error):
            return .error("Recover failed for window \(window.windowId) (\(window.windowTitle)): \(error.message)")
        }
    }

    /// Recovers a list of windows in-place.
    private func recoverWindows(_ windows: [PsWindow]) -> RecoveryResult {
        var processed = 0
        var recovered = 0
        var errors: [String] = []

        for window in windows {
            let outcome = recoverSingleWindow(window)
            switch outcome {
            case .recovered: recovered += 1
            case .notFound:
                errors.append("Window not found for recovery: \(window.windowId) (\(window.windowTitle))")
            case .error(let message):
                errors.append(message)
            case .unchanged:
                break
            }
            processed += 1
        }

        return RecoveryResult(
            windowsProcessed: processed,
            windowsRecovered: recovered,
            errors: errors
        )
    }

    private func intendedProjectWorkspace(for window: PsWindow) -> String? {
        guard window.appBundleId == PsVSCodeLauncher.bundleId || window.appBundleId == PsChromeLauncher.bundleId else {
            return nil
        }
        guard let projectId = projectId(fromWindowTitle: window.windowTitle) else {
            return nil
        }
        if let knownProjectIds, !knownProjectIds.contains(projectId) {
            return nil
        }
        return WorkspaceRouting.workspaceName(forProjectId: projectId)
    }

    private func projectId(fromWindowTitle title: String) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.hasPrefix(PsIdeToken.prefix) else {
            return nil
        }

        var suffix = trimmedTitle.dropFirst(PsIdeToken.prefix.count)
        if let delimiterRange = suffix.range(of: " - ") {
            suffix = suffix[..<delimiterRange.lowerBound]
        } else if let whitespaceIndex = suffix.firstIndex(where: { $0.isWhitespace }) {
            suffix = suffix[..<whitespaceIndex]
        }

        let projectId = String(suffix).trimmingCharacters(in: .whitespacesAndNewlines)
        return projectId.isEmpty ? nil : projectId
    }

    // MARK: - Layout-Aware Recovery

    /// Extracts project ID from an `ps-<projectId>` workspace name.
    private func projectId(fromWorkspace workspace: String) -> String? {
        WorkspaceRouting.projectId(fromWorkspace: workspace)
    }

    /// Runs layout-aware recovery for a project workspace.
    private func recoverProjectWorkspaceLayout(
        projectId: String,
        workspaceWindows: [PsWindow]
    ) async -> (recovered: Int, errors: [String], handledWindowIds: Set<Int>) {
        guard let detector = screenModeDetector else { return (0, [], []) }

        var errors: [String] = []

        let workspaceBundleIds = Set(workspaceWindows.map { $0.appBundleId })
        let layoutTargets: [(bundleId: String, frameKeyPath: KeyPath<WindowLayout, CGRect>, label: String)] = [
            (PsVSCodeLauncher.bundleId, \.ideFrame, "IDE"),
            (PsChromeLauncher.bundleId, \.chromeFrame, "Chrome"),
        ].filter { workspaceBundleIds.contains($0.bundleId) }

        guard !layoutTargets.isEmpty else { return (0, [], []) }

        let centerPoint = CGPoint(x: screenVisibleFrame.midX, y: screenVisibleFrame.midY)

        let screenMode: ScreenMode
        switch detector.detectMode(containingPoint: centerPoint, threshold: layoutConfig.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            logEvent("recover_layout.screen_mode_failed", level: .warn, message: error.message)
            errors.append("Recovery screen mode detection failed (\(error.message)); using wide fallback")
            screenMode = .wide
        }

        let physicalWidth: Double
        switch detector.physicalWidthInches(containingPoint: centerPoint) {
        case .success(let width):
            physicalWidth = width
        case .failure(let error):
            logEvent("recover_layout.physical_width_failed", level: .warn, message: error.message)
            errors.append("Recovery physical width detection failed (\(error.message)); using 32\" fallback")
            physicalWidth = 32.0
        }

        let targetLayout = WindowLayoutEngine.computeLayout(
            screenVisibleFrame: screenVisibleFrame,
            screenPhysicalWidthInches: physicalWidth,
            screenMode: screenMode,
            config: layoutConfig
        )

        let cascadeOffsetPoints = CGFloat(0.5 * (Double(screenVisibleFrame.width) / physicalWidth))

        let token = "\(PsIdeToken.prefix)\(projectId)"
        let recoveryRetryInterval: TimeInterval = 0.1
        let maxRecoveryRetries = 3
        var recovered = 0
        var handledWindowIds: Set<Int> = []

        for target in layoutTargets {
            let tokenMatchingWindows = workspaceWindows.filter {
                $0.appBundleId == target.bundleId && $0.windowTitle.contains(token)
            }
            let allBundleWindows = workspaceWindows.filter { $0.appBundleId == target.bundleId }
            let fallbackAnchorWindow: PsWindow? = {
                if tokenMatchingWindows.count == 1 { return tokenMatchingWindows[0] }
                if allBundleWindows.count == 1 { return allBundleWindows[0] }
                return nil
            }()

            // Bounded retry for transient token-miss errors, then fallback
            var attempt = 0
            retryLoop: while true {
                attempt += 1
                switch windowPositioner.setWindowFrames(
                    bundleId: target.bundleId,
                    projectId: projectId,
                    primaryFrame: targetLayout[keyPath: target.frameKeyPath],
                    cascadeOffsetPoints: cascadeOffsetPoints
                ) {
                case .success(let result):
                    if attempt > 1 {
                        logEvent("recover_layout.\(target.label.lowercased())_retried", context: [
                            "attempts": "\(attempt)"
                        ])
                    }
                    recovered += min(result.positioned, tokenMatchingWindows.count)
                    if result.hasPartialFailure || result.positioned < tokenMatchingWindows.count {
                        logEvent("recover_layout.\(target.label.lowercased())_partial", level: .warn, context: [
                            "positioned": "\(result.positioned)", "matched": "\(result.matched)"
                        ])
                        // Keep token windows eligible for generic recovery when layout positioning
                        // does not fully succeed and we cannot map successful AX writes to IDs.
                    } else {
                        for w in tokenMatchingWindows {
                            handledWindowIds.insert(w.windowId)
                        }
                    }
                    logEvent("recover_layout.\(target.label.lowercased())_positioned", context: [
                        "positioned": "\(result.positioned)", "matched": "\(result.matched)"
                    ])
                    break retryLoop
                case .failure(let error):
                    let isTransient = error.isWindowTokenNotFound
                    if isTransient && attempt < maxRecoveryRetries {
                        try? await Task.sleep(nanoseconds: UInt64(recoveryRetryInterval * 1_000_000_000))
                        continue
                    }
                    // Retry exhausted or permanent error — try fallback
                    if isTransient {
                        guard let fallbackAnchorWindow else {
                            logEvent("recover_layout.\(target.label.lowercased())_fallback_ambiguous", level: .warn, context: [
                                "attempts": "\(attempt)",
                                "workspace_bundle_windows": "\(allBundleWindows.count)",
                                "token_windows": "\(tokenMatchingWindows.count)"
                            ])
                            errors.append(
                                "Recovery \(target.label) positioning failed: fallback requires exactly one workspace window (found \(allBundleWindows.count))"
                            )
                            break retryLoop
                        }

                        if case .failure(let focusError) = aerospace.focusWindow(windowId: fallbackAnchorWindow.windowId) {
                            logEvent("recover_layout.\(target.label.lowercased())_fallback_focus_failed", level: .warn,
                                     message: focusError.message,
                                     context: ["attempts": "\(attempt)", "window_id": "\(fallbackAnchorWindow.windowId)"])
                            errors.append(
                                "Recovery \(target.label) positioning failed: focus failed for fallback window \(fallbackAnchorWindow.windowId): \(focusError.message)"
                            )
                            break retryLoop
                        }

                        switch windowPositioner.setFallbackWindowFrames(
                            bundleId: target.bundleId,
                            primaryFrame: targetLayout[keyPath: target.frameKeyPath],
                            cascadeOffsetPoints: cascadeOffsetPoints
                        ) {
                        case .success(let result):
                            logEvent("recover_layout.\(target.label.lowercased())_fallback_used", level: .warn, context: [
                                "attempts": "\(attempt)",
                                "positioned": "\(result.positioned)",
                                "window_id": "\(fallbackAnchorWindow.windowId)"
                            ])
                            if result.positioned > 0 {
                                recovered += result.positioned
                                handledWindowIds.insert(fallbackAnchorWindow.windowId)
                            } else {
                                errors.append("Recovery \(target.label) positioning failed: fallback positioned 0 windows")
                            }
                            break retryLoop
                        case .failure(let fallbackError):
                            logEvent("recover_layout.\(target.label.lowercased())_failed", level: .warn,
                                     message: "Token retry exhausted and fallback failed: \(fallbackError.message)",
                                     context: ["attempts": "\(attempt)"])
                            errors.append("Recovery \(target.label) positioning failed: \(fallbackError.message)")
                            break retryLoop
                        }
                    } else {
                        logEvent("recover_layout.\(target.label.lowercased())_failed", level: .warn, message: error.message)
                        errors.append("Recovery \(target.label) positioning failed: \(error.message)")
                        break retryLoop
                    }
                }
            }
        }

        return (recovered, errors, handledWindowIds)
    }

    private func logEvent(
        _ event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(event: event, level: level, message: message, context: context)
    }
}
