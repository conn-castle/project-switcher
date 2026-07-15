//
//  SwitcherOperationCoordinator.swift
//  ProjectSwitcher
//
//  Manages switcher project operations (select, close, exit, recover).
//  Extracted from SwitcherPanelController to reduce controller size.
//  Owns operation-guard state and orchestration sequences; the controller
//  keeps UI object ownership and thin wrappers.
//

import AppKit
import Foundation

import ProjectSwitcherCore

/// Coordinates project operations for the switcher panel.
///
/// Owns single-flight guards (`isActivating`, `isClosingProject`,
/// `isExitingToNonProject`, `isRecoveringProject`) and dispatches `ProjectManager` calls on
/// background queues. Reports results through closures so the controller
/// can perform UI updates.
final class SwitcherOperationCoordinator {

    // MARK: - Dependencies

    private let projectManager: ProjectManager
    private let session: SwitcherSession

    // MARK: - Callbacks

    /// Called on the main thread to enable/disable interactive controls.
    var onSetControlsEnabled: ((Bool) -> Void)?

    /// Called on the main thread to update the status bar.
    var onSetStatus: ((String, StatusLevel) -> Void)?

    /// Called on the main thread to dismiss the panel.
    var onDismiss: ((SwitcherDismissReason) -> Void)?

    /// Called on the main thread to focus the IDE window after project selection.
    var onFocusIdeWindow: ((Int) -> Void)?

    /// Called on the main thread to refresh workspace state and reapply the filter.
    /// Parameters: preferredSelectionKey, useDefaultSelection.
    var onRefreshWorkspaceAndFilter: ((String?, Bool) -> Void)?

    /// Called on the main thread to report a project operation failure.
    var onOperationFailed: ((ErrorContext) -> Void)?

    /// Called on the main thread to restore search field input focus.
    var onRestoreSearchFieldFocus: (() -> Void)?

    /// Called on the main thread to update captured focus after close.
    /// Parameter: the refreshed focus (nil if unavailable or self-referencing).
    var onUpdateCapturedFocus: ((CapturedFocus?) -> Void)?

    /// The external recover-project callback, wired by AppDelegate.
    var onRecoverProjectRequested: ((CapturedFocus, @escaping (Result<RecoveryResult, PsCoreError>) -> Void) -> Void)?

    // MARK: - Operation Guards

    private(set) var isActivating: Bool = false
    private(set) var isClosingProject: Bool = false
    private(set) var isExitingToNonProject: Bool = false
    private(set) var isRecoveringProject: Bool = false

    // MARK: - Init

    /// Creates an operation coordinator.
    ///
    /// - Parameters:
    ///   - projectManager: Manager for project lifecycle operations.
    ///   - session: Switcher session for structured logging.
    init(projectManager: ProjectManager, session: SwitcherSession) {
        self.projectManager = projectManager
        self.session = session
    }

    // MARK: - Reset

    /// Resets all operation guards. Called on dismiss.
    func resetGuards() {
        dispatchPrecondition(condition: .onQueue(.main))
        isActivating = false
        isClosingProject = false
        isExitingToNonProject = false
        isRecoveringProject = false
    }

    // MARK: - Project Selection

