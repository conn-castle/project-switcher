import Foundation

// MARK: - IDE Launchers

/// Shared IDE token prefix used to tag new IDE windows.
enum PsIdeToken {
    static let prefix = "PS:"

    /// Matches a leading project token without allowing project-ID prefix collisions.
    static func matches(windowTitle: String, projectId: String) -> Bool {
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = "\(prefix)\(projectId)"
        guard title.hasPrefix(token) else { return false }
        let suffix = title.dropFirst(token.count)
        return suffix.isEmpty || suffix.first?.isWhitespace == true
    }
}

/// Launches new VS Code windows with a tagged window title.
///
/// For local projects, injects an `PS:<id>` window title block into the project's
/// `.vscode/settings.json` and opens `code --new-window <projectPath>`.
///
/// For SSH projects, writes settings.json on the remote via SSH, then opens:
/// `code --new-window --remote <authority> <remotePath>`.
///
/// If remote settings.json cannot be written, the launch fails loudly (no workspace fallback).
struct PsVSCodeLauncher {
    /// VS Code bundle identifier used for filtering windows.
    static let bundleId = "com.microsoft.VSCode"

    private let commandRunner: CommandRunning
    private let settingsManager: PsVSCodeSettingsManager

    /// Creates a VS Code launcher.
    /// - Parameters:
    ///   - commandRunner: Command runner for launching VS Code and SSH commands.
    ///   - fileSystem: File system for settings.json I/O.
    ///   - settingsManager: Manager for .vscode/settings.json block injection.
    init(
        commandRunner: CommandRunning = PsSystemCommandRunner(),
        fileSystem: FileSystem = DefaultFileSystem(),
        settingsManager: PsVSCodeSettingsManager? = nil
    ) {
        self.commandRunner = commandRunner
        self.settingsManager = settingsManager ?? PsVSCodeSettingsManager(
            fileSystem: fileSystem,
            commandRunner: commandRunner
        )
    }

    /// Opens a new VS Code window with a tagged title for precise identification.
    ///
    /// - Parameters:
    ///   - identifier: Identifier embedded in the window title as `PS:<identifier>`.
    ///   - projectPath: Optional path to the project folder.
    ///     - Local projects: local absolute path.
    ///     - SSH projects: remote absolute path.
    ///   - remoteAuthority: Optional VS Code SSH remote authority (e.g., `ssh-remote+user@host`).
    ///     When set, requires SSH settings.json write to succeed (no workspace fallback).
    /// - Returns: Success or an error.
    func openNewWindow(
        identifier: String,
        projectPath: String? = nil,
        remoteAuthority: String? = nil,
        color: String? = nil
    ) -> Result<Void, PsCoreError> {
        let trimmedId = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            return .failure(PsCoreError(message: "Identifier cannot be empty."))
        }
        if trimmedId.contains("/") {
            return .failure(PsCoreError(message: "Identifier cannot contain '/'."))
        }

        guard let projectPath = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectPath.isEmpty else {
            return .failure(PsCoreError(message: "Project path is required for VS Code launch."))
        }

        // Decide strategy
        if let remoteAuthority = remoteAuthority?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteAuthority.isEmpty {
            // SSH project
            return openSSHWindow(
                identifier: trimmedId,
                remotePath: projectPath,
                remoteAuthority: remoteAuthority,
                color: color
            )
        }

        // Local project with path: use settings.json
        return openLocalWindow(identifier: trimmedId, projectPath: projectPath, color: color)
    }

    // MARK: - Local project

    private func openLocalWindow(
        identifier: String,
        projectPath: String,
        color: String? = nil
    ) -> Result<Void, PsCoreError> {
        switch settingsManager.writeLocalSettings(projectPath: projectPath, identifier: identifier, color: color) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        return launchCode(arguments: ["--new-window", projectPath])
    }

    // MARK: - SSH project

    private func openSSHWindow(
        identifier: String,
        remotePath: String,
        remoteAuthority: String,
        color: String? = nil
    ) -> Result<Void, PsCoreError> {
        // Write settings.json on the remote host. Without this, we cannot reliably tag the
        // window title for AeroSpace window identification.
        switch settingsManager.writeRemoteSettings(
            remoteAuthority: remoteAuthority,
            remotePath: remotePath,
            identifier: identifier,
            color: color
        ) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        return launchCode(arguments: [
            "--new-window",
            "--remote", remoteAuthority,
            remotePath
        ])
    }

    // MARK: - VS Code launch

    private func launchCode(arguments: [String]) -> Result<Void, PsCoreError> {
        switch commandRunner.run(executable: "code", arguments: arguments, timeoutSeconds: 10) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    PsCoreError(message: "code failed with exit code \(result.exitCode).\(suffix)")
                )
            }
            return .success(())
        }
    }
}

