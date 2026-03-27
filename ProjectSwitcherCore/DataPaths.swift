import Foundation

/// Canonical filesystem paths for ProjectSwitcher.
///
/// Provides path resolution for config, state, and logs. Does not perform I/O.
public struct DataPaths: Sendable {
    /// User home directory used as the root for derived paths.
    let homeDirectory: URL

    /// Creates a DataPaths rooted at the provided home directory.
    /// - Parameter homeDirectory: Home directory as a file URL.
    init(homeDirectory: URL) {
        precondition(homeDirectory.isFileURL, "homeDirectory must be a file URL")
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    /// Creates a DataPaths rooted at the current user's home directory.
    /// - Parameter fileManager: File manager used to resolve the home directory.
    /// - Returns: A `DataPaths` instance rooted at the user's home directory.
    public static func `default`(fileManager: FileManager = .default) -> DataPaths {
        DataPaths(homeDirectory: fileManager.homeDirectoryForCurrentUser)
    }

    // MARK: - Config paths

    /// Returns `~/.config/project-switcher/config.toml`.
    public var configFile: URL {
        configDirectory.appendingPathComponent("config.toml", isDirectory: false)
    }

    // MARK: - State paths

    /// Returns `~/.local/state/project-switcher/state.json`.
    var stateFile: URL {
        stateDirectory.appendingPathComponent("state.json", isDirectory: false)
    }

    /// Returns `~/.local/state/project-switcher/recent-projects.json`.
    var recentProjectsFile: URL {
        stateDirectory.appendingPathComponent("recent-projects.json", isDirectory: false)
    }

    /// Returns `~/.local/state/project-switcher/window-layouts.json`.
    var windowLayoutsFile: URL {
        stateDirectory.appendingPathComponent("window-layouts.json", isDirectory: false)
    }

    /// Returns `~/.local/state/project-switcher/chrome-tabs/`.
    var chromeTabsDirectory: URL {
        stateDirectory.appendingPathComponent("chrome-tabs", isDirectory: true)
    }

    /// Returns `~/.local/state/project-switcher/chrome-tabs/<projectId>.json`.
    /// - Parameter projectId: Project identifier used to name the snapshot file.
    /// - Returns: URL for the project's Chrome tab snapshot file.
    func chromeTabsFile(projectId: String) -> URL {
        chromeTabsDirectory.appendingPathComponent("\(projectId).json", isDirectory: false)
    }

    // MARK: - Log paths

    /// Returns `~/.local/state/project-switcher/logs`.
    var logsDirectory: URL {
        stateDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    /// Returns `~/.local/state/project-switcher/logs/project-switcher.log`.
    public var primaryLogFile: URL {
        logsDirectory.appendingPathComponent("project-switcher.log", isDirectory: false)
    }

    /// Returns `~/.local/state/project-switcher/logs/project-switcher.log.lock`.
    var logLockFile: URL {
        logsDirectory.appendingPathComponent("project-switcher.log.lock", isDirectory: false)
    }

    // MARK: - VS Code paths

    /// Returns `~/.vscode/extensions/`.
    var vscodeExtensionsDirectory: URL {
        homeDirectory
            .appendingPathComponent(".vscode", isDirectory: true)
            .appendingPathComponent("extensions", isDirectory: true)
    }

    // MARK: - Private

    private var configDirectory: URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("project-switcher", isDirectory: true)
    }

    private var stateDirectory: URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("project-switcher", isDirectory: true)
    }
}
