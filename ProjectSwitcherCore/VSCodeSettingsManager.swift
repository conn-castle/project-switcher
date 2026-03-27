import Foundation

/// Manages the `// >>> project-switcher` marker block in `.vscode/settings.json` files.
///
/// This manager injects a window title setting directly into the project's `.vscode/settings.json`.
/// The block is delimited by `// >>> project-switcher` / `// <<< project-switcher` markers,
/// allowing coexistence with other managed blocks (e.g., `// >>> agent-layer`).
struct PsVSCodeSettingsManager {
    private let fileSystem: FileSystem
    private let commandRunner: CommandRunning?

    /// Creates a settings manager.
    /// - Parameters:
    ///   - fileSystem: File system accessor for settings.json I/O.
    ///   - commandRunner: Command runner for SSH remote writes. Pass `nil` if only local writes are needed.
    init(fileSystem: FileSystem = DefaultFileSystem(), commandRunner: CommandRunning? = nil) {
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    // MARK: - Local settings.json write

    /// Writes the project-switcher block into the project's `.vscode/settings.json`.
    ///
    /// Reads the existing file (or defaults to `{}\n` if the file doesn't exist),
    /// injects the block, creates the `.vscode/` directory if needed, and writes the result.
    /// Returns an error if the file exists but cannot be read (e.g., permission denied).
    ///
    /// - Parameters:
    ///   - projectPath: Absolute path to the project directory.
    ///   - identifier: Project identifier for the `PS:<id>` window title.
    ///   - color: Optional project color for VS Code color customizations.
    /// - Returns: Success or an error.
    func writeLocalSettings(projectPath: String, identifier: String, color: String? = nil) -> Result<Void, PsCoreError> {
        let projectURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        // Fail loudly on misconfigured paths. Do not create missing project directories.
        guard fileSystem.directoryExists(at: projectURL) else {
            return .failure(PsCoreError(message: "Project path does not exist or is not a directory: \(projectURL.path)"))
        }

        let vscodeDir = projectURL.appendingPathComponent(".vscode", isDirectory: true)
        let settingsURL = vscodeDir.appendingPathComponent("settings.json", isDirectory: false)

        // Read existing content or default to empty object (file missing only).
        let existingContent: String
        if fileSystem.fileExists(at: settingsURL) {
            do {
                let data = try fileSystem.readFile(at: settingsURL)
                guard let content = String(data: data, encoding: .utf8) else {
                    return .failure(PsCoreError(
                        message: "Failed to decode .vscode/settings.json as UTF-8 at \(settingsURL.path)."
                    ))
                }
                // Treat empty files the same as missing files.
                existingContent = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}\n" : content
            } catch {
                return .failure(PsCoreError(
                    message: "Failed to read existing .vscode/settings.json at \(settingsURL.path): \(error.localizedDescription)"
                ))
            }
        } else {
            existingContent = "{}\n"
        }

        let updatedContent: String
        switch Self.injectBlock(into: existingContent, identifier: identifier, color: color) {
        case .failure(let error):
            return .failure(error)
        case .success(let content):
            updatedContent = content
        }

        do {
            try fileSystem.createDirectory(at: vscodeDir)
            guard let data = updatedContent.data(using: .utf8) else {
                return .failure(PsCoreError(message: "Failed to encode settings.json content as UTF-8."))
            }
            try fileSystem.writeFile(at: settingsURL, data: data)
        } catch {
            return .failure(PsCoreError(message: "Failed to write .vscode/settings.json: \(error.localizedDescription)"))
        }

        return .success(())
    }

    // MARK: - Remote settings.json write (SSH)

    /// Writes the project-switcher block into a remote project's `.vscode/settings.json` via SSH.
    ///
    /// Strategy: read existing file via `cat`, inject block, base64-encode, write back via
    /// `base64 -d`. All commands use safe SSH flags (ConnectTimeout, BatchMode, `--` terminator).
    ///
    /// - Parameters:
    ///   - remoteAuthority: VS Code SSH remote authority (e.g., `ssh-remote+user@host`).
    ///   - remotePath: Remote absolute path to the project directory.
    ///   - identifier: Project identifier for the `PS:<id>` window title.
    ///   - color: Optional project color for VS Code color customizations.
    /// - Returns: Success or an error.
    func writeRemoteSettings(
        remoteAuthority: String,
        remotePath: String,
        identifier: String,
        color: String? = nil
    ) -> Result<Void, PsCoreError> {
        guard let commandRunner else {
            return .failure(PsCoreError(message: "Command runner not available for remote settings write"))
        }

        guard let sshTarget = PsSSHHelpers.extractTarget(from: remoteAuthority) else {
            return .failure(PsCoreError(message: "Malformed SSH remote authority: \(remoteAuthority)"))
        }

        let escapedProjectPath = PsSSHHelpers.shellEscape(remotePath)
        let settingsPath = "\(escapedProjectPath)/.vscode/settings.json"

        // Read existing remote settings.json (or default to empty if file missing).
        // Uses `test -f` to distinguish "file missing" from "permission denied" or other errors.
        // Also asserts the remote project directory exists to avoid creating incorrect paths.
        let readCommand = [
            "if [ ! -d \(escapedProjectPath) ]; then echo Remote project path missing: \(escapedProjectPath) 1>&2; exit 1; fi",
            "if [ -f \(settingsPath) ]; then cat \(settingsPath); else echo '{}'; fi"
        ].joined(separator: "; ")
        let readResult = commandRunner.run(
            executable: "ssh",
            arguments: [
                "-o", "ConnectTimeout=2",
                "-o", "BatchMode=yes",
                "--",
                sshTarget,
                readCommand
            ],
            timeoutSeconds: 3
        )

        let existingContent: String
        switch readResult {
        case .failure(let error):
            return .failure(PsCoreError(
                category: .command,
                message: "SSH read failed for remote settings.json: \(sshTarget) \(remotePath)\n\(error.message)"
            ))
        case .success(let result):
            if result.exitCode != 0 {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(PsCoreError(
                    category: .command,
                    message: "SSH read failed with exit code \(result.exitCode): \(sshTarget) \(remotePath)\(suffix)"
                ))
            }
            // Treat empty files the same as missing files.
            existingContent = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}\n" : result.stdout
        }

