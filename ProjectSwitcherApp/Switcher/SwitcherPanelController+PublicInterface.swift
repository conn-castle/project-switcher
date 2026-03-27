import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - Public Interface

    /// Whether the switcher panel is currently visible.
    var isVisible: Bool {
        panel.isVisible
    }

    /// Toggles the switcher panel visibility.
    ///
    /// - Parameters:
    ///   - origin: Source that triggered the toggle.
    ///   - previousApp: The app that was active before ProjectSwitcher was activated.
    ///                  Must be captured BEFORE calling NSApp.activate().
    ///   - capturedFocus: The window focus state captured before activation.
    ///                    Must be captured BEFORE calling NSApp.activate().
    func toggle(
        origin: SwitcherPresentationSource = .unknown,
        previousApp: NSRunningApplication? = nil,
        capturedFocus: CapturedFocus? = nil
    ) {
        if panel.isVisible {
            dismiss(reason: .toggle)
        } else {
            show(origin: origin, previousApp: previousApp, capturedFocus: capturedFocus)
        }
    }

    /// Shows the switcher panel and resets transient state.
    ///
    /// - Parameters:
    ///   - origin: Source that triggered the show.
    ///   - previousApp: The app that was active before ProjectSwitcher was activated.
    ///                  Must be captured BEFORE calling NSApp.activate().
    ///   - capturedFocus: The window focus state captured before activation.
    ///                    Must be captured BEFORE calling NSApp.activate().
    func show(
        origin: SwitcherPresentationSource = .unknown,
        previousApp: NSRunningApplication? = nil,
        capturedFocus: CapturedFocus? = nil
    ) {
        let showInterval = Self.signposter.beginInterval("SwitcherShow")
        defer { Self.signposter.endInterval("SwitcherShow", showInterval) }

        let showStart = CFAbsoluteTimeGetCurrent()

        // Use provided previousApp, or fall back to current frontmost (less reliable)
        restoreFocusTask?.cancel()
        previouslyActiveApp = previousApp ?? NSWorkspace.shared.frontmostApplication
        resetState(initialQuery: "")
        expectsVisible = true
        session.begin(origin: origin)
        session.logShowRequested(origin: origin)

        // Use pre-captured focus (captured before NSApp.activate() in caller)
        self.capturedFocus = capturedFocus

        if let focus = capturedFocus {
            session.logEvent(
                event: "switcher.focus.received",
                context: [
                    "window_id": "\(focus.windowId)",
                    "app_bundle_id": focus.appBundleId
                ]
            )
        } else {
            session.logEvent(
                event: "switcher.focus.not_provided",
                level: .warn,
                message: "No focus state provided; restore-on-cancel may not work."
            )
        }

        // Seed workspace-derived state from captured focus so first paint is closer to final rows.
        seedWorkspaceStateFromCapturedFocus(capturedFocus)

        let configInterval = Self.signposter.beginInterval("SwitcherConfigLoadOrReuse")
        loadOrReuseProjectsForShow()
        Self.signposter.endInterval("SwitcherConfigLoadOrReuse", configInterval)

        let initialFilterInterval = Self.signposter.beginInterval("SwitcherInitialFilter")
        applyFilter(query: "", preferredSelectionKey: nil, useDefaultSelection: true)
        Self.signposter.endInterval("SwitcherInitialFilter", initialFilterInterval)

        // Show panel after initial rows are prepared to avoid opening at min height then jumping.
        let panelInterval = Self.signposter.beginInterval("SwitcherShowPanel")
        showPanel()
        installKeyEventMonitor()
        Self.signposter.endInterval("SwitcherShowPanel", panelInterval)

        if configErrorMessage == nil {
            refreshWorkspaceState(
                retryOnFailure: true,
                preferredSelectionKey: selectedRowKey(),
                useDefaultSelection: false
            )
        }

        let totalMs = Int((CFAbsoluteTimeGetCurrent() - showStart) * 1000)

        scheduleVisibilityCheck(origin: origin)

        session.logEvent(
            event: "switcher.show.timing",
            context: [
                "total_ms": "\(totalMs)"
            ]
        )
    }

    /// Dismisses the switcher panel and clears transient state.
    func dismiss(reason: SwitcherDismissReason = .unknown) {
        guard !isDismissing else {
            session.logEvent(
                event: "switcher.dismiss.reentrant_blocked",
                level: .warn,
                context: ["reason": reason.rawValue]
            )
            return
        }
        isDismissing = true
        defer { isDismissing = false }

        removeKeyEventMonitor()
        expectsVisible = false
        operationCoordinator.resetGuards()
        pendingVisibilityCheckToken = nil
        restoreFocusTask?.cancel()
        cancelPendingFilterWorkItem()
        workspaceRetryCoordinator.cancelRetry()
        session.end(reason: reason)

        let shouldRestore = SwitcherDismissPolicy.shouldRestoreFocus(reason: reason)

        // Restore focus unless the action handles it.
        // IMPORTANT: Activate the previous app BEFORE closing the panel to prevent
        // macOS from picking a random window when the panel disappears.
        if shouldRestore {
            if let previousApp = previouslyActiveApp {
                previousApp.activate()
            }
        }

        panel.orderOut(nil)

        // Do precise AeroSpace window focus async (can be slow).
        if shouldRestore {
            restorePreviousFocus()
        } else {
            previouslyActiveApp = nil
        }

        capturedFocus = nil
        resetState(initialQuery: "")

        onSessionEnded?()
    }

}
