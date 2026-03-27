import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - Status Display

    /// Updates the status label with a message and visual level.
    func setStatus(message: String, level: StatusLevel) {
        statusLabel.stringValue = message
        statusLabel.textColor = level.textColor
        statusLabel.isHidden = false

        let levelLabel: String
        switch level {
        case .info:
            levelLabel = "info"
        case .warning:
            levelLabel = "warning"
        case .error:
            levelLabel = "error"
        }

        if lastStatusMessage != message || lastStatusLevel != level {
            session.logEvent(
                event: "switcher.status.updated",
                level: level == .error ? .error : (level == .warning ? .warn : .info),
                message: message,
                context: ["status_level": levelLabel]
            )
            lastStatusMessage = message
            lastStatusLevel = level
        }
    }

    /// Hides the status label.
    func clearStatus() {
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.textColor = .secondaryLabelColor

        if lastStatusMessage != nil || lastStatusLevel != nil {
            session.logEvent(event: "switcher.status.cleared")
            lastStatusMessage = nil
            lastStatusLevel = nil
        }
    }

    /// Updates footer hints based on row selection and available actions.
    func updateFooterHints() {
        var parts: [String] = ["esc Dismiss"]

        if capturedFocus != nil, onRecoverProjectRequested != nil {
            parts.append("\u{2318}R Recover Project")
        }

        if let selectedProject = selectedProjectRow(), selectedProject.isOpen {
            parts.append("\u{2318}\u{232B} Close Project")
        }

        if rows.contains(where: {
            if case .backAction = $0 {
                return true
            }
            return false
        }) {
            parts.append("\u{21E7}\u{21A9} Back to Non-Project Space")
        }

        parts.append("\u{21A9} Switch")

        keybindHintLabel.stringValue = parts.joined(separator: "      ")
    }

    /// Cancels pending debounced filter work.
    func cancelPendingFilterWorkItem() {
        pendingFilterWorkItem?.cancel()
        pendingFilterWorkItem = nil
        // Invalidate any outstanding debounce token so canceled callbacks are no longer latest.
        _ = filterDebounceTokens.issueToken()
    }

    /// Schedules a debounced filter update for keystroke-driven query changes.
    func scheduleDebouncedFilter(query: String) {
        cancelPendingFilterWorkItem()
        let preferredSelectionKey = selectedRowKey()
        let token = filterDebounceTokens.issueToken()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.filterDebounceTokens.isLatest(token) else { return }
            self.pendingFilterWorkItem = nil
            self.applyFilter(
                query: query,
                preferredSelectionKey: preferredSelectionKey,
                useDefaultSelection: false
            )
        }
        pendingFilterWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SwitcherTiming.filterDebounceSeconds,
            execute: workItem
        )
    }

    /// Applies a pending debounced filter synchronously before running a primary action.
    ///
    /// Without this flush, pressing Enter immediately after typing can act on stale rows
    /// while the debounced filter callback is still pending.
    func flushPendingFilterForPrimaryActionIfNeeded() {
        guard pendingFilterWorkItem != nil else {
            return
        }

        // Invalidate any in-flight token before canceling to prevent stale callbacks
        // from applying after the synchronous flush.
        _ = filterDebounceTokens.issueToken()
        cancelPendingFilterWorkItem()

        applyFilter(
            query: searchField.stringValue,
            preferredSelectionKey: selectedRowKey(),
            useDefaultSelection: false
        )

        session.logEvent(
            event: "switcher.filter.flushed_for_primary_action",
            context: ["query": searchField.stringValue]
        )
    }

}
