import Foundation

/// Canonical workspace naming and routing conventions for ProjectSwitcher.
///
/// All workspace identity decisions — prefix, project detection, non-project
/// fallback — go through this utility to maintain a single source of truth.
/// Consumers should reference these constants and helpers rather than
/// duplicating workspace naming logic.
public enum WorkspaceRouting {
    /// Prefix for all ProjectSwitcher project workspaces (e.g., `"ps-myproject"`).
    public static let projectPrefix = "ps-"

    /// Default non-project workspace when dynamic discovery yields no candidate.
    public static let fallbackWorkspace = "1"

    /// Returns `true` if the workspace belongs to a ProjectSwitcher project.
    /// - Parameter name: AeroSpace workspace name.
    public static func isProjectWorkspace(_ name: String) -> Bool {
        name.hasPrefix(projectPrefix)
    }

    /// Extracts the project ID from a `ps-<projectId>` workspace name.
    /// Returns `nil` for non-project workspaces or empty project IDs.
    /// - Parameter name: AeroSpace workspace name.
    public static func projectId(fromWorkspace name: String) -> String? {
        guard isProjectWorkspace(name) else { return nil }
        let id = String(name.dropFirst(projectPrefix.count))
        return id.isEmpty ? nil : id
    }

    /// Returns the workspace name for a given project ID.
    /// - Parameter id: Project identifier.
    public static func workspaceName(forProjectId id: String) -> String {
        "\(projectPrefix)\(id)"
    }

    /// Selects the best non-project workspace from a list of candidates.
    ///
    /// Strategy (in priority order):
    /// 1. First non-project workspace that has windows (via `hasWindows` predicate).
    /// 2. First non-project workspace without windows.
    /// 3. ``fallbackWorkspace`` if no non-project workspace exists.
    ///
    /// - Parameters:
    ///   - workspaces: Available workspace names.
    ///   - hasWindows: Predicate returning `true` if the workspace has at least one window.
    /// - Returns: The selected non-project workspace name.
    public static func preferredNonProjectWorkspace(
        from workspaces: [String],
        hasWindows: (String) -> Bool
    ) -> String {
        let nonProject = workspaces.filter { !isProjectWorkspace($0) }
        if let withWindows = nonProject.first(where: { hasWindows($0) }) {
            return withWindows
        }
        if let any = nonProject.first {
            return any
        }
        return fallbackWorkspace
    }
}