/// Launches new Chrome windows with a tagged window title.
struct PsChromeLauncher {
    /// Chrome bundle identifier used for filtering windows.
    static let bundleId = "com.google.Chrome"

    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = PsSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Opens a new Chrome window tagged with the provided identifier.
    /// - Parameters:
    ///   - identifier: Identifier embedded in the window title token.
    ///   - initialURLs: URLs to open in the new window. First URL becomes the active tab,
    ///     remaining URLs open as additional tabs. If empty, opens Chrome's default new tab page.
    /// - Returns: Success or an error.
    func openNewWindow(identifier: String, initialURLs: [String] = []) -> Result<Void, PsCoreError> {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(PsCoreError(message: "Identifier cannot be empty."))
        }
        if trimmed.contains("/") {
            return .failure(PsCoreError(message: "Identifier cannot contain '/'."))
        }

        let windowTitle = PsChromeLauncher.escapeForAppleScriptString("\(PsIdeToken.prefix)\(trimmed)")

        var scriptLines = [
            "tell application \"Google Chrome\"",
            "set newWindow to make new window",
            // Tag immediately. If a later URL/tab operation fails, the already-created
            // side-effect window remains discoverable and will not be duplicated by retry.
            "set given name of newWindow to \"\(windowTitle)\""
        ]

        if !initialURLs.isEmpty {
            // Set first URL on the active tab (replaces Chrome's default new tab page)
            let firstURL = PsChromeLauncher.escapeForAppleScriptString(initialURLs[0])
            scriptLines.append("set URL of active tab of newWindow to \"\(firstURL)\"")

            // Create additional tabs for remaining URLs
            for url in initialURLs.dropFirst() {
                let escapedURL = PsChromeLauncher.escapeForAppleScriptString(url)
                scriptLines.append("tell newWindow to make new tab with properties {URL:\"\(escapedURL)\"}")
            }
        }

        scriptLines.append("end tell")

        switch commandRunner.run(executable: "osascript", arguments: PsChromeLauncher.scriptArguments(lines: scriptLines), timeoutSeconds: 15) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    PsCoreError(
                        message: "osascript failed with exit code \(result.exitCode).\(suffix)"
                    )
                )
            }
            return .success(())
        }
    }

    /// Builds osascript arguments for a list of script lines.
    /// - Parameter lines: AppleScript lines to execute.
    /// - Returns: Arguments for osascript.
    private static func scriptArguments(lines: [String]) -> [String] {
        var args: [String] = []
        for line in lines {
            args.append("-e")
            args.append(line)
        }
        return args
    }

    /// Escapes a string for insertion into a double-quoted AppleScript string.
    /// - Parameter value: Raw value.
    /// - Returns: Escaped string.
    private static func escapeForAppleScriptString(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }
}

/// Launches VS Code for Agent Layer projects using a two-step approach.
///
/// Used for projects with `useAgentLayer = true`. Injects an `PS:<id>` window title
/// block into the project's `.vscode/settings.json`, then:
/// 1. Runs `al sync` with CWD = project path to regenerate agent layer config.
/// 2. Runs `al vscode --no-sync --new-window` (CWD = project path) to open VS Code with
///    Agent Layer environment variables (including `CODEX_HOME`) configured.
///
/// The project-switcher block coexists with agent-layer's own `// >>> agent-layer` block
/// since `al sync` preserves content outside its markers.
///
/// We intentionally do not pass a positional path to `al vscode`: agent-layer's VS Code
/// launcher appends "." to the `code` args. By setting CWD to the project path, "." maps
/// to the repo root and avoids opening two VS Code windows.
struct PsAgentLayerVSCodeLauncher {
    private let commandRunner: CommandRunning
    private let executableResolver: ExecutableResolver
    private let settingsManager: PsVSCodeSettingsManager

