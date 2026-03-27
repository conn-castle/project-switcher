import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - Selection and Actions

    /// Handles the primary action for the selected row.
    func handlePrimaryAction() {
        guard let selectedModel = selectedRowModel() else {
            session.logEvent(
                event: "switcher.selection.skipped",
                level: .warn,
                message: "Selection skipped because no row is selected.",
                context: ["reason": "no_selection"]
            )
            return
        }

        switch selectedModel {
        case .project(let project, _, _):
            handleProjectSelection(project)
        case .backAction:
            handleExitToNonProject(fromShortcut: false)
        case .sectionHeader, .emptyState:
            break
        }
    }

    /// Handles project switching for a selected project row.
    func handleProjectSelection(_ project: ProjectConfig) {
        operationCoordinator.handleProjectSelection(project, capturedFocus: capturedFocus)
    }

    /// Handles "close selected project" keyboard action.
    func handleCloseSelectedProject() {
        guard let selectedProject = selectedProjectRow() else {
            session.logEvent(
                event: "switcher.close_project.skipped",
                level: .warn,
                message: "No project selected."
            )
            NSSound.beep()
            return
        }

        guard selectedProject.isOpen else {
            session.logEvent(
                event: "switcher.close_project.skipped",
                level: .warn,
                message: "Selected project is not open.",
                context: ["project_id": selectedProject.project.id]
            )
            setStatus(message: "Project is not currently open.", level: .warning)
            NSSound.beep()
            return
        }

        performCloseProject(
            projectId: selectedProject.project.id,
            projectName: selectedProject.project.name,
            source: "keybind",
            selectedRowAtRequestTime: tableView.selectedRow
        )
    }

    /// Handles "recover project" keyboard action.
    func handleRecoverProjectFromShortcut() {
        operationCoordinator.handleRecoverProjectFromShortcut(capturedFocus: capturedFocus)
    }

    /// Restores keyboard input focus to the search field after background operations.
    ///
    /// Some operations temporarily disable controls and can leave the panel without
    /// a text responder, which breaks Escape handling routed through command dispatch.
    func restoreSearchFieldInputFocus() {
        guard panel.isVisible else { return }
        _ = panel.makeFirstResponder(searchField)
    }

    /// Handles close button clicks from a project row.
    func handleCloseProjectButtonClick(projectId: String, rowIndex: Int) {
        suppressedActionEventNumber = NSApp.currentEvent?.eventNumber

        let projectName = allProjects.first(where: { $0.id == projectId })?.name ?? projectId
        performCloseProject(
            projectId: projectId,
            projectName: projectName,
            source: "button",
            selectedRowAtRequestTime: rowIndex
        )
    }

    /// Closes a project and keeps the palette open for additional actions.
    func performCloseProject(
        projectId: String,
        projectName: String,
        source: String,
        selectedRowAtRequestTime: Int
    ) {
        let fallbackSelectionKey = selectionKeyAfterClosingRow(
            closedProjectId: projectId,
            closedRowIndex: selectedRowAtRequestTime
        )
        operationCoordinator.performCloseProject(
            projectId: projectId,
            projectName: projectName,
            source: source,
            fallbackSelectionKey: fallbackSelectionKey
        )
    }

    /// Computes the next selection key after closing a row.
    private func selectionKeyAfterClosingRow(
        closedProjectId: String,
        closedRowIndex: Int
    ) -> String? {
        guard !rows.isEmpty else {
            return nil
        }

        for index in (closedRowIndex + 1)..<rows.count {
            guard let key = rows[index].selectionKey else { continue }
            if key != "project:\(closedProjectId)" {
                return key
            }
        }

        if closedRowIndex > 0 {
            for index in stride(from: closedRowIndex - 1, through: 0, by: -1) {
                guard let key = rows[index].selectionKey else { continue }
                if key != "project:\(closedProjectId)" {
                    return key
                }
            }
        }

        return nil
    }

    /// Exits to non-project space and dismisses the panel on success.
    func handleExitToNonProject(fromShortcut: Bool) {
        let hasBackActionRow = rows.contains(where: {
            if case .backAction = $0 { return true }
            return false
        })
        operationCoordinator.handleExitToNonProject(
            fromShortcut: fromShortcut,
            hasBackActionRow: hasBackActionRow
        )
    }

    /// Moves selection up/down while skipping non-selectable rows.
    func moveSelection(delta: Int) {
        guard !rows.isEmpty else { return }

        var currentIndex = tableView.selectedRow
        if currentIndex < 0 {
            currentIndex = delta > 0 ? -1 : rows.count
        }

        var candidate = currentIndex + delta
        while candidate >= 0 && candidate < rows.count {
            if rows[candidate].isSelectable {
                tableView.selectRowIndexes(IndexSet(integer: candidate), byExtendingSelection: false)
                tableView.scrollRowToVisible(candidate)
                return
            }
            candidate += delta
        }
    }

}
