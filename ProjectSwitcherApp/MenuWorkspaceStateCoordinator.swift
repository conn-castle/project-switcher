import AppKit
import Foundation

import ProjectSwitcherCore

/// Coordinates cached workspace state and focus capture for non-blocking menu population.
///
/// Owns `cachedWorkspaceState` and `menuFocusCapture` so that AppDelegate accesses
/// workspace/focus mutable state only through this coordinator's API.
/// Background refreshes run off the main thread; cached values are read on the main thread
/// by `menuNeedsUpdate`.
final class MenuWorkspaceStateCoordinator {

    /// Cached workspace state for non-blocking menu population.
    /// Updated by background refreshes; read by `menuNeedsUpdate`.
    private(set) var cachedWorkspaceState: ProjectWorkspaceState?

    /// Captured AeroSpace focus for menu actions (recover, move window, etc.).
    /// Updated by background refreshes and explicit captures.
    private(set) var menuFocusCapture: CapturedFocus?

    /// Generation counter for focus capture. Incremented on explicit `updateFocusCapture()`
    /// calls so that stale background refresh callbacks do not overwrite explicit values.
    private var focusCaptureGeneration: UInt64 = 0

    private let projectManager: ProjectManager

    // MARK: - Init

    /// - Parameters:
    ///   - projectManager: Project manager for workspace state and focus capture.
    init(
        projectManager: ProjectManager
    ) {
        self.projectManager = projectManager
    }

    // MARK: - Focus capture

    /// Updates the cached focus capture with a new value.
    ///
    /// Passing `nil` clears stale focus so menu actions are disabled until
    /// fresh focus data is captured.
    ///
    /// - Parameter focus: Newly captured focus or `nil`.
    func updateFocusCapture(_ focus: CapturedFocus?) {
        precondition(Thread.isMainThread, "updateFocusCapture(_:) must be called on the main thread.")
        focusCaptureGeneration &+= 1
        menuFocusCapture = focus
    }

    // MARK: - Background refresh

    /// Refreshes cached workspace state and focus in the background.
    ///
    /// Called after Doctor refreshes, switcher session ends, and on menu open.
    /// The cached values are used by `menuNeedsUpdate` to avoid blocking the
    /// main thread with AeroSpace CLI calls.
    ///
    /// Thread safety: `captureCurrentFocus()` and `workspaceState()` are safe off-main
    /// and use ProjectManager's internal serialization (focus capture may persist history).
    func refreshInBackground() {
        precondition(Thread.isMainThread, "refreshInBackground() must be called on the main thread.")
        let expectedGeneration = focusCaptureGeneration
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let focus = self.projectManager.captureCurrentFocus()
            let state = try? self.projectManager.workspaceState().get()
            DispatchQueue.main.async {
                self.cachedWorkspaceState = state
                // Only update focus if no explicit updateFocusCapture() call occurred
                // since the refresh started. This prevents stale background data from
                // overwriting a value that was explicitly set.
                if self.focusCaptureGeneration == expectedGeneration {
                    self.menuFocusCapture = focus
                }
            }
        }
    }

    // MARK: - Submenu population

    /// Populates the "Move Current Window" submenu from cached workspace state.
    ///
    /// - Parameters:
    ///   - submenu: The submenu to populate (cleared and rebuilt).
    ///   - addWindowTarget: The target for "Move to project" menu item actions.
    ///   - addWindowAction: The selector for "Move to project" menu item actions.
    ///   - removeWindowTarget: The target for "No Project" menu item action.
    ///   - removeWindowAction: The selector for "No Project" menu item action.
    /// - Returns: Whether the submenu should be visible (has open projects or window is in a project workspace).
    func populateMoveWindowSubmenu(
        _ submenu: NSMenu,
        addWindowTarget: AnyObject,
        addWindowAction: Selector,
        removeWindowTarget: AnyObject,
        removeWindowAction: Selector
    ) -> Bool {
        submenu.removeAllItems()

        let currentWorkspace = menuFocusCapture?.workspace
        let inProjectWorkspaceForMove = currentWorkspace?.hasPrefix(ProjectManager.workspacePrefix) ?? false

        var hasOpenProjects = false
        if let state = cachedWorkspaceState {
            let openProjects = projectManager.projects.filter { state.openProjectIds.contains($0.id) }
            if !openProjects.isEmpty {
                hasOpenProjects = true
                for project in openProjects {
                    let item = NSMenuItem(
                        title: project.name,
                        action: addWindowAction,
                        keyEquivalent: ""
                    )
                    item.target = addWindowTarget
                    item.representedObject = project.id
                    if currentWorkspace == ProjectManager.workspacePrefix + project.id {
                        item.state = .on
                    }
                    submenu.addItem(item)
                }
            }
        }

        // Separator + "No Project" option
        if hasOpenProjects {
            submenu.addItem(.separator())
        }
        let noProjectItem = NSMenuItem(
            title: "No Project",
            action: removeWindowAction,
            keyEquivalent: ""
        )
        noProjectItem.target = removeWindowTarget
        if !inProjectWorkspaceForMove {
            noProjectItem.state = .on
        }
        submenu.addItem(noProjectItem)

        return hasOpenProjects || inProjectWorkspaceForMove
    }
}
