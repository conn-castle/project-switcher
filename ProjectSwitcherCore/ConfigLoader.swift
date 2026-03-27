import Foundation

// MARK: - Config Loading

/// Kind of config loading error for programmatic handling.
enum ConfigErrorKind: String, Equatable, Sendable {
    /// Config file does not exist (starter config was created).
    case fileNotFound
    /// Failed to create starter config file.
    case createFailed
    /// Failed to read existing config file.
    case readFailed
}

/// Errors emitted by config loading operations.
struct ConfigError: Error, Equatable {
    let kind: ConfigErrorKind
    let message: String

    init(kind: ConfigErrorKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// Result of loading and parsing configuration.
struct ConfigLoadResult: Equatable, Sendable {
    /// Parsed config when successful.
    let config: Config?
    /// Findings from parsing (warnings and errors).
    let findings: [ConfigFinding]
    /// Parsed projects (may be partial on error).
    let projects: [ProjectConfig]
    /// True if the TOML could not be parsed (syntax error vs validation error).
    let hasParseError: Bool

    init(
        config: Config?,
        findings: [ConfigFinding],
        projects: [ProjectConfig] = [],
        hasParseError: Bool = false
    ) {
        self.config = config
        self.findings = findings
        self.projects = projects
        self.hasParseError = hasParseError
    }
}

/// Severity level for config findings.
public enum ConfigFindingSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"
}

/// A single finding from config parsing.
public struct ConfigFinding: Equatable, Sendable {
    public let severity: ConfigFindingSeverity
    public let title: String
    let detail: String?
    let fix: String?

    init(severity: ConfigFindingSeverity, title: String, detail: String? = nil, fix: String? = nil) {
        self.severity = severity
        self.title = title
        self.detail = detail
        self.fix = fix
    }
}

/// Loads and parses the ProjectSwitcher configuration file.
struct ConfigLoader {
    private static let starterConfigTemplate = """
# ProjectSwitcher configuration
#
# [app] (optional) — Application settings
# - autoStartAtLogin: launch ProjectSwitcher when you log in (default: false)
#
# [agentLayer] (optional) — Global Agent Layer settings
# - enabled: default useAgentLayer value for all projects (default: false)
#
# [chrome] (optional) — Global Chrome tab settings
# - pinnedTabs: URLs always opened as leftmost tabs in every fresh Chrome window
# - defaultTabs: URLs opened when no tab history exists for a project
# - openGitRemote: auto-detect git remote URL and add it as an always-open tab (default: false)
#
# [layout] (optional) — Window positioning settings (requires Accessibility permission)
# - smallScreenThreshold: physical monitor width in inches below which "small mode" is used (default: 24)
# - windowHeight: window height as % of screen height, 1–100 (default: 90)
# - maxWindowWidth: max window width in inches (default: 18)
# - idePosition: IDE window side, "left" or "right" (default: "left")
# - justification: which screen edge windows align to, "left" or "right" (default: "right")
# - maxGap: max gap between windows as % of screen width, 0–100 (default: 10)
#
# Each [[project]] entry describes one git repo (local or SSH remote).
# - name: Display name (id is derived by lowercasing and replacing non [a-z0-9] with '-')
# - remote: (optional) VS Code SSH remote authority (e.g., ssh-remote+user@host)
# - path: Absolute path to the repo (local when remote is absent, remote path when remote is set)
# - color: "#RRGGBB" or a named color (\(ProjectColorPalette.sortedNames.joined(separator: ", ")))
# - useAgentLayer: (optional) override the global agentLayer.enabled default per project
# - chromePinnedTabs: (optional) per-project URLs always opened as leftmost tabs
# - chromeDefaultTabs: (optional) per-project URLs opened when no tab history exists
#
# Example:
#
# [app]
# autoStartAtLogin = true
#
# [agentLayer]
# enabled = true
#
# [chrome]
# pinnedTabs = ["https://dashboard.example.com"]
# defaultTabs = ["https://docs.example.com"]
# openGitRemote = true
#
# [layout]
# smallScreenThreshold = 24
# windowHeight = 90
# maxWindowWidth = 18
# idePosition = "left"
# justification = "right"
# maxGap = 10
#
# [[project]]
# name = "ProjectSwitcher"
# path = "/Users/you/src/project-switcher"
# color = "indigo"
# useAgentLayer = false
# chromePinnedTabs = ["https://api.example.com"]
# chromeDefaultTabs = ["https://jira.example.com"]
#
# [[project]]
# name = "Remote ML"
# remote = "ssh-remote+nconn@my-remote-host.local"
# path = "/Users/nconn/Documents/git-repos/local-ml"
# color = "teal"
# useAgentLayer = false
"""

    /// Loads and parses the default config file.
    static func loadDefault() -> Result<ConfigLoadResult, ConfigError> {
        loadDefault(dataStore: DataPaths.default())
    }

    /// Loads and parses the default config file using the provided data store.
    static func loadDefault(dataStore: DataPaths) -> Result<ConfigLoadResult, ConfigError> {
        load(from: dataStore.configFile)
    }

    /// Loads and parses a config file at the given URL.
    static func load(from url: URL, fileSystem: FileSystem = DefaultFileSystem()) -> Result<ConfigLoadResult, ConfigError> {
        let path = url.path
        if !fileSystem.fileExists(at: url) {
            do {
                try createStarterConfig(at: url, fileSystem: fileSystem)
            } catch {
                return .failure(ConfigError(
                    kind: .createFailed,
                    message: "Failed to create config at \(path): \(error.localizedDescription)"
                ))
            }
            return .failure(ConfigError(
                kind: .fileNotFound,
                message: "Config file not found. Created a starter config at \(path). Edit it to add projects."
            ))
        }

        let raw: String
        do {
            let data = try fileSystem.readFile(at: url)
            guard let decoded = String(data: data, encoding: .utf8) else {
                return .failure(ConfigError(
                    kind: .readFailed,
                    message: "Failed to read config at \(path): file is not valid UTF-8."
                ))
            }
            raw = decoded
        } catch {
            return .failure(ConfigError(
                kind: .readFailed,
                message: "Failed to read config at \(path): \(error.localizedDescription)"
            ))
        }

        return .success(ConfigParser.parse(toml: raw))
    }

    /// Writes a starter config template at the provided location.
    private static func createStarterConfig(at url: URL, fileSystem: FileSystem) throws {
        let directory = url.deletingLastPathComponent()
        try fileSystem.createDirectory(at: directory)
        guard let data = starterConfigTemplate.data(using: .utf8) else {
            throw NSError(domain: "ConfigLoader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode starter config as UTF-8"])
        }
        try fileSystem.writeFile(at: url, data: data)
    }
}
