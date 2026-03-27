import Foundation
// MARK: - ProjectError

/// Errors that can occur during project operations.
public enum ProjectError: Error, Equatable, Sendable {
    /// Project ID not found in config.
    case projectNotFound(projectId: String)

    /// Config has not been loaded yet.
    case configNotLoaded

    /// AeroSpace operation failed.
    case aeroSpaceError(detail: String)

    /// IDE failed to launch or appear.
    case ideLaunchFailed(detail: String)

    /// Chrome failed to launch or appear.
    case chromeLaunchFailed(detail: String)

    /// No project is currently active (for exit operation).
    case noActiveProject

    /// No recent non-project window to return to.
    case noPreviousWindow

    /// Expected window not found after setup.
    case windowNotFound(detail: String)

    /// Focus could not be stabilized on the IDE window.
    case focusUnstable(detail: String)

    /// User-friendly error message for display in the UI.
    public var userFacingMessage: String {
        switch self {
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .configNotLoaded:
            return "Config not loaded"
        case .aeroSpaceError(let detail):
            return "AeroSpace error: \(detail)"
        case .ideLaunchFailed(let detail):
            return "IDE launch failed: \(detail)"
        case .chromeLaunchFailed(let detail):
            return "Chrome launch failed: \(detail)"
        case .noActiveProject:
            return "No active project"
        case .noPreviousWindow:
            return "No recent non-project window"
        case .windowNotFound(let detail):
            return "Window not found: \(detail)"
        case .focusUnstable(let detail):
            return "Focus unstable: \(detail)"
        }
    }
}

/// Snapshot of ProjectSwitcher workspace state from a single AeroSpace query.
public struct ProjectWorkspaceState: Equatable, Sendable {
    /// The currently focused ProjectSwitcher project ID, if any.
    public let activeProjectId: String?

    /// Set of ProjectSwitcher project IDs with open workspaces.
    public let openProjectIds: Set<String>

    /// Creates a workspace state snapshot.
    /// - Parameters:
    ///   - activeProjectId: Focused ProjectSwitcher project ID, if present.
    ///   - openProjectIds: Open ProjectSwitcher project workspace IDs.
    public init(activeProjectId: String?, openProjectIds: Set<String>) {
        self.activeProjectId = activeProjectId
        self.openProjectIds = openProjectIds
    }
}

/// Success result from project activation.
public struct ProjectActivationSuccess: Equatable, Sendable {
    /// AeroSpace window ID for the IDE window (used for post-dismissal focusing).
    public let ideWindowId: Int
    /// Warning message if tab restore failed (non-fatal).
    public let tabRestoreWarning: String?
    /// Warning message if window positioning failed (non-fatal).
    public let layoutWarning: String?

    /// Creates a new activation success result.
    /// - Parameters:
    ///   - ideWindowId: AeroSpace window ID for the IDE window.
    ///   - tabRestoreWarning: Optional non-fatal warning if tab restore failed.
    ///   - layoutWarning: Optional non-fatal warning if window positioning failed.
    public init(ideWindowId: Int, tabRestoreWarning: String?, layoutWarning: String? = nil) {
        self.ideWindowId = ideWindowId
        self.tabRestoreWarning = tabRestoreWarning
        self.layoutWarning = layoutWarning
    }
}

/// Success result from project close.
public struct ProjectCloseSuccess: Equatable, Sendable {
    /// Warning message if tab capture failed (non-fatal).
    public let tabCaptureWarning: String?

    /// Creates a new close success result.
    /// - Parameter tabCaptureWarning: Optional non-fatal warning if tab capture failed.
    public init(tabCaptureWarning: String?) {
        self.tabCaptureWarning = tabCaptureWarning
    }
}

// Note: CapturedFocus and internal protocols (AeroSpaceProviding,
// IdeLauncherProviding, ChromeLauncherProviding) are defined in Dependencies.swift

// MARK: - FocusStack

/// LIFO stack of non-project focus entries for "exit project space" restoration.
///
/// Only non-project windows should be pushed (the caller is responsible for filtering).
/// Persisted by ProjectManager so CLI + app share focus history across restarts.
struct FocusStack {
    private var entries: [FocusHistoryEntry] = []
    private let maxSize: Int

    init(maxSize: Int = 20) {
        self.maxSize = maxSize
    }

    init(entries: [FocusHistoryEntry], maxSize: Int = 20) {
        self.maxSize = maxSize
        if entries.count > maxSize {
            self.entries = Array(entries.suffix(maxSize))
        } else {
            self.entries = entries
        }
    }

    /// Pushes a focus entry onto the stack.
    ///
    /// Deduplicates: if the top entry already matches this windowId, the push is skipped.
    /// Enforces maxSize by dropping the oldest (first) entry when full.
    mutating func push(_ focus: FocusHistoryEntry) {
        // Deduplicate consecutive pushes of the same window
        if let top = entries.last, top.windowId == focus.windowId {
            return
        }
        entries.append(focus)
        // Enforce max size — drop oldest
        if entries.count > maxSize {
            entries.removeFirst(entries.count - maxSize)
        }
    }

    /// Pops entries from the top until one passes the validity check.
    ///
    /// Invalid entries (stale windows) are discarded. Returns nil if the stack
    /// is exhausted without finding a valid entry.
    mutating func popFirstValid(isValid: (FocusHistoryEntry) -> Bool) -> FocusHistoryEntry? {
        while let entry = entries.popLast() {
            if isValid(entry) {
                return entry
            }
            // Entry invalid (window gone), discard and try next
        }
        return nil
    }

    /// Pops the most recent entry (LIFO).
    mutating func pop() -> FocusHistoryEntry? {
        entries.popLast()
    }

    /// Removes any entries that match the provided window ID.
    mutating func remove(windowId: Int) {
        entries.removeAll { $0.windowId == windowId }
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    func snapshot() -> [FocusHistoryEntry] {
        entries
    }
}

