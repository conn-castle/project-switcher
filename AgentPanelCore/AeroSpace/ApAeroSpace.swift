//
//  ApAeroSpace.swift
//  AgentPanelCore
//
//  CLI wrapper for the AeroSpace window manager.
//  Provides methods for installing, starting, and controlling AeroSpace,
//  including workspace management, window operations, and compatibility checks.
//

import Foundation
import os

/// Minimal window data returned by AeroSpace queries.
struct ApWindow: Equatable {
    /// AeroSpace window id.
    let windowId: Int
    /// App bundle identifier for the window.
    let appBundleId: String
    /// Workspace name for the window.
    let workspace: String
    /// Window title as reported by AeroSpace.
    let windowTitle: String
}

/// Workspace summary data returned by AeroSpace queries.
struct ApWorkspaceSummary: Equatable, Sendable {
    /// Workspace name.
    let workspace: String
    /// True when this workspace is focused.
    let isFocused: Bool
}

/// AeroSpace CLI wrapper for ap.
public struct ApAeroSpace {
    private static let logger = Logger(subsystem: "com.agentpanel", category: "ApAeroSpace")
    /// Structured logger for JSON log file events (complements os.Logger for triage).
    private static let structuredLogger = AgentPanelLogger()

    /// Default timeout for aerospace command execution.
    private static let defaultCommandTimeoutSeconds: TimeInterval = 5

    /// Cooldown between tree-node recovery reloads to avoid repeated
    /// `reload-config` in tight polling loops (e.g., `focusWindowStableSync`).
    private static let treeNodeReloadCooldownSeconds: TimeInterval = 5.0
    private static var lastTreeNodeReloadDate = Date.distantPast

    /// Recovery detail when hung-process termination fails.
    private static let recoveryTerminateFailedDetail =
        "AeroSpace process is running but unresponsive, and termination failed. Restart AeroSpace manually."

    /// Recovery detail when a checker cannot terminate a hung process.
    private static let recoveryTerminateUnsupportedDetail =
        "AeroSpace process is running but unresponsive, and the process checker cannot terminate it. Restart AeroSpace manually."

    /// Recovery detail when responsiveness probe fails without timing out.
    private static let recoveryProbeNonTimeoutFailureDetail =
        "AeroSpace responsiveness probe failed without timing out. Refusing automatic termination; restart AeroSpace manually."

    /// AeroSpace bundle identifier for Launch Services lookups.
    public static let bundleIdentifier = "bobko.aerospace"

    /// Legacy app path for fallback detection.
    private static let legacyAppPath = "/Applications/AeroSpace.app"

    /// Default maximum time to wait for AeroSpace to become ready after launch.
    public static let defaultStartupTimeoutSeconds: TimeInterval = 10.0

    /// Default interval between readiness checks during startup.
    public static let defaultReadinessCheckInterval: TimeInterval = 0.25

    let startupTimeoutSeconds: TimeInterval
    let readinessCheckInterval: TimeInterval

    private let transport: AeroSpaceCommandTransport
    private let appDiscovery: AppDiscovering
    private let fileSystem: FileSystem
    private let processChecker: RunningApplicationChecking?

    /// Convenience accessors for shared dependencies.
    private var commandRunner: CommandRunning { transport.commandRunner }
    private var circuitBreaker: AeroSpaceCircuitBreaker { transport.circuitBreaker }
    /// Test seam: true when this wrapper is wired to the shared circuit breaker.
    var usesSharedCircuitBreaker: Bool { circuitBreaker === AeroSpaceCircuitBreaker.shared }

    /// Creates a new AeroSpace wrapper with default dependencies.
    /// - Parameters:
    ///   - processChecker: Optional process checker for auto-recovery.
    ///     When provided and the circuit breaker is open, the wrapper will
    ///     probe AeroSpace responsiveness directly. Responsive processes skip
    ///     restart; running+unresponsive processes attempt termination before
    ///     restart. If the checker cannot terminate, recovery fails fast for
    ///     hung-process cases.
    ///     Pass `nil` to disable auto-recovery (e.g., for Doctor diagnostics).
    ///   - startupTimeoutSeconds: Maximum time to wait for readiness after launch.
    ///   - readinessCheckInterval: Interval between readiness checks during startup.
    public init(
        processChecker: RunningApplicationChecking? = nil,
        startupTimeoutSeconds: TimeInterval = defaultStartupTimeoutSeconds,
        readinessCheckInterval: TimeInterval = defaultReadinessCheckInterval
    ) {
        precondition(startupTimeoutSeconds.isFinite, "startupTimeoutSeconds must be finite")
        precondition(readinessCheckInterval.isFinite, "readinessCheckInterval must be finite")
        precondition(startupTimeoutSeconds > 0, "startupTimeoutSeconds must be positive")
        precondition(readinessCheckInterval > 0, "readinessCheckInterval must be positive")
        precondition(readinessCheckInterval < startupTimeoutSeconds, "readinessCheckInterval must be less than startupTimeoutSeconds")

        self.transport = AeroSpaceCommandTransport(
            commandRunner: ApSystemCommandRunner(),
            circuitBreaker: .shared
        )
        self.appDiscovery = LaunchServicesAppDiscovery()
        self.fileSystem = DefaultFileSystem()
        self.processChecker = processChecker
        self.startupTimeoutSeconds = startupTimeoutSeconds
        self.readinessCheckInterval = readinessCheckInterval
    }

