import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - Focus Capture and Restore

    /// Restores focus to the previously focused window or app.
    /// Runs asynchronously to avoid blocking the main thread if AeroSpace commands are slow.
    func restorePreviousFocus() {
        let focus = capturedFocus
        let previousApp = previouslyActiveApp
        let projectManager = self.projectManager
        let session = self.session

        // Clear references immediately so they're not reused
        previouslyActiveApp = nil

        restoreFocusTask?.cancel()
        restoreFocusTask = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            let restoreStart = CFAbsoluteTimeGetCurrent()

            // Try AeroSpace restore first via ProjectManager
            if let focus {
                if projectManager.restoreFocus(focus) {
                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    await MainActor.run {
                        session.logEvent(
                            event: "switcher.focus.restored",
                            context: [
                                "window_id": "\(focus.windowId)",
                                "method": "aerospace",
                                "restore_ms": "\(restoreMs)"
                            ]
                        )
                    }
                    return
                } else {
                    // Window gone — try focusing the workspace the user was on
                    if projectManager.focusWorkspace(name: focus.workspace) {
                        let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                        await MainActor.run {
                            session.logEvent(
                                event: "switcher.focus.restored",
                                context: [
                                    "workspace": focus.workspace,
                                    "method": "workspace_fallback",
                                    "restore_ms": "\(restoreMs)"
                                ]
                            )
                        }
                        return
                    }

                    if previousApp == nil {
                        let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                        await MainActor.run {
                            session.logEvent(
                                event: "switcher.focus.restore_failed",
                                level: .warn,
                                message: "AeroSpace focus restore failed and no previous app fallback is available.",
                                context: [
                                    "window_id": "\(focus.windowId)",
                                    "has_app_fallback": "false",
                                    "restore_ms": "\(restoreMs)"
                                ]
                            )
                        }
                    }
                }
            }

            // Fallback: activate the previously active app (must be on main thread)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let previousApp {
                    previousApp.activate()
                    let restoreMs = Int((CFAbsoluteTimeGetCurrent() - restoreStart) * 1000)
                    session.logEvent(
                        event: "switcher.focus.restored",
                        context: [
                            "app_bundle_id": previousApp.bundleIdentifier ?? "unknown",
                            "method": "app_activation",
                            "restore_ms": "\(restoreMs)"
                        ]
                    )
                }
            }
        }
    }

    /// Focuses the IDE window after panel dismissal.
    /// Called after project selection to focus the IDE once the panel is closed.
    func focusIdeWindow(windowId: Int) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if self?.projectManager.focusWindow(windowId: windowId) == true {
                DispatchQueue.main.async {
                    self?.session.logEvent(
                        event: "switcher.ide.focused",
                        context: ["window_id": "\(windowId)"]
                    )
                }
            }
        }
    }

}
