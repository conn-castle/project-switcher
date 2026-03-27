import Foundation

import ProjectSwitcherCore

/// Coordinates Option-Tab overlay lifecycle on top of `WindowCycler`.
///
/// State transitions:
/// - `start` on first Option-Tab while Option is held
/// - `advance` on repeated Tab presses while Option is held
/// - `commit` when Option is released
final class WindowCycleOverlayCoordinator {
    private let windowCycler: WindowCycler
    private let overlayController: WindowCycleOverlayController
    private let logger: ProjectSwitcherLogging
    private let shouldSuppressOverlay: () -> Bool
    private let windowPositioner: WindowPositioning?
    private let mainScreenVisibleFrame: (() -> CGRect?)?
    private let queue = DispatchQueue(label: "com.projectswitcher.window-cycle-overlay", qos: .userInteractive)
    private var activeSession: WindowCycler.CycleSession?

    init(
        windowCycler: WindowCycler,
        logger: ProjectSwitcherLogging = ProjectSwitcherLogger(),
        overlayController: WindowCycleOverlayController = WindowCycleOverlayController(),
        shouldSuppressOverlay: @escaping () -> Bool,
        windowPositioner: WindowPositioning? = nil,
        mainScreenVisibleFrame: (() -> CGRect?)? = nil
    ) {
        self.windowCycler = windowCycler
        self.logger = logger
        self.overlayController = overlayController
        self.shouldSuppressOverlay = shouldSuppressOverlay
        self.windowPositioner = windowPositioner
        self.mainScreenVisibleFrame = mainScreenVisibleFrame
    }

    /// Starts a new overlay cycle session.
    ///
    /// Falls back to immediate cycle behavior if no overlay session is available
    /// (0/1 windows, switcher conflict, or AeroSpace failure).
    /// - Parameters:
    ///   - direction: Initial cycle direction.
    ///   - fallbackCycle: Immediate fallback behavior (legacy cycle).
    func start(direction: CycleDirection, fallbackCycle: @escaping () -> Void) {
        // Read suppression state before dispatching to the serial queue to avoid
        // calling DispatchQueue.main.sync from within the queue, which risks
        // deadlock if start() is ever invoked from the main thread.
        let suppressed = isOverlaySuppressed()
        queue.async { [weak self] in
            guard let self else { return }

            if suppressed {
                self.activeSession = nil
                self.hideOverlay()
                fallbackCycle()
                return
            }

            switch self.windowCycler.startSession(direction: direction) {
            case .success(let session?):
                self.activeSession = session
                self.showOverlay(session)
            case .success(nil):
                self.activeSession = nil
                self.hideOverlay()
                fallbackCycle()
            case .failure(let error):
                self.activeSession = nil
                self.hideOverlay()
                _ = self.logger.log(
                    event: "focus_cycle.overlay.start_failed",
                    level: .warn,
                    message: error.message,
                    context: nil
                )
                fallbackCycle()
            }
        }
    }

    /// Advances selection in the active overlay session.
    ///
    /// Falls back to immediate cycle behavior when no session is active.
    /// - Parameters:
    ///   - direction: Selection direction.
    ///   - fallbackCycle: Immediate fallback behavior (legacy cycle).
    func advance(direction: CycleDirection, fallbackCycle: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let session = self.activeSession else {
                fallbackCycle()
                return
            }
            let updated = self.windowCycler.advanceSelection(session: session, direction: direction)
            self.activeSession = updated
            self.showOverlay(updated)
        }
    }

    /// Commits the current session selection and dismisses overlay UI.
    func commit() {
        queue.async { [weak self] in
            guard let self else { return }
            guard let session = self.activeSession else {
                self.hideOverlay()
                return
            }
            self.activeSession = nil
            if case .failure(let error) = self.windowCycler.commitSelection(session: session) {
                _ = self.logger.log(
                    event: "focus_cycle.overlay.commit_failed",
                    level: .warn,
                    message: error.message,
                    context: nil
                )
            } else {
                self.recoverFocusedWindowIfNeeded(bundleId: session.selectedCandidate.appBundleId)
            }
            self.hideOverlay()
        }
    }

    // MARK: - Private

    /// Recovers the focused window if it is off-screen or oversized. Non-fatal.
    private func recoverFocusedWindowIfNeeded(bundleId: String) {
        guard let windowPositioner,
              let screenFrame = mainScreenVisibleFrame?() else { return }
        _ = windowPositioner.recoverFocusedWindow(bundleId: bundleId, screenVisibleFrame: screenFrame)
    }

    private func isOverlaySuppressed() -> Bool {
        if Thread.isMainThread {
            return shouldSuppressOverlay()
        }
        return DispatchQueue.main.sync {
            shouldSuppressOverlay()
        }
    }

    private func showOverlay(_ session: WindowCycler.CycleSession) {
        DispatchQueue.main.async { [overlayController] in
            overlayController.show(session: session)
        }
    }

    private func hideOverlay() {
        DispatchQueue.main.async { [overlayController] in
            overlayController.hide()
        }
    }
}