    /// Creates a new AeroSpace wrapper with custom dependencies.
    /// - Parameters:
    ///   - commandRunner: Command runner for CLI operations.
    ///   - appDiscovery: App discovery for installation checks.
    ///   - fileSystem: File system for path checks.
    ///   - circuitBreaker: Circuit breaker for timeout cascade prevention.
    ///   - processChecker: Optional process checker for auto-recovery.
    ///     When provided and the circuit breaker is open, recovery probes
    ///     responsiveness directly. Responsive processes skip restart;
    ///     running+unresponsive processes attempt termination before restart.
    ///     If the checker cannot terminate, recovery fails fast for
    ///     hung-process cases.
    ///   - startupTimeoutSeconds: Maximum time to wait for readiness after launch.
    ///   - readinessCheckInterval: Interval between readiness checks during startup.
    init(
        commandRunner: CommandRunning,
        appDiscovery: AppDiscovering,
        fileSystem: FileSystem = DefaultFileSystem(),
        circuitBreaker: AeroSpaceCircuitBreaker = .shared,
        processChecker: RunningApplicationChecking? = nil,
        startupTimeoutSeconds: TimeInterval = defaultStartupTimeoutSeconds,
        readinessCheckInterval: TimeInterval = defaultReadinessCheckInterval
    ) {
        precondition(startupTimeoutSeconds.isFinite, "startupTimeoutSeconds must be finite")
        precondition(readinessCheckInterval.isFinite, "readinessCheckInterval must be finite")
        precondition(startupTimeoutSeconds > 0, "startupTimeoutSeconds must be positive")
        precondition(readinessCheckInterval > 0, "readinessCheckInterval must be positive")
        precondition(readinessCheckInterval < startupTimeoutSeconds, "readinessCheckInterval must be less than startupTimeoutSeconds")

        self.transport = AeroSpaceCommandTransport(
            commandRunner: commandRunner,
            circuitBreaker: circuitBreaker
        )
        self.appDiscovery = appDiscovery
        self.fileSystem = fileSystem
        self.processChecker = processChecker
        self.startupTimeoutSeconds = startupTimeoutSeconds
        self.readinessCheckInterval = readinessCheckInterval
    }

    /// Returns the path to AeroSpace.app if installed.
    /// Uses Launch Services to find the app by bundle ID, with fallback to legacy path.
    var appPath: String? {
        // Try Launch Services first (handles all install locations)
        if let url = appDiscovery.applicationURL(bundleIdentifier: Self.bundleIdentifier) {
            return url.path
        }
        // Fallback for edge cases where Launch Services hasn't indexed yet
        let legacyURL = URL(fileURLWithPath: Self.legacyAppPath, isDirectory: true)
        if fileSystem.directoryExists(at: legacyURL) {
            return Self.legacyAppPath
        }
        return nil
    }

    // MARK: - App Lifecycle

