import Foundation

extension ProjectManager {
    // MARK: - Sequential Window Setup

    /// Outcome from find-or-launch: the window and whether it was freshly launched.
    struct FindOrLaunchOutcome {
        let window: PsWindow
        let wasLaunched: Bool
    }

    /// Finds an existing tagged window or launches a new one and polls until it appears.
    ///
    /// This helper handles find/launch/poll only — it does NOT move the window.
    /// The caller is responsible for moving the window to the target workspace.
    ///
    /// - Parameters:
    ///   - appBundleId: Bundle ID to search for (e.g., Chrome or VS Code).
    ///   - projectId: Project ID used for the window token.
    ///   - launchAction: Closure that launches a new window if none exists.
    ///   - windowLabel: Human-readable label for logging (e.g., "Chrome", "VS Code").
    ///   - eventSource: Stable log event key source (e.g., "chrome", "vscode").
    /// - Returns: The found or launched window on success, with a flag indicating whether it was freshly launched.
    func findOrLaunchWindow(
        appBundleId: String,
        projectId: String,
        launchAction: () -> Result<Void, PsCoreError>,
        windowLabel: String,
        eventSource: String
    ) async -> Result<FindOrLaunchOutcome, ProjectError> {
        // Capture the pre-launch inventory so Chrome can be identified by a newly
        // appeared window ID when AeroSpace has not refreshed its title yet.
        let windowsBeforeLaunch: [PsWindow]
        switch aerospace.listWindowsForApp(bundleId: appBundleId) {
        case .success(let windows):
            windowsBeforeLaunch = windows
        case .failure(let error):
            logEvent("window_lookup.list_failed", level: .warn,
                     message: error.message,
                     context: ["app_bundle_id": appBundleId, "project_id": projectId])
            // Absence has not been established. Launching here can duplicate a
            // window that is merely hidden by an AeroSpace outage.
            return .failure(.aeroSpaceError(detail: error.message))
        }

        // Find existing tagged window (global search with fallback)
        if let window = windowsBeforeLaunch.first(where: {
            PsIdeToken.matches(windowTitle: $0.windowTitle, projectId: projectId)
        }) {
            logEvent(Self.activationWindowEventName(source: eventSource, action: "found"), context: ["window_id": "\(window.windowId)"])
            return .success(FindOrLaunchOutcome(window: window, wasLaunched: false))
        }

        // Launch a new window
        switch launchAction() {
        case .failure(let error):
            logEvent(Self.activationWindowEventName(source: eventSource, action: "launch_failed"), level: .error, context: ["error": error.message])
            let projectError: ProjectError = windowLabel == "Chrome"
                ? .chromeLaunchFailed(detail: "\(windowLabel) launch failed: \(error.message)")
                : .ideLaunchFailed(detail: "\(windowLabel) launch failed: \(error.message)")
            return .failure(projectError)
        case .success:
            logEvent(Self.activationWindowEventName(source: eventSource, action: "launched"), context: ["project_id": projectId])
        }

        // Poll until window appears
        let newWindowBaselineIds = appBundleId == PsChromeLauncher.bundleId
            ? Set(windowsBeforeLaunch.map(\.windowId))
            : nil
        return await pollForWindowByToken(
            appBundleId: appBundleId,
            projectId: projectId,
            windowLabel: windowLabel,
            newWindowBaselineIds: newWindowBaselineIds
        )
            .map { FindOrLaunchOutcome(window: $0, wasLaunched: true) }
    }

}
