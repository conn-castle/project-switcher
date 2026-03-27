import Foundation

// MARK: - Doctor Models

/// Severity level for Doctor findings.
public enum DoctorSeverity: String, CaseIterable, Sendable {
    case pass = "PASS"
    case warn = "WARN"
    case fail = "FAIL"

    /// Sort order for display purposes (failures first).
    public var sortOrder: Int {
        switch self {
        case .fail: return 0
        case .warn: return 1
        case .pass: return 2
        }
    }

    /// ANSI escape code for this severity's color.
    var ansiColor: String {
        switch self {
        case .pass: return "\u{1b}[32m" // green
        case .warn: return "\u{1b}[33m" // yellow
        case .fail: return "\u{1b}[31m" // red
        }
    }

    /// ANSI reset escape code.
    static let ansiReset = "\u{1b}[0m"

    /// Returns the severity label wrapped in ANSI color codes.
    func coloredLabel() -> String {
        "\(ansiColor)\(rawValue)\(Self.ansiReset)"
    }
}

/// A single Doctor finding rendered in the report.
public struct DoctorFinding: Equatable, Sendable {
    public let severity: DoctorSeverity
    public let title: String
    public let bodyLines: [String]
    public let snippet: String?
    public let snippetLanguage: String

    /// Creates a Doctor finding.
    /// - Parameters:
    ///   - severity: PASS, WARN, or FAIL severity.
    ///   - title: Short summary of the finding.
    ///   - detail: Optional detail text for additional context.
    ///   - fix: Optional "Fix:" guidance for the user.
    ///   - bodyLines: Additional lines to render verbatim after the title.
    ///   - snippet: Optional copy/paste snippet to resolve the finding.
    ///   - snippetLanguage: Language tag for the snippet code fence (default: "toml").
    init(
        severity: DoctorSeverity,
        title: String,
        detail: String? = nil,
        fix: String? = nil,
        bodyLines: [String] = [],
        snippet: String? = nil,
        snippetLanguage: String = "toml"
    ) {
        self.severity = severity
        self.title = title
        var lines = bodyLines
        if let detail, !detail.isEmpty {
            lines.append("Detail: \(detail)")
        }
        if let fix, !fix.isEmpty {
            lines.append("Fix: \(fix)")
        }
        self.bodyLines = lines
        self.snippet = snippet
        self.snippetLanguage = snippetLanguage
    }
}

/// Report metadata rendered in the Doctor header.
public struct DoctorMetadata: Equatable, Sendable {
    public let timestamp: String
    public let projectSwitcherVersion: String
    public let macOSVersion: String
    public let aerospaceApp: String
    public let aerospaceCli: String
    public let errorContext: ErrorContext?
    /// Total Doctor.run() duration in milliseconds.
    public let durationMs: Int
    /// Per-section timing breakdown in milliseconds.
    public let sectionTimings: [String: Int]
}

/// Action availability for Doctor UI buttons.
public struct DoctorActionAvailability: Equatable, Sendable {
    public let canInstallAeroSpace: Bool
    public let canStartAeroSpace: Bool
    public let canReloadAeroSpaceConfig: Bool
    public let canRequestAccessibility: Bool

    init(
        canInstallAeroSpace: Bool,
        canStartAeroSpace: Bool,
        canReloadAeroSpaceConfig: Bool,
        canRequestAccessibility: Bool = false
    ) {
        self.canInstallAeroSpace = canInstallAeroSpace
        self.canStartAeroSpace = canStartAeroSpace
        self.canReloadAeroSpaceConfig = canReloadAeroSpaceConfig
        self.canRequestAccessibility = canRequestAccessibility
    }

    /// Returns a disabled action set.
    static let none = DoctorActionAvailability(
        canInstallAeroSpace: false,
        canStartAeroSpace: false,
        canReloadAeroSpaceConfig: false,
        canRequestAccessibility: false
    )
}

/// A structured Doctor report.
public struct DoctorReport: Equatable, Sendable {
    public let metadata: DoctorMetadata
    public let findings: [DoctorFinding]
    public let actions: DoctorActionAvailability

    init(
        metadata: DoctorMetadata,
        findings: [DoctorFinding],
        actions: DoctorActionAvailability = .none
    ) {
        self.metadata = metadata
        self.findings = findings
        self.actions = actions
    }

    /// Returns true when the report contains any FAIL findings.
    public var hasFailures: Bool {
        overallSeverity == .fail
    }

    /// Returns the worst severity present in findings (FAIL > WARN > PASS).
    /// When no findings are present, returns PASS.
    public var overallSeverity: DoctorSeverity {
        if findings.contains(where: { $0.severity == .fail }) {
            return .fail
        }
        if findings.contains(where: { $0.severity == .warn }) {
            return .warn
        }
        return .pass
    }

