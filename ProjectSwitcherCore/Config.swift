import Foundation

// MARK: - ID Normalization

/// Normalizes identifiers (project names, workspace names) to a consistent format.
///
/// Used for deriving project IDs from names and normalizing workspace names.
/// Rules: lowercase, non-alphanumeric characters become hyphens, consecutive hyphens collapsed, trimmed.
enum IdNormalizer {
    /// Allowed characters in a normalized ID.
    private static let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")

    /// Normalizes a string to a valid identifier.
    /// - Parameter value: Raw string (e.g., project name, workspace name).
    /// - Returns: Normalized identifier (lowercase, hyphens for separators, no leading/trailing hyphens).
    static func normalize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalized = ""
        var previousWasHyphen = false

        for scalar in trimmed.lowercased().unicodeScalars {
            if allowedCharacters.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                normalized.append("-")
                previousWasHyphen = true
            }
        }

        let hyphenSet = CharacterSet(charactersIn: "-")
        return normalized.trimmingCharacters(in: hyphenSet)
    }

    /// Checks if an identifier is valid (non-empty after normalization).
    /// - Parameter value: String to check.
    /// - Returns: True if the string normalizes to a non-empty identifier.
    static func isValid(_ value: String) -> Bool {
        !normalize(value).isEmpty
    }

    /// Reserved identifiers that cannot be used.
    static let reserved: Set<String> = ["inbox"]

    /// Checks if an identifier is reserved.
    /// - Parameter normalizedId: Already-normalized identifier.
    /// - Returns: True if the identifier is reserved.
    static func isReserved(_ normalizedId: String) -> Bool {
        reserved.contains(normalizedId)
    }
}

// MARK: - Config Models

/// Global Chrome tab configuration.
public struct ChromeConfig: Equatable, Sendable {
    /// URLs always opened as leftmost tabs on every fresh Chrome window creation.
    public let pinnedTabs: [String]
    /// URLs opened when no tab history exists for a project.
    public let defaultTabs: [String]
    /// When true, auto-detect git remote URL and add it as an always-open tab.
    public let openGitRemote: Bool

    init(pinnedTabs: [String] = [], defaultTabs: [String] = [], openGitRemote: Bool = false) {
        self.pinnedTabs = pinnedTabs
        self.defaultTabs = defaultTabs
        self.openGitRemote = openGitRemote
    }
}

/// Application-level configuration.
public struct AppConfig: Equatable, Sendable {
    /// When true, register as a login item via SMAppService on startup.
    public let autoStartAtLogin: Bool

    public init(autoStartAtLogin: Bool = false) {
        self.autoStartAtLogin = autoStartAtLogin
    }
}

/// Global Agent Layer configuration.
public struct AgentLayerConfig: Equatable, Sendable {
    /// When true, projects default to using Agent Layer unless overridden per-project.
    public let enabled: Bool

    init(enabled: Bool = false) {
        self.enabled = enabled
    }
}

/// Full parsed configuration for ProjectSwitcher.
public struct Config: Equatable, Sendable {
    public let projects: [ProjectConfig]
    public let chrome: ChromeConfig
    public let agentLayer: AgentLayerConfig
    public let layout: LayoutConfig
    public let app: AppConfig

    init(
        projects: [ProjectConfig],
        chrome: ChromeConfig = ChromeConfig(),
        agentLayer: AgentLayerConfig = AgentLayerConfig(),
        layout: LayoutConfig = LayoutConfig(),
        app: AppConfig = AppConfig()
    ) {
        self.projects = projects
        self.chrome = chrome
        self.agentLayer = agentLayer
        self.layout = layout
        self.app = app
    }
}

/// Project-level configuration values.
public struct ProjectConfig: Equatable, Sendable {
    public let id: String
    public let name: String
    /// Optional VS Code remote authority (e.g., "ssh-remote+user@host") for SSH projects.
    ///
    /// When set, `path` is interpreted as a remote absolute path and VS Code is opened
    /// via a `vscode-remote://` folder URI.
    public let remote: String?
    public let path: String
    public let color: String
    public let useAgentLayer: Bool
    /// Per-project URLs always opened as leftmost tabs.
    public let chromePinnedTabs: [String]
    /// Per-project URLs opened when no tab history exists.
    public let chromeDefaultTabs: [String]

    /// Whether this project uses an SSH remote (Remote-SSH).
    public var isSSH: Bool { remote != nil }

    init(
        id: String,
        name: String,
        remote: String? = nil,
        path: String,
        color: String,
        useAgentLayer: Bool,
        chromePinnedTabs: [String] = [],
        chromeDefaultTabs: [String] = []
    ) {
        self.id = id
        self.name = name
        self.remote = remote
        self.path = path
        self.color = color
        self.useAgentLayer = useAgentLayer
        self.chromePinnedTabs = chromePinnedTabs
        self.chromeDefaultTabs = chromeDefaultTabs
    }
}

