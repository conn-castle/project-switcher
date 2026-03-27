import Foundation
// MARK: - ProjectManager

/// Single point of entry for all project operations.
///
/// Handles:
/// - Config loading
/// - Project listing and sorting
/// - Project selection, closing, and exit
/// - Focus capture/restore for switcher UX
///
/// ## Thread Safety
///
/// **All mutable state** is serialized via two internal serial queues:
/// - `stateQueue`: protects config, projects, focus stack, recency, and callbacks.
/// - `persistenceQueue`: protects file I/O for focus history and recency.
///
/// **Lock ordering**: always acquire `stateQueue` before `persistenceQueue`
/// when both are needed in a single operation.
///
/// **Callers** may invoke any public method from any queue. Long-running
/// AeroSpace CLI calls execute on the caller's thread/queue, so callers
/// should dispatch off-main to avoid UI freezes.
///
/// **Stateless methods** (`restoreFocus(_:)`, `focusWorkspace(name:)`,
/// `focusWindow(windowId:)`) only invoke AeroSpace CLI commands and do not
/// mutate ProjectManager state; they may safely be called from detached tasks.
public final class ProjectManager {
    /// Prefix for all ProjectSwitcher workspaces (delegates to ``WorkspaceRouting/projectPrefix``).
    public static let workspacePrefix = WorkspaceRouting.projectPrefix

    static let defaultWindowPollTimeout: TimeInterval = 10.0
    static let defaultWindowPollInterval: TimeInterval = 0.1
    let windowPollTimeout: TimeInterval
    let windowPollInterval: TimeInterval
    static let maxRecentProjects = 100
    static let focusHistoryMaxEntries = 20
    static let focusHistoryMaxAge: TimeInterval = 7 * 24 * 60 * 60
    static let focusRestoreMaxRetryAttempts = 2
    static let focusRestoreRetryMaxAge: TimeInterval = 10 * 60

    // State (serialized via stateQueue)
    var config: Config?
    let configLoader: () -> Result<ConfigLoadSuccess, ConfigLoadError>

    /// Non-fatal warnings from the most recent config load.
    public private(set) var configWarnings: [ConfigFinding] {
        get { withState { configWarningsStorage } }
        set { withState { configWarningsStorage = newValue } }
    }
    var configWarningsStorage: [ConfigFinding] = []

    /// Called when the project list changes after a config load.
    /// Fires on first load (nil → projects) and on subsequent loads when the project list differs.
    public var onProjectsChanged: (([ProjectConfig]) -> Void)? {
        get { withState { onProjectsChangedStorage } }
        set { withState { onProjectsChangedStorage = newValue } }
    }
    var onProjectsChangedStorage: (([ProjectConfig]) -> Void)?

    // Recency tracking - simple list of project IDs, most recent first
    var recentProjectIds: [String] = []
    let recencyFilePath: URL

    // File I/O abstraction for testability (recency + persistence).
    let fileSystem: FileSystem
    let focusHistoryStore: FocusHistoryStore

    // Focus stack for "exit project space" restoration (non-project windows only)
    var focusStack = FocusStack(maxSize: ProjectManager.focusHistoryMaxEntries)
    // Most recently observed non-project focus for restoration fallback.
    var mostRecentNonProjectFocus: FocusHistoryEntry?
    // Retry bookkeeping for focus candidates that fail to stabilize.
    var focusRestoreRetryAttemptsByWindowId: [Int: Int] = [:]
    /// Per-project snapshot of the focus state at action-initiation time.
    /// When a user activates Project B from Project A's window, this stores A's window
    /// under key "B". On close of B, we try to restore A's window first.
    var preEntryFocus: [String: FocusHistoryEntry] = [:]

    // Serializes all mutable state across background + main usage.
    let stateQueue = DispatchQueue(label: "com.projectswitcher.project_manager.state")
    let stateQueueKey = DispatchSpecificKey<Bool>()
    let persistenceQueue = DispatchQueue(label: "com.projectswitcher.project_manager.persistence")
    let persistenceQueueKey = DispatchSpecificKey<Bool>()

    // Internal dependencies
    let aerospace: AeroSpaceProviding
    let ideLauncher: IdeLauncherProviding
    let agentLayerIdeLauncher: IdeLauncherProviding
    let chromeLauncher: ChromeLauncherProviding
    let chromeTabStore: ChromeTabStore
    let chromeTabCapture: ChromeTabCapturing
    let gitRemoteResolver: GitRemoteResolving
    let windowPositioner: WindowPositioning?
    let windowPositionStore: WindowPositionStoring?
    let screenModeDetector: ScreenModeDetecting?
    let mainScreenVisibleFrame: (() -> CGRect?)?
    let logger: ProjectSwitcherLogging

    // MARK: - Public Properties

    /// All projects from config, or empty if config not loaded.
    public var projects: [ProjectConfig] {
        withState { config?.projects ?? [] }
    }

