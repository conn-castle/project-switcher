import Foundation

// MARK: - Command Execution

/// Result of executing an external command.
struct PsCommandResult: Equatable, Sendable {
    /// Process termination status.
    let exitCode: Int32
    /// Captured standard output.
    let stdout: String
    /// Captured standard error.
    let stderr: String

    /// Creates a new command result.
    /// - Parameters:
    ///   - exitCode: Process termination status.
    ///   - stdout: Captured standard output.
    ///   - stderr: Captured standard error.
    init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Command execution interface for testability.
///
/// Production code uses `PsSystemCommandRunner`; tests can supply a mock.
protocol CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError>
}

extension CommandRunning {
    /// Convenience: default timeout, no working directory.
    func run(
        executable: String,
        arguments: [String]
    ) -> Result<PsCommandResult, PsCoreError> {
        run(executable: executable, arguments: arguments, timeoutSeconds: 5, workingDirectory: nil)
    }

    /// Convenience: explicit timeout, no working directory.
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?
    ) -> Result<PsCommandResult, PsCoreError> {
        run(executable: executable, arguments: arguments, timeoutSeconds: timeoutSeconds, workingDirectory: nil)
    }
}

/// Runs external commands with executable path resolution for GUI environments.
///
/// Child processes receive an augmented PATH that includes standard Homebrew/system
/// paths and the user's login shell PATH. This ensures tools like `al` (which internally
/// call `code`) can find executables even when launched from a GUI app with a minimal PATH.
///
/// The augmented environment is computed **once** on first use and cached globally.
/// This avoids spawning a login shell process for every instance — critical because
/// multiple components create their own `PsSystemCommandRunner` during app init on the
/// main thread. Without caching, each instance blocks the main thread for up to 7 seconds
/// while the login shell runs.
struct PsSystemCommandRunner: CommandRunning {
    private let executableResolver: ExecutableResolver

    /// Cached augmented environment — computed lazily on first access.
    ///
    /// The login shell PATH doesn't change during the app's lifetime. Computing it once
    /// (on the first `run()` call) eliminates the cost of spawning a login shell for each
    /// `PsSystemCommandRunner` instance. Uses Swift `static let` for thread-safe lazy
    /// initialization (`dispatch_once` under the hood).
    ///
    /// Important: this is NOT computed during `init()`. The first `run()` call triggers
    /// computation, which should always happen on a background thread.
    private static let cachedEnvironment: [String: String] = {
        buildAugmentedEnvironment(resolver: ExecutableResolver())
    }()

    /// Creates a command runner with the default executable resolver.
    ///
    /// Init is intentionally lightweight (no process spawning). The augmented PATH
    /// environment is computed lazily on the first `run()` call to avoid blocking
    /// the main thread during app startup.
    ///
    /// - Parameter executableResolver: Resolver for finding executable paths.
    init(executableResolver: ExecutableResolver = ExecutableResolver()) {
        self.executableResolver = executableResolver
    }

    /// Builds an environment dictionary with an augmented PATH for child processes.
    ///
    /// PATH is constructed by merging (in order, deduplicated):
    /// 1. Standard search paths (Homebrew ARM/Intel, system)
    /// 2. Login shell PATH (user's full PATH from their shell profile)
    /// 3. Current process PATH (inherited from parent)
    static func buildAugmentedEnvironment(resolver: ExecutableResolver) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""

        // Collect all PATH sources
        var allPaths: [String] = []

        // 1. Standard search paths first (ensures Homebrew is always available)
        allPaths.append(contentsOf: ExecutableResolver.standardSearchPaths)

        // 2. Login shell PATH (user's full profile PATH, including custom tools)
        if let shellPath = resolver.resolveLoginShellPath() {
            allPaths.append(contentsOf: shellPath.split(separator: ":").map(String.init))
        }

        // 3. Current process PATH (preserve anything already present)
        allPaths.append(contentsOf: currentPath.split(separator: ":").map(String.init))

