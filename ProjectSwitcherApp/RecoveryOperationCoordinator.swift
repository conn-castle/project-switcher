import Foundation

import ProjectSwitcherCore

/// Coordinates async window recovery operations and delivers results on the main thread.
///
/// Extracts the background-dispatch → main-thread-callback pattern from `AppDelegate`
/// so that main-thread delivery can be unit tested. Each method captures state on the
/// main thread, dispatches to a background queue, and delivers results back via closures.
final class RecoveryOperationCoordinator {

    // MARK: - Dependencies

    private let logger: ProjectSwitcherLogging

    /// Factory that creates a `WindowRecoveryManager`. Called on a background thread.
    /// Parameters: `(screenFrame, layoutConfig)`.
    private let makeRecoveryManager: (_ screenFrame: CGRect, _ layoutConfig: LayoutConfig?) -> WindowRecoveryManager

    /// Returns the current layout config from `ProjectManager` (read on background thread).
    private let currentLayoutConfig: () -> LayoutConfig?

    // MARK: - Callbacks (all called on the main thread)

    /// Called after recovering a single window.
    /// Parameters: `(result, windowId, workspace)`.
    var onCurrentWindowRecovered: ((_ result: Result<RecoveryOutcome, PsCoreError>, _ windowId: Int, _ workspace: String) -> Void)?

    /// Called after recovering all windows in a workspace.
    /// Parameters: `(result, focus)`.
    var onWorkspaceRecovered: ((_ result: Result<RecoveryResult, PsCoreError>, _ focus: CapturedFocus) -> Void)?

    /// Called with progress updates during recover-all.
    /// Parameters: `(current, total)`.
    var onAllWindowsProgress: ((_ current: Int, _ total: Int) -> Void)?

    /// Called after recovering all windows across all workspaces.
    var onAllWindowsCompleted: ((_ result: Result<RecoveryResult, PsCoreError>) -> Void)?

    // MARK: - Init

    /// Creates a recovery operation coordinator.
    ///
    /// - Parameters:
    ///   - logger: Logger for structured event logging.
    ///   - makeRecoveryManager: Factory that creates a `WindowRecoveryManager` on a background thread.
    ///   - currentLayoutConfig: Returns the current layout config from `ProjectManager`.
    init(
        logger: ProjectSwitcherLogging,
        makeRecoveryManager: @escaping (_ screenFrame: CGRect, _ layoutConfig: LayoutConfig?) -> WindowRecoveryManager,
        currentLayoutConfig: @escaping () -> LayoutConfig?
    ) {
        self.logger = logger
        self.makeRecoveryManager = makeRecoveryManager
        self.currentLayoutConfig = currentLayoutConfig
    }

    // MARK: - Operations

    /// Recovers a single window by ID.
    ///
    /// Dispatches recovery to a background queue and delivers the result
    /// via `onCurrentWindowRecovered` on the main thread.
    ///
    /// - Parameters:
    ///   - windowId: The window to recover.
    ///   - workspace: The workspace containing the window.
    ///   - screenFrame: Visible screen frame (captured on main thread by caller).
    func recoverCurrentWindow(windowId: Int, workspace: String, screenFrame: CGRect) {
        logEvent("recover_current_window.requested", context: [
            "window_id": "\(windowId)",
            "workspace": workspace
        ])

        // Snapshot mutable callback on the caller's thread (main) before entering
        // the detached task to avoid a data race on the non-Sendable property.
        let callback = onCurrentWindowRecovered
        let capturedLogger = self.logger

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                _ = capturedLogger.log(event: "recover_current_window.coordinator_unavailable", level: .warn, message: "Recovery coordinator deallocated during recovery", context: nil)
                return
            }
            let manager = self.makeRecoveryManager(screenFrame, nil)
            let result = manager.recoverCurrentWindow(windowId: windowId, workspace: workspace)
            await MainActor.run {
                callback?(result, windowId, workspace)
            }
        }
    }

    /// Recovers all windows in a workspace (layout-aware for project workspaces).
    ///
    /// Dispatches recovery to a background queue and delivers the result
    /// via `onWorkspaceRecovered` on the main thread.
    ///
    /// - Parameters:
    ///   - focus: Captured focus that determines the target workspace.
    ///   - screenFrame: Visible screen frame (captured on main thread by caller).
    func recoverWorkspaceWindows(focus: CapturedFocus, screenFrame: CGRect) {
        logEvent("recover_workspace.requested", context: ["workspace": focus.workspace])

        let callback = onWorkspaceRecovered
        let capturedLogger = self.logger

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                _ = capturedLogger.log(event: "recover_workspace.coordinator_unavailable", level: .warn, message: "Recovery coordinator deallocated during recovery", context: nil)
                return
            }
            let layoutConfig = self.currentLayoutConfig()
            let manager = self.makeRecoveryManager(screenFrame, layoutConfig)
            let result = await manager.recoverWorkspaceWindows(workspace: focus.workspace)
            await MainActor.run {
                callback?(result, focus)
            }
        }
    }

    /// Recovers all windows in a workspace with a completion callback.
    ///
    /// Used by the switcher recovery path where the caller needs the result
    /// delivered via a specific completion handler rather than the generic callback.
    /// The completion is called on the main thread.
    ///
    /// - Parameters:
    ///   - focus: Captured focus that determines the target workspace.
    ///   - screenFrame: Visible screen frame (captured on main thread by caller).
    ///   - completion: Completion callback invoked on the main thread.
    func recoverWorkspaceWindows(
        focus: CapturedFocus,
        screenFrame: CGRect,
        completion: @escaping (Result<RecoveryResult, PsCoreError>) -> Void
    ) {
        logEvent("recover_workspace.requested")

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                await MainActor.run {
                    completion(.failure(PsCoreError(category: .command, message: "Recovery coordinator unavailable.")))
                }
                return
            }
            let layoutConfig = self.currentLayoutConfig()
            let manager = self.makeRecoveryManager(screenFrame, layoutConfig)
            let result = await manager.recoverWorkspaceWindows(workspace: focus.workspace)
            await MainActor.run {
                completion(result)
            }
        }
    }

    /// Recovers all windows across all workspaces.
    ///
    /// Dispatches recovery to a background queue, delivers progress updates
    /// via `onAllWindowsProgress` and the final result via `onAllWindowsCompleted`,
    /// both on the main thread.
    ///
    /// - Parameter screenFrame: Visible screen frame (captured on main thread by caller).
    func recoverAllWindows(screenFrame: CGRect) {
        logEvent("recover_all_windows.requested", context: [
            "screen_width": "\(Int(screenFrame.width))",
            "screen_height": "\(Int(screenFrame.height))"
        ])

        // Snapshot mutable callbacks on the caller's thread (main) before
        // entering the detached task to avoid a data race on non-Sendable properties.
        let progressCallback = onAllWindowsProgress
        let completionCallback = onAllWindowsCompleted
        let capturedLogger = self.logger

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                _ = capturedLogger.log(event: "recover_all_windows.coordinator_unavailable", level: .warn, message: "Recovery coordinator deallocated during recovery", context: nil)
                return
            }
            let layoutConfig = self.currentLayoutConfig()
            let manager = self.makeRecoveryManager(screenFrame, layoutConfig)
            let result = await manager.recoverAllWindows { current, total in
                DispatchQueue.main.async {
                    progressCallback?(current, total)
                }
            }

            await MainActor.run {
                completionCallback?(result)
            }
        }
    }

    // MARK: - Private

    private func logEvent(
        _ event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(event: event, level: level, message: message, context: context)
    }
}