    /// Installs AeroSpace via Homebrew.
    /// - Returns: Success or an error.
    public func installViaHomebrew() -> Result<Void, ApCoreError> {
        switch commandRunner.run(
            executable: "brew",
            arguments: ["install", "--cask", "nikitabobko/tap/aerospace"],
            timeoutSeconds: 300
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("brew install --cask nikitabobko/tap/aerospace", result: result))
            }
            return .success(())
        }
    }

    /// Starts the AeroSpace application.
    /// - Returns: Success or an error.
    public func start() -> Result<Void, ApCoreError> {
        guard !Thread.isMainThread else {
            return .failure(
                ApCoreError(
                    category: .command,
                    message: "AeroSpace start must run off the main thread."
                )
            )
        }

        switch commandRunner.run(executable: "open", arguments: ["-a", "AeroSpace"], timeoutSeconds: 10) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("open -a AeroSpace", result: result))
            }
            // Fresh start outside recovery clears breaker state.
            // During recovery, preserve in-progress tracking until endRecovery.
            if !circuitBreaker.isRecoveryInProgress {
                circuitBreaker.reset()
            }
            // Poll for readiness instead of fixed sleep
            return waitForReadiness()
        }
    }

    /// Waits for AeroSpace CLI to become responsive after launch.
    /// - Returns: Success when CLI is available, or an error on timeout.
    private func waitForReadiness() -> Result<Void, ApCoreError> {
        let deadline = Date().addingTimeInterval(startupTimeoutSeconds)

        while Date() < deadline {
            // During recovery, avoid re-entering recovery orchestration from readiness probes.
            let ready = circuitBreaker.isRecoveryInProgress
                ? isCliReadyOffBreakerProbe()
                : isCliAvailable()
            if ready {
                return .success(())
            }
            Thread.sleep(forTimeInterval: readinessCheckInterval)
        }

        return .failure(ApCoreError(
            category: .command,
            message: "AeroSpace did not become ready within \(startupTimeoutSeconds)s after launch."
        ))
    }

    /// Reloads the AeroSpace configuration.
    /// - Returns: Success or an error.
    public func reloadConfig() -> Result<Void, ApCoreError> {
        switch runAerospace(arguments: ["reload-config"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace reload-config", result: result))
            }
            return .success(())
        }
    }

    /// Returns true when AeroSpace.app is installed.
    /// - Returns: True if AeroSpace.app exists on disk.
    public func isAppInstalled() -> Bool {
        appPath != nil
    }

    /// Returns true when the aerospace CLI is available on PATH.
    /// - Returns: True if `aerospace --help` succeeds.
    public func isCliAvailable() -> Bool {
        switch runAerospace(arguments: ["--help"], timeoutSeconds: 2) {
        case .failure:
            return false
        case .success(let result):
            return result.exitCode == 0
        }
    }

    // MARK: - Compatibility

    /// Checks whether the installed aerospace CLI supports required commands and flags.
    /// - Returns: Success when compatible, or an error describing missing support.
    func checkCompatibility() -> Result<Void, ApCoreError> {
        let checks: [(command: String, requiredFlags: [String])] = [
            ("list-workspaces", ["--all", "--focused"]),
            ("list-windows", ["--monitor", "--workspace", "--focused", "--app-bundle-id", "--format"]),
            ("summon-workspace", []),
            ("move-node-to-workspace", ["--window-id"]),
            ("focus", ["--window-id", "--boundaries", "--boundaries-action", "dfs-next", "dfs-prev"]),
            ("close", ["--window-id"])
        ]

        let lock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: checks.count) { index in
            let check = checks[index]
            var localFailure: String?

            switch commandHelpOutput(command: check.command) {
            case .failure(let error):
                localFailure = "aerospace \(check.command) --help failed: \(error.message)"
            case .success(let output):
                let missing = check.requiredFlags.filter { !output.contains($0) }
                if !missing.isEmpty {
                    localFailure = "aerospace \(check.command) missing flags: \(missing.joined(separator: ", "))"
                }
            }

            if let failure = localFailure {
                lock.lock()
                failures.append(failure)
                lock.unlock()
            }
        }

        guard failures.isEmpty else {
            // Sort for deterministic output regardless of concurrent execution order
            let sorted = failures.sorted()
            return .failure(
                ApCoreError(
                    category: .validation,
                    message: "AeroSpace CLI compatibility check failed.",
                    detail: sorted.joined(separator: "\n")
                )
            )
        }

        return .success(())
    }

    // MARK: - Workspaces

    /// Returns a list of focused AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    func listWorkspacesFocused() -> Result<[String], ApCoreError> {
        switch runAerospace(arguments: ["list-workspaces", "--focused"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-workspaces --focused", result: result))
            }

            let workspaces = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return .success(workspaces)
        }
    }

    /// Returns a list of AeroSpace workspaces.
    /// - Returns: Workspace names on success, or an error.
    func getWorkspaces() -> Result<[String], ApCoreError> {
        switch runAerospace(arguments: ["list-workspaces", "--all"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-workspaces --all", result: result))
            }

            let workspaces = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return .success(workspaces)
        }
    }

    /// Returns all AeroSpace workspaces with focus metadata in a single query.
    /// - Returns: Workspace summaries on success, or an error.
    func listWorkspacesWithFocus() -> Result<[ApWorkspaceSummary], ApCoreError> {
        switch runAerospace(
            arguments: ["list-workspaces", "--all", "--format", "%{workspace}||%{workspace-is-focused}"]
        ) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(
                    commandError(
                        "aerospace list-workspaces --all --format %{workspace}||%{workspace-is-focused}",
                        result: result
                    )
                )
            }
            return parseWorkspaceSummaries(output: result.stdout)
        }
    }

    /// Checks whether a workspace name exists.
    /// - Parameter name: Workspace name to look up.
    /// - Returns: True if the workspace exists, or an error.
    func workspaceExists(_ name: String) -> Result<Bool, ApCoreError> {
        switch getWorkspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let workspaces):
            return .success(workspaces.contains(name))
        }
    }

    /// Creates a new workspace with the provided name.
    /// - Parameter name: Workspace name to create.
    /// - Returns: Success or an error.
    func createWorkspace(_ name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }

        switch workspaceExists(trimmed) {
        case .failure(let error):
            return .failure(error)
        case .success(true):
            return .failure(validationError("Workspace already exists: \(trimmed)"))
        case .success(false):
            break
        }

        switch runAerospace(arguments: ["summon-workspace", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace summon-workspace \(trimmed)", result: result))
            }
            return .success(())
        }
    }

    /// Closes all windows in the provided workspace.
    /// - Parameter name: Workspace name to close windows in.
    /// - Returns: Success or an error.
    func closeWorkspace(name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }

        switch listWindowsWorkspace(workspace: trimmed) {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            var failedIds: [Int] = []
            var failureDetails: [String] = []

            for window in windows {
                switch closeWindow(windowId: window.windowId) {
                case .failure(let error):
                    failedIds.append(window.windowId)
                    failureDetails.append("window \(window.windowId): \(error.message)")
                case .success:
                    continue
                }
            }

            // If first pass had failures, re-query and retry IDs still present.
            if !failedIds.isEmpty {
                let remainingIds: Set<Int>
                switch listWindowsWorkspace(workspace: trimmed) {
                case .failure:
                    // Re-query failed — return original first-pass error with window IDs.
                    return .failure(
                        ApCoreError(
                            category: .command,
                            message: "Failed to close \(failedIds.count) windows in workspace \(trimmed): \(failedIds).",
                            detail: failureDetails.joined(separator: "\n")
                        )
                    )
                case .success(let currentWindows):
                    remainingIds = Set(currentWindows.map(\.windowId))
                }

                // Retry only IDs that are still present (transient misses will have disappeared).
                let retryIds = failedIds.filter { remainingIds.contains($0) }
                failedIds = []
                failureDetails = []

                for windowId in retryIds {
                    switch closeWindow(windowId: windowId) {
                    case .failure(let error):
                        failedIds.append(windowId)
                        failureDetails.append("window \(windowId): \(error.message)")
                    case .success:
                        continue
                    }
                }
            }

            guard failedIds.isEmpty else {
                return .failure(
                    ApCoreError(
                        category: .command,
                        message: "Failed to close \(failedIds.count) windows in workspace \(trimmed): \(failedIds).",
                        detail: failureDetails.joined(separator: "\n")
                    )
                )
            }

            return .success(())
        }
    }

    // MARK: - Workspace Focus

    /// Focuses a workspace by name.
    ///
    /// Uses `summon-workspace` (preferred, pulls workspace to current monitor) with
    /// fallback to `workspace` (switches to workspace wherever it is).
    ///
    /// - Parameter name: Workspace name to focus.
    /// - Returns: Success or an error.
    func focusWorkspace(name: String) -> Result<Void, ApCoreError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }

        // Try summon-workspace first (preferred for multi-monitor)
        let summonResult = runAerospace(arguments: ["summon-workspace", trimmed])
        if !Self.shouldAttemptCompatibilityFallback(summonResult) {
            switch summonResult {
            case .success(let result):
                if result.exitCode == 0 {
                    return .success(())
                }
                return .failure(commandError("aerospace summon-workspace \(trimmed)", result: result))
            case .failure(let error):
                return .failure(error)
            }
        }

        // Fallback to workspace command
        switch runAerospace(arguments: ["workspace", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace workspace \(trimmed)", result: result))
            }
            return .success(())
        }
    }

    // MARK: - Windows

    /// Returns windows for the given app across all monitors.
    ///
    /// Searches globally first (no `--monitor` flag). If that fails (older AeroSpace builds),
    /// falls back to `--monitor focused`. This is the one exception to the "prefer scoped
    /// queries" guidance — tagged-window resolution needs global scope.
    ///
    /// - Parameter bundleId: App bundle identifier to filter.
    /// - Returns: Window list or an error.
    func listWindowsForApp(bundleId: String) -> Result<[ApWindow], ApCoreError> {
        // Preferred: global search (no --monitor flag)
        let globalResult = runAerospace(arguments: [
            "list-windows",
            "--app-bundle-id",
            bundleId,
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ])
        if !Self.shouldAttemptCompatibilityFallback(globalResult) {
            switch globalResult {
            case .success(let result):
                if result.exitCode == 0 {
                    return parseWindowSummaries(output: result.stdout)
                }
                return .failure(commandError("aerospace list-windows --app-bundle-id \(bundleId)", result: result))
            case .failure(let error):
                return .failure(error)
            }
        }

        // Fallback: focused monitor only
        return listWindowsOnFocusedMonitor(appBundleId: bundleId)
    }

    /// Moves a window into the provided workspace.
    /// - Parameters:
    ///   - workspace: Destination workspace name.
    ///   - windowId: AeroSpace window id to move.
    ///   - focusFollows: When true, includes `--focus-follows-window` so focus moves
    ///     with the window into the target workspace. Falls back to a plain move if
    ///     the flag is not supported.
    /// - Returns: Success or an error.
    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool = false) -> Result<Void, ApCoreError> {
        let trimmed = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(validationError("Workspace name cannot be empty."))
        }
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        if focusFollows {
            // Try with --focus-follows-window first; fall back to plain move
            let focusFollowsResult = runAerospace(
                arguments: ["move-node-to-workspace", "--focus-follows-window", "--window-id", "\(windowId)", trimmed]
            )
            if !Self.shouldAttemptCompatibilityFallback(focusFollowsResult) {
                switch focusFollowsResult {
                case .success(let result):
                    if result.exitCode == 0 {
                        return .success(())
                    }
                    return .failure(
                        commandError(
                            "aerospace move-node-to-workspace --focus-follows-window --window-id \(windowId) \(trimmed)",
                            result: result
                        )
                    )
                case .failure(let error):
                    return .failure(error)
                }
            }
        }

        switch runAerospace(arguments: ["move-node-to-workspace", "--window-id", "\(windowId)", trimmed]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace move-node-to-workspace --window-id \(windowId) \(trimmed)", result: result))
            }
            return .success(())
        }
    }

    /// Focuses a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to focus.
    /// - Returns: Success or an error.
    func focusWindow(windowId: Int) -> Result<Void, ApCoreError> {
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        switch runAerospace(arguments: ["focus", "--window-id", "\(windowId)"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                let error = commandError("aerospace focus --window-id \(windowId)", result: result)
                // AeroSpace may crash in makeFloatingWindowsSeenAsTiling with
                // "MacWindow is already unbound" due to stale tree nodes after
                // workspace closure or monitor changes. Reload config to flush
                // the stale state, then retry the focus once.
                if error.isAeroSpaceTreeNodeError,
                   Date().timeIntervalSince(Self.lastTreeNodeReloadDate) >= Self.treeNodeReloadCooldownSeconds {
                    Self.lastTreeNodeReloadDate = Date()
                    Self.logger.warning("Tree-node error focusing window \(windowId), retrying after reload-config")
                    _ = Self.structuredLogger.log(
                        event: "aerospace.focus_window.tree_node_error",
                        level: .warn,
                        message: "AeroSpace tree-node error, retrying after config reload",
                        context: ["window_id": "\(windowId)"]
                    )
                    _ = reloadConfig()
                    switch runAerospace(arguments: ["focus", "--window-id", "\(windowId)"]) {
                    case .failure(let retryError):
                        return .failure(retryError)
                    case .success(let retryResult):
                        guard retryResult.exitCode == 0 else {
                            return .failure(commandError("aerospace focus --window-id \(windowId)", result: retryResult))
                        }
                        return .success(())
                    }
                }
                return .failure(error)
            }
            return .success(())
        }
    }

    /// Returns windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listWindowsFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--monitor",
            "focused",
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --monitor focused", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns windows on the focused monitor filtered by app bundle id.
    /// - Parameter appBundleId: App bundle identifier to filter.
    /// - Returns: Window list or an error.
    func listWindowsOnFocusedMonitor(appBundleId: String) -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--monitor",
            "focused",
            "--app-bundle-id",
            appBundleId,
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --monitor focused --app-bundle-id \(appBundleId)", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns VS Code windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listVSCodeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        listWindowsOnFocusedMonitor(appBundleId: ApVSCodeLauncher.bundleId)
    }

    /// Returns Chrome windows on the focused monitor.
    /// - Returns: Window list or an error.
    func listChromeWindowsOnFocusedMonitor() -> Result<[ApWindow], ApCoreError> {
        listWindowsOnFocusedMonitor(appBundleId: ApChromeLauncher.bundleId)
    }

    /// Returns the currently focused window.
    /// - Returns: Focused window or an error.
    func focusedWindow() -> Result<ApWindow, ApCoreError> {
        switch listWindowsFocused() {
        case .failure(let error):
            return .failure(error)
        case .success(let windows):
            guard windows.count == 1, let window = windows.first else {
                return .failure(
                    ApCoreError(
                        category: .parse,
                        message: "Expected exactly one focused window, found \(windows.count)."
                    )
                )
            }
            return .success(window)
        }
    }

    /// Returns windows for the given workspace.
    /// - Parameter workspace: Workspace name to query.
    /// - Returns: Window list or an error.
    func listWindowsWorkspace(workspace: String) -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--workspace",
            workspace,
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --workspace \(workspace)", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Returns all windows across all workspaces.
    /// - Returns: Combined window list from all workspaces, or an error.
    func listAllWindows() -> Result<[ApWindow], ApCoreError> {
        let workspaces: [String]
        switch getWorkspaces() {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            workspaces = result
        }

        var allWindows: [ApWindow] = []
        for workspace in workspaces {
            switch listWindowsWorkspace(workspace: workspace) {
            case .success(let windows):
                allWindows.append(contentsOf: windows)
            case .failure(let error):
                // Propagate infrastructure errors immediately; skip transient workspace errors
                if error.reason == .circuitBreakerOpen || error.isCommandTimeout {
                    return .failure(error)
                }
                continue
            }
        }
        return .success(allWindows)
    }

    // MARK: - Circuit Breaker

    /// Runs an aerospace CLI command with circuit breaker protection and auto-recovery.
    ///
    /// Checks the breaker before spawning a process. If AeroSpace is unresponsive
    /// (breaker open), returns a descriptive error immediately instead of waiting
    /// for a 5s timeout. After the call, records the outcome so that a timeout
    /// trips the breaker for subsequent calls.
    ///
    /// When a `processChecker` is available and the breaker is open, automatically
    /// attempts to recover AeroSpace (up to 2 attempts). If the process is
    /// running, a direct probe (outside breaker gating) checks responsiveness.
    /// Responsive probes skip restart and retry the original command directly.
    /// Only timeout-class probe failures are treated as hung-process signals
    /// and may trigger termination before restart.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to pass to the `aerospace` executable.
    ///   - timeoutSeconds: Timeout in seconds. Defaults to 5s.
    /// - Returns: Command result on success, or an error.
    private func runAerospace(
        arguments: [String],
        timeoutSeconds: TimeInterval = ApAeroSpace.defaultCommandTimeoutSeconds
    ) -> Result<ApCommandResult, ApCoreError> {
        if transport.shouldAllow() {
            return transport.executeAndRecord(arguments: arguments, timeoutSeconds: timeoutSeconds)
        }

        // Breaker is open — attempt auto-recovery if process checker is available
        if let checker = processChecker,
           circuitBreaker.beginRecovery() {
            let terminatingChecker = checker as? (RunningApplicationChecking & RunningApplicationTerminating)
            let thread = Thread.isMainThread ? "main" : "background"
            Self.logger.info("circuit_breaker.recovery_started thread=\(thread, privacy: .public)")
            Self.logRecoveryEvent(
                "circuit_breaker.recovery_started",
                message: "Auto-recovery initiated for unresponsive AeroSpace",
                context: ["thread": thread]
            )
            if Thread.isMainThread {
                // Main thread: fire-and-forget recovery in the background, fail fast now.
                // start() blocks for up to ~10s (open + readiness poll) — unacceptable on main.
                // The next off-main call will benefit from the recovered state.
                //
                // Extract reference-type dependencies into local bindings before the
                // @Sendable closure to avoid capturing non-Sendable self (a struct).
                let recoveryCommandRunner = commandRunner
                let recoveryCircuitBreaker = circuitBreaker
                let recoveryStartupTimeout = startupTimeoutSeconds
                let recoveryReadinessInterval = readinessCheckInterval
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.performBackgroundBreakerRecovery(
                        commandRunner: recoveryCommandRunner,
                        circuitBreaker: recoveryCircuitBreaker,
                        processChecker: checker,
                        terminatingChecker: terminatingChecker,
                        startupTimeoutSeconds: recoveryStartupTimeout,
                        readinessCheckInterval: recoveryReadinessInterval
                    )
                }
            } else {
                switch Self.prepareForRecoveryStart(
                    commandRunner: commandRunner,
                    processChecker: checker,
                    terminatingChecker: terminatingChecker
                ) {
                case .readyToRestart:
                    break
                case .recoveredWithoutRestart:
                    Self.logger.info("circuit_breaker.recovery_succeeded_without_restart")
                    Self.logRecoveryEvent(
                        "circuit_breaker.recovery_succeeded",
                        message: "AeroSpace responded to probe — recovered without restart",
                        context: ["method": "probe_only"]
                    )
                    circuitBreaker.endRecovery(success: true)
                    return transport.executeAndRecord(arguments: arguments, timeoutSeconds: timeoutSeconds)
                case .failed(let detail):
                    Self.logger.warning("circuit_breaker.recovery_failed reason=prepare_failed detail=\(detail, privacy: .public)")
                    Self.logRecoveryEvent(
                        "circuit_breaker.recovery_failed",
                        level: .error,
                        message: "Recovery preparation failed",
                        context: ["reason": "prepare_failed", "detail": detail]
                    )
                    circuitBreaker.endRecovery(success: false)
                    return .failure(transport.breakerOpenError(detailOverride: detail))
                }

                // Off-main: recover synchronously and retry the command.
                switch start() {
                case .success:
                    Self.logger.info("circuit_breaker.recovery_succeeded")
                    Self.logRecoveryEvent(
                        "circuit_breaker.recovery_succeeded",
                        message: "AeroSpace restarted successfully",
                        context: ["method": "restart"]
                    )
                    circuitBreaker.endRecovery(success: true)
                    return transport.executeAndRecord(arguments: arguments, timeoutSeconds: timeoutSeconds)
                case .failure:
                    Self.logger.warning("circuit_breaker.recovery_failed")
                    Self.logRecoveryEvent(
                        "circuit_breaker.recovery_failed",
                        level: .error,
                        message: "AeroSpace restart failed",
                        context: ["method": "restart"]
                    )
                    circuitBreaker.endRecovery(success: false)
                }
            }
        }

        return .failure(transport.breakerOpenError())
    }

    // MARK: - Private Helpers

    /// Returns windows scoped to the focused window query.
    /// - Returns: Window list or an error.
    private func listWindowsFocused() -> Result<[ApWindow], ApCoreError> {
        switch runAerospace(arguments: [
            "list-windows",
            "--focused",
            "--format",
            "%{window-id}||%{app-bundle-id}||%{workspace}||%{window-title}"
        ]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace list-windows --focused", result: result))
            }
            return parseWindowSummaries(output: result.stdout)
        }
    }

    /// Closes a window by its AeroSpace window id.
    /// - Parameter windowId: AeroSpace window id to close.
    /// - Returns: Success or an error.
    private func closeWindow(windowId: Int) -> Result<Void, ApCoreError> {
        guard windowId > 0 else {
            return .failure(validationError("Window ID must be positive."))
        }

        switch runAerospace(arguments: ["close", "--window-id", "\(windowId)"]) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace close --window-id \(windowId)", result: result))
            }
            return .success(())
        }
    }

    private func parseWindowSummaries(output: String) -> Result<[ApWindow], ApCoreError> {
        AeroSpaceParser.parseWindowSummaries(output: output)
    }

    private func parseWorkspaceSummaries(output: String) -> Result<[ApWorkspaceSummary], ApCoreError> {
        AeroSpaceParser.parseWorkspaceSummaries(output: output)
    }

    /// Recovery preparation state before attempting `start()`.
    private enum RecoveryPreparationResult {
        /// Recovery requires a restart attempt.
        case readyToRestart
        /// Recovery succeeded without a restart attempt.
        case recoveredWithoutRestart
        /// Recovery cannot proceed and should fail fast with the provided detail.
        case failed(detail: String)
    }

    /// Direct recovery probe outcome for running AeroSpace processes.
    private enum RecoveryProbeResult {
        /// Daemon responded successfully.
        case responsive
        /// Probe failed due to command timeout (hung-process signal).
        case timedOut
        /// Probe failed for a non-timeout reason and should not trigger termination.
        case failed(detail: String)
    }

    /// Performs circuit-breaker recovery on a background queue.
    ///
    /// Static to avoid capturing non-Sendable `ApAeroSpace` (a struct) in the
    /// `@Sendable` GCD closure. Only reference-type dependencies (which handle
    /// their own synchronization) and value-type parameters are passed in.
    private static func performBackgroundBreakerRecovery(
        commandRunner: CommandRunning,
        circuitBreaker: AeroSpaceCircuitBreaker,
        processChecker: RunningApplicationChecking,
        terminatingChecker: (RunningApplicationChecking & RunningApplicationTerminating)?,
        startupTimeoutSeconds: TimeInterval,
        readinessCheckInterval: TimeInterval
    ) {
        switch prepareForRecoveryStart(
            commandRunner: commandRunner,
            processChecker: processChecker,
            terminatingChecker: terminatingChecker
        ) {
        case .readyToRestart:
            break
        case .recoveredWithoutRestart:
            logger.info("circuit_breaker.recovery_succeeded_without_restart")
            logRecoveryEvent(
                "circuit_breaker.recovery_succeeded",
                message: "AeroSpace responded to probe — recovered without restart (background)",
                context: ["method": "probe_only", "thread": "background"]
            )
            circuitBreaker.endRecovery(success: true)
            return
        case .failed(let detail):
            logger.warning("circuit_breaker.recovery_failed reason=prepare_failed detail=\(detail, privacy: .public)")
            logRecoveryEvent(
                "circuit_breaker.recovery_failed",
                level: .error,
                message: "Recovery preparation failed (background)",
                context: ["reason": "prepare_failed", "detail": detail, "thread": "background"]
            )
            circuitBreaker.endRecovery(success: false)
            return
        }

        // Start AeroSpace and wait for readiness (recovery-specific path).
        // Uses off-breaker probes since circuitBreaker.isRecoveryInProgress is true.
        switch commandRunner.run(executable: "open", arguments: ["-a", "AeroSpace"], timeoutSeconds: 10) {
        case .failure(let error):
            logger.warning("circuit_breaker.recovery_failed")
            logRecoveryEvent(
                "circuit_breaker.recovery_failed",
                level: .error,
                message: "AeroSpace launch command failed (background)",
                context: ["reason": "launch_failed", "detail": error.message, "thread": "background"]
            )
            circuitBreaker.endRecovery(success: false)
            return
        case .success(let result):
            guard result.exitCode == 0 else {
                logger.warning("circuit_breaker.recovery_failed")
                logRecoveryEvent(
                    "circuit_breaker.recovery_failed",
                    level: .error,
                    message: "AeroSpace launch exited with non-zero code (background)",
                    context: ["reason": "launch_exit_code", "exit_code": "\(result.exitCode)", "thread": "background"]
                )
                circuitBreaker.endRecovery(success: false)
                return
            }
            // Poll for readiness using off-breaker CLI probe
            let deadline = Date().addingTimeInterval(startupTimeoutSeconds)
            while Date() < deadline {
                switch commandRunner.run(executable: "aerospace", arguments: ["list-workspaces", "--focused"], timeoutSeconds: 2) {
                case .success(let r) where r.exitCode == 0:
                    logger.info("circuit_breaker.recovery_succeeded")
                    logRecoveryEvent(
                        "circuit_breaker.recovery_succeeded",
                        message: "AeroSpace restarted successfully (background)",
                        context: ["method": "restart", "thread": "background"]
                    )
                    circuitBreaker.endRecovery(success: true)
                    return
                default:
                    Thread.sleep(forTimeInterval: readinessCheckInterval)
                }
            }
            logger.warning("circuit_breaker.recovery_failed")
            logRecoveryEvent(
                "circuit_breaker.recovery_failed",
                level: .error,
                message: "AeroSpace did not become ready after restart (background)",
                context: [
                    "reason": "readiness_timeout",
                    "timeout_seconds": "\(startupTimeoutSeconds)",
                    "thread": "background"
                ]
            )
            circuitBreaker.endRecovery(success: false)
        }
    }

    private static func prepareForRecoveryStart(
        commandRunner: CommandRunning,
        processChecker: RunningApplicationChecking,
        terminatingChecker: (RunningApplicationChecking & RunningApplicationTerminating)?
    ) -> RecoveryPreparationResult {
        guard processChecker.isApplicationRunning(bundleIdentifier: bundleIdentifier) else {
            logger.info("circuit_breaker.recovery_process_not_running")
            logRecoveryEvent(
                "circuit_breaker.recovery_process_not_running",
                message: "AeroSpace process not running, proceeding with restart"
            )
            return .readyToRestart
        }

        switch recoveryProbeResultOffBreaker(commandRunner: commandRunner) {
        case .responsive:
            logger.info("circuit_breaker.recovery_process_responsive")
            logRecoveryEvent(
                "circuit_breaker.recovery_process_responsive",
                message: "AeroSpace process is running and responded to probe"
            )
            return .recoveredWithoutRestart
        case .failed(let detail):
            logger.warning("circuit_breaker.recovery_probe_failed_non_timeout detail=\(detail, privacy: .public)")
            logRecoveryEvent(
                "circuit_breaker.recovery_probe_failed",
                level: .warn,
                message: "Recovery probe failed with non-timeout error",
                context: ["detail": detail]
            )
            return .failed(detail: detail)
        case .timedOut:
            logRecoveryEvent(
                "circuit_breaker.recovery_probe_timed_out",
                level: .warn,
                message: "AeroSpace process is running but unresponsive (probe timed out)"
            )
            break
        }

        guard let terminatingChecker else {
            logger.warning("circuit_breaker.recovery_terminate_unsupported")
            logRecoveryEvent(
                "circuit_breaker.recovery_terminate_unsupported",
                level: .error,
                message: "Cannot terminate unresponsive AeroSpace — process checker does not support termination"
            )
            return .failed(detail: recoveryTerminateUnsupportedDetail)
        }

        logger.info("circuit_breaker.recovery_terminating_unresponsive_process")
        logRecoveryEvent(
            "circuit_breaker.recovery_terminating",
            level: .warn,
            message: "Terminating unresponsive AeroSpace process before restart"
        )
        guard terminatingChecker.terminateApplication(bundleIdentifier: bundleIdentifier) else {
            logger.warning("circuit_breaker.recovery_terminate_failed")
            logRecoveryEvent(
                "circuit_breaker.recovery_terminate_failed",
                level: .error,
                message: "Failed to terminate unresponsive AeroSpace process"
            )
            return .failed(detail: recoveryTerminateFailedDetail)
        }

        logRecoveryEvent(
            "circuit_breaker.recovery_terminated",
            message: "Unresponsive AeroSpace process terminated, proceeding with restart"
        )
        return .readyToRestart
    }

    /// Probes AeroSpace daemon responsiveness without circuit-breaker gating.
    ///
    /// Used only in recovery prep to avoid assuming every running process is
    /// hung when the breaker is open. This intentionally uses a daemon-backed
    /// command (not `--help`) so success reflects daemon health, not just CLI
    /// availability.
    ///
    /// - Returns: Probe outcome used to decide whether termination is allowed.
    private static func recoveryProbeResultOffBreaker(commandRunner: CommandRunning) -> RecoveryProbeResult {
        let probeTimeoutSeconds = recoveryProbeTimeoutSeconds(commandRunner: commandRunner)
        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["list-workspaces", "--focused"],
            timeoutSeconds: probeTimeoutSeconds
        ) {
        case .failure(let error):
            if error.isCommandTimeout {
                return .timedOut
            }
            return .failed(detail: recoveryProbeNonTimeoutFailureDetail(error, commandRunner: commandRunner))
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failed(detail: recoveryProbeNonZeroExitDetail(exitCode: result.exitCode))
            }
            return .responsive
        }
    }

    /// Probes CLI availability directly during startup readiness checks.
    ///
    /// This bypasses circuit-breaker/recovery orchestration to prevent
    /// start()->readiness probes from re-entering recovery while a recovery
    /// attempt is already running.
    ///
    /// - Returns: True when `aerospace list-workspaces --focused` exits successfully.
    private func isCliReadyOffBreakerProbe() -> Bool {
        switch commandRunner.run(
            executable: "aerospace",
            arguments: ["list-workspaces", "--focused"],
            timeoutSeconds: 2
        ) {
        case .failure:
            return false
        case .success(let result):
            return result.exitCode == 0
        }
    }

    /// Recovery detail for non-zero responsiveness probe exits.
    private static func recoveryProbeNonZeroExitDetail(exitCode: Int32) -> String {
        "AeroSpace responsiveness probe exited with code \(exitCode). Refusing automatic termination; restart AeroSpace manually."
    }

    /// Recovery detail for non-timeout responsiveness probe failures.
    ///
    /// Includes a concise, sanitized probe error context for diagnostics.
    private static func recoveryProbeNonTimeoutFailureDetail(_ error: ApCoreError, commandRunner: CommandRunning) -> String {
        guard commandRunner is ApSystemCommandRunner else {
            return recoveryProbeNonTimeoutFailureDetail
        }
        let context = conciseRecoveryProbeErrorContext(error)
        return "\(recoveryProbeNonTimeoutFailureDetail) Probe error: \(context)."
    }

    /// Produces a bounded, single-line diagnostic context from a probe failure.
    private static func conciseRecoveryProbeErrorContext(_ error: ApCoreError) -> String {
        let rawContext = [error.detail, error.message]
            .compactMap { $0 }
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "unknown error"

        let maxLength = 120
        guard rawContext.count > maxLength else {
            return rawContext
        }

        let endIndex = rawContext.index(rawContext.startIndex, offsetBy: maxLength)
        return "\(rawContext[..<endIndex])..."
    }

    /// Returns the timeout used for direct off-breaker recovery probes.
    ///
    /// For the live system runner, keep probe timeout at least the normal command
    /// timeout to avoid classifying a process as hung more aggressively than
    /// normal command execution. Injected runners keep the legacy probe timeout
    /// to preserve deterministic test contracts.
    private static func recoveryProbeTimeoutSeconds(commandRunner: CommandRunning) -> TimeInterval {
        if commandRunner is ApSystemCommandRunner {
            return max(2, defaultCommandTimeoutSeconds)
        }
        return 2
    }

    /// Returns help output for a CLI command.
    ///
    /// Bypasses the circuit breaker intentionally: `--help` tests the CLI binary,
    /// not daemon connectivity, and must work during compatibility checks even
    /// when the breaker is open.
    ///
    /// - Parameter command: AeroSpace command name to query.
    /// - Returns: Help output or an error.
    private func commandHelpOutput(command: String) -> Result<String, ApCoreError> {
        switch commandRunner.run(executable: "aerospace", arguments: [command, "--help"], timeoutSeconds: 2) {
        case .failure(let error):
            return .failure(error)
        case .success(let result):
            guard result.exitCode == 0 else {
                return .failure(commandError("aerospace \(command) --help", result: result))
            }

            let output = [result.stdout, result.stderr]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return .success(output)
        }
    }

    // MARK: - Structured Recovery Logging

    /// Writes a structured log entry for circuit breaker and recovery events.
    ///
    /// Static so it can be called from both instance and static recovery methods.
    /// Uses the shared `structuredLogger` to write to the JSON log file.
    private static func logRecoveryEvent(
        _ event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = structuredLogger.log(event: event, level: level, message: message, context: context)
    }
}

