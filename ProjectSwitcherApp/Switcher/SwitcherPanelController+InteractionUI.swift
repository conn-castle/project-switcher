import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - Key Event Monitor

    /// Installs a local event monitor for palette-specific shortcuts.
    /// Used instead of performKeyEquivalent because non-activating panels
    /// do not reliably route key equivalents through the standard responder chain.
    func installKeyEventMonitor() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Shift+Return => Back to non-project space.
            if (event.keyCode == 36 || event.keyCode == 76), modifiers == [.shift] {
                self.session.logEvent(event: "switcher.action.exit_to_previous_keybind")
                self.handleExitToNonProject(fromShortcut: true)
                return nil
            }

            // Cmd+Delete / Cmd+ForwardDelete => close selected project.
            if (event.keyCode == 51 || event.keyCode == 117), modifiers == [.command] {
                self.session.logEvent(event: "switcher.action.close_project_keybind")
                self.handleCloseSelectedProject()
                return nil
            }

            // Cmd+R => recover focused workspace windows.
            if event.keyCode == 15, modifiers == [.command] {
                self.session.logEvent(event: "switcher.action.recover_project_keybind")
                self.handleRecoverProjectFromShortcut()
                return nil
            }

            return event
        }
    }

    /// Removes the local event monitor.
    func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }

    // MARK: - Table Row Appearance

    /// Updates selection visuals for previously-selected and newly-selected rows.
    func updateSelectionVisuals(previousSelectedRow: Int, newSelectedRow: Int) {
        if previousSelectedRow == newSelectedRow {
            updateProjectRowSelection(at: newSelectedRow, isSelected: true)
            return
        }
        updateProjectRowSelection(at: previousSelectedRow, isSelected: false)
        updateProjectRowSelection(at: newSelectedRow, isSelected: true)
    }

    /// Updates selection visual state for a single project row, if visible.
    private func updateProjectRowSelection(at rowIndex: Int, isSelected: Bool) {
        guard rowIndex >= 0, rowIndex < rows.count else {
            return
        }
        guard case .project = rows[rowIndex] else {
            return
        }
        guard let rowView = tableView.view(
            atColumn: 0,
            row: rowIndex,
            makeIfNecessary: false
        ) as? ProjectRowView else {
            return
        }
        rowView.setRowSelected(isSelected)
    }

    // MARK: - Sizing and Positioning

    /// Returns the display frame currently under the mouse pointer.
    private func activeDisplayFrame() -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// Centers the panel on the active display.
    func centerPanelOnActiveDisplay() {
        let displayFrame = activeDisplayFrame()
        let x = displayFrame.midX - (panel.frame.width / 2)
        let y = displayFrame.midY - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Updates panel height based on row count and available display height.
    func updatePanelSizeForCurrentRows() {
        let displayFrame = activeDisplayFrame()
        let maxHeight = floor(displayFrame.height * SwitcherLayout.maxHeightScreenFraction)
        let rowHeights = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + heightForRow(row)
        }
        let targetHeight = max(
            SwitcherLayout.minPanelHeight,
            min(maxHeight, SwitcherLayout.chromeHeightEstimate + rowHeights)
        )

        if abs(panel.frame.height - targetHeight) < 0.5 {
            return
        }

        var frame = panel.frame
        frame.size = NSSize(width: SwitcherLayout.panelWidth, height: targetHeight)
        panel.setFrame(frame, display: true)
        centerPanelOnActiveDisplay()
    }

    /// Returns row height for a given row type.
    func heightForRow(_ row: SwitcherListRow) -> CGFloat {
        switch row {
        case .sectionHeader:
            return 22
        case .backAction:
            return 36
        case .project:
            return 44
        case .emptyState:
            return 36
        }
    }

    // MARK: - Visibility Verification

    /// Schedules a visibility check to confirm the panel appeared.
    func scheduleVisibilityCheck(origin: SwitcherPresentationSource) {
        let token = UUID()
        pendingVisibilityCheckToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitcherTiming.visibilityCheckDelaySeconds) { [weak self] in
            self?.verifyPanelVisibility(token: token, origin: origin)
        }
    }

    /// Verifies panel visibility and logs failures.
    private func verifyPanelVisibility(token: UUID, origin: SwitcherPresentationSource) {
        guard pendingVisibilityCheckToken == token, expectsVisible else {
            return
        }

        let context = [
            "source": origin.rawValue,
            "visible": panel.isVisible ? "true" : "false",
            "key": panel.isKeyWindow ? "true" : "false",
            "main": panel.isMainWindow ? "true" : "false"
        ]

        if panel.isVisible {
            session.logEvent(
                event: "switcher.show.visible",
                context: context
            )
        } else {
            session.logEvent(
                event: "switcher.show.not_visible",
                level: .error,
                message: "Switcher panel failed to become visible.",
                context: context
            )
        }
    }

    // MARK: - Table Click Action

    /// Handles single-click actions on selectable rows.
    @objc func handleTableViewAction(_ sender: Any?) {
        guard panel.isVisible else { return }

        if let suppressedEventNumber = suppressedActionEventNumber,
           let currentEventNumber = NSApp.currentEvent?.eventNumber,
           currentEventNumber == suppressedEventNumber {
            suppressedActionEventNumber = nil
            return
        }
        suppressedActionEventNumber = nil
        handlePrimaryAction()
    }
}