        // Inject block.
        let updatedContent: String
        switch Self.injectBlock(into: existingContent, identifier: identifier, color: color) {
        case .failure(let error):
            return .failure(error)
        case .success(let content):
            updatedContent = content
        }

        // Base64-encode and write.
        guard let data = updatedContent.data(using: .utf8) else {
            return .failure(PsCoreError(message: "Failed to encode settings.json as UTF-8"))
        }
        let base64 = data.base64EncodedString()

        // Defense-in-depth: base64 output is limited to [A-Za-z0-9+/=] and is safe to embed
        // inside single quotes. Keep this invariant if you change the encoding scheme.
        let writeCommand = "if [ ! -d \(escapedProjectPath) ]; then echo Remote project path missing: \(escapedProjectPath) 1>&2; exit 1; fi && mkdir -p \(escapedProjectPath)/.vscode && echo '\(base64)' | base64 -d > \(settingsPath)"
        let writeResult = commandRunner.run(
            executable: "ssh",
            arguments: [
                "-o", "ConnectTimeout=2",
                "-o", "BatchMode=yes",
                "--",
                sshTarget,
                writeCommand
            ],
            timeoutSeconds: 3
        )

        switch writeResult {
        case .failure(let error):
            return .failure(PsCoreError(
                category: .command,
                message: "SSH write failed for remote settings.json: \(sshTarget) \(remotePath)\n\(error.message)"
            ))
        case .success(let result):
            if result.exitCode != 0 {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(PsCoreError(
                    category: .command,
                    message: "SSH write failed with exit code \(result.exitCode): \(sshTarget) \(remotePath)\(suffix)"
                ))
            }
            return .success(())
        }
    }

    // MARK: - Ensure all settings blocks

    /// Writes the project-switcher settings.json block for all configured projects.
    ///
    /// For local projects, writes directly via the file system.
    /// For SSH projects, writes via SSH (requires `commandRunner` to be set).
    /// Each project is processed independently; failures do not affect other projects.
    ///
    /// - Parameter projects: All configured projects.
    /// - Returns: Per-project results keyed by project ID.
    @discardableResult
    func ensureAllSettingsBlocks(projects: [ProjectConfig]) -> [String: Result<Void, PsCoreError>] {
        var results: [String: Result<Void, PsCoreError>] = [:]

        for project in projects {
            if project.isSSH {
                guard let remote = project.remote else {
                    results[project.id] = .failure(PsCoreError(
                        message: "SSH project \(project.id) missing remote authority"
                    ))
                    continue
                }
                results[project.id] = writeRemoteSettings(
                    remoteAuthority: remote,
                    remotePath: project.path,
                    identifier: project.id,
                    color: project.color
                )
            } else {
                results[project.id] = writeLocalSettings(
                    projectPath: project.path,
                    identifier: project.id,
                    color: project.color
                )
            }
        }

        return results
    }
}

// MARK: - Public Convenience API

/// Proactively ensures the ProjectSwitcher-managed VS Code settings block exists for projects.
///
/// This is a public wrapper around internal settings management logic so the App/CLI can
/// trigger pre-flight settings writes without depending on internal types.
public enum VSCodeSettingsBlocks {
    /// Writes the ProjectSwitcher settings block into `.vscode/settings.json` for all projects.
    ///
    /// - Local projects: Writes via the local file system.
    /// - SSH projects: Writes via SSH (read → inject → base64 → write).
    ///
    /// - Parameter projects: Projects to process.
    /// - Returns: Per-project results keyed by project id.
    @discardableResult
    public static func ensureAll(projects: [ProjectConfig]) -> [String: Result<Void, PsCoreError>] {
        let runner = PsSystemCommandRunner()
        let manager = PsVSCodeSettingsManager(commandRunner: runner)
        return manager.ensureAllSettingsBlocks(projects: projects)
    }
}
