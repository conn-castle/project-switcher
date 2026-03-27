import Foundation

// MARK: - Executable Resolution

/// Resolves executable names to full paths for GUI app environments.
///
/// GUI applications on macOS do not inherit the user's shell PATH environment.
/// This resolver checks standard installation paths and falls back to a login
/// shell `which` lookup for non-standard locations.
struct ExecutableResolver {
    /// Structured logger for executable resolution events.
    private static let structuredLogger = ProjectSwitcherLogger()

    /// Standard search paths for macOS executables.
    static let standardSearchPaths: [String] = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/opt/homebrew/sbin",
        "/usr/local/sbin",
        "/usr/sbin",
        "/sbin"
    ]

    private let fileSystem: FileSystem
    private let searchPaths: [String]
    private let loginShellFallbackEnabled: Bool
    private let loginShellTimeoutSeconds: TimeInterval

    /// Whether a login-shell timeout value is valid (finite and positive).
    static func isValidLoginShellTimeout(_ timeout: TimeInterval) -> Bool {
        timeout.isFinite && timeout > 0
    }

    /// Creates an executable resolver.
    /// - Parameters:
    ///   - fileSystem: File system accessor for existence and executable checks.
    ///   - searchPaths: Paths to search for executables.
    ///   - loginShellFallbackEnabled: Whether to fall back to login shell `which` lookup. Default true.
    ///     Set to false in tests to control which executables are "found".
    ///   - loginShellTimeoutSeconds: Timeout for login shell commands. Default 5s.
    ///     Protects against slow shell init files. Pass a shorter value in tests.
    init(
        fileSystem: FileSystem = DefaultFileSystem(),
        searchPaths: [String] = ExecutableResolver.standardSearchPaths,
        loginShellFallbackEnabled: Bool = true,
        loginShellTimeoutSeconds: TimeInterval = 5
    ) {
        precondition(
            Self.isValidLoginShellTimeout(loginShellTimeoutSeconds),
            "loginShellTimeoutSeconds must be finite and positive, got \(loginShellTimeoutSeconds)"
        )
        self.fileSystem = fileSystem
        self.searchPaths = searchPaths
        self.loginShellFallbackEnabled = loginShellFallbackEnabled
        self.loginShellTimeoutSeconds = loginShellTimeoutSeconds
    }

    /// Resolves an executable name to its full path.
    /// - Parameter name: Executable name (e.g., "brew", "aerospace", "code").
    /// - Returns: Full path to executable, or nil if not found.
    func resolve(_ name: String) -> String? {
        // If already an absolute path, verify it exists and is executable
        if name.hasPrefix("/") {
            let url = URL(fileURLWithPath: name)
            if fileSystem.isExecutableFile(at: url) {
                return name
            }
            return nil
        }

        // Search standard paths
        for searchPath in searchPaths {
            let candidatePath = "\(searchPath)/\(name)"
            let candidateURL = URL(fileURLWithPath: candidatePath)
            if fileSystem.isExecutableFile(at: candidateURL) {
                return candidatePath
            }
        }

        // Fallback: try login shell which
        guard loginShellFallbackEnabled else { return nil }
        return resolveViaLoginShell(name)
    }

    /// Resolves the user's login shell PATH.
    ///
    /// Spawns a login shell to load the user's profile and capture the full PATH,
    /// including custom additions like Homebrew, nvm, pyenv, etc. This is needed
    /// because GUI apps inherit a minimal PATH that excludes most user-installed tools.
    ///
    /// Fish shell emits space-separated PATH entries via `echo $PATH`, so this method
    /// uses `string join : $PATH` for fish to produce colon-separated output directly.
    ///
    /// - Returns: The colon-separated PATH string from the login shell, or nil if
    ///   resolution fails or login shell fallback is disabled.
    func resolveLoginShellPath() -> String? {
        guard loginShellFallbackEnabled else { return nil }
        let command = Self.isFishShell ? "string join : $PATH" : "echo $PATH"
        return runLoginShellCommand(command)
    }

    /// Falls back to login shell `which` for non-standard locations.
    ///
    /// GUI apps have a minimal PATH. Using a login shell (`-l`) loads the user's
    /// shell profile (`.zshrc`, `.zprofile`, etc.) to get their full PATH including
    /// custom additions like Homebrew or tool-specific paths.
    ///
    /// - Parameter name: Executable name to resolve.
    /// - Returns: Full path from login shell, or nil if not found.
    private func resolveViaLoginShell(_ name: String) -> String? {
        runLoginShellCommand("which \(name)")
    }

    /// Detects the user's login shell from `$SHELL`, falling back to `/bin/zsh`.
    /// Validates that the value is an absolute path to avoid `Process(executableURL:)` failures.
    private static var loginShellPath: String {
        if let shell = ProcessInfo.processInfo.environment["SHELL"],
           shell.hasPrefix("/") {
            return shell
        }
        return "/bin/zsh"
    }

    /// Whether the detected login shell is fish.
    ///
    /// Fish shell uses space-separated PATH entries and requires different commands
    /// for PATH resolution (e.g., `string join : $PATH` instead of `echo $PATH`).
    static var isFishShell: Bool {
        loginShellPath.hasSuffix("/fish")
    }

    /// Runs a command in a login shell and returns the trimmed stdout.
    ///
    /// Uses the user's configured shell (from `$SHELL`) with a bounded timeout
    /// to avoid hangs from slow shell init files.
    private func runLoginShellCommand(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.loginShellPath)
        process.arguments = ["-l", "-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Read pipe data asynchronously to avoid blocking on background processes
        // that inherit the pipe's write-end file descriptor. Shell config files
        // (e.g., .zshrc sourcing `eval "$(tool init)"`) may spawn daemons that keep
        // the write end open after the shell exits, causing readDataToEndOfFile() to
        // block forever. Using readabilityHandler + EOF semaphore with a timeout
        // prevents this deadlock.
        var outputData = Data()
        let dataLock = NSLock()
        let eofSemaphore = DispatchSemaphore(value: 0)
        let handle = pipe.fileHandleForReading

        handle.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty {
                eofSemaphore.signal()
            } else {
                dataLock.lock()
                outputData.append(data)
                dataLock.unlock()
            }
        }

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            handle.readabilityHandler = nil
            _ = Self.structuredLogger.log(
                event: "executable_resolver.shell_launch_failed",
                level: .warn,
                message: "Login shell process failed to start",
                context: [
                    "command": command,
                    "shell": Self.loginShellPath,
                    "error": error.localizedDescription
                ]
            )
            return nil
        }

        let waitResult = completion.wait(timeout: .now() + loginShellTimeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 1)
        }

        // Wait for pipe EOF with a short timeout after process exits.
        // Background processes may keep the write end open, so don't wait forever.
        _ = eofSemaphore.wait(timeout: .now() + 2)
        handle.readabilityHandler = nil

        guard waitResult == .success else {
            _ = Self.structuredLogger.log(
                event: "executable_resolver.shell_timeout",
                level: .warn,
                message: "Login shell command timed out",
                context: [
                    "command": command,
                    "timeout_seconds": "\(loginShellTimeoutSeconds)",
                    "shell": Self.loginShellPath
                ]
            )
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        dataLock.lock()
        let capturedData = outputData
        dataLock.unlock()

        guard let output = String(data: capturedData, encoding: .utf8) else {
            return nil
        }

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
