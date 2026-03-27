import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < rows.count else {
            return 32
        }
        return heightForRow(rows[row])
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < rows.count else {
            return nil
        }

        switch rows[row] {
        case .sectionHeader(let title):
            return sectionHeaderCell(title: title, tableView: tableView)
        case .backAction:
            return backActionCell(tableView: tableView)
        case .project(let project, let isCurrent, let isOpen):
            return projectCell(
                for: project,
                isActive: isCurrent,
                isOpen: isOpen,
                query: lastFilterQuery,
                isSelected: row == tableView.selectedRow,
                onClose: isOpen ? { [weak self] in
                    self?.handleCloseProjectButtonClick(projectId: project.id, rowIndex: row)
                } : nil,
                tableView: tableView
            )
        case .emptyState(let message):
            return emptyStateCell(message: message, tableView: tableView)
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < rows.count else {
            return false
        }
        return rows[row].isSelectable
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectionInterval = Self.signposter.beginInterval("SwitcherSelectionChanged")
        defer { Self.signposter.endInterval("SwitcherSelectionChanged", selectionInterval) }

        let previousSelectedRow = lastSelectedRowIndex
        let rowIndex = tableView.selectedRow
        lastSelectedRowIndex = rowIndex

        guard rowIndex >= 0, rowIndex < rows.count else {
            session.logEvent(event: "switcher.selection.cleared")
            updateFooterHints()
            updateSelectionVisuals(previousSelectedRow: previousSelectedRow, newSelectedRow: rowIndex)
            return
        }

        switch rows[rowIndex] {
        case .project(let project, _, _):
            session.logEvent(
                event: "switcher.selection.changed",
                context: [
                    "row": "\(rowIndex)",
                    "project_id": project.id,
                    "project_name": project.name
                ]
            )
        case .backAction:
            session.logEvent(
                event: "switcher.selection.changed",
                context: [
                    "row": "\(rowIndex)",
                    "action": "back_to_previous_window"
                ]
            )
        case .sectionHeader, .emptyState:
            break
        }

        updateFooterHints()
        updateSelectionVisuals(previousSelectedRow: previousSelectedRow, newSelectedRow: rowIndex)
    }
}