        // Deduplicate while preserving order
        var seen = Set<String>()
        let deduped = allPaths.filter { path in
            guard !path.isEmpty else { return false }
            return seen.insert(path).inserted
        }

        env["PATH"] = deduped.joined(separator: ":")
        return env
    }

    /// Runs the provided executable with arguments.
    /// - Parameters:
    ///   - executable: Executable name to run.
    ///   - arguments: Arguments to pass to the executable.
    ///   - timeoutSeconds: Timeout in seconds. Defaults to 5s. Pass nil to wait indefinitely.
    ///   - workingDirectory: Optional working directory for the process.
    /// - Returns: Captured output on success, or an error.
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval? = 5,
        workingDirectory: String? = nil
    ) -> Result<PsCommandResult, PsCoreError> {
        // Resolve executable path for GUI environment
        guard let executablePath = executableResolver.resolve(executable) else {
            return .failure(PsCoreError(
                category: .command,
                message: "Executable not found: \(executable)",
                detail: "Searched: \(ExecutableResolver.standardSearchPaths.joined(separator: ", "))"
            ))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = Self.cachedEnvironment
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Collect output concurrently to avoid pipe buffer deadlock.
        // If we wait for termination before reading, and the process writes
        // more than the pipe buffer size (~64KB), it will block and never terminate.
        var stdoutData = Data()
        var stderrData = Data()
        let dataLock = NSLock()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        // Use semaphores to detect when each pipe has reached EOF.
        // This ensures we capture all data even for fast-completing processes.
        let stdoutEOF = DispatchSemaphore(value: 0)
        let stderrEOF = DispatchSemaphore(value: 0)

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stdoutEOF.signal()
            } else {
                dataLock.lock()
                stdoutData.append(data)
                dataLock.unlock()
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                stderrEOF.signal()
            } else {
                dataLock.lock()
                stderrData.append(data)
                dataLock.unlock()
            }
        }

        let completion = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            // Clean up handlers
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            return .failure(PsCoreError(message: "Failed to launch \(executable): \(error.localizedDescription)"))
        }

        // Wait for process with optional timeout
        let didTimeout: Bool
        let timeoutSecondsForMessage: TimeInterval?
        if let timeoutSeconds = timeoutSeconds {
            timeoutSecondsForMessage = timeoutSeconds
            let waitResult = completion.wait(timeout: .now() + timeoutSeconds)
            didTimeout = waitResult == .timedOut
            if didTimeout {
                process.terminate()
                _ = completion.wait(timeout: .now() + 1)
            }
        } else {
            timeoutSecondsForMessage = nil
            completion.wait()
            didTimeout = false
        }

        // Clean up immediately on timeout — we don't need the output
        if didTimeout {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
        } else {
            // Wait for both pipes to reach EOF to ensure all data is captured.
            // This prevents race conditions where fast processes terminate before
            // all output is read by the readabilityHandler.
            // Use a short fixed timeout: once the process exits, pipes should EOF
            // almost immediately. A 2s grace period handles edge cases without
            // doubling the caller's intended timeout.
            let pipeEOFTimeout: DispatchTimeInterval = .seconds(2)
            _ = stdoutEOF.wait(timeout: .now() + pipeEOFTimeout)
            _ = stderrEOF.wait(timeout: .now() + pipeEOFTimeout)
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
        }

        if didTimeout {
            let label = timeoutSecondsForMessage.map { "\($0)" } ?? "unknown"
            return .failure(
                PsCoreError(
                    category: .command,
                    message: "Command timed out after \(label)s: \(executable) \(arguments.joined(separator: " "))",
                    reason: .commandTimeout
                )
            )
        }

        guard let stdout = String(data: stdoutData, encoding: .utf8) else {
            return .failure(PsCoreError(message: "Command output was not valid UTF-8 (stdout)."))
        }

        guard let stderr = String(data: stderrData, encoding: .utf8) else {
            return .failure(PsCoreError(message: "Command output was not valid UTF-8 (stderr)."))
        }

        return .success(
            PsCommandResult(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        )
    }
}
