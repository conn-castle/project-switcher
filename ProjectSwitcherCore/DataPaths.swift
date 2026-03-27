import Foundation

/// Canonical filesystem paths for ProjectSwitcher.
///
/// Provides path resolution for config, state, and logs.
public struct DataPaths: Sendable {
    private static let currentDirectoryName = "project-switcher"
    private static let legacyDirectoryName = "agent-panel"
    private static let currentLogFileName = "project-switcher.log"
    private static let currentLogLockFileName = "project-switcher.log.lock"
    private static let legacyLogFileName = "agent-panel.log"
    private static let legacyLogLockFileName = "agent-panel.log.lock"

    /// User home directory used as the root for derived paths.
    let homeDirectory: URL
    private let resolvedConfigDirectory: URL
    private let resolvedStateDirectory: URL
    private let resolvedPrimaryLogFileName: String
    private let resolvedLogLockFileName: String

    /// Creates a DataPaths rooted at the provided home directory.
    /// - Parameter homeDirectory: Home directory as a file URL.
    init(homeDirectory: URL) {
        let standardizedHome = homeDirectory.standardizedFileURL
        self.init(
            homeDirectory: standardizedHome,
            configDirectory: Self.currentConfigDirectory(homeDirectory: standardizedHome),
            stateDirectory: Self.currentStateDirectory(homeDirectory: standardizedHome),
            primaryLogFileName: Self.currentLogFileName,
            logLockFileName: Self.currentLogLockFileName
        )
    }

    /// Creates a DataPaths rooted at the current user's home directory.
    /// Prefers legacy `agent-panel` paths when they still hold the user's real data and
    /// the renamed `project-switcher` paths are absent or only contain fresh-install artifacts.
    ///
    /// - Parameter fileManager: File manager used to resolve the home directory and probe legacy files.
    /// - Returns: A `DataPaths` instance rooted at the user's home directory.
    public static func `default`(fileManager: FileManager = .default) -> DataPaths {
        `default`(homeDirectory: fileManager.homeDirectoryForCurrentUser, fileManager: fileManager)
    }

    static func `default`(homeDirectory: URL, fileManager: FileManager = .default) -> DataPaths {
        let standardizedHome = homeDirectory.standardizedFileURL
        let useLegacyConfig = shouldUseLegacyConfigDirectory(homeDirectory: standardizedHome, fileManager: fileManager)
        let useLegacyState = shouldUseLegacyStateDirectory(homeDirectory: standardizedHome, fileManager: fileManager)

        return DataPaths(
            homeDirectory: standardizedHome,
            configDirectory: useLegacyConfig
                ? legacyConfigDirectory(homeDirectory: standardizedHome)
                : currentConfigDirectory(homeDirectory: standardizedHome),
            stateDirectory: useLegacyState
                ? legacyStateDirectory(homeDirectory: standardizedHome)
                : currentStateDirectory(homeDirectory: standardizedHome),
            primaryLogFileName: useLegacyState ? legacyLogFileName : currentLogFileName,
            logLockFileName: useLegacyState ? legacyLogLockFileName : currentLogLockFileName
        )
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
        logsDirectory.appendingPathComponent(resolvedPrimaryLogFileName, isDirectory: false)
    }

    /// Returns `~/.local/state/project-switcher/logs/project-switcher.log.lock`.
    var logLockFile: URL {
        logsDirectory.appendingPathComponent(resolvedLogLockFileName, isDirectory: false)
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
        resolvedConfigDirectory
    }

    private var stateDirectory: URL {
        resolvedStateDirectory
    }

    private init(
        homeDirectory: URL,
        configDirectory: URL,
        stateDirectory: URL,
        primaryLogFileName: String,
        logLockFileName: String
    ) {
        precondition(homeDirectory.isFileURL, "homeDirectory must be a file URL")
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.resolvedConfigDirectory = configDirectory
        self.resolvedStateDirectory = stateDirectory
        self.resolvedPrimaryLogFileName = primaryLogFileName
        self.resolvedLogLockFileName = logLockFileName
    }

    private static func currentConfigDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(currentDirectoryName, isDirectory: true)
    }

    private static func legacyConfigDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)
    }

    private static func currentStateDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent(currentDirectoryName, isDirectory: true)
    }

    private static func legacyStateDirectory(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)
    }

    private static func shouldUseLegacyConfigDirectory(homeDirectory: URL, fileManager: FileManager) -> Bool {
        let legacyConfigFile = legacyConfigDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("config.toml", isDirectory: false)
        guard fileManager.fileExists(atPath: legacyConfigFile.path) else {
            return false
        }

        let currentConfigFile = currentConfigDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent("config.toml", isDirectory: false)
        guard fileManager.fileExists(atPath: currentConfigFile.path) else {
            return true
        }

        guard let currentConfigData = try? Data(contentsOf: currentConfigFile),
              let currentConfig = String(data: currentConfigData, encoding: .utf8) else {
            return false
        }
        return currentConfig == ConfigLoader.starterConfigTemplate
    }

    private static func shouldUseLegacyStateDirectory(homeDirectory: URL, fileManager: FileManager) -> Bool {
        let legacyState = legacyStateDirectory(homeDirectory: homeDirectory)
        guard directoryExists(at: legacyState, fileManager: fileManager) else {
            return false
        }

        let currentState = currentStateDirectory(homeDirectory: homeDirectory)
        guard directoryExists(at: currentState, fileManager: fileManager) else {
            return true
        }

        return !hasStatePayload(in: currentState, fileManager: fileManager)
            && hasStatePayload(in: legacyState, fileManager: fileManager)
    }

    private static func directoryExists(at url: URL, fileManager: FileManager) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func hasStatePayload(in directory: URL, fileManager: FileManager) -> Bool {
        let payloadFiles = [
            "state.json",
            "recent-projects.json",
            "window-layouts.json"
        ]
        if payloadFiles.contains(where: {
            fileManager.fileExists(atPath: directory.appendingPathComponent($0, isDirectory: false).path)
        }) {
            return true
        }

        let chromeTabsDirectory = directory.appendingPathComponent("chrome-tabs", isDirectory: true)
        return directoryExists(at: chromeTabsDirectory, fileManager: fileManager)
    }
}