    /// Returns the open + focused ProjectSwitcher workspace state from a single AeroSpace query.
    public func workspaceState() -> Result<ProjectWorkspaceState, ProjectError> {
        let workspaceSummaries: [PsWorkspaceSummary]
        switch aerospace.listWorkspacesWithFocus() {
        case .failure(let error):
            logEvent("workspace_state.failed", level: error.isBreakerOpen ? .info : .warn, message: error.message)
            return .failure(.aeroSpaceError(detail: error.message))
        case .success(let result):
            workspaceSummaries = result
        }

        var openProjectIds = Set<String>()
        var activeProjectId: String?

        for summary in workspaceSummaries {
            guard let projectId = Self.projectId(fromWorkspace: summary.workspace) else {
                continue
            }

            openProjectIds.insert(projectId)
            if summary.isFocused, activeProjectId == nil {
                activeProjectId = projectId
            }
        }

        return .success(
            ProjectWorkspaceState(
                activeProjectId: activeProjectId,
                openProjectIds: openProjectIds
            )
        )
    }

    // MARK: - Initialization

    /// Creates a ProjectManager with default dependencies.
    ///
    /// - Parameters:
    ///   - windowPositioner: Window positioning provider (from AppKit module). Pass nil to disable positioning.
    ///   - screenModeDetector: Screen mode detection provider (from AppKit module). Pass nil to disable positioning.
    ///   - processChecker: Process checker for AeroSpace auto-recovery. Pass nil to disable.
    public init(
        windowPositioner: WindowPositioning? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        processChecker: RunningApplicationChecking? = nil,
        mainScreenVisibleFrame: (() -> CGRect?)? = nil
    ) {
        let dataPaths = DataPaths.default()
        let fileSystem = DefaultFileSystem()
        self.aerospace = PsAeroSpace(processChecker: processChecker)
        self.ideLauncher = PsVSCodeLauncher()
        self.agentLayerIdeLauncher = PsAgentLayerVSCodeLauncher()
        self.chromeLauncher = PsChromeLauncher()
        self.chromeTabStore = ChromeTabStore(directory: dataPaths.chromeTabsDirectory, fileSystem: fileSystem)
        self.chromeTabCapture = PsChromeTabController()
        self.gitRemoteResolver = GitRemoteResolver()
        self.windowPositioner = windowPositioner
        self.screenModeDetector = screenModeDetector
        self.windowPositionStore = (windowPositioner != nil && screenModeDetector != nil)
            ? WindowPositionStore(filePath: dataPaths.windowLayoutsFile)
            : nil
        self.mainScreenVisibleFrame = mainScreenVisibleFrame
        self.logger = ProjectSwitcherLogger()
        self.recencyFilePath = dataPaths.recentProjectsFile
        self.configLoader = { Config.loadDefault() }
        self.fileSystem = fileSystem
        self.focusHistoryStore = FocusHistoryStore(
            fileURL: dataPaths.stateFile,
            fileSystem: fileSystem,
            maxAge: Self.focusHistoryMaxAge,
            maxEntries: Self.focusHistoryMaxEntries
        )
        self.windowPollTimeout = Self.defaultWindowPollTimeout
        self.windowPollInterval = Self.defaultWindowPollInterval

        configureStateQueue()
        configurePersistenceQueue()
        loadRecency()
        loadFocusHistory()
    }

    /// Creates a ProjectManager with injected dependencies (for testing).
    init(
        aerospace: AeroSpaceProviding,
        ideLauncher: IdeLauncherProviding,
        agentLayerIdeLauncher: IdeLauncherProviding,
        chromeLauncher: ChromeLauncherProviding,
        chromeTabStore: ChromeTabStore,
        chromeTabCapture: ChromeTabCapturing,
        gitRemoteResolver: GitRemoteResolving,
        logger: ProjectSwitcherLogging,
        recencyFilePath: URL,
        focusHistoryFilePath: URL,
        configLoader: @escaping () -> Result<ConfigLoadSuccess, ConfigLoadError> = { Config.loadDefault() },
        fileSystem: FileSystem = DefaultFileSystem(),
        windowPositioner: WindowPositioning? = nil,
        windowPositionStore: WindowPositionStoring? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        mainScreenVisibleFrame: (() -> CGRect?)? = nil,
        windowPollTimeout: TimeInterval = defaultWindowPollTimeout,
        windowPollInterval: TimeInterval = defaultWindowPollInterval
    ) {
        self.aerospace = aerospace
        self.ideLauncher = ideLauncher
        self.agentLayerIdeLauncher = agentLayerIdeLauncher
        self.chromeLauncher = chromeLauncher
        self.chromeTabStore = chromeTabStore
        self.chromeTabCapture = chromeTabCapture
        self.gitRemoteResolver = gitRemoteResolver
        self.windowPositioner = windowPositioner
        self.windowPositionStore = windowPositionStore
        self.screenModeDetector = screenModeDetector
        self.mainScreenVisibleFrame = mainScreenVisibleFrame
        self.logger = logger
        self.recencyFilePath = recencyFilePath
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.focusHistoryStore = FocusHistoryStore(
            fileURL: focusHistoryFilePath,
            fileSystem: fileSystem,
            maxAge: Self.focusHistoryMaxAge,
            maxEntries: Self.focusHistoryMaxEntries
        )
        precondition(windowPollTimeout.isFinite && windowPollTimeout >= 0, "windowPollTimeout must be finite and non-negative")
        precondition(windowPollInterval.isFinite && windowPollInterval >= 0, "windowPollInterval must be finite and non-negative")
        self.windowPollTimeout = windowPollTimeout
        self.windowPollInterval = windowPollInterval

        configureStateQueue()
        configurePersistenceQueue()
        loadRecency()
        loadFocusHistory()
    }

