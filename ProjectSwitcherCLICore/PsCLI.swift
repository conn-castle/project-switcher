import Foundation

import ProjectSwitcherCore

/// Minimal interface required by the CLI runner for project operations.
public protocol ProjectManaging {
    func loadConfig() -> Result<ConfigLoadSuccess, ConfigLoadError>
    func sortedProjects(query: String) -> [ProjectConfig]
    func captureCurrentFocus() -> CapturedFocus?
    func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<ProjectActivationSuccess, ProjectError>
    func closeProject(projectId: String) async -> Result<ProjectCloseSuccess, ProjectError>
    func exitToNonProjectWindow() async -> Result<Void, ProjectError>
}

extension ProjectManager: ProjectManaging {}

/// Exit codes used by `pswitcher`.
public enum PsExitCode: Int32 {
    case ok = 0
    case failure = 1
    case usage = 64
}

/// Output sink for the CLI.
public struct PsCLIOutput {
    public let stdout: (String) -> Void
    public let stderr: (String) -> Void

    public init(stdout: @escaping (String) -> Void, stderr: @escaping (String) -> Void) {
        self.stdout = stdout
        self.stderr = stderr
    }

    public static let standard = PsCLIOutput(
        stdout: { print($0) },
        stderr: { printStderr($0) }
    )
}

/// Dependencies for the CLI runner.
public struct PsCLIDependencies {
    public let version: () -> String
    public let projectManagerFactory: () -> any ProjectManaging
    public let doctorRunner: () -> DoctorReport

    public init(
        version: @escaping () -> String,
        projectManagerFactory: @escaping () -> any ProjectManaging,
        doctorRunner: @escaping () -> DoctorReport
    ) {
        self.version = version
        self.projectManagerFactory = projectManagerFactory
        self.doctorRunner = doctorRunner
    }
}

/// CLI runner that returns an exit code instead of calling exit().
public struct PsCLI {
    public let parser: PsArgumentParser
    public let dependencies: PsCLIDependencies
    public let output: PsCLIOutput

    public init(parser: PsArgumentParser, dependencies: PsCLIDependencies, output: PsCLIOutput) {
        self.parser = parser
        self.dependencies = dependencies
        self.output = output
    }

    public func run(arguments: [String]) -> Int32 {
        switch parser.parse(arguments: arguments) {
        case .success(let command):
            return run(command: command)
        case .failure(let error):
            output.stderr("error: \(error.message)")
            output.stderr(usageText(for: error.usageTopic))
            return PsExitCode.usage.rawValue
        }
    }

    private func run(command: PsCommand) -> Int32 {
        switch command {
        case .help(let topic):
            output.stdout(usageText(for: topic))
            return PsExitCode.ok.rawValue

        case .version:
            output.stdout("pswitcher \(dependencies.version())")
            return PsExitCode.ok.rawValue

        case .doctor:
            let report = dependencies.doctorRunner()
            let useColor = isatty(STDOUT_FILENO) != 0
                && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            output.stdout(report.rendered(colorize: useColor))
            return report.hasFailures ? PsExitCode.failure.rawValue : PsExitCode.ok.rawValue

        case .showConfig:
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return PsExitCode.failure.rawValue
            case .success(let success):
                for warning in success.warnings {
                    output.stderr("warning: \(warning.title)")
                }
                output.stdout(formatConfig(success.config))
                return PsExitCode.ok.rawValue
            }

        case .listProjects(let query):
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return PsExitCode.failure.rawValue
            case .success:
                let projects = manager.sortedProjects(query: query ?? "")
                for project in projects {
                    output.stdout(formatProjectLine(project))
                }
                return PsExitCode.ok.rawValue
            }

        case .selectProject(let projectId):
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return PsExitCode.failure.rawValue
            case .success:
                guard let capturedFocus = manager.captureCurrentFocus() else {
                    output.stderr("error: Could not capture current focus")
                    return PsExitCode.failure.rawValue
                }
                guard let result: Result<ProjectActivationSuccess, ProjectError> = runBlocking(
                    timeout: 30,
                    timeoutMessage: "Project activation timed out after 30 seconds",
                    operation: { await manager.selectProject(projectId: projectId, preCapturedFocus: capturedFocus) }
                ) else {
                    return PsExitCode.failure.rawValue
                }

