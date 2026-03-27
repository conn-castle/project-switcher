import Foundation
import TOMLDecoder

extension ConfigParser {
    // MARK: - Chrome Section Parsing

    static func parseChromeSection(
        table: TOMLTable,
        findings: inout [ConfigFinding]
    ) -> ChromeConfig {
        guard table.contains(key: "chrome") else {
            return ChromeConfig()
        }

        guard let chromeTable = try? table.table(forKey: "chrome") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "[chrome] must be a table",
                fix: "Use [chrome] as a TOML table section."
            ))
            return ChromeConfig()
        }

        checkForUnknownKeys(in: chromeTable, knownKeys: knownChromeKeys, section: "[chrome]", findings: &findings)

        let pinnedTabs = readOptionalStringArray(
            from: chromeTable, key: "pinnedTabs",
            label: "chrome.pinnedTabs", findings: &findings
        )
        validateURLs(pinnedTabs, label: "chrome.pinnedTabs", findings: &findings)

        let defaultTabs = readOptionalStringArray(
            from: chromeTable, key: "defaultTabs",
            label: "chrome.defaultTabs", findings: &findings
        )
        validateURLs(defaultTabs, label: "chrome.defaultTabs", findings: &findings)

        let openGitRemote = readOptionalBool(
            from: chromeTable, key: "openGitRemote",
            defaultValue: false,
            label: "chrome.openGitRemote", findings: &findings
        )

        return ChromeConfig(
            pinnedTabs: pinnedTabs,
            defaultTabs: defaultTabs,
            openGitRemote: openGitRemote
        )
    }

    // MARK: - App Section Parsing

    static func parseAppSection(
        table: TOMLTable,
        findings: inout [ConfigFinding]
    ) -> AppConfig {
        guard table.contains(key: "app") else {
            return AppConfig()
        }

        guard let appTable = try? table.table(forKey: "app") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "[app] must be a table",
                fix: "Use [app] as a TOML table section."
            ))
            return AppConfig()
        }

        checkForUnknownKeys(in: appTable, knownKeys: knownAppKeys, section: "[app]", findings: &findings)

        let autoStartAtLogin = readOptionalBool(
            from: appTable, key: "autoStartAtLogin",
            defaultValue: false,
            label: "app.autoStartAtLogin", findings: &findings
        )

        return AppConfig(autoStartAtLogin: autoStartAtLogin)
    }

    // MARK: - Agent Layer Section Parsing

    static func parseAgentLayerSection(
        table: TOMLTable,
        findings: inout [ConfigFinding]
    ) -> AgentLayerConfig {
        guard table.contains(key: "agentLayer") else {
            return AgentLayerConfig()
        }

        guard let agentLayerTable = try? table.table(forKey: "agentLayer") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "[agentLayer] must be a table",
                fix: "Use [agentLayer] as a TOML table section."
            ))
            return AgentLayerConfig()
        }

        checkForUnknownKeys(in: agentLayerTable, knownKeys: knownAgentLayerKeys, section: "[agentLayer]", findings: &findings)

        let enabled = readOptionalBool(
            from: agentLayerTable, key: "enabled",
            defaultValue: false,
            label: "agentLayer.enabled", findings: &findings
        )

        return AgentLayerConfig(enabled: enabled)
    }

    // MARK: - Layout Section Parsing

    static func parseLayoutSection(
        table: TOMLTable,
        findings: inout [ConfigFinding]
    ) -> LayoutConfig {
        guard table.contains(key: "layout") else {
            return LayoutConfig()
        }

        guard let layoutTable = try? table.table(forKey: "layout") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "[layout] must be a table",
                fix: "Use [layout] as a TOML table section."
            ))
            return LayoutConfig()
        }

        checkForUnknownKeys(in: layoutTable, knownKeys: knownLayoutKeys, section: "[layout]", findings: &findings)

        let smallScreenThreshold = readOptionalNumber(
            from: layoutTable, key: "smallScreenThreshold",
            label: "layout.smallScreenThreshold", findings: &findings
        )
        let windowHeight = readOptionalInteger(
            from: layoutTable, key: "windowHeight",
            label: "layout.windowHeight", findings: &findings
        )
        let maxWindowWidth = readOptionalNumber(
            from: layoutTable, key: "maxWindowWidth",
            label: "layout.maxWindowWidth", findings: &findings
        )
        let idePositionStr = readOptionalNonEmptyString(
            from: layoutTable, key: "idePosition",
            label: "layout.idePosition", findings: &findings
        )
        let justificationStr = readOptionalNonEmptyString(
            from: layoutTable, key: "justification",
            label: "layout.justification", findings: &findings
        )
        let maxGap = readOptionalInteger(
            from: layoutTable, key: "maxGap",
            label: "layout.maxGap", findings: &findings
        )

        // Validate bounds
        var valid = true

        if let v = smallScreenThreshold, v <= 0 {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "layout.smallScreenThreshold must be > 0",
                detail: "Got \(v).",
                fix: "Set smallScreenThreshold to a positive number (default: 24)."
            ))
            valid = false
        }

        if let v = windowHeight {
            if v < 1 || v > 100 {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "layout.windowHeight must be 1–100",
                    detail: "Got \(v).",
                    fix: "Set windowHeight to a value between 1 and 100 (default: 90)."
                ))
                valid = false
            }
        }

        if let v = maxWindowWidth, v <= 0 {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "layout.maxWindowWidth must be > 0",
                detail: "Got \(v).",
                fix: "Set maxWindowWidth to a positive number (default: 18)."
            ))
            valid = false
        }

        var idePosition: LayoutConfig.IdePosition = LayoutConfig.Defaults.idePosition
        if let str = idePositionStr {
            if let pos = LayoutConfig.IdePosition(rawValue: str) {
                idePosition = pos
            } else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "layout.idePosition must be \"left\" or \"right\"",
                    detail: "Got \"\(str)\".",
                    fix: "Set idePosition to \"left\" or \"right\" (default: \"left\")."
                ))
                valid = false
            }
        }

        var justification: LayoutConfig.Justification = LayoutConfig.Defaults.justification
        if let str = justificationStr {
            if let j = LayoutConfig.Justification(rawValue: str) {
                justification = j
            } else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "layout.justification must be \"left\" or \"right\"",
                    detail: "Got \"\(str)\".",
                    fix: "Set justification to \"left\" or \"right\" (default: \"right\")."
                ))
                valid = false
            }
        }

        if let v = maxGap {
            if v < 0 || v > 100 {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "layout.maxGap must be 0–100",
                    detail: "Got \(v).",
                    fix: "Set maxGap to a value between 0 and 100 (default: 10)."
                ))
                valid = false
            }
        }

        guard valid else {
            return LayoutConfig()
        }

        return LayoutConfig(
            smallScreenThreshold: smallScreenThreshold ?? LayoutConfig.Defaults.smallScreenThreshold,
            windowHeight: windowHeight.map { Int($0) } ?? LayoutConfig.Defaults.windowHeight,
            maxWindowWidth: maxWindowWidth ?? LayoutConfig.Defaults.maxWindowWidth,
            idePosition: idePosition,
            justification: justification,
            maxGap: maxGap.map { Int($0) } ?? LayoutConfig.Defaults.maxGap
        )
    }
}