/// RGB components for named project colors.
public struct ProjectColorRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Supported named colors for project color values.
public enum ProjectColorPalette {
    static let named: [String: ProjectColorRGB] = [
        "black": ProjectColorRGB(red: 0.0, green: 0.0, blue: 0.0),
        "blue": ProjectColorRGB(red: 0.0, green: 0.0, blue: 1.0),
        "brown": ProjectColorRGB(red: 0.6471, green: 0.1647, blue: 0.1647),
        "cyan": ProjectColorRGB(red: 0.0, green: 1.0, blue: 1.0),
        "gray": ProjectColorRGB(red: 0.5020, green: 0.5020, blue: 0.5020),
        "grey": ProjectColorRGB(red: 0.5020, green: 0.5020, blue: 0.5020),
        "green": ProjectColorRGB(red: 0.0, green: 0.5020, blue: 0.0),
        "indigo": ProjectColorRGB(red: 0.2941, green: 0.0, blue: 0.5098),
        "orange": ProjectColorRGB(red: 1.0, green: 0.6471, blue: 0.0),
        "pink": ProjectColorRGB(red: 1.0, green: 0.7529, blue: 0.7961),
        "purple": ProjectColorRGB(red: 0.5020, green: 0.0, blue: 0.5020),
        "red": ProjectColorRGB(red: 1.0, green: 0.0, blue: 0.0),
        "teal": ProjectColorRGB(red: 0.0, green: 0.5020, blue: 0.5020),
        "white": ProjectColorRGB(red: 1.0, green: 1.0, blue: 1.0),
        "yellow": ProjectColorRGB(red: 1.0, green: 1.0, blue: 0.0)
    ]

    static let sortedNames: [String] = named.keys.sorted()

    /// Resolves a color string (hex or named) to RGB components.
    /// - Parameter value: A hex color (#RRGGBB) or named color string.
    /// - Returns: RGB components if valid, nil otherwise.
    public static func resolve(_ value: String) -> ProjectColorRGB? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if let hex = parseHex(trimmed) {
            return hex
        }

        return named[trimmed.lowercased()]
    }

    /// Parses a hex color string (#RRGGBB) to RGB components.
    private static func parseHex(_ value: String) -> ProjectColorRGB? {
        guard value.count == 7, value.hasPrefix("#") else {
            return nil
        }

        let hexDigits = String(value.dropFirst())
        guard let intValue = Int(hexDigits, radix: 16) else {
            return nil
        }

        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        return ProjectColorRGB(red: red, green: green, blue: blue)
    }
}

// MARK: - ConfigLoadError

/// Errors that can occur when loading configuration via `Config.loadDefault()`.
///
/// This is the public error type for the simplified config loading API.
public enum ConfigLoadError: Error, Equatable, Sendable {
    /// Config file not found at the expected path.
    case fileNotFound(path: String)

    /// Config file exists but could not be read.
    case readFailed(path: String, detail: String)

    /// Config file could not be parsed as valid TOML.
    case parseFailed(detail: String)

    /// Config file parsed but failed validation.
    case validationFailed(findings: [ConfigFinding])
}

// MARK: - ConfigLoadSuccess

/// Successful result of loading configuration via `Config.loadDefault()`.
///
/// Carries the validated config and any non-fatal warnings from parsing.
public struct ConfigLoadSuccess: Equatable, Sendable {
    /// The validated configuration.
    public let config: Config
    /// Non-fatal warnings from config parsing (severity == .warn).
    public let warnings: [ConfigFinding]

    public init(config: Config, warnings: [ConfigFinding] = []) {
        self.config = config
        self.warnings = warnings
    }
}

// MARK: - Config Public Loading API

extension Config {
    /// Loads and validates configuration from the default path.
    ///
    /// This is the recommended entry point for App to load configuration.
    /// It provides a simplified API that returns either a valid `ConfigLoadSuccess`
    /// (config + warnings) or a descriptive error. Uses `ConfigLoader` as the
    /// single source of truth.
    ///
    /// - Returns: Result with ConfigLoadSuccess or ConfigLoadError.
    public static func loadDefault() -> Result<ConfigLoadSuccess, ConfigLoadError> {
        loadDefault(dataStore: DataPaths.default())
    }

    static func loadDefault(dataStore: DataPaths) -> Result<ConfigLoadSuccess, ConfigLoadError> {
        let path = dataStore.configFile.path

        // Use ConfigLoader as single source of truth
        switch ConfigLoader.loadDefault(dataStore: dataStore) {
        case .failure(let error):
            // Translate ConfigError to ConfigLoadError using the error kind.
            switch error.kind {
            case .fileNotFound:
                return .failure(.fileNotFound(path: path))
            case .createFailed, .readFailed:
                return .failure(.readFailed(path: path, detail: error.message))
            }

        case .success(let result):
            // Check for parse or validation errors
            let failures = result.findings.filter { $0.severity == .fail }
            if !failures.isEmpty || result.config == nil {
                // Use the explicit flag instead of string matching
                if result.hasParseError, let parseError = failures.first {
                    return .failure(.parseFailed(detail: parseError.detail ?? parseError.title))
                }
                return .failure(.validationFailed(findings: failures))
            }

            guard let config = result.config else {
                return .failure(.validationFailed(findings: result.findings))
            }

            let warnings = result.findings.filter { $0.severity == .warn }
            return .success(ConfigLoadSuccess(config: config, warnings: warnings))
        }
    }
}
