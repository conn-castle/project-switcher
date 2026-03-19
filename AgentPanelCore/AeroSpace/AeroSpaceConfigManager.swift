//
//  AeroSpaceConfigManager.swift
//  AgentPanelCore
//
//  Manages the AeroSpace configuration file (~/.aerospace.toml).
//  Handles config status detection, backup creation, and writing
//  the AgentPanel-managed safe configuration.
//

import Foundation

/// Manages the AeroSpace configuration file.
public struct AeroSpaceConfigManager {
    /// Marker comment that identifies configs managed by AgentPanel.
    static let managedByMarker = "# Managed by AgentPanel - do not edit manually"

    /// Resource name for the safe config template.
    private static let safeConfigResourceName = "aerospace-safe"

    /// Structured logger for config management events.
    private static let structuredLogger = AgentPanelLogger()

    /// Default path to the AeroSpace config file.
    public static var configPath: String {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".aerospace.toml", isDirectory: false)
            .path
    }

    /// Path for backing up existing configs before overwriting.
    private static var backupPath: String {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".aerospace.toml.agentpanel-backup", isDirectory: false)
            .path
    }

    private let fileManager: FileManager
    private let configPath: String
    private let backupPath: String
    private let safeConfigLoader: () -> String?

    /// Loads the bundled aerospace-safe.toml, logging any read errors.
    ///
    /// Returns nil when the resource is not bundled (expected for CLI tools) or
    /// when reading fails (logged as an error).
    private static func loadBundledConfigContent() -> String? {
        guard let url = Bundle.main.url(forResource: safeConfigResourceName, withExtension: "toml") else {
            return nil
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            _ = structuredLogger.log(
                event: "config.bundle_resource_read_failed",
                level: .error,
                message: "Failed to read bundled aerospace-safe.toml",
                context: ["error": error.localizedDescription, "url": url.path]
            )
            return nil
        }
    }

    /// Creates a config manager.
    public init() {
        self.fileManager = .default
        self.configPath = Self.configPath
        self.backupPath = Self.backupPath
        self.safeConfigLoader = { Self.loadBundledConfigContent() }
    }

    /// Creates a config manager with a custom file manager.
    /// - Parameter fileManager: File manager to use for file operations.
    init(
        fileManager: FileManager,
        configPath: String = AeroSpaceConfigManager.configPath,
        backupPath: String = AeroSpaceConfigManager.backupPath,
        safeConfigLoader: @escaping () -> String? = { AeroSpaceConfigManager.loadBundledConfigContent() }
    ) {
        self.fileManager = fileManager
        self.configPath = configPath
        self.backupPath = backupPath
        self.safeConfigLoader = safeConfigLoader
    }

    /// Loads the safe AeroSpace config from the app bundle.
    /// - Returns: The config content, or nil if not found.
    private func loadSafeConfigFromBundle() -> String? {
        safeConfigLoader()
    }

    /// Returns true if the AeroSpace config file exists.
    private func configExists() -> Bool {
        fileManager.fileExists(atPath: configPath)
    }

    /// Returns true if the existing config is managed by AgentPanel.
    /// - Returns: True if the config starts with the managed-by marker, false otherwise.
    private func configIsManagedByAgentPanel() -> Result<Bool, ApCoreError> {
        guard configExists() else {
            return .success(false)
        }

        do {
            let contents = try String(contentsOfFile: configPath, encoding: .utf8)
            return .success(contents.hasPrefix(Self.managedByMarker))
        } catch {
            return .failure(fileSystemError(
                "Failed to read AeroSpace config.",
                detail: error.localizedDescription
            ))
        }
    }

    /// Backs up the existing config file if it exists.
    /// - Returns: Success, or an error if backup fails.
    private func backupExistingConfig() -> Result<Void, ApCoreError> {
        guard configExists() else {
            return .success(())
        }

        do {
            // Remove old backup if it exists
            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.removeItem(atPath: backupPath)
            }
            try fileManager.copyItem(atPath: configPath, toPath: backupPath)
            return .success(())
        } catch {
            return .failure(fileSystemError(
                "Failed to backup AeroSpace config.",
                detail: error.localizedDescription
            ))
        }
    }

    /// Writes the safe AeroSpace config, backing up any existing config first.
    /// - Returns: Success, or an error if writing fails.
    public func writeSafeConfig() -> Result<Void, ApCoreError> {
        // Load the safe config from bundle
        guard let safeConfig = loadSafeConfigFromBundle() else {
            return .failure(fileSystemError(
                "Failed to load aerospace-safe.toml from app bundle.",
                detail: "The app may be corrupted."
            ))
        }

        // Backup existing config if it exists and isn't ours
        switch configIsManagedByAgentPanel() {
        case .failure(let error):
            return .failure(error)
        case .success(let isOurs):
            if !isOurs && configExists() {
                switch backupExistingConfig() {
                case .failure(let error):
                    return .failure(error)
                case .success:
                    break
                }
            }
        }

        // Write the safe config
        do {
            try safeConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
            return .success(())
        } catch {
            return .failure(fileSystemError(
                "Failed to write AeroSpace config.",
                detail: error.localizedDescription
            ))
        }
    }

    /// Returns the raw contents of the AeroSpace config file, or nil if the file
    /// does not exist or cannot be read.
    public func configContents() -> String? {
        guard configExists() else { return nil }
        do {
            return try String(contentsOfFile: configPath, encoding: .utf8)
        } catch {
            _ = Self.structuredLogger.log(
                event: "config.file_read_failed",
                level: .error,
                message: "Failed to read AeroSpace config file",
                context: ["path": configPath, "error": error.localizedDescription]
            )
            return nil
        }
    }

    /// Returns the status of the AeroSpace config for diagnostic purposes.
    public func configStatus() -> AeroSpaceConfigStatus {
        guard configExists() else {
            return .missing
        }

        switch configIsManagedByAgentPanel() {
        case .failure:
            return .unknown
        case .success(true):
            return .managedByAgentPanel
        case .success(false):
            return .externalConfig
        }
    }

    // MARK: - Config Version & User Section Management

    /// Marker prefix for the config version line.
    static let versionPrefix = "# ap-config-version: "

    /// Start marker for user keybindings section.
    static let userKeybindingsStart = "# >>> user-keybindings"
    /// End marker for user keybindings section.
    static let userKeybindingsEnd = "# <<< user-keybindings"
    /// Start marker for user config section.
    static let userConfigStart = "# >>> user-config"
    /// End marker for user config section.
    static let userConfigEnd = "# <<< user-config"

    /// Extracts the `ap-config-version` number from config content.
    /// - Parameter content: The config file content.
    /// - Returns: The version number, or nil if not found or malformed.
    static func parseConfigVersion(from content: String) -> Int? {
        for line in content.components(separatedBy: .newlines) {
            if line.hasPrefix(versionPrefix) {
                let versionString = line.dropFirst(versionPrefix.count).trimmingCharacters(in: .whitespaces)
                return Int(versionString)
            }
        }
        return nil
    }

    /// Extracts the content between two markers (exclusive of the markers themselves).
    /// - Parameters:
    ///   - content: The full config content to search.
    ///   - startMarker: The start marker line.
    ///   - endMarker: The end marker line.
    /// - Returns: The content between the markers, or nil if markers are not found.
    static func extractUserSection(from content: String?, startMarker: String, endMarker: String) -> String? {
        guard let content else { return nil }
        let lines = content.components(separatedBy: .newlines)
        guard let startIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == startMarker }),
              let endIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == endMarker }),
              endIndex > startIndex else {
            return nil
        }
        let sectionLines = Array(lines[(startIndex + 1)..<endIndex])
        return sectionLines.joined(separator: "\n")
    }

    /// Replaces the content between two markers with new content.
    /// - Parameters:
    ///   - content: The full config content.
    ///   - startMarker: The start marker line.
    ///   - endMarker: The end marker line.
    ///   - replacement: The new content to insert between markers.
    /// - Returns: The updated config content.
    static func replaceUserSection(in content: String, startMarker: String, endMarker: String, with replacement: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        guard let startIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == startMarker }),
              let endIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == endMarker }),
              endIndex > startIndex else {
            return content
        }

        var result = Array(lines[0...startIndex])
        let replacementLines = replacement.components(separatedBy: .newlines)
        result.append(contentsOf: replacementLines)
        result.append(contentsOf: Array(lines[endIndex...]))
        return result.joined(separator: "\n")
    }

    /// Returns true if the safe config template resource is available.
    ///
    /// This is false when running from a CLI tool that does not bundle
    /// `aerospace-safe.toml` (expected), and true when running from the app.
    public func isTemplateAvailable() -> Bool {
        loadSafeConfigFromBundle() != nil
    }

    /// Returns the config version from the bundled template.
    /// - Returns: The template version number, or nil if the template is missing or has no version.
    public func templateVersion() -> Int? {
        guard let template = loadSafeConfigFromBundle() else { return nil }
        return Self.parseConfigVersion(from: template)
    }

    /// Returns the config version from the existing config file.
    /// - Returns: The current config version number, or nil if the file is missing or has no version.
    public func currentConfigVersion() -> Int? {
        guard let contents = configContents() else { return nil }
        return Self.parseConfigVersion(from: contents)
    }

    /// Updates a managed config by merging user sections from the existing config into the template.
    /// - Returns: Success, or an error if the template cannot be loaded or the file cannot be written.
    public func updateManagedConfig() -> Result<Void, ApCoreError> {
        guard let template = loadSafeConfigFromBundle() else {
            return .failure(fileSystemError(
                "Failed to load aerospace-safe.toml from app bundle.",
                detail: "The app may be corrupted."
            ))
        }

        let existingContents = configContents()

        // Extract user sections from existing config (nil if markers don't exist)
        let userKeybindings = Self.extractUserSection(
            from: existingContents,
            startMarker: Self.userKeybindingsStart,
            endMarker: Self.userKeybindingsEnd
        )
        let userConfig = Self.extractUserSection(
            from: existingContents,
            startMarker: Self.userConfigStart,
            endMarker: Self.userConfigEnd
        )

        // Start with the template and replace user sections if we have content to preserve
        var merged = template
        if let userKeybindings {
            merged = Self.replaceUserSection(
                in: merged,
                startMarker: Self.userKeybindingsStart,
                endMarker: Self.userKeybindingsEnd,
                with: userKeybindings
            )
        }
        if let userConfig {
            merged = Self.replaceUserSection(
                in: merged,
                startMarker: Self.userConfigStart,
                endMarker: Self.userConfigEnd,
                with: userConfig
            )
        }

        do {
            try merged.write(toFile: configPath, atomically: true, encoding: .utf8)
            return .success(())
        } catch {
            return .failure(fileSystemError(
                "Failed to write updated AeroSpace config.",
                detail: error.localizedDescription
            ))
        }
    }

    /// Ensures the AeroSpace config is up to date.
    ///
    /// - `.missing` → writes a fresh config via `writeSafeConfig()`, returns `.freshInstall`.
    /// - `.managedByAgentPanel` with stale version → calls `updateManagedConfig()`, returns `.updated`.
    /// - `.managedByAgentPanel` with current version → returns `.alreadyCurrent`.
    /// - `.externalConfig` → returns `.skippedExternal`.
    /// - `.unknown` → returns `.failure` (cannot read config).
    ///
    /// - Returns: The update result, or an error if writing fails.
    public func ensureUpToDate() -> Result<ConfigUpdateResult, ApCoreError> {
        switch configStatus() {
        case .missing:
            switch writeSafeConfig() {
            case .failure(let error):
                return .failure(error)
            case .success:
                return .success(.freshInstall)
            }

        case .managedByAgentPanel:
            let currentVersion = currentConfigVersion()
            let latestVersion = templateVersion()

            // If the template cannot be loaded or lacks a version, this is a broken bundle
            guard let latestVersion else {
                return .failure(fileSystemError(
                    "Cannot determine template config version.",
                    detail: "The bundled aerospace-safe.toml is missing or has no ap-config-version line."
                ))
            }

            // If the installed config has no version or a lower version, update it
            if currentVersion == nil || currentVersion! < latestVersion {
                let fromVersion = currentVersion ?? 0
                switch updateManagedConfig() {
                case .failure(let error):
                    return .failure(error)
                case .success:
                    return .success(.updated(fromVersion: fromVersion, toVersion: latestVersion))
                }
            }

            return .success(.alreadyCurrent)

        case .externalConfig:
            return .success(.skippedExternal)

        case .unknown:
            return .failure(fileSystemError(
                "Cannot read AeroSpace config file.",
                detail: "Check file permissions on \(configPath)."
            ))
        }
    }

}
