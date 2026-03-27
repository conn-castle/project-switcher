import AppKit
import os

import ProjectSwitcherCore
// MARK: - Supporting Types

/// Source of a switcher presentation request.
enum SwitcherPresentationSource: String {
    case menu
    case hotkey
    case reopen
    case unknown
}

// SwitcherDismissReason is defined in ProjectSwitcherCore/SwitcherDismissPolicy.swift

/// Timing constants for switcher behavior.
enum SwitcherTiming {
    static let visibilityCheckDelaySeconds: TimeInterval = 0.15
    static let filterDebounceSeconds: TimeInterval = 0.03
}

/// Layout constants for the switcher panel.
enum SwitcherLayout {
    static let panelWidth: CGFloat = 560
    static let initialPanelHeight: CGFloat = 420
    static let minPanelHeight: CGFloat = 280
    static let maxHeightScreenFraction: CGFloat = 0.65
    static let chromeHeightEstimate: CGFloat = 185
}

/// Visual severity level for status messages.
enum StatusLevel: Equatable {
    case info
    case warning
    case error

    var textColor: NSColor {
        switch self {
        case .info:
            return .secondaryLabelColor
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }
}

/// Row model for the grouped switcher results list.
enum SwitcherListRow {
    case sectionHeader(title: String)
    case backAction
    case project(project: ProjectConfig, isCurrent: Bool, isOpen: Bool)
    case emptyState(message: String)

    var isSelectable: Bool {
        switch self {
        case .backAction, .project:
            return true
        case .sectionHeader, .emptyState:
            return false
        }
    }

    var selectionKey: String? {
        switch self {
        case .backAction:
            return "action:back"
        case .project(let project, _, _):
            return "project:\(project.id)"
        case .sectionHeader, .emptyState:
            return nil
        }
    }
}

/// Builder for grouped switcher rows and selection indices.
enum SwitcherListModelBuilder {
    /// Builds grouped rows from current filter and workspace state.
    static func buildRows(
        filteredProjects: [ProjectConfig],
        activeProjectId: String?,
        openIds: Set<String>,
        query: String
    ) -> [SwitcherListRow] {
        var rows: [SwitcherListRow] = []

        if activeProjectId != nil {
            rows.append(.sectionHeader(title: "Actions"))
            rows.append(.backAction)
        }

        if let activeProjectId,
           let currentProject = filteredProjects.first(where: { $0.id == activeProjectId }) {
            rows.append(.sectionHeader(title: "Current"))
            rows.append(
                .project(
                    project: currentProject,
                    isCurrent: true,
                    isOpen: openIds.contains(currentProject.id)
                )
            )
        }

        let recentProjects = filteredProjects.filter { $0.id != activeProjectId }
        if !recentProjects.isEmpty {
            rows.append(.sectionHeader(title: "Recent"))
            for project in recentProjects {
                rows.append(
                    .project(
                        project: project,
                        isCurrent: false,
                        isOpen: openIds.contains(project.id)
                    )
                )
            }
        }

        if rows.isEmpty {
            let message = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "No projects available"
                : "No matching projects"
            rows = [.emptyState(message: message)]
        }

        return rows
    }

    /// Returns the row index for a stable selection key.
    static func rowIndex(forSelectionKey selectionKey: String, in rows: [SwitcherListRow]) -> Int? {
        rows.firstIndex(where: { $0.selectionKey == selectionKey && $0.isSelectable })
    }

    /// Returns the default selection index for open/filter states.
    static func defaultSelectionIndex(in rows: [SwitcherListRow], preferCurrentProject: Bool) -> Int? {
        if preferCurrentProject,
           let currentProjectIndex = rows.firstIndex(where: {
               if case .project(_, let isCurrent, _) = $0 {
                   return isCurrent
               }
               return false
           }) {
            return currentProjectIndex
        }

        if let firstProjectIndex = rows.firstIndex(where: {
            if case .project = $0 {
                return true
            }
            return false
        }) {
            return firstProjectIndex
        }

        return rows.firstIndex(where: { $0.isSelectable })
    }
}

/// Cached config data used for switcher warm-open performance.
struct SwitcherConfigSnapshot {
    let projects: [ProjectConfig]
    let warningTitle: String?
    let errorMessage: String?
}

// MARK: - Controller

/// Controls the switcher panel lifecycle and keyboard-driven UX.
final class SwitcherPanelController: NSObject {
    static let signposter = OSSignposter(
        subsystem: "com.projectswitcher.ProjectSwitcher",
        category: "SwitcherPerformance"
    )

    let logger: ProjectSwitcherLogging
    let session: SwitcherSession
    let projectManager: ProjectManager
    let dataPaths: DataPaths

    let panel: SwitcherPanel
    let titleLabel: NSTextField
    let searchField: NSSearchField
    let tableView: NSTableView
    let scrollView: NSScrollView
    let statusLabel: NSTextField
    let keybindHintLabel: NSTextField
    var visualEffectView: NSVisualEffectView?

    var allProjects: [ProjectConfig] = []
    var filteredProjects: [ProjectConfig] = []
    var rows: [SwitcherListRow] = []
    var activeProjectId: String?
    var openIds: Set<String> = []
    var keyEventMonitor: Any?
    var configErrorMessage: String?
    var cachedConfigFingerprint: SwitcherConfigFingerprint?
    var cachedConfigSnapshot: SwitcherConfigSnapshot?
    var lastFilterQuery: String = ""
    var lastStatusMessage: String?
    var lastStatusLevel: StatusLevel?
    var pendingFilterWorkItem: DispatchWorkItem?
    var filterDebounceTokens = DebounceTokenSource()
    var expectsVisible: Bool = false
    var pendingVisibilityCheckToken: UUID?
    var previouslyActiveApp: NSRunningApplication?
    var suppressedActionEventNumber: Int?
    var isDismissing: Bool = false
    var restoreFocusTask: Task<Void, Never>?
    var lastSelectedRowIndex: Int = -1
    let operationCoordinator: SwitcherOperationCoordinator
    let workspaceRetryCoordinator: SwitcherWorkspaceRetryCoordinator