    /// Renders the report as a human-readable string for CLI and App display.
    /// - Parameter colorize: When true, severity labels are wrapped in ANSI color codes.
    public func rendered(colorize: Bool = false) -> String {
        let indexed = findings.enumerated()
        let sortedFindings = indexed.sorted { lhs, rhs in
            let leftOrder = lhs.element.severity.sortOrder
            let rightOrder = rhs.element.severity.sortOrder
            if leftOrder == rightOrder {
                return lhs.offset < rhs.offset
            }
            return leftOrder < rightOrder
        }.map { $0.element }

        func severityLabel(_ severity: DoctorSeverity) -> String {
            colorize ? severity.coloredLabel() : severity.rawValue
        }

        let name = ProjectSwitcher.displayName
        var lines: [String] = []
        lines.append("\(name) Doctor Report")
        lines.append("Timestamp: \(metadata.timestamp)")
        lines.append("\(name) version: \(metadata.projectSwitcherVersion)")
        lines.append("macOS version: \(metadata.macOSVersion)")
        lines.append("AeroSpace app: \(metadata.aerospaceApp)")
        lines.append("aerospace CLI: \(metadata.aerospaceCli)")
        if let ctx = metadata.errorContext {
            lines.append("Triggered by: \(ctx.trigger) (\(ctx.category.rawValue)): \(ctx.message)")
        }
        lines.append("Duration: \(metadata.durationMs)ms")
        if !metadata.sectionTimings.isEmpty {
            let sortedSections = metadata.sectionTimings.sorted { $0.key < $1.key }
            let timingParts = sortedSections.map { "\($0.key)=\($0.value)ms" }
            lines.append("Sections: \(timingParts.joined(separator: ", "))")
        }
        lines.append("")

        if sortedFindings.isEmpty {
            lines.append("\(severityLabel(.pass))  no issues found")
        } else {
            for finding in sortedFindings {
                if finding.title.isEmpty {
                    for line in finding.bodyLines {
                        lines.append(line)
                    }
                    continue
                }

                lines.append("\(severityLabel(finding.severity))  \(finding.title)")
                for line in finding.bodyLines {
                    lines.append(line)
                }
                if let snippet = finding.snippet, !snippet.isEmpty {
                    lines.append("  Snippet:")
                    lines.append("  ```\(finding.snippetLanguage)")
                    for line in snippet.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("  \(line)")
                    }
                    lines.append("  ```")
                }
            }
        }

        let countedFindings = sortedFindings.filter { !$0.title.isEmpty }
        let passCount = countedFindings.filter { $0.severity == .pass }.count
        let warnCount = countedFindings.filter { $0.severity == .warn }.count
        let failCount = countedFindings.filter { $0.severity == .fail }.count

        lines.append("")
        lines.append("Summary: \(passCount) \(severityLabel(.pass)), \(warnCount) \(severityLabel(.warn)), \(failCount) \(severityLabel(.fail))")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Doctor Implementation

/// Checks system requirements and environment for ProjectSwitcher.
public struct Doctor {
    /// VS Code bundle identifier.
    private static let vscodeBundleId = "com.microsoft.VSCode"
    /// Chrome bundle identifier.
    private static let chromeBundleId = "com.google.Chrome"

    private let runningApplicationChecker: RunningApplicationChecking
    private let hotkeyStatusProvider: HotkeyStatusProviding?
    private let focusCycleStatusProvider: FocusCycleStatusProviding?
    private let dateProvider: DateProviding
    private let aerospaceHealth: AeroSpaceHealthChecking
    private let appDiscovery: AppDiscovering
    private let executableResolver: ExecutableResolver
    private let commandRunner: CommandRunning
    private let fileSystem: FileSystem
    private let dataStore: DataPaths
    private let windowPositioner: WindowPositioning?
    private let configManager: AeroSpaceConfigManager
    /// True when the default Doctor wiring uses a dedicated breaker (not `.shared`).
    let usesDedicatedAeroSpaceCircuitBreaker: Bool

    /// Creates a Doctor instance with default dependencies.
    /// - Parameters:
    ///   - runningApplicationChecker: Running application checker (required, provided by CLI/App).
    ///   - hotkeyStatusProvider: Optional hotkey status provider for hotkey registration checks.
    ///   - focusCycleStatusProvider: Optional focus-cycle hotkey status provider.
    public init(
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyStatusProviding? = nil,
        focusCycleStatusProvider: FocusCycleStatusProviding? = nil,
        windowPositioner: WindowPositioning? = nil
    ) {
        self.runningApplicationChecker = runningApplicationChecker
        self.hotkeyStatusProvider = hotkeyStatusProvider
        self.focusCycleStatusProvider = focusCycleStatusProvider
        self.dateProvider = SystemDateProvider()
        let doctorCircuitBreaker = AeroSpaceCircuitBreaker()
        let doctorAeroSpace = PsAeroSpace(
            commandRunner: PsSystemCommandRunner(),
            appDiscovery: LaunchServicesAppDiscovery(),
            circuitBreaker: doctorCircuitBreaker
        )
        // Doctor uses a dedicated circuit breaker so diagnostic checks are never
        // blocked by the shared breaker state (which may be open due to a timeout
        // in the main app flow). Doctor is a diagnostic tool and should independently
        // verify actual system state.
        self.usesDedicatedAeroSpaceCircuitBreaker = !doctorAeroSpace.usesSharedCircuitBreaker
        self.aerospaceHealth = doctorAeroSpace
        self.appDiscovery = LaunchServicesAppDiscovery()
        self.executableResolver = ExecutableResolver()
        self.commandRunner = PsSystemCommandRunner()
        self.fileSystem = DefaultFileSystem()
        self.dataStore = .default()
        self.windowPositioner = windowPositioner
        self.configManager = AeroSpaceConfigManager()
    }

