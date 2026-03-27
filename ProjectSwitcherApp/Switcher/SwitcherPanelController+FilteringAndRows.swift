import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - Filtering and Rows

    /// Applies filtering and updates grouped rows and selection.
    func applyFilter(
        query: String,
        preferredSelectionKey: String?,
        useDefaultSelection: Bool
    ) {
        let applyFilterInterval = Self.signposter.beginInterval("SwitcherApplyFilter")
        defer { Self.signposter.endInterval("SwitcherApplyFilter", applyFilterInterval) }

        let previousQuery = lastFilterQuery
        let queryChanged = previousQuery != query
        let fallbackSelectionKey = preferredSelectionKey ?? selectedRowKey()
        let previousRows = rows
        let previousSelectedRow = tableView.selectedRow
        lastFilterQuery = query

        guard configErrorMessage == nil else {
            rows = [.emptyState(message: configErrorMessage ?? "Config error")]
            filteredProjects = []
            tableView.reloadData()
            tableView.deselectAll(nil)
            lastSelectedRowIndex = tableView.selectedRow
            updatePanelSizeForCurrentRows()
            updateFooterHints()
            session.logEvent(
                event: "switcher.filter.skipped",
                level: .warn,
                message: "Filter skipped due to config error.",
                context: [
                    "query": query,
                    "previous_query": previousQuery,
                    "reason": "config_error"
                ]
            )
            return
        }

        let filterBuildInterval = Self.signposter.beginInterval("SwitcherFilterBuild")
        filteredProjects = projectManager.sortedProjects(query: query)
        let nextRows = SwitcherListModelBuilder.buildRows(
            filteredProjects: filteredProjects,
            activeProjectId: activeProjectId,
            openIds: openIds,
            query: query
        )
        let contentChanged = queryChanged || rowContentSignatures(for: previousRows) != rowContentSignatures(for: nextRows)
        let reloadMode = SwitcherTableReloadPlanner.plan(
            previous: rowStructuralSignatures(for: previousRows),
            next: rowStructuralSignatures(for: nextRows),
            contentChanged: contentChanged
        )
        rows = nextRows
        Self.signposter.endInterval("SwitcherFilterBuild", filterBuildInterval)

        let tableUpdateInterval = Self.signposter.beginInterval("SwitcherFilterTableUpdate")
        switch reloadMode {
        case .fullReload:
            tableView.reloadData()
        case .visibleRowsReload:
            guard !rows.isEmpty else { break }
            let visibleRowsRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRowsRange.location != NSNotFound, visibleRowsRange.length > 0 else {
                tableView.reloadData()
                break
            }

            let start = max(0, visibleRowsRange.location)
            let endExclusive = min(start + visibleRowsRange.length, rows.count)
            guard start < endExclusive else {
                tableView.reloadData()
                break
            }

            tableView.reloadData(
                forRowIndexes: IndexSet(integersIn: start..<endExclusive),
                columnIndexes: IndexSet(integer: 0)
            )
        case .noReload:
            break
        }
        Self.signposter.endInterval("SwitcherFilterTableUpdate", tableUpdateInterval)

        restoreSelection(
            preferredSelectionKey: fallbackSelectionKey,
            useDefaultSelection: useDefaultSelection
        )
        let newSelectedRow = tableView.selectedRow
        updateSelectionVisuals(previousSelectedRow: previousSelectedRow, newSelectedRow: newSelectedRow)
        lastSelectedRowIndex = newSelectedRow
        updatePanelSizeForCurrentRows()
        updateFooterHints()

        session.logEvent(
            event: "switcher.filter.applied",
            context: [
                "query": query,
                "previous_query": previousQuery,
                "total_count": "\(allProjects.count)",
                "filtered_count": "\(filteredProjects.count)",
                "reload_mode": reloadMode.rawValue
            ]
        )

        if !rows.contains(where: { if case .project = $0 { return true } else { return false } }) {
            session.logEvent(
                event: "switcher.filter.empty",
                message: "No matches.",
                context: ["query": query]
            )
        }
    }

    /// Returns structural signatures for planner decisions.
    private func rowStructuralSignatures(for rows: [SwitcherListRow]) -> [SwitcherRowSignature] {
        rows.map { row in
            switch row {
            case .sectionHeader:
                return SwitcherRowSignature(kind: .sectionHeader, selectionKey: row.selectionKey)
            case .backAction:
                return SwitcherRowSignature(kind: .backAction, selectionKey: row.selectionKey)
            case .project:
                return SwitcherRowSignature(kind: .project, selectionKey: row.selectionKey)
            case .emptyState:
                return SwitcherRowSignature(kind: .emptyState, selectionKey: row.selectionKey)
            }
        }
    }

    /// Returns row-content signatures used to detect non-structural content changes.
    private func rowContentSignatures(for rows: [SwitcherListRow]) -> [String] {
        rows.map { row in
            switch row {
            case .sectionHeader(let title):
                return "section:\(title)"
            case .backAction:
                return "action:back"
            case .project(let project, let isCurrent, let isOpen):
                return "project:\(project.id)|current:\(isCurrent)|open:\(isOpen)"
            case .emptyState(let message):
                return "empty:\(message)"
            }
        }
    }

    /// Restores selection by key, with a fallback default selection policy.
    private func restoreSelection(preferredSelectionKey: String?, useDefaultSelection: Bool) {
        if let preferredSelectionKey,
           let preferredRow = SwitcherListModelBuilder.rowIndex(forSelectionKey: preferredSelectionKey, in: rows) {
            tableView.selectRowIndexes(IndexSet(integer: preferredRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(preferredRow)
            return
        }

        if let fallbackRow = SwitcherListModelBuilder.defaultSelectionIndex(
            in: rows,
            preferCurrentProject: useDefaultSelection
        ) {
            tableView.selectRowIndexes(IndexSet(integer: fallbackRow), byExtendingSelection: false)
            tableView.scrollRowToVisible(fallbackRow)
        } else {
            tableView.deselectAll(nil)
        }
    }

    /// Returns the currently selected row model.
    func selectedRowModel() -> SwitcherListRow? {
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else {
            return nil
        }
        return rows[row]
    }

    /// Returns the stable key for the selected row, when available.
    func selectedRowKey() -> String? {
        selectedRowModel()?.selectionKey
    }

    /// Returns the currently selected project row values.
    func selectedProjectRow() -> (project: ProjectConfig, isCurrent: Bool, isOpen: Bool)? {
        guard let selectedModel = selectedRowModel() else {
            return nil
        }
        if case .project(let project, let isCurrent, let isOpen) = selectedModel {
            return (project, isCurrent, isOpen)
        }
        return nil
    }

}
