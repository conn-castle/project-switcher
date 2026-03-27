import AppKit

import ProjectSwitcherCore

#if DEBUG
// Test-only hooks for app-layer integration tests.
extension SwitcherPanelController {
    func testing_handleExitToNonProject(fromShortcut: Bool = false) {
        handleExitToNonProject(fromShortcut: fromShortcut)
    }

    func testing_performCloseProject(
        projectId: String,
        projectName: String,
        source: String,
        selectedRowAtRequestTime: Int
    ) {
        performCloseProject(
            projectId: projectId,
            projectName: projectName,
            source: source,
            selectedRowAtRequestTime: selectedRowAtRequestTime
        )
    }

    func testing_handleProjectSelection(_ project: ProjectConfig) {
        handleProjectSelection(project)
    }

    func testing_setCapturedFocus(_ focus: CapturedFocus?) {
        capturedFocus = focus
    }

    func testing_handleRecoverProjectFromShortcut() {
        handleRecoverProjectFromShortcut()
    }

    func testing_updateFooterHints() {
        updateFooterHints()
    }

    func testing_showPanelForFocusAssertions() {
        showPanel()
    }

    /// Orders the panel out to prevent keyboard focus theft during async test waits.
    func testing_orderOutPanel() {
        panel.orderOut(nil)
    }

    @discardableResult
    func testing_makeSearchFieldFirstResponder() -> Bool {
        panel.makeFirstResponder(searchField)
    }

    @discardableResult
    func testing_makeTableViewFirstResponder() -> Bool {
        panel.makeFirstResponder(tableView)
    }

    var testing_searchFieldHasInputFocus: Bool {
        let responder = panel.firstResponder
        return responder === searchField || responder === searchField.currentEditor()
    }

    var testing_searchFieldValue: String {
        searchField.stringValue
    }

    func testing_setSearchFieldValue(_ value: String) {
        searchField.stringValue = value
    }

    var testing_footerHints: String {
        keybindHintLabel.stringValue
    }

    var testing_capturedFocus: CapturedFocus? {
        capturedFocus
    }

    func testing_enableBackActionRow() {
        rows = [.backAction]
    }
}
#endif