    /// Creates a Doctor instance with full dependency injection (internal, for testing).
    /// - Parameters:
    ///   - runningApplicationChecker: Running application checker.
    ///   - hotkeyStatusProvider: Optional hotkey status provider.
    ///   - focusCycleStatusProvider: Optional focus-cycle hotkey status provider.
    ///   - dateProvider: Date provider for timestamps.
    ///   - aerospaceHealth: AeroSpace health checker for status and remediation actions.
    ///   - appDiscovery: App discovery for checking installed apps.
    ///   - executableResolver: Resolver for checking CLI tools.
    ///   - commandRunner: Command runner for SSH remote path checks.
    ///   - dataStore: Data store for path checks.
    ///   - usesDedicatedAeroSpaceCircuitBreaker: Whether the injected `aerospaceHealth`
    ///     uses a dedicated breaker instance (test seam for wiring assertions).
    ///   - configManager: AeroSpace config manager for config status and content checks.
    init(
        runningApplicationChecker: RunningApplicationChecking,
        hotkeyStatusProvider: HotkeyStatusProviding?,
        focusCycleStatusProvider: FocusCycleStatusProviding? = nil,
        dateProvider: DateProviding,
        aerospaceHealth: AeroSpaceHealthChecking,
        appDiscovery: AppDiscovering,
        executableResolver: ExecutableResolver,
        commandRunner: CommandRunning,
        dataStore: DataPaths,
        usesDedicatedAeroSpaceCircuitBreaker: Bool = false,
        fileSystem: FileSystem = DefaultFileSystem(),
        windowPositioner: WindowPositioning? = nil,
        configManager: AeroSpaceConfigManager = AeroSpaceConfigManager()
    ) {
        self.runningApplicationChecker = runningApplicationChecker
        self.hotkeyStatusProvider = hotkeyStatusProvider
        self.focusCycleStatusProvider = focusCycleStatusProvider
        self.dateProvider = dateProvider
        self.aerospaceHealth = aerospaceHealth
        self.appDiscovery = appDiscovery
        self.executableResolver = executableResolver
        self.commandRunner = commandRunner
        self.dataStore = dataStore
        self.usesDedicatedAeroSpaceCircuitBreaker = usesDedicatedAeroSpaceCircuitBreaker
        self.fileSystem = fileSystem
        self.windowPositioner = windowPositioner
        self.configManager = configManager
    }