    /// Creates an Agent Layer VS Code launcher.
    /// - Parameters:
    ///   - commandRunner: Command runner for running `al sync` and `al vscode`.
    ///   - executableResolver: Resolver for finding the `al` executable.
    ///   - fileSystem: File system for settings.json I/O.
    ///   - settingsManager: Manager for .vscode/settings.json block injection.
    init(
        commandRunner: CommandRunning = PsSystemCommandRunner(),
        executableResolver: ExecutableResolver = ExecutableResolver(),
        fileSystem: FileSystem = DefaultFileSystem(),
        settingsManager: PsVSCodeSettingsManager? = nil
    ) {
        self.commandRunner = commandRunner
        self.executableResolver = executableResolver
        self.settingsManager = settingsManager ?? PsVSCodeSettingsManager(
            fileSystem: fileSystem,
            commandRunner: commandRunner
        )
    }

    /// Opens a new VS Code window through the Agent Layer.
    ///
    /// - Parameters:
    ///   - identifier: Project identifier embedded in the window title as `PS:<identifier>`.
    ///   - projectPath: Path to the project folder. Required for Agent Layer launch.
    ///   - remoteAuthority: Optional VS Code remote authority. Must be nil for Agent Layer launch.
    /// - Returns: Success or an error with a clear message.
    func openNewWindow(
        identifier: String,
        projectPath: String?,
        remoteAuthority: String? = nil,
        color: String? = nil
    ) -> Result<Void, PsCoreError> {
        if let remoteAuthority = remoteAuthority?.trimmingCharacters(in: .whitespacesAndNewlines),
           !remoteAuthority.isEmpty {
            return .failure(PsCoreError(message: "Agent Layer launch does not support SSH remote projects."))
        }

        guard let projectPath = projectPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !projectPath.isEmpty else {
            return .failure(PsCoreError(message: "Project path is required for Agent Layer launch."))
        }

        // Inject PS:<id> window title into .vscode/settings.json
        switch settingsManager.writeLocalSettings(projectPath: projectPath, identifier: identifier, color: color) {
        case .failure(let error):
            return .failure(error)
        case .success:
            break
        }

        guard let alPath = executableResolver.resolve("al") else {
            return .failure(PsCoreError(
                category: .command,
                message: "Agent Layer CLI (al) not found.",
                detail: "Install the Agent Layer CLI and ensure it is on your PATH."
            ))
        }

        // Step 1: Sync agent layer config.
        // workingDirectory is required: `al` needs the CWD to find `.agent-layer/` in the project.
        switch commandRunner.run(
            executable: alPath,
            arguments: ["sync"],
            timeoutSeconds: 30,
            workingDirectory: projectPath
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    PsCoreError(message: "al sync failed with exit code \(result.exitCode).\(suffix)")
                )
            }
        }

        // Step 2: Launch VS Code via Agent Layer so `CODEX_HOME` and AL_* env vars are set.
        // We avoid the `al vscode` dual-window bug by not passing a positional path. The
        // agent-layer launcher appends ".", and since we set CWD to projectPath, "." maps to it.
        guard executableResolver.resolve("code") != nil else {
            return .failure(PsCoreError(
                category: .command,
                message: "VS Code CLI (code) not found.",
                detail: "Install VS Code and ensure the 'code' command is on your PATH."
            ))
        }

        switch commandRunner.run(
            executable: alPath,
            arguments: ["vscode", "--no-sync", "--new-window"],
            timeoutSeconds: 10,
            workingDirectory: projectPath
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let trimmedStderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                let suffix = trimmedStderr.isEmpty ? "" : "\n\(trimmedStderr)"
                return .failure(
                    PsCoreError(message: "al vscode failed with exit code \(result.exitCode).\(suffix)")
                )
            }
            return .success(())
        }
    }
}
