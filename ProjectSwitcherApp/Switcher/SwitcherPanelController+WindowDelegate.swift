import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        true
    }

    func windowWillClose(_ notification: Notification) {
        dismiss(reason: .windowClose)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel.isVisible else { return }
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: operationCoordinator.isActivating,
            isVisible: true,
            isExternalFocusTransitionInProgress: operationCoordinator.isExitingToNonProject
                || operationCoordinator.isClosingProject
        )
        switch decision {
        case .dismiss:
            dismiss(reason: .windowClose)
        case .suppress(let reason):
            session.logEvent(
                event: "switcher.resign_key.suppressed",
                level: .info,
                context: ["reason": reason]
            )
        }
    }
}