    /// Handles project switching for a selected project.
    ///
    /// - Parameters:
    ///   - project: The project to activate.
    ///   - capturedFocus: The pre-switcher focus for exit restoration.
    func handleProjectSelection(_ project: ProjectConfig, capturedFocus: CapturedFocus?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isActivating else {
            session.logEvent(
                event: "switcher.project.selection_skipped",
                level: .warn,
                message: "Project activation is already in progress.",
                context: ["project_id": project.id, "reason": "activation_in_progress"]
            )
            return
        }
        session.logEvent(
            event: "switcher.project.selected",
            context: [
                "project_id": project.id,
                "project_name": project.name
            ]
        )

        onSetStatus?("Switching to \(project.name)...", .info)
        onSetControlsEnabled?(false)
        isActivating = true

        if capturedFocus == nil {
            session.logEvent(
                event: "switcher.project.selection_without_focus",
                level: .warn,
                message: "Proceeding with project selection without captured focus; restore will use workspace routing"
            )
        }

        let projectId = project.id
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let result = await self.projectManager.selectProject(
                projectId: projectId,
                preCapturedFocus: capturedFocus
            )

            await MainActor.run {
                self.isActivating = false
                self.onSetControlsEnabled?(true)

                switch result {
                case .success(let activation):
                    if let warning = activation.chromeWarning {
                        self.session.logEvent(
                            event: "switcher.project.chrome_warning",
                            level: .warn,
                            message: warning,
                            context: ["project_id": projectId]
                        )
                    }
                    if let warning = activation.layoutWarning {
                        self.session.logEvent(
                            event: "switcher.project.layout_warning",
                            level: .warn,
                            message: warning,
                            context: ["project_id": projectId]
                        )
                    }
                    self.onDismiss?(.projectSelected)
                    self.onFocusIdeWindow?(activation.ideWindowId)
                case .failure(let error):
                    self.onSetStatus?(error.userFacingMessage, .error)
                    self.onRestoreSearchFieldFocus?()
                    self.session.logEvent(
                        event: "switcher.project.activation_failed",
                        level: .error,
                        message: "\(error)",
                        context: ["project_id": projectId]
                    )
                    self.onOperationFailed?(ErrorContext(
                        category: .command,
                        message: "\(error)",
                        trigger: "activation"
                    ))
                }
            }
        }
    }

    // MARK: - Close Project

    /// Closes a project and reports results for UI update.
    ///
    /// Dispatches `closeProject()` and `captureCurrentFocus()` to a background
    /// queue to avoid blocking the main thread with AeroSpace CLI calls.
    ///
    /// - Parameters:
    ///   - projectId: The ID of the project to close.
    ///   - projectName: The display name (for status messages).
    ///   - source: Source of the close request (e.g. "keybind", "button").
    ///   - fallbackSelectionKey: Preferred row key to restore selection after close.
    func performCloseProject(
        projectId: String,
        projectName: String,
        source: String,
        fallbackSelectionKey: String?
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isClosingProject else {
            session.logEvent(
                event: "switcher.close_project.duplicate_ignored",
                level: .info,
                context: ["project_id": projectId]
            )
            return
        }

        isClosingProject = true
        onSetControlsEnabled?(false)
        session.logEvent(
            event: "switcher.close_project.requested",
            context: [
                "project_id": projectId,
                "source": source
            ]
        )

        onSetStatus?("Closing '\(projectName)'\u{2026}", .info)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let closeResult = await self.projectManager.closeProject(projectId: projectId)

            var refreshedFocus: CapturedFocus?
            if case .success = closeResult {
                refreshedFocus = self.projectManager.captureCurrentFocus()
            }

            let capturedFocus = refreshedFocus
            await MainActor.run {
                self.isClosingProject = false
                self.onSetControlsEnabled?(true)
                switch closeResult {
                case .success(let result):
                    if let warning = result.tabCaptureWarning {
                        self.session.logEvent(
                            event: "switcher.close_project.tab_capture_warning",
                            level: .warn,
                            message: warning,
                            context: ["project_id": projectId]
                        )
                    }
                    self.session.logEvent(
                        event: "switcher.close_project.succeeded",
                        context: ["project_id": projectId]
                    )

                    // Update captured focus so dismiss doesn't restore stale state.
                    if let capturedFocus,
                       let selfBundleId = Bundle.main.bundleIdentifier,
                       capturedFocus.appBundleId != selfBundleId {
                        self.onUpdateCapturedFocus?(capturedFocus)
                    } else {
                        self.onUpdateCapturedFocus?(nil)
                    }

                    self.onRefreshWorkspaceAndFilter?(fallbackSelectionKey, false)
                    if result.tabCaptureWarning != nil {
                        self.onSetStatus?("Closed '\(projectName)' (tab capture failed)", .warning)
                    } else {
                        self.onSetStatus?("Closed '\(projectName)'", .info)
                    }
                case .failure(let error):
                    self.onSetStatus?(error.userFacingMessage, .error)
                    self.session.logEvent(
                        event: "switcher.close_project.failed",
                        level: .error,
                        message: "\(error)",
                        context: ["project_id": projectId]
                    )
                    self.onOperationFailed?(ErrorContext(
                        category: .command,
                        message: "\(error)",
                        trigger: "closeProject"
                    ))
                }
            }
        }
    }

    // MARK: - Exit to Non-Project

    /// Exits to non-project space and requests dismiss on success.
    ///
    /// - Parameter fromShortcut: Whether triggered from a keyboard shortcut.
    /// - Parameter hasBackActionRow: Whether the back-action row is present.
    func handleExitToNonProject(fromShortcut: Bool, hasBackActionRow: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard hasBackActionRow else {
            if fromShortcut {
                NSSound.beep()
            }
            return
        }
        guard !isExitingToNonProject else { return }

        session.logEvent(event: "switcher.exit_to_previous.requested")
        isExitingToNonProject = true
        onSetControlsEnabled?(false)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let result = await self.projectManager.exitToNonProjectWindow()

            await MainActor.run {
                self.onSetControlsEnabled?(true)
                switch result {
                case .success:
                    self.session.logEvent(event: "switcher.exit_to_previous.succeeded")
                    self.onDismiss?(.exitedToNonProject)
                    self.isExitingToNonProject = false
                case .failure(let error):
                    self.isExitingToNonProject = false
                    self.onSetStatus?(error.userFacingMessage, .error)
                    self.session.logEvent(
                        event: "switcher.exit_to_previous.failed",
                        level: .error,
                        message: "\(error)"
                    )
                    self.onOperationFailed?(ErrorContext(
                        category: .command,
                        message: "\(error)",
                        trigger: "exitToPrevious"
                    ))
                    NSSound.beep()

                    self.onRefreshWorkspaceAndFilter?(nil, false)
                }
            }
        }
    }

    // MARK: - Recover Project

    /// Handles "recover project" from the switcher keyboard shortcut.
    ///
    /// - Parameter capturedFocus: The pre-switcher focus for workspace identification.
    func handleRecoverProjectFromShortcut(capturedFocus: CapturedFocus?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let focus = capturedFocus else {
            session.logEvent(
                event: "switcher.recover_project.skipped",
                level: .warn,
                message: "No captured focus available."
            )
            onSetStatus?("Recover Project unavailable: no focused workspace.", .warning)
            NSSound.beep()
            return
        }

        guard let onRecoverProjectRequested else {
            session.logEvent(
                event: "switcher.recover_project.skipped",
                level: .warn,
                message: "Recover action is not wired."
            )
            onSetStatus?("Recover Project is not available.", .warning)
            NSSound.beep()
            return
        }

        guard !isRecoveringProject else {
            session.logEvent(
                event: "switcher.recover_project.skipped",
                level: .warn,
                message: "Recovery already in progress."
            )
            onSetStatus?("Recover Project already in progress.", .warning)
            NSSound.beep()
            return
        }

        session.logEvent(
            event: "switcher.recover_project.requested",
            context: [
                "workspace": focus.workspace,
                "window_id": "\(focus.windowId)"
            ]
        )
        isRecoveringProject = true
        onSetControlsEnabled?(false)
        onSetStatus?("Recovering focused workspace...", .info)

        onRecoverProjectRequested(focus) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRecoveringProject = false
                self.onSetControlsEnabled?(true)
                self.onRestoreSearchFieldFocus?()
                switch result {
                case .success(let recovery):
                    if recovery.errors.isEmpty {
                        self.onSetStatus?(
                            "Recovered \(recovery.windowsRecovered) of \(recovery.windowsProcessed) windows.",
                            .info
                        )
                    } else {
                        self.onSetStatus?(
                            "Recovered \(recovery.windowsRecovered) of \(recovery.windowsProcessed) windows (\(recovery.errors.count) errors).",
                            .warning
                        )
                    }
                case .failure(let error):
                    self.onSetStatus?("Recover Project failed: \(error.message)", .error)
                    self.onOperationFailed?(ErrorContext(
                        category: .command,
                        message: error.message,
                        trigger: "recoverProject"
                    ))
                    NSSound.beep()
                }
            }
        }
    }

}