// MARK: - AeroSpaceHealthChecking Conformance

extension ApAeroSpace: AeroSpaceHealthChecking {
    /// Returns the installation status of AeroSpace.
    func installStatus() -> AeroSpaceInstallStatus {
        AeroSpaceInstallStatus(isInstalled: isAppInstalled(), appPath: appPath)
    }

    /// Checks whether the installed aerospace CLI is compatible.
    /// Translates the internal Result type to the intent-based AeroSpaceCompatibility enum.
    func healthCheckCompatibility() -> AeroSpaceCompatibility {
        guard isCliAvailable() else {
            return .cliUnavailable
        }
        switch checkCompatibility() {
        case .success:
            return .compatible
        case .failure(let error):
            return .incompatible(detail: error.detail ?? error.message)
        }
    }

    /// Installs AeroSpace via Homebrew.
    /// - Returns: True if installation succeeded.
    func healthInstallViaHomebrew() -> Bool {
        switch installViaHomebrew() {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Starts AeroSpace.
    /// - Returns: True if start succeeded.
    func healthStart() -> Bool {
        switch start() {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    /// Reloads the AeroSpace configuration.
    /// - Returns: True if reload succeeded.
    func healthReloadConfig() -> Bool {
        switch reloadConfig() {
        case .success:
            return true
        case .failure:
            return false
        }
    }
}
