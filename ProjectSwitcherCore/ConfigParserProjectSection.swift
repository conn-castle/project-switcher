import Foundation
import TOMLDecoder

extension ConfigParser {
    // MARK: - Project Parsing

    struct ProjectOutcome {
        let config: ProjectConfig?
    }

    static func parseProjects(
        table: TOMLTable,
        globalAgentLayerEnabled: Bool,
        findings: inout [ConfigFinding]
    ) -> [ProjectOutcome] {
        guard table.contains(key: "project") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "No [[project]] entries",
                fix: "Add at least one [[project]] entry to config.toml."
            ))
            return []
        }

        guard let projectsArray = try? table.array(forKey: "project") else {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "project must be an array of tables",
                fix: "Use [[project]] entries in config.toml."
            ))
            return []
        }

        if projectsArray.count == 0 {
            findings.append(ConfigFinding(
                severity: .fail,
                title: "No [[project]] entries",
                fix: "Add at least one [[project]] entry to config.toml."
            ))
            return []
        }

        var outcomes: [ProjectOutcome] = []
        var seenIds: [String: Int] = [:]

        for index in 0..<projectsArray.count {
            guard let projectTable = try? projectsArray.table(atIndex: index) else {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)] must be a table",
                    fix: "Ensure each [[project]] entry is a TOML table."
                ))
                outcomes.append(ProjectOutcome(config: nil))
                continue
            }

            let outcome = parseProject(
                table: projectTable,
                index: index,
                globalAgentLayerEnabled: globalAgentLayerEnabled,
                seenIds: &seenIds,
                findings: &findings
            )
            outcomes.append(outcome)
        }

        return outcomes
    }

    static func parseProject(
        table: TOMLTable,
        index: Int,
        globalAgentLayerEnabled: Bool,
        seenIds: inout [String: Int],
        findings: inout [ConfigFinding]
    ) -> ProjectOutcome {
        var projectIsValid = true

        checkForUnknownKeys(in: table, knownKeys: knownProjectKeys, section: "[[project]]", findings: &findings)

        let name = readNonEmptyString(
            from: table,
            key: "name",
            label: "project[\(index)].name",
            findings: &findings
        )
        let remote = readOptionalNonEmptyString(
            from: table,
            key: "remote",
            label: "project[\(index)].remote",
            findings: &findings
        )
        let path = readNonEmptyString(
            from: table,
            key: "path",
            label: "project[\(index)].path",
            findings: &findings
        )
        let color = readNonEmptyString(
            from: table,
            key: "color",
            label: "project[\(index)].color",
            findings: &findings
        )
        let useAgentLayer = readOptionalBool(
            from: table,
            key: "useAgentLayer",
            defaultValue: globalAgentLayerEnabled,
            label: "project[\(index)].useAgentLayer",
            findings: &findings
        )

        // Name validation + id derivation
        var derivedId: String?
        if let name {
            let normalized = IdNormalizer.normalize(name)
            if normalized.isEmpty {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].name cannot derive an id",
                    detail: "Normalized id was empty after removing invalid characters.",
                    fix: "Use a name with letters or numbers so an id can be derived."
                ))
                projectIsValid = false
            } else if IdNormalizer.isReserved(normalized) {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].id is reserved",
                    detail: "The id '\(normalized)' is reserved.",
                    fix: "Choose a different project name so the derived id is not reserved."
                ))
                projectIsValid = false
            } else if let existingIndex = seenIds[normalized] {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "Duplicate project.id: \(normalized)",
                    detail: "Derived from project indexes \(existingIndex) and \(index).",
                    fix: "Ensure project names normalize to unique ids."
                ))
                projectIsValid = false
            } else {
                derivedId = normalized
                seenIds[normalized] = index
            }
        } else {
            projectIsValid = false
        }

        // Color validation
        var normalizedColor: String?
        if let color {
            let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidColorHex(trimmed) {
                normalizedColor = trimmed
            } else {
                let lowercased = trimmed.lowercased()
                if ProjectColorPalette.named.keys.contains(lowercased) {
                    normalizedColor = lowercased
                } else {
                    findings.append(ConfigFinding(
                        severity: .fail,
                        title: "project[\(index)].color is invalid",
                        detail: "Color must be #RRGGBB or a named color.",
                        fix: "Use a hex color or one of: \(ProjectColorPalette.sortedNames.joined(separator: ", "))."
                    ))
                    projectIsValid = false
                }
            }
        } else {
            projectIsValid = false
        }

        // Remote SSH validation (VS Code Remote-SSH)
        var normalizedRemote: String?
        if let remote {
            switch PsSSHHelpers.parseRemoteAuthority(remote) {
            case .success:
                normalizedRemote = remote
            case .failure(.missingPrefix):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority must start with 'ssh-remote+'",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            case .failure(.containsWhitespace):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority must not contain whitespace",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            case .failure(.missingTarget):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority is missing host (expected ssh-remote+user@host)",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            case .failure(.targetStartsWithDash):
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].remote: SSH remote authority must not start with '-'",
                    fix: "Use format: remote = \"ssh-remote+user@host\""
                ))
                projectIsValid = false
            }
        }

        if normalizedRemote != nil {
            // SSH + Agent Layer mutual exclusion
            if useAgentLayer {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)]: Agent Layer is not supported with SSH projects",
                    fix: "Set useAgentLayer = false for this project (SSH projects cannot use Agent Layer)."
                ))
                projectIsValid = false
            }

            // Remote path must be absolute
            if let path, !path.hasPrefix("/") {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].path: remote path must be an absolute path (starting with /)",
                    fix: "Use a remote absolute path, e.g. /Users/you/src/project"
                ))
                projectIsValid = false
            }
        } else if let path {
            if path.hasPrefix("ssh-remote+") {
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].path: legacy SSH path format is not supported",
                    detail: "Found an ssh-remote+ prefix in project.path but project.remote is not set.",
                    fix: "Use remote = \"ssh-remote+user@host\" and path = \"/remote/absolute/path\""
                ))
                projectIsValid = false
            } else if !path.hasPrefix("/") {
                // Local path must be absolute
                findings.append(ConfigFinding(
                    severity: .fail,
                    title: "project[\(index)].path: local path must be an absolute path (starting with /)",
                    fix: "Use an absolute path, e.g. /Users/you/src/project"
                ))
                projectIsValid = false
            }
        }

        // Chrome tab fields (optional, default empty)
        let chromePinnedTabs = readOptionalStringArray(
            from: table, key: "chromePinnedTabs",
            label: "project[\(index)].chromePinnedTabs", findings: &findings
        )
        if !chromePinnedTabs.isEmpty {
            if !validateURLs(chromePinnedTabs, label: "project[\(index)].chromePinnedTabs", findings: &findings) {
                projectIsValid = false
            }
        }

        let chromeDefaultTabs = readOptionalStringArray(
            from: table, key: "chromeDefaultTabs",
            label: "project[\(index)].chromeDefaultTabs", findings: &findings
        )
        if !chromeDefaultTabs.isEmpty {
            if !validateURLs(chromeDefaultTabs, label: "project[\(index)].chromeDefaultTabs", findings: &findings) {
                projectIsValid = false
            }
        }

        guard let name, let path, let normalizedColor, let derivedId, projectIsValid else {
            return ProjectOutcome(config: nil)
        }

        let projectConfig = ProjectConfig(
            id: derivedId,
            name: name,
            remote: normalizedRemote,
            path: path,
            color: normalizedColor,
            useAgentLayer: useAgentLayer,
            chromePinnedTabs: chromePinnedTabs,
            chromeDefaultTabs: chromeDefaultTabs
        )
        return ProjectOutcome(config: projectConfig)
    }
}