    /// The captured focus state before the switcher opened.
    /// Used for restore-on-cancel via ProjectManager.
    var capturedFocus: CapturedFocus?

    /// Called when a project operation fails (select, close, exit, workspace query, config load).
    /// Used by AppDelegate to trigger a background health indicator refresh.
    var onProjectOperationFailed: ((ErrorContext) -> Void)?

    /// Called when the user triggers "Recover Project" from the switcher keybind.
    ///
    /// Parameters:
    /// - focus: Focus captured before the switcher opened.
    /// - completion: Invoked when recovery completes.
    var onRecoverProjectRequested: ((CapturedFocus, @escaping (Result<RecoveryResult, PsCoreError>) -> Void) -> Void)? {
        get { operationCoordinator.onRecoverProjectRequested }
        set { operationCoordinator.onRecoverProjectRequested = newValue }
    }

    /// Called when the switcher session ends (panel dismissed for any reason).
    /// Used to defer background work (like Doctor refresh) until after the session
    /// to avoid concurrent AeroSpace CLI calls.
    var onSessionEnded: (() -> Void)?

    /// Creates a switcher panel controller.
    /// - Parameters:
    ///   - logger: Logger used for switcher diagnostics.
    ///   - projectManager: Project manager for config, sorting, and focus operations.
    init(
        logger: ProjectSwitcherLogging = ProjectSwitcherLogger(),
        projectManager: ProjectManager = ProjectManager(),
        dataPaths: DataPaths = .default()
    ) {
        self.logger = logger
        self.session = SwitcherSession(logger: logger)
        self.projectManager = projectManager
        self.dataPaths = dataPaths

        self.panel = SwitcherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SwitcherLayout.panelWidth,
                height: SwitcherLayout.initialPanelHeight
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.titleLabel = NSTextField(labelWithString: "Project Switcher")
        self.searchField = NSSearchField()
        self.tableView = NSTableView()
        self.scrollView = NSScrollView()
        self.statusLabel = NSTextField(labelWithString: "")
        self.keybindHintLabel = NSTextField(labelWithString: "")

        self.operationCoordinator = SwitcherOperationCoordinator(
            projectManager: projectManager,
            session: session
        )
        self.workspaceRetryCoordinator = SwitcherWorkspaceRetryCoordinator(
            projectManager: projectManager,
            session: session
        )

        super.init()

        wireOperationCoordinator()
        wireWorkspaceRetryCoordinator()
        configurePanel()
        configureTitleLabel()
        configureSearchField()
        configureTableView()
        configureStatusLabel()
        configureKeybindHints()
        layoutContent()
    }

    /// Wires operation coordinator callbacks to controller methods.
    private func wireOperationCoordinator() {
        operationCoordinator.onSetControlsEnabled = { [weak self] enabled in
            guard let self else { return }
            self.searchField.isEnabled = enabled
            self.tableView.isEnabled = enabled
        }
        operationCoordinator.onSetStatus = { [weak self] message, level in
            self?.setStatus(message: message, level: level)
        }
        operationCoordinator.onDismiss = { [weak self] reason in
            self?.dismiss(reason: reason)
        }
        operationCoordinator.onFocusIdeWindow = { [weak self] windowId in
            self?.focusIdeWindow(windowId: windowId)
        }
        operationCoordinator.onRefreshWorkspaceAndFilter = { [weak self] selectionKey, useDefault in
            guard let self else { return }
            self.refreshWorkspaceState()
            self.applyFilter(
                query: self.searchField.stringValue,
                preferredSelectionKey: selectionKey ?? self.selectedRowKey(),
                useDefaultSelection: useDefault
            )
        }
        operationCoordinator.onOperationFailed = { [weak self] context in
            self?.onProjectOperationFailed?(context)
        }
        operationCoordinator.onRestoreSearchFieldFocus = { [weak self] in
            self?.restoreSearchFieldInputFocus()
        }
        operationCoordinator.onUpdateCapturedFocus = { [weak self] focus in
            guard let self else { return }
            self.capturedFocus = focus
            self.previouslyActiveApp = focus != nil ? NSWorkspace.shared.frontmostApplication : nil
        }
    }

    /// Wires workspace retry coordinator callbacks to controller methods.
    private func wireWorkspaceRetryCoordinator() {
        workspaceRetryCoordinator.onRetrySucceeded = { [weak self] state in
            guard let self else { return }
            let didChange = self.applyWorkspaceState(state)
            self.clearStatus()
            if didChange {
                self.applyFilter(
                    query: self.searchField.stringValue,
                    preferredSelectionKey: self.selectedRowKey(),
                    useDefaultSelection: false
                )
            }
        }
        workspaceRetryCoordinator.onRetryExhausted = { [weak self] error in
            guard let self else { return }
            self.setStatus(
                message: "Workspace state unavailable: \(error.userFacingMessage)",
                level: .warning
            )
        }
    }

    deinit {
        removeKeyEventMonitor()
        cancelPendingFilterWorkItem()
        restoreFocusTask?.cancel()
        workspaceRetryCoordinator.cancelRetryForTeardown()
    }

}