                switch result {
                case .failure(let error):
                    output.stderr("error: \(formatProjectError(error))")
                    return PsExitCode.failure.rawValue
                case .success(let activation):
                    if let warning = activation.chromeWarning {
                        output.stderr("warning: \(warning)")
                    }
                    if let warning = activation.layoutWarning {
                        output.stderr("warning: \(warning)")
                    }
                    output.stdout("Selected project: \(projectId)")
                    return PsExitCode.ok.rawValue
                }
            }

        case .closeProject(let projectId):
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return PsExitCode.failure.rawValue
            case .success:
                guard let result: Result<ProjectCloseSuccess, ProjectError> = runBlocking(
                    timeout: 30,
                    timeoutMessage: "Close project timed out after 30 seconds",
                    operation: { await manager.closeProject(projectId: projectId) }
                ) else {
                    return PsExitCode.failure.rawValue
                }

                switch result {
                case .failure(let error):
                    output.stderr("error: \(formatProjectError(error))")
                    return PsExitCode.failure.rawValue
                case .success(let closeResult):
                    if let warning = closeResult.tabCaptureWarning {
                        output.stderr("warning: \(warning)")
                    }
                    output.stdout("Closed project: \(projectId)")
                    return PsExitCode.ok.rawValue
                }
            }

        case .returnToWindow:
            let manager = dependencies.projectManagerFactory()
            switch manager.loadConfig() {
            case .failure(let error):
                output.stderr("error: \(formatConfigError(error))")
                return PsExitCode.failure.rawValue
            case .success:
                guard let result: Result<Void, ProjectError> = runBlocking(
                    timeout: 30,
                    timeoutMessage: "Return to non-project space timed out after 30 seconds",
                    operation: { await manager.exitToNonProjectWindow() }
                ) else {
                    return PsExitCode.failure.rawValue
                }

                switch result {
                case .failure(let error):
                    output.stderr("error: \(formatProjectError(error))")
                    return PsExitCode.failure.rawValue
                case .success:
                    output.stdout("Returned to non-project space")
                    return PsExitCode.ok.rawValue
                }
            }
        }
    }

    /// Bridges an async operation to synchronous CLI execution with a timeout.
    /// Returns `nil` and prints an error if the operation times out. Cancels
    /// the in-flight task on timeout to prevent stale state mutations.
    private func runBlocking<T>(
        timeout seconds: TimeInterval,
        timeoutMessage: String,
        operation: @escaping () async -> T
    ) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        let task = Task {
            result = await operation()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + seconds) == .timedOut {
            task.cancel()
            output.stderr("error: \(timeoutMessage)")
            return nil
        }
        return result
    }
}

/// Builds the `pswitcher` usage string for a given help topic.
func usageText(for topic: PsHelpTopic) -> String {
    switch topic {
    case .root:
        return """
        pswitcher (ProjectSwitcher CLI)

        Usage:
          pswitcher <command> [args]

        Commands:
          doctor              Run diagnostic checks
          show-config         Show current configuration
          list-projects [q]   List projects (optionally filtered by query)
          select-project <id> Activate a project
          close-project <id>  Close a project and return to non-project space
          return              Return to most recent non-project window without closing project

        Options:
          -h, --help      Show help
          -v, --version   Show version
        """
    case .doctor:
        return """
        Usage:
          pswitcher doctor

        Run diagnostic checks for ProjectSwitcher dependencies.

        Options:
          -h, --help   Show help
        """
    case .showConfig:
        return """
        Usage:
          pswitcher show-config

        Display the current ProjectSwitcher configuration.

        Options:
          -h, --help   Show help
        """
    case .listProjects:
        return """
        Usage:
          pswitcher list-projects [query]

        List all projects, optionally filtered by a search query.
        Projects are sorted by recency (most recently used first).

        Options:
          -h, --help   Show help
        """
    case .selectProject:
        return """
        Usage:
          pswitcher select-project <project-id>

        Activate a project by its ID. This will:
        - Create/focus the project's workspace
        - Open Chrome and VS Code windows if needed
        - Move windows to the workspace
        - Focus the IDE window

        Options:
          -h, --help   Show help
        """
    case .closeProject:
        return """
        Usage:
          pswitcher close-project <project-id>

        Close a project by its ID. This will:
        - Close all windows in the project's workspace
        - Return focus to non-project space

        Options:
          -h, --help   Show help
        """
    case .returnToWindow:
        return """
        Usage:
          pswitcher return

        Return to the most recent non-project window without closing the current project.
        Use this to temporarily leave a project while keeping it open.

        Options:
          -h, --help   Show help
        """
    }
}

private func formatProjectLine(_ project: ProjectConfig) -> String {
    "\(project.id)\t\(project.name)\t\(project.path)"
}

private func formatConfig(_ config: Config) -> String {
    var lines: [String] = []
    lines.append("# ProjectSwitcher Configuration")
    lines.append("")

    for project in config.projects {
        lines.append("[[project]]")
        lines.append("id = \"\(project.id)\"")
        lines.append("name = \"\(project.name)\"")
        lines.append("path = \"\(project.path)\"")
        lines.append("color = \"\(project.color)\"")
        lines.append("useAgentLayer = \(project.useAgentLayer)")
        lines.append("")
    }

    return lines.joined(separator: "\n")
}

private func formatConfigError(_ error: ConfigLoadError) -> String {
    switch error {
    case .fileNotFound(let path):
        return "Config file not found: \(path)"
    case .readFailed(let path, let detail):
        return "Failed to read config at \(path): \(detail)"
    case .parseFailed(let detail):
        return "Failed to parse config: \(detail)"
    case .validationFailed(let findings):
        let firstFail = findings.first { $0.severity == .fail }
        return firstFail?.title ?? "Config validation failed"
    }
}

private func formatProjectError(_ error: ProjectError) -> String {
    switch error {
    case .projectNotFound(let projectId):
        return "Project not found: \(projectId)"
    case .configNotLoaded:
        return "Config not loaded"
    case .aeroSpaceError(let detail):
        return "AeroSpace error: \(detail)"
    case .ideLaunchFailed(let detail):
        return "IDE launch failed: \(detail)"
    case .chromeLaunchFailed(let detail):
        return "Chrome launch failed: \(detail)"
    case .noActiveProject:
        return "No active project"
    case .noPreviousWindow:
        return "No recent non-project window to return to"
    case .windowNotFound(let detail):
        return "Window not found: \(detail)"
    case .focusUnstable(let detail):
        return "Focus unstable: \(detail)"
    }
}

/// Prints text to stderr.
private func printStderr(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}