    private func configureStateQueue() {
        stateQueue.setSpecific(key: stateQueueKey, value: true)
    }

    private func configurePersistenceQueue() {
        persistenceQueue.setSpecific(key: persistenceQueueKey, value: true)
    }

    // MARK: - Configuration

    /// Returns the current layout config from the last config load, or defaults if not loaded.
    ///
    /// Use this when you need to read layout config without triggering a config load
    /// (which would mutate shared state on failure).
    public var currentLayoutConfig: LayoutConfig {
        withState { config?.layout ?? LayoutConfig() }
    }

    /// Sets config directly for testing (internal; accessible via @testable import).
    func loadTestConfig(_ config: Config) {
        withState {
            self.config = config
        }
    }

    func withState<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: stateQueueKey) == true {
            return work()
        }
        return stateQueue.sync { work() }
    }

    func withPersistence<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: persistenceQueueKey) == true {
            return work()
        }
        return persistenceQueue.sync { work() }
    }

    struct FocusHistorySnapshot {
        let stackCount: Int
        let recentWindowId: Int?
    }

    func focusHistorySnapshot() -> FocusHistorySnapshot {
        withState {
            FocusHistorySnapshot(
                stackCount: focusStack.count,
                recentWindowId: mostRecentNonProjectFocus?.windowId
            )
        }
    }

    func focusHistoryContext(
        windowId: Int? = nil,
        workspace: String? = nil,
        appBundleId: String? = nil,
        method: String? = nil,
        reason: String? = nil,
        snapshot: FocusHistorySnapshot? = nil
    ) -> [String: String] {
        var context: [String: String] = [:]
        if let windowId {
            context["window_id"] = "\(windowId)"
        }
        if let workspace {
            context["workspace"] = workspace
        }
        if let appBundleId {
            context["app_bundle_id"] = appBundleId
        }
        if let method {
            context["method"] = method
        }
        if let reason {
            context["reason"] = reason
        }
        if let snapshot {
            context["stack_count"] = "\(snapshot.stackCount)"
            if let recentWindowId = snapshot.recentWindowId {
                context["recent_window_id"] = "\(recentWindowId)"
            }
        }
        return context
    }

    /// Pushes a focus entry directly onto the focus stack (no filtering).
    ///
    /// Test-only helper for injecting known stack state. Does NOT replicate
    /// the project-workspace filtering from `selectProject` — that logic is
    /// tested via integration tests that drive through `selectProject` directly.
    /// Internal; accessible via @testable import.
    func pushFocusForTest(_ focus: CapturedFocus) {
        let entry = FocusHistoryEntry(focus: focus, capturedAt: Date())
        withState {
            focusStack.push(entry)
            mostRecentNonProjectFocus = entry
            focusRestoreRetryAttemptsByWindowId[focus.windowId] = 0
        }
        persistFocusHistory()
    }

    /// Test helper: sets the pre-entry focus for a project (simulates selectProject storing it).
    func setPreEntryFocusForTest(projectId: String, focus: CapturedFocus) {
        withState {
            preEntryFocus[projectId] = FocusHistoryEntry(focus: focus, capturedAt: Date())
        }
    }

    /// Loads configuration from the default path.
    ///
    /// Call this before using other methods. Returns the config on success.
    @discardableResult
    public func loadConfig() -> Result<ConfigLoadSuccess, ConfigLoadError> {
        switch configLoader() {
        case .success(let success):
            let callbackPayload: (([ProjectConfig]) -> Void, [ProjectConfig])? = withState {
                let oldProjects = self.config?.projects ?? []
                self.config = success.config
                self.configWarningsStorage = success.warnings
                guard success.config.projects != oldProjects,
                      let callback = self.onProjectsChangedStorage else {
                    return nil
                }
                return (callback, success.config.projects)
            }
            logEvent("config.loaded", context: ["project_count": "\(success.config.projects.count)"])
            if let (callback, projects) = callbackPayload {
                callback(projects)
            }
            return .success(success)
        case .failure(let error):
            withState {
                self.config = nil
                self.configWarningsStorage = []
            }
            logEvent("config.failed", level: .error, message: "\(error)")
            return .failure(error)
        }
    }

}