    /// Builds a UTC ISO-8601 timestamp string with fractional seconds.
    /// - Returns: Timestamp string in UTC timezone.
    private func makeUTCTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: dateProvider.now())
    }

    /// Returns elapsed milliseconds since a given start time.
    private static func elapsedMs(since start: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    /// Runs all Doctor checks and returns a report.
    /// - Parameter context: Optional error context that triggered this run (informational, for logging).
    public func run(context: ErrorContext? = nil) -> DoctorReport {
        let runStart = DispatchTime.now().uptimeNanoseconds
        var findings: [DoctorFinding] = []
        var sectionTimings: [String: Int] = [:]

        // Homebrew
        var sectionStart = runStart
        findings.append(contentsOf: checkHomebrew())
        sectionTimings["homebrew"] = Self.elapsedMs(since: sectionStart)

        // AeroSpace
        sectionStart = DispatchTime.now().uptimeNanoseconds
        let aeroResult = checkAeroSpace()
        findings.append(contentsOf: aeroResult.findings)
        sectionTimings["aerospace"] = Self.elapsedMs(since: sectionStart)

        // Config and projects
        sectionStart = DispatchTime.now().uptimeNanoseconds
        let configResult = checkConfigAndProjects()
        findings.append(contentsOf: configResult.findings)
        sectionTimings["config_and_projects"] = Self.elapsedMs(since: sectionStart)

        // Apps (VS Code, Chrome, Peacock)
        sectionStart = DispatchTime.now().uptimeNanoseconds
        findings.append(contentsOf: checkApps(
            vscodeURL: configResult.vscodeURL,
            chromeURL: configResult.chromeURL,
            hasValidProjects: configResult.hasValidProjects
        ))
        sectionTimings["apps"] = Self.elapsedMs(since: sectionStart)

        // Accessibility and hotkeys
        sectionStart = DispatchTime.now().uptimeNanoseconds
        let accessResult = checkAccessibilityAndHotkeys()
        findings.append(contentsOf: accessResult.findings)
        sectionTimings["accessibility_and_hotkeys"] = Self.elapsedMs(since: sectionStart)

        // Critical failures that onboarding can fix
        let appDisplayName = ProjectSwitcher.displayName
        let hasCriticalAeroSpaceFailure = !aeroResult.installStatus.isInstalled || !aeroResult.cliAvailable
        if hasCriticalAeroSpaceFailure {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "Critical: AeroSpace setup incomplete",
                fix: "Launch \(appDisplayName).app to run onboarding, or install manually: brew install --cask nikitabobko/tap/aerospace"
            ))
        }

        let totalDurationMs = Self.elapsedMs(since: runStart)
        let metadata = DoctorMetadata(
            timestamp: makeUTCTimestamp(),
            projectSwitcherVersion: ProjectSwitcher.version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            aerospaceApp: aeroResult.appLabel,
            aerospaceCli: aeroResult.cliLabel,
            errorContext: context,
            durationMs: totalDurationMs,
            sectionTimings: sectionTimings
        )

        let actions = DoctorActionAvailability(
            canInstallAeroSpace: !aeroResult.installStatus.isInstalled,
            canStartAeroSpace: aeroResult.installStatus.isInstalled && !aeroResult.isRunning,
            canReloadAeroSpaceConfig: aeroResult.isRunning,
            canRequestAccessibility: accessResult.accessibilityNotGranted
        )

        return DoctorReport(metadata: metadata, findings: findings, actions: actions)
    }

    // MARK: - Section: Homebrew

    /// Checks whether Homebrew is installed.
    /// - Returns: Findings for the Homebrew section.
    private func checkHomebrew() -> [DoctorFinding] {
        if executableResolver.resolve("brew") != nil {
            return [DoctorFinding(severity: .pass, title: "Homebrew installed")]
        } else {
            return [DoctorFinding(
                severity: .fail,
                title: "Homebrew not found",
                fix: "Install Homebrew from https://brew.sh"
            )]
        }
    }

    // MARK: - Section: AeroSpace

    /// Result of the AeroSpace section check, carrying findings and state
    /// needed by later sections and the report metadata/actions.
    private struct AeroSpaceCheckResult {
        let findings: [DoctorFinding]
        let appLabel: String
        let cliLabel: String
        let installStatus: AeroSpaceInstallStatus
        let cliAvailable: Bool
        let isRunning: Bool
    }

    /// Checks AeroSpace app, CLI, compatibility, running state, and config.
    /// - Returns: Findings and metadata needed for the report header and actions.
    private func checkAeroSpace() -> AeroSpaceCheckResult {
        let appDisplayName = ProjectSwitcher.displayName
        var findings: [DoctorFinding] = []

        // App installation
        let installStatus = aerospaceHealth.installStatus()
        var appLabel = "NOT FOUND"
        if installStatus.isInstalled {
            appLabel = installStatus.appPath ?? "FOUND"
            findings.append(DoctorFinding(
                severity: .pass,
                title: "AeroSpace.app installed",
                detail: installStatus.appPath
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "AeroSpace.app not found",
                fix: "Install AeroSpace via Homebrew: brew install --cask nikitabobko/tap/aerospace"
            ))
        }

        // CLI availability
        var cliLabel = "NOT FOUND"
        let cliAvailable = aerospaceHealth.isCliAvailable()
        if cliAvailable {
            cliLabel = "AVAILABLE"
            findings.append(DoctorFinding(
                severity: .pass,
                title: "aerospace CLI available"
            ))

            // Compatibility
            switch aerospaceHealth.healthCheckCompatibility() {
            case .compatible:
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "aerospace CLI compatibility verified"
                ))
            case .cliUnavailable:
                findings.append(DoctorFinding(
                    severity: .fail,
                    title: "aerospace CLI not available for compatibility check",
                    fix: "Ensure AeroSpace is installed and the CLI is in your PATH."
                ))
            case .incompatible(let detail):
                findings.append(DoctorFinding(
                    severity: .fail,
                    title: "aerospace CLI compatibility issues",
                    detail: detail
                ))
            }
        } else {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "aerospace CLI not available",
                fix: "Ensure AeroSpace is installed and the CLI is in your PATH."
            ))
        }

        // Running state
        let isRunning = runningApplicationChecker.isApplicationRunning(bundleIdentifier: "bobko.aerospace")
        if isRunning {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "AeroSpace is running"
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .warn,
                title: "AeroSpace is not running",
                fix: "Start AeroSpace from Applications or enable 'start-at-login' in ~/.aerospace.toml."
            ))
        }

        // Config
        switch configManager.configStatus() {
        case .managedByProjectSwitcher:
            findings.append(DoctorFinding(
                severity: .pass,
                title: "AeroSpace config managed by \(appDisplayName)"
            ))
            let currentVer = configManager.currentConfigVersion()
            let templateVer = configManager.templateVersion()
            if let templateVer {
                if currentVer == nil || currentVer! < templateVer {
                    let currentLabel = currentVer.map { "\($0)" } ?? "none"
                    findings.append(DoctorFinding(
                        severity: .warn,
                        title: "AeroSpace config is outdated (version \(currentLabel), latest is \(templateVer))",
                        fix: "Restart \(appDisplayName) to auto-update, or run `pswitcher doctor` for details."
                    ))
                }
            } else if configManager.isTemplateAvailable() {
                findings.append(DoctorFinding(
                    severity: .fail,
                    title: "AeroSpace config template has no version",
                    detail: "The bundled aerospace-safe.toml has no ps-config-version line.",
                    fix: "Reinstall \(appDisplayName) — the app bundle may be corrupted."
                ))
            }
        case .missing:
            findings.append(DoctorFinding(
                severity: .fail,
                title: "AeroSpace config file missing",
                detail: AeroSpaceConfigManager.configPath,
                fix: "Run \(appDisplayName) setup to create a compatible AeroSpace config."
            ))
        case .externalConfig:
            findings.append(DoctorFinding(
                severity: .warn,
                title: "AeroSpace config not managed by \(appDisplayName)",
                detail: "Config exists but was not created by \(appDisplayName).",
                fix: "\(appDisplayName) may not function correctly. Consider allowing \(appDisplayName) to manage the config."
            ))
        case .unknown:
            findings.append(DoctorFinding(
                severity: .warn,
                title: "Could not read AeroSpace config",
                fix: "Check file permissions on \(AeroSpaceConfigManager.configPath)"
            ))
        }

        return AeroSpaceCheckResult(
            findings: findings,
            appLabel: appLabel,
            cliLabel: cliLabel,
            installStatus: installStatus,
            cliAvailable: cliAvailable,
            isRunning: isRunning
        )
    }

    // MARK: - Section: Config and Projects

    /// Result of the config-and-projects section check.
    private struct ConfigAndProjectsResult {
        let findings: [DoctorFinding]
        let hasValidProjects: Bool
        let vscodeURL: URL?
        let chromeURL: URL?
    }

    /// Checks VS Code / Chrome installation detection, required directories,
    /// ProjectSwitcher config, and project paths.
    ///
    /// VS Code / Chrome URLs are detected here (alongside config) but their
    /// findings are emitted in ``checkApps(vscodeURL:chromeURL:hasValidProjects:)``
    /// because severity depends on whether projects are configured.
    ///
    /// - Returns: Findings and state needed by the apps section.
    private func checkConfigAndProjects() -> ConfigAndProjectsResult {
        var findings: [DoctorFinding] = []

        // Detect VS Code / Chrome installation
        let vscodeURL = appDiscovery.applicationURL(bundleIdentifier: Self.vscodeBundleId)
        let chromeURL = appDiscovery.applicationURL(bundleIdentifier: Self.chromeBundleId)

        // Check required directories
        let logsDir = dataStore.logsDirectory
        if fileSystem.directoryExists(at: logsDir) {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Logs directory exists",
                detail: logsDir.path
            ))
        } else {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Logs directory will be created on first use",
                detail: logsDir.path
            ))
        }

        // Check ProjectSwitcher config
        var hasValidProjects = false
        switch ConfigLoader.load(from: dataStore.configFile) {
        case .failure(let error):
            findings.append(DoctorFinding(
                severity: .fail,
                title: "Config file error",
                detail: error.message
            ))
        case .success(let result):
            if result.config != nil {
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "Config file parsed successfully"
                ))
            }
            for finding in result.findings {
                findings.append(DoctorFinding(
                    severity: finding.severity == .fail ? .fail : (finding.severity == .warn ? .warn : .pass),
                    title: finding.title,
                    detail: finding.detail,
                    fix: finding.fix
                ))
            }

            hasValidProjects = !result.projects.isEmpty

            // Check agent-layer CLI if any project uses it
            let agentLayerProjects = result.projects.filter { $0.useAgentLayer }
            if !agentLayerProjects.isEmpty {
                if executableResolver.resolve("al") != nil {
                    findings.append(DoctorFinding(
                        severity: .pass,
                        title: "Agent layer CLI (al) installed"
                    ))
                } else {
                    let projectNames = agentLayerProjects.map { $0.id }.joined(separator: ", ")
                    findings.append(DoctorFinding(
                        severity: .fail,
                        title: "Agent layer CLI (al) not found",
                        detail: "Required by: \(projectNames)",
                        fix: "Install: brew install conn-castle/tap/agent-layer (or set useAgentLayer=false for these projects)"
                    ))
                }
            }

            // Check project paths exist and agent-layer if required.
            let localProjects = result.projects.filter { !$0.isSSH }
            let sshProjects = result.projects.filter { $0.isSSH }

            for project in localProjects {
                checkLocalProjectPath(project: project, findings: &findings)
            }

            if !sshProjects.isEmpty {
                let sshFindings = concurrentSSHChecks(projects: sshProjects)
                findings.append(contentsOf: sshFindings)
            }
        }

        return ConfigAndProjectsResult(
            findings: findings,
            hasValidProjects: hasValidProjects,
            vscodeURL: vscodeURL,
            chromeURL: chromeURL
        )
    }

    // MARK: - Section: Apps

    /// Checks VS Code, Chrome, and Peacock extension installation.
    ///
    /// - Parameters:
    ///   - vscodeURL: VS Code application URL (nil if not found).
    ///   - chromeURL: Chrome application URL (nil if not found).
    ///   - hasValidProjects: Whether any valid projects are configured (affects severity).
    /// - Returns: Findings for the apps section.
    private func checkApps(vscodeURL: URL?, chromeURL: URL?, hasValidProjects: Bool) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        if let vscodeURL {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "VS Code installed",
                detail: vscodeURL.path
            ))
        } else {
            let severity: DoctorSeverity = hasValidProjects ? .fail : .warn
            findings.append(DoctorFinding(
                severity: severity,
                title: "VS Code not found",
                detail: "Required for IDE window management",
                fix: "Install: brew install --cask visual-studio-code"
            ))
        }

        if let chromeURL {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Google Chrome installed",
                detail: chromeURL.path
            ))
        } else {
            let severity: DoctorSeverity = hasValidProjects ? .fail : .warn
            findings.append(DoctorFinding(
                severity: severity,
                title: "Google Chrome not found",
                detail: "Required for browser window management",
                fix: "Install: brew install --cask google-chrome"
            ))
        }

        // Check Peacock VS Code extension (only when projects are configured)
        if hasValidProjects {
            let extensionsDir = dataStore.vscodeExtensionsDirectory
            let hasPeacock: Bool
            if let entries = try? fileSystem.contentsOfDirectory(at: extensionsDir) {
                hasPeacock = entries.contains { $0.hasPrefix("johnpapa.vscode-peacock-") }
            } else {
                hasPeacock = false
            }

            if hasPeacock {
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "Peacock VS Code extension installed"
                ))
            } else {
                findings.append(DoctorFinding(
                    severity: .warn,
                    title: "Peacock VS Code extension not found",
                    detail: "Required for project color differentiation in VS Code",
                    fix: "Install: code --install-extension johnpapa.vscode-peacock"
                ))
            }
        }

        return findings
    }

    // MARK: - Section: Accessibility and Hotkeys

    /// Result of the accessibility-and-hotkeys section check.
    private struct AccessibilityCheckResult {
        let findings: [DoctorFinding]
        let accessibilityNotGranted: Bool
    }

    /// Checks accessibility permission and hotkey registration status.
    /// - Returns: Findings and whether accessibility permission was not granted (for action availability).
    private func checkAccessibilityAndHotkeys() -> AccessibilityCheckResult {
        let appDisplayName = ProjectSwitcher.displayName
        var findings: [DoctorFinding] = []
        var accessibilityNotGranted = false

        if let positioner = windowPositioner {
            if positioner.isAccessibilityTrusted() {
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "Accessibility permission granted"
                ))
            } else {
                accessibilityNotGranted = true
                findings.append(DoctorFinding(
                    severity: .warn,
                    title: "Accessibility permission not granted",
                    detail: "Required for automatic window positioning when activating projects. macOS revokes this permission when the app binary changes (e.g., after an update).",
                    fix: "Open System Settings > Privacy & Security > Accessibility > Enable \(appDisplayName)"
                ))
            }
        }

        if let provider = hotkeyStatusProvider {
            switch provider.hotkeyRegistrationStatus() {
            case .registered:
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "Hotkey registered (Cmd+Shift+Space)"
                ))
            case .failed(let osStatus):
                findings.append(DoctorFinding(
                    severity: .warn,
                    title: "Hotkey registration failed",
                    detail: "OSStatus: \(osStatus)",
                    fix: "Another application may have claimed Cmd+Shift+Space. Check System Settings > Keyboard > Keyboard Shortcuts."
                ))
            case .none:
                break
            }
        }

        if let provider = focusCycleStatusProvider {
            switch provider.focusCycleRegistrationStatus() {
            case .registered:
                findings.append(DoctorFinding(
                    severity: .pass,
                    title: "Focus cycling hotkeys registered (Option-Tab / Option-Shift-Tab)"
                ))
            case .failed(let osStatus):
                findings.append(DoctorFinding(
                    severity: .warn,
                    title: "Focus cycling hotkey registration failed",
                    detail: "OSStatus: \(osStatus)",
                    fix: "Another application may have claimed Option-Tab. Check System Settings > Keyboard > Keyboard Shortcuts."
                ))
            case .none:
                break
            }
        }

        return AccessibilityCheckResult(
            findings: findings,
            accessibilityNotGranted: accessibilityNotGranted
        )
    }

    // MARK: - Project Path Checks

    /// Checks a local project path exists and has .agent-layer if required.
    private func checkLocalProjectPath(project: ProjectConfig, findings: inout [DoctorFinding]) {
        let pathURL = URL(fileURLWithPath: project.path, isDirectory: true)
        if fileSystem.directoryExists(at: pathURL) {
            findings.append(DoctorFinding(
                severity: .pass,
                title: "Project path exists: \(project.id)",
                detail: project.path
            ))

            // Check agent-layer directory if useAgentLayer is true
            if project.useAgentLayer {
                let agentLayerPath = pathURL.appendingPathComponent(".agent-layer", isDirectory: true)
                if fileSystem.directoryExists(at: agentLayerPath) {
                    findings.append(DoctorFinding(
                        severity: .pass,
                        title: "Agent layer exists: \(project.id)",
                        detail: agentLayerPath.path
                    ))
                } else {
                    findings.append(DoctorFinding(
                        severity: .warn,
                        title: "Agent layer missing: \(project.id)",
                        detail: "useAgentLayer=true but .agent-layer directory not found",
                        fix: "Create .agent-layer directory in \(project.path) or set useAgentLayer=false"
                    ))
                }
            }
        } else {
            findings.append(DoctorFinding(
                severity: .fail,
                title: "Project path missing: \(project.id)",
                detail: project.path,
                fix: "Update project.path to an existing directory."
            ))
        }
    }

    /// Checks an SSH project's remote path exists via ssh command.
    private func checkSSHProjectPath(project: ProjectConfig) -> [DoctorFinding] {
        guard let remoteAuthority = project.remote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !remoteAuthority.isEmpty else {
            // Malformed remote authority — config validation should have caught this
            return [DoctorFinding(
                severity: .fail,
                title: "Malformed SSH remote authority: \(project.id)",
                detail: project.remote,
                fix: "Use format: remote = \"ssh-remote+user@host\" and path = \"/remote/path\""
            )]
        }

        guard let authority = PsSSHHelpers.extractTarget(from: remoteAuthority) else {
            return [DoctorFinding(
                severity: .fail,
                title: "Malformed SSH remote authority: \(project.id)",
                detail: remoteAuthority,
                fix: "Use format: remote = \"ssh-remote+user@host\""
            )]
        }

        let remotePath = project.path
        if remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !remotePath.hasPrefix("/") {
            return [DoctorFinding(
                severity: .fail,
                title: "Malformed SSH remote path: \(project.id)",
                detail: remotePath,
                fix: "Use format: path = \"/remote/absolute/path\""
            )]
        }

        // Pre-check: is ssh available?
        guard executableResolver.resolve("ssh") != nil else {
            return [DoctorFinding(
                severity: .warn,
                title: "ssh not found: cannot verify remote path for \(project.id)",
                fix: "Install OpenSSH."
            )]
        }

        let escapedPath = PsSSHHelpers.shellEscape(remotePath)

        let result = commandRunner.run(
            executable: "ssh",
            arguments: [
                "-o", "ConnectTimeout=2",
                "-o", "BatchMode=yes",
                "--",
                authority,
                "test -d \(escapedPath)"
            ],
            timeoutSeconds: 3
        )

        switch result {
        case .failure(let error):
            return [DoctorFinding(
                severity: .warn,
                title: "Cannot verify remote path for \(project.id)",
                detail: error.message,
                fix: "Check SSH configuration and network connectivity to \(authority)."
            )]
        case .success(let cmdResult):
            switch cmdResult.exitCode {
            case 0:
                return [DoctorFinding(
                    severity: .pass,
                    title: "Remote project path exists: \(project.id)",
                    detail: "\(remoteAuthority) \(remotePath)"
                )]
            case 1:
                return [DoctorFinding(
                    severity: .fail,
                    title: "Remote project path missing: \(project.id)",
                    detail: "\(remoteAuthority) \(remotePath)",
                    fix: "Update path or create directory on remote host."
                )]
            case 255:
                let stderr = cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return [DoctorFinding(
                    severity: .warn,
                    title: "Cannot verify remote path: \(project.id)",
                    detail: stderr.isEmpty ? "SSH connection failed" : stderr,
                    fix: "Check SSH configuration and connectivity to \(authority)."
                )]
            default:
                let stderr = cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return [DoctorFinding(
                    severity: .warn,
                    title: "Unexpected SSH result (exit \(cmdResult.exitCode)): \(project.id)",
                    detail: stderr.isEmpty ? nil : stderr,
                    fix: "Check SSH configuration."
                )]
            }
        }
    }

    /// Checks whether the SSH project's remote `.vscode/settings.json` contains the project-switcher block.
    ///
    /// - PASS: File exists and contains `// >>> project-switcher`.
    /// - WARN: File is missing, missing the block, or SSH fails. Includes actionable snippet.
    private func checkSSHSettingsBlock(project: ProjectConfig) -> [DoctorFinding] {
        guard let remoteAuthority = project.remote?.trimmingCharacters(in: .whitespacesAndNewlines),
              !remoteAuthority.isEmpty else {
            return []
        }

        guard let sshTarget = PsSSHHelpers.extractTarget(from: remoteAuthority) else {
            return []
        }

        let remotePath = project.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remotePath.isEmpty, remotePath.hasPrefix("/") else {
            return []
        }

        guard executableResolver.resolve("ssh") != nil else {
            return [DoctorFinding(
                severity: .warn,
                title: "Cannot check remote VS Code settings for \(project.id)",
                detail: "ssh not available"
            )]
        }

        let settingsPath = PsSSHHelpers.shellEscape("\(remotePath)/.vscode/settings.json")

        let result = commandRunner.run(
            executable: "ssh",
            arguments: [
                "-o", "ConnectTimeout=2",
                "-o", "BatchMode=yes",
                "--",
                sshTarget,
                "cat \(settingsPath)"
            ],
            timeoutSeconds: 3
        )

        // Generate the block content for the snippet using the same function.
        // This should never fail for "{}" input, but guard anyway.
        let blockContent: String
        switch PsVSCodeSettingsManager.injectBlock(into: "{}", identifier: project.id) {
        case .success(let content):
            blockContent = content
        case .failure:
            blockContent = "// >>> project-switcher\n// (failed to generate block)\n// <<< project-switcher"
        }

        switch result {
        case .failure(let error):
            return [makeSettingsWarnFinding(
                project: project,
                remotePath: remotePath,
                blockContent: blockContent,
                fileExists: false,
                checkErrorDetail: error.message
            )]
        case .success(let cmdResult):
            if cmdResult.exitCode == 0
                && cmdResult.stdout.contains(PsVSCodeSettingsManager.startMarker)
                && cmdResult.stdout.contains(PsVSCodeSettingsManager.endMarker) {
                return [DoctorFinding(
                    severity: .pass,
                    title: "Remote VS Code settings block present: \(project.id)"
                )]
            } else {
                let fileExists = cmdResult.exitCode == 0 && !cmdResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let checkErrorDetail: String? = {
                    guard cmdResult.exitCode != 0 else { return nil }
                    let trimmed = cmdResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? "SSH command failed (exit \(cmdResult.exitCode))" : trimmed
                }()
                return [makeSettingsWarnFinding(
                    project: project,
                    remotePath: remotePath,
                    blockContent: blockContent,
                    fileExists: fileExists,
                    checkErrorDetail: checkErrorDetail
                )]
            }
        }
    }

    /// Builds a WARN finding for missing SSH settings.json block with an actionable snippet.
    private func makeSettingsWarnFinding(
        project: ProjectConfig,
        remotePath: String,
        blockContent: String,
        fileExists: Bool,
        checkErrorDetail: String?
    ) -> DoctorFinding {
        let name = ProjectSwitcher.displayName
        let fixText: String
        let snippet: String

        if fileExists {
            fixText = "Add the following block inside the root `{}` of your existing \(remotePath)/.vscode/settings.json"
            // Extract just the block lines (without outer braces)
            let lines = blockContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let innerLines = lines.filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed != "{" && trimmed != "}"
            }
            snippet = innerLines.joined(separator: "\n")
        } else {
            fixText = "Create or update \(remotePath)/.vscode/settings.json on the remote machine with the content below. The markers allow \(name) to manage this block automatically when SSH access is available."
            snippet = blockContent
        }

        return DoctorFinding(
            severity: .warn,
            title: "Remote .vscode/settings.json missing \(name) block: \(project.id)",
            detail: checkErrorDetail.map { "Could not read remote .vscode/settings.json: \($0)" }
                ?? "\(name) cannot reliably identify the VS Code window for this SSH project until the \(name) settings block exists and is writable via SSH.",
            fix: fixText,
            snippet: snippet,
            snippetLanguage: "jsonc"
        )
    }

    /// Runs SSH project checks concurrently and returns all findings.
    /// Each project's path check and settings block check run as a unit;
    /// multiple projects run in parallel to avoid sequential timeout accumulation.
    private func concurrentSSHChecks(projects: [ProjectConfig]) -> [DoctorFinding] {
        let lock = NSLock()
        var allFindings: [DoctorFinding] = []

        DispatchQueue.concurrentPerform(iterations: projects.count) { index in
            let project = projects[index]
            var projectFindings: [DoctorFinding] = []
            projectFindings.append(contentsOf: checkSSHProjectPath(project: project))
            projectFindings.append(contentsOf: checkSSHSettingsBlock(project: project))

            lock.lock()
            allFindings.append(contentsOf: projectFindings)
            lock.unlock()
        }

        return allFindings
    }

    /// Installs AeroSpace via Homebrew and returns an updated report.
    public func installAeroSpace() -> DoctorReport {
        _ = aerospaceHealth.healthInstallViaHomebrew()
        return run()
    }

    /// Starts AeroSpace and returns an updated report.
    public func startAeroSpace() -> DoctorReport {
        _ = aerospaceHealth.healthStart()
        return run()
    }

    /// Reloads the AeroSpace config and returns an updated report.
    public func reloadAeroSpaceConfig() -> DoctorReport {
        _ = aerospaceHealth.healthReloadConfig()
        return run()
    }

    /// Prompts for Accessibility permission and returns an updated report.
    public func requestAccessibility() -> DoctorReport {
        _ = windowPositioner?.promptForAccessibility()
        return run()
    }
}
