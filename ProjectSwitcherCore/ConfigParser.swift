import Foundation
import TOMLDecoder

// MARK: - Config Parser

/// Parses TOML config into typed models with validation.
struct ConfigParser {
    static func parse(toml: String) -> ConfigLoadResult {
        do {
            let table = try TOMLTable(source: toml)
            return parse(table: table)
        } catch {
            return ConfigLoadResult(
                config: nil,
                findings: [
                    ConfigFinding(
                        severity: .fail,
                        title: "Config TOML parse error",
                        detail: String(describing: error),
                        fix: "Fix the TOML syntax in config.toml."
                    )
                ],
                hasParseError: true
            )
        }
    }

    private static func parse(table: TOMLTable) -> ConfigLoadResult {
        var findings: [ConfigFinding] = []

        checkForUnknownKeys(in: table, knownKeys: knownTopLevelKeys, section: "top-level", findings: &findings)

        let appConfig = parseAppSection(table: table, findings: &findings)
        let chromeConfig = parseChromeSection(table: table, findings: &findings)
        let agentLayerConfig = parseAgentLayerSection(table: table, findings: &findings)
        let layoutConfig = parseLayoutSection(table: table, findings: &findings)
        let projectOutcomes = parseProjects(
            table: table,
            globalAgentLayerEnabled: agentLayerConfig.enabled,
            findings: &findings
        )
        let parsedProjects = projectOutcomes.compactMap { $0.config }

        let validationFailed = findings.contains { $0.severity == .fail }
        let config: Config? = validationFailed
            ? nil
            : Config(projects: parsedProjects, chrome: chromeConfig, agentLayer: agentLayerConfig, layout: layoutConfig, app: appConfig)

        return ConfigLoadResult(
            config: config,
            findings: findings,
            projects: parsedProjects
        )
    }

    // MARK: - Unknown Key Detection

    /// Known top-level keys in config.toml.
    static let knownTopLevelKeys: Set<String> = ["chrome", "agentLayer", "project", "layout", "app"]

    /// Known keys in the [chrome] section.
    static let knownChromeKeys: Set<String> = ["pinnedTabs", "defaultTabs", "openGitRemote"]

    /// Known keys in the [agentLayer] section.
    static let knownAgentLayerKeys: Set<String> = ["enabled"]

    /// Known keys in the [app] section.
    static let knownAppKeys: Set<String> = ["autoStartAtLogin"]

    /// Known keys in the [layout] section.
    static let knownLayoutKeys: Set<String> = [
        "smallScreenThreshold", "windowHeight", "maxWindowWidth",
        "idePosition", "justification", "maxGap"
    ]

    /// Known keys in each [[project]] entry.
    static let knownProjectKeys: Set<String> = [
        "name", "remote", "path", "color", "useAgentLayer", "chromePinnedTabs", "chromeDefaultTabs"
    ]

    /// Checks for unrecognized keys in a TOMLTable and emits FAIL findings for each.
    /// - Parameters:
    ///   - table: The TOML table to check.
    ///   - knownKeys: Set of recognized key names.
    ///   - section: Human-readable section label (e.g., "top-level", "[chrome]", "project[0]").
    ///   - findings: Findings array to append to.
    static func checkForUnknownKeys(
        in table: TOMLTable,
        knownKeys: Set<String>,
        section: String,
        findings: inout [ConfigFinding]
    ) {
        let unknown = Set(table.keys).subtracting(knownKeys).sorted()
        for key in unknown {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "Unrecognized \(section) config key: \(key)",
                fix: "Remove '\(key)' from config.toml. Known \(section) keys are: \(knownKeys.sorted().joined(separator: ", "))."
            ))
        }
    }

}
