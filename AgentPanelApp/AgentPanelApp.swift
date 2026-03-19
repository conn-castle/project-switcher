import AppKit
import ServiceManagement
import SwiftUI

import AgentPanelAppKit
import AgentPanelCore

/// Timing constants for menu behavior.
private enum MenuTiming {
    /// Delay after dismissing the menu before showing the switcher.
    /// Required to let AppKit finish menu dismissal animation.
    static let menuDismissDelaySeconds: TimeInterval = 0.05
}

/// Menu bar indicator constants.
private enum MenuBarHealthIndicator {
    static let symbolName = "square.stack"
    static let accessibilityDescription = "AgentPanel health indicator"
    static let devBadgeTitle = " Dev"
    /// Minimum interval between background Doctor refreshes to avoid spamming CLI calls.
    static let refreshDebounceSeconds: TimeInterval = 30.0
}

/// User interaction source for switcher toggles managed by AppDelegate.
private enum SwitcherToggleTrigger {
    case hotkey
    case reopen
}

@main
struct AgentPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

private struct MenuItems {
    let hotkeyWarning: NSMenuItem
    let openSwitcher: NSMenuItem
    let addWindowToProject: NSMenuItem
    let recoverCurrentWindow: NSMenuItem
    let recoverAgentPanel: NSMenuItem
    let recoverAllWindows: NSMenuItem
    let launchAtLogin: NSMenuItem
}

/// App lifecycle hook used to create a minimal menu bar presence.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Reads `NSScreen.main?.visibleFrame` on the main thread and can be called
    /// safely from background queues used by focus cycling/restoration flows.
    private static func mainScreenVisibleFrame() -> CGRect? {
        if Thread.isMainThread {
            return NSScreen.main?.visibleFrame
        }
        return DispatchQueue.main.sync {
            NSScreen.main?.visibleFrame
        }
    }

    private var statusItem: NSStatusItem?
    private var doctorController: DoctorWindowController?
    private var recoveryController: RecoveryProgressController?
    private var hotkeyManager: HotkeyManager?
    private var focusCycleHotkeyManager: FocusCycleHotkeyManager?
    private var windowCycleOverlayCoordinator: WindowCycleOverlayCoordinator?
    private var switcherController: SwitcherPanelController?
    private var menuItems: MenuItems?
    private var doctorIndicatorSeverity: DoctorSeverity?
    private var lastHotkeyToggleAt: Date?
    /// Set when the accessibility permission prompt fires this launch.
    /// Prevents Doctor's startup health refresh from stealing focus from the system dialog.
    private var didPromptForAccessibilityThisLaunch = false
    private var healthCoordinator: AppHealthCoordinator?
    private var menuWorkspaceCoordinator: MenuWorkspaceStateCoordinator?
    private var recoveryOperationCoordinator: RecoveryOperationCoordinator?
    /// Serial queue for immediate (non-overlay) Option-Tab fallback to avoid focus races.
    private let immediateWindowCycleQueue = DispatchQueue(
        label: "com.agentpanel.window-cycle-immediate",
        qos: .userInteractive
    )
    private let logger: AgentPanelLogging = AgentPanelLogger()
    private let launchAtLoginToggler = LaunchAtLoginToggler()
    private let appDisplayName = AgentPanel.displayName
    private let isDevAppVariant = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    private let projectManager = ProjectManager(
        windowPositioner: AXWindowPositioner(),
        screenModeDetector: ScreenModeDetector(),
        processChecker: AppKitRunningApplicationChecker(),
        mainScreenVisibleFrame: { AppDelegate.mainScreenVisibleFrame() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Skip real app setup when running inside the test host.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // Run onboarding check asynchronously before setting up the app
        let onboarding = Onboarding(logger: logger)
        onboarding.runIfNeeded { [weak self] result in
            guard let self else { return }

            if result == .declined {
                NSApplication.shared.terminate(nil)
                return
            }

            self.completeAppSetup()
        }
    }

    /// Handles app reopen events (for example double-clicking the app while it's already running).
    ///
    /// AgentPanel is a menu bar app (`LSUIElement`) without a standard window, so reopen events
    /// should produce immediate visible feedback by showing/toggling the switcher.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logAppEvent(
            event: "app.reopen.requested",
            context: ["has_visible_windows": flag ? "true" : "false"]
        )
        guard statusItem != nil else {
            return false
        }
        toggleSwitcher(trigger: .reopen)
        return false
    }

    /// Completes app setup after onboarding succeeds.
    private func completeAppSetup() {
        NSApp.setActivationPolicy(.accessory)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = makeMenu()
        self.statusItem = statusItem
        updateMenuBarHealthIndicator(severity: nil)

        // Initialize coordinators — closures capture [weak self] to avoid retain cycles.
        let menuWSCoordinator = MenuWorkspaceStateCoordinator(
            projectManager: projectManager
        )
        self.menuWorkspaceCoordinator = menuWSCoordinator

        let healthCoord = AppHealthCoordinator(
            logger: logger,
            refreshDebounceSeconds: MenuBarHealthIndicator.refreshDebounceSeconds,
            makeDoctor: { [weak self] in
                self?.makeDoctor() ?? Doctor(
                    runningApplicationChecker: AppKitRunningApplicationChecker(),
                    hotkeyStatusProvider: nil,
                    focusCycleStatusProvider: nil,
                    windowPositioner: AXWindowPositioner()
                )
            },
            currentIndicatorSeverity: { [weak self] in
                self?.doctorIndicatorSeverity
            },
            updateMenuBarHealthIndicator: { [weak self] severity in
                self?.updateMenuBarHealthIndicator(severity: severity)
            },
            showDoctorReport: { [weak self] report, skipActivation in
                self?.showDoctorReport(report, skipActivation: skipActivation)
            },
            refreshMenuStateInBackground: { [weak self] in
                self?.menuWorkspaceCoordinator?.refreshInBackground()
            },
            shouldSkipAutoShowActivation: { [weak self] trigger in
                trigger == "startup" && (self?.didPromptForAccessibilityThisLaunch ?? false)
            }
        )
        self.healthCoordinator = healthCoord

        let recoveryCoord = RecoveryOperationCoordinator(
            logger: logger,
            makeRecoveryManager: { [weak self] screenFrame, layoutConfig in
                self?.makeWindowRecoveryManager(screenFrame: screenFrame, layoutConfig: layoutConfig)
                    ?? WindowRecoveryManager(
                        windowPositioner: AXWindowPositioner(),
                        screenVisibleFrame: screenFrame,
                        logger: AgentPanelLogger()
                    )
            },
            currentLayoutConfig: { [weak self] in
                self?.projectManager.currentLayoutConfig
            }
        )
        recoveryCoord.onCurrentWindowRecovered = { [weak self] result, windowId, workspace in
            guard let self else { return }
            switch result {
            case .success(let outcome):
                let outcomeLabel: String
                switch outcome {
                case .recovered: outcomeLabel = "recovered"
                case .unchanged: outcomeLabel = "unchanged"
                case .notFound: outcomeLabel = "not_found"
                }
                self.logAppEvent(
                    event: "recover_current_window.completed",
                    context: [
                        "window_id": "\(windowId)",
                        "workspace": workspace,
                        "outcome": outcomeLabel
                    ]
                )
            case .failure(let error):
                self.logAppEvent(
                    event: "recover_current_window.failed",
                    level: .error,
                    message: error.message
                )
            }
        }
        recoveryCoord.onWorkspaceRecovered = { [weak self] result, focus in
            guard let self else { return }
            switch result {
            case .success(let recovery):
                let workspaceType = WorkspaceRouting.isProjectWorkspace(focus.workspace) ? "project" : "non_project"
                self.logAppEvent(
                    event: "recover_agent_panel.completed",
                    context: [
                        "workspace": focus.workspace,
                        "workspace_type": workspaceType,
                        "processed": "\(recovery.windowsProcessed)",
                        "recovered": "\(recovery.windowsRecovered)"
                    ]
                )
            case .failure(let error):
                self.logAppEvent(
                    event: "recover_agent_panel.failed",
                    level: .error,
                    message: error.message
                )
            }
        }
        recoveryCoord.onAllWindowsProgress = { [weak self] current, total in
            self?.recoveryController?.updateProgress(current: current, total: total)
        }
        recoveryCoord.onAllWindowsCompleted = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let recovery):
                let message: String
                if recovery.errors.isEmpty {
                    message = "Recovered \(recovery.windowsRecovered) of \(recovery.windowsProcessed) windows."
                } else {
                    message = "Recovered \(recovery.windowsRecovered) of \(recovery.windowsProcessed) windows (\(recovery.errors.count) errors)."
                }
                self.recoveryController?.showCompletion(message: message)
                self.logAppEvent(
                    event: "recover_all_windows.completed",
                    context: [
                        "processed": "\(recovery.windowsProcessed)",
                        "recovered": "\(recovery.windowsRecovered)",
                        "errors": "\(recovery.errors.count)"
                    ]
                )
            case .failure(let error):
                self.recoveryController?.showCompletion(
                    message: "Recovery failed: \(error.message)"
                )
                self.logAppEvent(
                    event: "recover_all_windows.failed",
                    level: .error,
                    message: error.message
                )
            }
        }
        self.recoveryOperationCoordinator = recoveryCoord

        requestAccessibilityOnFirstLaunchIfNeeded()

        self.switcherController = makeSwitcherController()

        let hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkey = { [weak self] in
            self?.toggleSwitcher(trigger: .hotkey)
        }
        hotkeyManager.onStatusChange = { [weak self] status in
            self?.updateHotkeyStatus(status)
        }
        hotkeyManager.registerHotkey()
        self.hotkeyManager = hotkeyManager
        updateHotkeyStatus(hotkeyManager.hotkeyRegistrationStatus())

        // Auto-start AeroSpace if installed but not running
        ensureAeroSpaceRunning()

        // Auto-update AeroSpace config if stale (preserves user sections)
        let aeroConfigManager = AeroSpaceConfigManager()
        switch aeroConfigManager.ensureUpToDate() {
        case .success(let result):
            if case .updated(let from, let to) = result {
                logAppEvent(event: "aerospace_config.updated", context: ["from": "\(from)", "to": "\(to)"])
                // Apply updated config to the running AeroSpace process.
                // Dispatched to background to avoid blocking the main thread — the
                // reload calls ApSystemCommandRunner.run() which may trigger the
                // one-time login shell PATH resolution on first use.
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let aerospace = ApAeroSpace()
                    switch aerospace.reloadConfig() {
                    case .success:
                        self?.logAppEvent(event: "aerospace_config.reloaded")
                    case .failure(let error):
                        self?.logAppEvent(event: "aerospace_config.reload_failed", level: .warn, message: error.message)
                    }
                }
            }
            // Cleanup stale focus scripts from the script-based approach
            cleanupStaleFocusScripts()
        case .failure(let error):
            logAppEvent(event: "aerospace_config.update_failed", level: .warn, message: error.message)
        }

        // Register window cycling hotkeys (Option-Tab / Option-Shift-Tab)
        let windowCycler = WindowCycler(processChecker: AppKitRunningApplicationChecker())
        let focusCycleManager = FocusCycleHotkeyManager()
        let windowPositioner = AXWindowPositioner()
        let mainScreenVisibleFrame = { AppDelegate.mainScreenVisibleFrame() }
        let overlayCoordinator = WindowCycleOverlayCoordinator(
            windowCycler: windowCycler,
            logger: logger,
            shouldSuppressOverlay: { [weak self] in
                self?.switcherController?.isVisible == true
            },
            windowPositioner: windowPositioner,
            mainScreenVisibleFrame: mainScreenVisibleFrame
        )
        focusCycleManager.onCycleNext = { [weak self] in
            self?.performImmediateWindowCycle(windowCycler: windowCycler, direction: .next)
        }
        focusCycleManager.onCyclePrevious = { [weak self] in
            self?.performImmediateWindowCycle(windowCycler: windowCycler, direction: .previous)
        }
        focusCycleManager.onCycleOverlayStart = { direction in
            overlayCoordinator.start(direction: direction) { [weak self] in
                self?.performImmediateWindowCycle(windowCycler: windowCycler, direction: direction)
            }
        }
        focusCycleManager.onCycleOverlayAdvance = { direction in
            overlayCoordinator.advance(direction: direction) { [weak self] in
                self?.performImmediateWindowCycle(windowCycler: windowCycler, direction: direction)
            }
        }
        focusCycleManager.onCycleOverlayCommit = {
            overlayCoordinator.commit()
        }
        focusCycleManager.registerHotkeys()
        self.focusCycleHotkeyManager = focusCycleManager
        self.windowCycleOverlayCoordinator = overlayCoordinator

        // Wire settings block writes: fires on first loadConfig() and whenever the project list changes.
        // On startup the first fire triggers ensureAll → then Doctor. On subsequent config reloads
        // (e.g., switcher open), only ensureAll runs (Doctor is triggered separately by session end).
        projectManager.onProjectsChanged = { [weak self] projects in
            DispatchQueue.global(qos: .userInitiated).async {
                let results = VSCodeSettingsBlocks.ensureAll(projects: projects)
                for (projectId, result) in results {
                    if case .failure(let error) = result {
                        let isSSH = projects.first(where: { $0.id == projectId })?.isSSH == true
                        self?.logAppEvent(
                            event: "settings_block.write_failed",
                            level: .warn,
                            message: error.message,
                            context: [
                                "project_id": projectId,
                                "type": isSSH ? "ssh" : "local"
                            ]
                        )
                    }
                }
                // On startup, run Doctor after settings blocks are written so it doesn't
                // report spurious warnings for blocks that are still being written.
                // Check lastHealthRefreshAt on the main thread (AppHealthCoordinator
                // is main-thread-confined) to avoid a data race.
                DispatchQueue.main.async {
                    if self?.healthCoordinator?.lastHealthRefreshAt == nil {
                        self?.healthCoordinator?.refreshHealthInBackground(trigger: "startup", force: true)
                    }
                }
            }
        }

        // Load config on the main thread (ProjectManager is not thread-safe).
        // The onProjectsChanged callback above handles settings block writes + startup Doctor.
        let configResult = projectManager.loadConfig()
        let loadedConfig = try? configResult.get()

        // Apply auto-start at login from config (only when config loaded successfully)
        if let loadedConfig {
            syncLaunchAtLogin(configValue: loadedConfig.config.app.autoStartAtLogin)
        }

        // If config load failed (no projects), the callback never fired — run Doctor directly.
        if loadedConfig == nil {
            healthCoordinator?.refreshHealthInBackground(trigger: "startup", force: true)
        }

        let dataStore = DataPaths.default()
        // Monitor display configuration changes (dock/undock, monitor connect/disconnect).
        // These events correlate with AeroSpace tree-node bugs and window scrambling.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        logAppEvent(
            event: "app.started",
            context: [
                "version": AgentPanel.version,
                "binary_path": Bundle.main.executablePath ?? "unknown",
                "bundle_path": Bundle.main.bundlePath,
                "log_path": dataStore.primaryLogFile.path,
                "config_path": dataStore.configFile.path,
                "macos_version": ProcessInfo.processInfo.operatingSystemVersionString
            ]
        )
    }

    /// Requests Accessibility once per app build on startup if not already granted.
    ///
    /// The prompt is shown on first launch of each installed build (`CFBundleVersion`).
    /// If permission is already granted, this records the build and skips prompting.
    private func requestAccessibilityOnFirstLaunchIfNeeded() {
        let windowPositioner = AXWindowPositioner()
        let isTrusted = windowPositioner.isAccessibilityTrusted()
        let currentBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? AgentPanel.version

        let gate = AccessibilityStartupPromptGate()
        let shouldPrompt = gate.shouldPromptOnFirstLaunchOfCurrentBuild(
            currentBuild: currentBuild,
            isAccessibilityTrusted: isTrusted
        )

        guard shouldPrompt else {
            let reason = isTrusted ? "already_trusted" : "already_prompted_for_build"
            logAppEvent(
                event: "accessibility.startup_prompt.skipped",
                context: ["reason": reason, "build": currentBuild]
            )
            return
        }

        logAppEvent(
            event: "accessibility.startup_prompt.requested",
            context: ["build": currentBuild]
        )
        didPromptForAccessibilityThisLaunch = true
        let trustedAfterPrompt = windowPositioner.promptForAccessibility()
        logAppEvent(
            event: "accessibility.startup_prompt.completed",
            context: [
                "build": currentBuild,
                "trusted_after_prompt": trustedAfterPrompt ? "true" : "false"
            ]
        )
    }

    /// Ensures AeroSpace is running if it's installed.
    private func ensureAeroSpaceRunning() {
        let aerospace = ApAeroSpace()
        let checker = AppKitRunningApplicationChecker()

        guard aerospace.isAppInstalled() else {
            logAppEvent(
                event: "aerospace.autostart.skipped",
                level: .warn,
                message: "AeroSpace not installed"
            )
            return
        }

        if checker.isApplicationRunning(bundleIdentifier: ApAeroSpace.bundleIdentifier) {
            logAppEvent(event: "aerospace.autostart.skipped", message: "Already running")
            return
        }

        logAppEvent(event: "aerospace.autostart.starting")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch aerospace.start() {
            case .success:
                self?.logAppEvent(event: "aerospace.autostart.success")
            case .failure(let error):
                self?.logAppEvent(
                    event: "aerospace.autostart.failed",
                    level: .error,
                    message: error.message
                )
            }
        }
    }

    /// Removes stale focus cycling scripts from the previous script-based approach.
    private func cleanupStaleFocusScripts() {
        let binDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/agent-panel/bin")
        for name in ["ap-focus-next", "ap-focus-prev"] {
            let fileURL = binDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    /// Creates the menu bar menu.
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About \(appDisplayName)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        if isDevAppVariant {
            let variantItem = NSMenuItem(
                title: "Running \(appDisplayName) (dev identity)",
                action: nil,
                keyEquivalent: ""
            )
            variantItem.isEnabled = false
            menu.addItem(variantItem)
        }

        menu.addItem(.separator())

        let hotkeyWarningItem = NSMenuItem(
            title: "Hotkey unavailable",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyWarningItem.isEnabled = false
        hotkeyWarningItem.isHidden = true
        menu.addItem(hotkeyWarningItem)

        let openSwitcherItem = NSMenuItem(
            title: "Open Switcher...",
            action: #selector(openSwitcher(_:)),
            keyEquivalent: ""
        )
        openSwitcherItem.target = self
        menu.addItem(openSwitcherItem)

        let viewConfigItem = NSMenuItem(
            title: "View Config File...",
            action: #selector(viewConfigFile),
            keyEquivalent: ""
        )
        viewConfigItem.target = self
        menu.addItem(viewConfigItem)

        menu.addItem(.separator())

        // Recovery and window management items
        let addWindowToProjectItem = NSMenuItem(
            title: "Move Current Window",
            action: nil,
            keyEquivalent: ""
        )
        addWindowToProjectItem.submenu = NSMenu()
        addWindowToProjectItem.isHidden = true // Toggled in menuNeedsUpdate
        menu.addItem(addWindowToProjectItem)

        let recoverCurrentWindowItem = NSMenuItem(
            title: "Recover Current Window",
            action: #selector(recoverCurrentWindow),
            keyEquivalent: ""
        )
        recoverCurrentWindowItem.target = self
        recoverCurrentWindowItem.isEnabled = false // Toggled in menuNeedsUpdate
        menu.addItem(recoverCurrentWindowItem)

        let recoverAgentPanelItem = NSMenuItem(
            title: "Recover Project",
            action: #selector(recoverAgentPanel),
            keyEquivalent: ""
        )
        recoverAgentPanelItem.target = self
        recoverAgentPanelItem.isEnabled = false // Toggled in menuNeedsUpdate
        menu.addItem(recoverAgentPanelItem)

        let recoverAllWindowsItem = NSMenuItem(
            title: "Recover All Projects...",
            action: #selector(recoverAllWindowsAction),
            keyEquivalent: ""
        )
        recoverAllWindowsItem.target = self
        menu.addItem(recoverAllWindowsItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Run Doctor...",
                action: #selector(runDoctor),
                keyEquivalent: "d"
            )
        )
        menu.addItem(.separator())

        let launchAtLoginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        menu.delegate = self

        menuItems = MenuItems(
            hotkeyWarning: hotkeyWarningItem,
            openSwitcher: openSwitcherItem,
            addWindowToProject: addWindowToProjectItem,
            recoverCurrentWindow: recoverCurrentWindowItem,
            recoverAgentPanel: recoverAgentPanelItem,
            recoverAllWindows: recoverAllWindowsItem,
            launchAtLogin: launchAtLoginItem
        )

        return menu
    }

    /// Opens the switcher panel from the menu bar.
    @objc private func openSwitcher(_ sender: Any?) {
        logAppEvent(
            event: "switcher.menu.invoked",
            context: ["menu_item": "Open Switcher..."]
        )
        // Capture the previously active app immediately (AppKit API, non-blocking).
        let previousApp = NSWorkspace.shared.frontmostApplication
        statusItem?.menu?.cancelTracking()

        // Capture AeroSpace focus in the background to avoid blocking the menu thread.
        // We still wait for the menu-dismiss delay before showing the switcher.
        let showAfter = Date().addingTimeInterval(MenuTiming.menuDismissDelaySeconds)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let capturedFocus = self.projectManager.captureCurrentFocus()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.menuWorkspaceCoordinator?.updateFocusCapture(capturedFocus)
                let delay = max(0, showAfter.timeIntervalSinceNow)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    // The panel uses .nonactivatingPanel style mask, so it receives keyboard input
                    // without activating the app (and therefore without switching workspaces).
                    self.ensureSwitcherController().show(origin: .menu, previousApp: previousApp, capturedFocus: self.menuWorkspaceCoordinator?.menuFocusCapture)
                }
            }
        }
    }

    /// Minimum interval between hotkey toggles to prevent session storms during AeroSpace outages.
    private static let hotkeyDebounceSeconds: TimeInterval = 0.3

    /// Toggles the switcher panel from a user interaction source.
    /// - Parameter trigger: Interaction source that requested the toggle.
    private func toggleSwitcher(trigger: SwitcherToggleTrigger) {
        if trigger == .hotkey {
            // Debounce: ignore rapid presses within 300ms to prevent session storms
            // when AeroSpace is unresponsive and the user mashes the hotkey.
            let now = Date()
            if let last = lastHotkeyToggleAt,
               now.timeIntervalSince(last) < Self.hotkeyDebounceSeconds {
                logAppEvent(event: "switcher.hotkey.debounced")
                return
            }
            lastHotkeyToggleAt = now
        }

        // Capture the previously active app immediately (AppKit API, instant).
        let previousApp = NSWorkspace.shared.frontmostApplication

        // Capture AeroSpace focus in background to avoid blocking the main thread.
        // The switcher toggle is dispatched to main thread once the capture completes.
        // Thread-safe: captureCurrentFocus() serializes ProjectManager state/persistence.
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let capturedFocus = self.projectManager.captureCurrentFocus()
            DispatchQueue.main.async {
                let origin: SwitcherPresentationSource
                switch trigger {
                case .hotkey:
                    origin = .hotkey
                    self.logAppEvent(
                        event: "switcher.hotkey.invoked",
                        context: ["hotkey": "Cmd+Shift+Space"]
                    )
                case .reopen:
                    origin = .reopen
                    self.logAppEvent(event: "switcher.reopen.invoked")
                }
                // The panel uses .nonactivatingPanel style mask, so it receives keyboard input
                // without activating the app (and therefore without switching workspaces).
                self.ensureSwitcherController().toggle(
                    origin: origin,
                    previousApp: previousApp,
                    capturedFocus: capturedFocus
                )
            }
        }
    }

    /// Runs a single immediate window cycle (legacy fallback path).
    /// - Parameters:
    ///   - windowCycler: Window cycler used to perform focus movement.
    ///   - direction: Cycle direction to apply.
    private func performImmediateWindowCycle(windowCycler: WindowCycler, direction: CycleDirection) {
        immediateWindowCycleQueue.async { [weak self] in
            switch windowCycler.cycleFocus(direction: direction) {
            case .success(let candidate?):
                // Recover the focused window if it is off-screen or oversized.
                if let screenFrame = AppDelegate.mainScreenVisibleFrame() {
                    _ = AXWindowPositioner().recoverFocusedWindow(
                        bundleId: candidate.appBundleId,
                        screenVisibleFrame: screenFrame
                    )
                }
            case .success(nil):
                break
            case .failure(let error):
                switch direction {
                case .next:
                    self?.logAppEvent(event: "focus_cycle.next.failed", level: .warn, message: error.message)
                case .previous:
                    self?.logAppEvent(event: "focus_cycle.prev.failed", level: .warn, message: error.message)
                }
            }
        }
    }

    /// Creates a new SwitcherPanelController instance.
    private func makeSwitcherController() -> SwitcherPanelController {
        let controller = SwitcherPanelController(logger: logger, projectManager: projectManager)
        controller.onProjectOperationFailed = { [weak self] context in
            self?.healthCoordinator?.refreshHealthInBackground(trigger: "project_operation_failed", errorContext: context)
        }
        controller.onRecoverProjectRequested = { [weak self] focus, completion in
            guard let self else {
                completion(.failure(ApCoreError(category: .command, message: "Recover Project unavailable.")))
                return
            }

            guard let screenFrame = NSScreen.main?.visibleFrame else {
                self.logAppEvent(event: "recovery.no_screen", level: .error, message: "No primary screen available")
                let error = ApCoreError(category: .system, message: "No primary screen available")
                self.logAppEvent(event: "switcher.recover_project.failed", level: .error, message: error.message)
                completion(.failure(error))
                return
            }

            guard let recoveryCoord = self.recoveryOperationCoordinator else {
                let error = ApCoreError(category: .system, message: "Recovery coordinator unavailable")
                self.logAppEvent(event: "switcher.recover_project.failed", level: .error, message: error.message)
                completion(.failure(error))
                return
            }

            recoveryCoord.recoverWorkspaceWindows(focus: focus, screenFrame: screenFrame) { [weak self] result in
                guard let self else {
                    completion(result)
                    return
                }
                switch result {
                case .success(let recovery):
                    let workspaceType = WorkspaceRouting.isProjectWorkspace(focus.workspace) ? "project" : "non_project"
                    self.logAppEvent(
                        event: "switcher.recover_project.completed",
                        context: [
                            "workspace": focus.workspace,
                            "workspace_type": workspaceType,
                            "processed": "\(recovery.windowsProcessed)",
                            "recovered": "\(recovery.windowsRecovered)"
                        ]
                    )
                case .failure(let error):
                    self.logAppEvent(event: "switcher.recover_project.failed", level: .error, message: error.message)
                }
                completion(result)
            }
        }
        controller.onSessionEnded = { [weak self] in
            self?.healthCoordinator?.refreshHealthInBackground(trigger: "switcher_session_ended")
        }
        return controller
    }

    /// Ensures the switcher controller exists for menu/hotkey actions.
    /// - Returns: Switcher panel controller instance.
    private func ensureSwitcherController() -> SwitcherPanelController {
        if let switcherController {
            return switcherController
        }
        let controller = makeSwitcherController()
        switcherController = controller
        return controller
    }

    /// Updates menu bar UI and tooltip based on hotkey registration status.
    private func updateHotkeyStatus(_ status: HotkeyRegistrationStatus?) {
        guard let statusItem, let menuItems else {
            return
        }

        switch status {
        case .registered:
            menuItems.hotkeyWarning.isHidden = true
            statusItem.button?.toolTip = nil
        case .failed(let osStatus):
            menuItems.hotkeyWarning.title = "Hotkey unavailable (OSStatus: \(osStatus))"
            menuItems.hotkeyWarning.isHidden = false
            statusItem.button?.toolTip = "Hotkey unavailable (OSStatus: \(osStatus))"
        case nil:
            menuItems.hotkeyWarning.isHidden = true
            statusItem.button?.toolTip = nil
        }
    }

    /// Updates the menu bar icon using the latest Doctor severity.
    ///
    /// For pending (nil) and pass states, the image uses template rendering so macOS
    /// handles light/dark menu bar appearance automatically. For warn/fail, palette
    /// colors are baked into the symbol configuration so the color is always visible
    /// regardless of menu bar appearance.
    ///
    /// - Parameter severity: Worst severity from the latest Doctor report. Nil means pending/unknown.
    private func updateMenuBarHealthIndicator(severity: DoctorSeverity?) {
        doctorIndicatorSeverity = severity
        guard let button = statusItem?.button else {
            return
        }

        if isDevAppVariant {
            button.title = MenuBarHealthIndicator.devBadgeTitle
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.contentTintColor = nil

        let sizeConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)

        let image: NSImage?
        switch severity {
        case .fail:
            let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            image = NSImage(
                systemSymbolName: MenuBarHealthIndicator.symbolName,
                accessibilityDescription: MenuBarHealthIndicator.accessibilityDescription
            )?.withSymbolConfiguration(sizeConfig.applying(colorConfig))
            image?.isTemplate = false
        case .warn:
            let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            image = NSImage(
                systemSymbolName: MenuBarHealthIndicator.symbolName,
                accessibilityDescription: MenuBarHealthIndicator.accessibilityDescription
            )?.withSymbolConfiguration(sizeConfig.applying(colorConfig))
            image?.isTemplate = false
        case .pass, .none:
            image = NSImage(
                systemSymbolName: MenuBarHealthIndicator.symbolName,
                accessibilityDescription: MenuBarHealthIndicator.accessibilityDescription
            )?.withSymbolConfiguration(sizeConfig)
            image?.isTemplate = true
        }

        button.image = image
    }

    /// Writes a structured log entry for app-level events.
    /// - Parameters:
    ///   - event: Event name to log.
    ///   - level: Severity level.
    ///   - message: Optional message for the log entry.
    ///   - context: Optional structured context.
    private func logAppEvent(
        event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(event: event, level: level, message: message, context: context)
    }

    /// Creates a Doctor instance with the current hotkey status providers.
    private func makeDoctor() -> Doctor {
        Doctor(
            runningApplicationChecker: AppKitRunningApplicationChecker(),
            hotkeyStatusProvider: hotkeyManager,
            focusCycleStatusProvider: focusCycleHotkeyManager,
            windowPositioner: AXWindowPositioner()
        )
    }

    /// Runs Doctor and presents the report in a modal-style panel.
    @objc private func runDoctor() {
        logAppEvent(event: "doctor.run.requested")
        // Capture focus before dispatching to background if no focus is currently held.
        // Re-runs from within the Doctor window keep the original focus (capturedFocus != nil).
        let needsCapture = doctorController?.capturedFocus == nil && doctorController?.previousApp == nil
        // Capture previousApp instantly (AppKit API, non-blocking) on the main thread.
        let previousApp = needsCapture ? NSWorkspace.shared.frontmostApplication : nil

        // Show Doctor window immediately with loading state so the user gets instant
        // feedback. Doctor.run() can take 20-30s (SSH timeouts) on the background thread.
        let controller = ensureDoctorController()
        if let previousApp, needsCapture {
            controller.previousApp = previousApp
        }
        controller.showLoading()

        // Focus capture and Doctor run both dispatch to background to avoid blocking
        // the main thread — captureCurrentFocus() calls AeroSpace CLI which can timeout.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let capturedFocus = needsCapture ? self.projectManager.captureCurrentFocus() : nil
            let report = self.makeDoctor().run()
            DispatchQueue.main.async {
                if let capturedFocus {
                    controller.capturedFocus = capturedFocus
                }
                self.updateMenuBarHealthIndicator(severity: report.overallSeverity)
                controller.showReport(report)
                self.healthCoordinator?.logDoctorSummary(report, event: "doctor.run.completed")
            }
        }
    }

    /// Copies the current Doctor report to the clipboard.
    private func copyDoctorReport() {
        guard let report = doctorController?.lastReport?.rendered() else {
            logAppEvent(event: "doctor.copy.skipped", level: .warn, message: "No report to copy.")
            return
        }
        logAppEvent(event: "doctor.copy.requested")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }

    /// Installs AeroSpace via Homebrew and refreshes the report.
    private func installAeroSpace() {
        healthCoordinator?.runDoctorAction(
            { $0.installAeroSpace() },
            requestedEvent: "doctor.install_aerospace.requested",
            completedEvent: "doctor.install_aerospace.completed",
            showLoading: { [weak self] in self?.doctorController?.showLoading() }
        )
    }

    /// Starts AeroSpace and refreshes the report.
    private func startAeroSpace() {
        healthCoordinator?.runDoctorAction(
            { $0.startAeroSpace() },
            requestedEvent: "doctor.start_aerospace.requested",
            completedEvent: "doctor.start_aerospace.completed",
            showLoading: { [weak self] in self?.doctorController?.showLoading() }
        )
    }

    /// Reloads AeroSpace config and refreshes the report.
    private func reloadAeroSpaceConfig() {
        healthCoordinator?.runDoctorAction(
            { $0.reloadAeroSpaceConfig() },
            requestedEvent: "doctor.reload_aerospace.requested",
            completedEvent: "doctor.reload_aerospace.completed",
            showLoading: { [weak self] in self?.doctorController?.showLoading() }
        )
    }

    /// Requests Accessibility permission and refreshes the report.
    private func requestAccessibility() {
        healthCoordinator?.runDoctorAction(
            { $0.requestAccessibility() },
            requestedEvent: "doctor.request_accessibility.requested",
            completedEvent: "doctor.request_accessibility.completed",
            showLoading: { [weak self] in self?.doctorController?.showLoading() }
        )
    }

    /// Closes the Doctor window and restores previously captured focus.
    ///
    /// Focus restoration runs on a detached task so AeroSpace CLI calls don't block the main
    /// thread. Without this, clicking the menu bar immediately after closing Doctor causes a
    /// beachball. This mirrors SwitcherPanelController.restorePreviousFocus().
    private func closeDoctorWindow() {
        logAppEvent(event: "doctor.window.closed")
        let focus = doctorController?.capturedFocus
        let previousApp = doctorController?.previousApp
        doctorController?.capturedFocus = nil
        doctorController?.previousApp = nil
        let projectManager = self.projectManager
        let logEvent: (String, [String: String]?) -> Void = { [weak self] event, context in
            self?.logAppEvent(event: event, context: context)
        }
        Task.detached(priority: .userInitiated) {
            // Try to restore precise window focus first.
            if let focus, projectManager.restoreFocus(focus) {
                await MainActor.run {
                    logEvent("doctor.focus.restored", ["window_id": "\(focus.windowId)"])
                }
                return
            }

            // If precise focus restore fails or was not possible, fall back to activating the previous app.
            if let previousApp {
                await MainActor.run {
                    previousApp.activate()
                    logEvent("doctor.focus.restored.app_fallback", ["bundle_id": previousApp.bundleIdentifier ?? "unknown"])
                }
            }
        }
    }

    /// Opens Finder to reveal the config file.
    /// If the config file does not exist, triggers config load (which creates a starter config).
    @objc private func viewConfigFile() {
        logAppEvent(event: "config.view.requested")
        statusItem?.menu?.cancelTracking()
        let configURL = DataPaths.default().configFile
        if !FileManager.default.fileExists(atPath: configURL.path) {
            // loadConfig() calls ConfigLoader which creates a starter config as a side-effect
            _ = projectManager.loadConfig()
            if FileManager.default.fileExists(atPath: configURL.path) {
                logAppEvent(event: "config.view.created_starter")
            } else {
                logAppEvent(
                    event: "config.view.create_failed",
                    level: .error,
                    message: "Failed to create starter config at \(configURL.path)"
                )
            }
        }
        // Reveal the file if it exists, otherwise reveal the parent directory
        if FileManager.default.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([configURL])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([configURL.deletingLastPathComponent()])
        }
    }

    /// Shows the standard About panel with app name and version.
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appDisplayName,
            .applicationVersion: AgentPanel.version
        ])
    }

    /// Terminates the app.
    @objc private func quit() {
        logAppEvent(event: "app.quit.requested")
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Launch at Login

    /// Syncs SMAppService registration with the config value.
    /// - Parameter configValue: The `autoStartAtLogin` value from config.
    private func syncLaunchAtLogin(configValue: Bool) {
        let service = SMAppService.mainApp
        if configValue {
            do {
                try service.register()
                logAppEvent(event: "launch_at_login.registered")
            } catch {
                logAppEvent(
                    event: "launch_at_login.register_failed",
                    level: .warn,
                    message: "Launch at login configured but registration failed: \(error.localizedDescription)"
                )
            }
        } else {
            guard service.status != .notRegistered else { return }
            do {
                try service.unregister()
                logAppEvent(event: "launch_at_login.unregistered")
            } catch {
                logAppEvent(
                    event: "launch_at_login.unregister_failed",
                    level: .warn,
                    message: "\(error.localizedDescription)"
                )
            }
        }
    }

    /// Toggles the Launch at Login menu item.
    @objc private func toggleLaunchAtLogin() {
        let configURL = DataPaths.default().configFile
        let entries = launchAtLoginToggler.toggle(configURL: configURL)
        for entry in entries {
            _ = logger.log(payload: entry)
        }
        menuItems?.launchAtLogin.title = "Launch at Login"
    }

    // MARK: - App Lifecycle State Management

    /// Called when the app is about to terminate.
    func applicationWillTerminate(_ notification: Notification) {
        logAppEvent(event: "app.terminated")
    }

    /// Called when display configuration changes (monitor connect/disconnect, dock/undock, resolution change).
    ///
    /// Logs the new display state and triggers a health refresh since display changes
    /// can cause AeroSpace tree-node bugs and window position scrambling.
    @objc private func screenParametersDidChange(_ notification: Notification) {
        let screens = NSScreen.screens
        let screenDescriptions = screens.enumerated().map { index, screen in
            let name = screen.localizedName
            let frame = screen.frame
            let visibleFrame = screen.visibleFrame
            return "\(index):\(name) \(Int(frame.width))x\(Int(frame.height)) visible=\(Int(visibleFrame.width))x\(Int(visibleFrame.height))"
        }
        logAppEvent(
            event: "display.configuration_changed",
            context: [
                "screen_count": "\(screens.count)",
                "screens": screenDescriptions.joined(separator: "; ")
            ]
        )
        // Trigger health check — display changes can cause AeroSpace state corruption.
        healthCoordinator?.refreshHealthInBackground(trigger: "display_change")
    }

    /// Displays the Doctor report using the DoctorWindowController.
    /// - Parameters:
    ///   - report: Doctor report payload.
    ///   - capturedFocus: AeroSpace focus captured before showing the window (nil if re-opening).
    ///   - previousApp: Frontmost app captured before showing the window (nil if re-opening).
    ///   - skipActivation: When `true`, the window appears without stealing focus via
    ///     `NSApp.activate`. Used during startup when the accessibility prompt may be open.
    private func showDoctorReport(
        _ report: DoctorReport,
        capturedFocus: CapturedFocus? = nil,
        previousApp: NSRunningApplication? = nil,
        skipActivation: Bool = false
    ) {
        let controller = ensureDoctorController()
        // Only set focus state on first open (capturedFocus/previousApp are nil on re-runs).
        if let capturedFocus {
            controller.capturedFocus = capturedFocus
        }
        if let previousApp {
            controller.previousApp = previousApp
        }
        controller.showReport(report, skipActivation: skipActivation)
    }

    /// Ensures the DoctorWindowController exists and has callbacks configured.
    /// - Returns: The doctor window controller instance.
    private func ensureDoctorController() -> DoctorWindowController {
        if let existing = doctorController {
            return existing
        }

        let controller = DoctorWindowController()
        controller.onRunDoctor = { [weak self] in self?.runDoctor() }
        controller.onCopyReport = { [weak self] in self?.copyDoctorReport() }
        controller.onInstallAeroSpace = { [weak self] in self?.installAeroSpace() }
        controller.onStartAeroSpace = { [weak self] in self?.startAeroSpace() }
        controller.onReloadConfig = { [weak self] in self?.reloadAeroSpaceConfig() }
        controller.onRequestAccessibility = { [weak self] in self?.requestAccessibility() }
        controller.onClose = { [weak self] in self?.closeDoctorWindow() }
        doctorController = controller
        return controller
    }

    // MARK: - Window Recovery & Move to Project

    /// Creates a WindowRecoveryManager with an already-captured screen frame.
    /// The screen frame must be read on the main thread before calling this.
    /// - Parameters:
    ///   - screenFrame: Screen visible frame captured on the main thread.
    ///   - layoutConfig: Layout config for layout-aware recovery. Pass nil to disable layout phase.
    private func makeWindowRecoveryManager(screenFrame: CGRect, layoutConfig: LayoutConfig? = nil) -> WindowRecoveryManager {
        let knownProjectIds = Set(projectManager.projects.map(\.id))
        return WindowRecoveryManager(
            windowPositioner: AXWindowPositioner(),
            screenVisibleFrame: screenFrame,
            logger: logger,
            processChecker: AppKitRunningApplicationChecker(),
            screenModeDetector: layoutConfig != nil ? ScreenModeDetector() : nil,
            layoutConfig: layoutConfig ?? LayoutConfig(),
            knownProjectIds: knownProjectIds
        )
    }

    /// Recovers only the currently focused window.
    @objc private func recoverCurrentWindow() {
        statusItem?.menu?.cancelTracking()

        guard let focus = menuWorkspaceCoordinator?.menuFocusCapture else {
            logAppEvent(event: "recover_current_window.skipped", level: .warn, message: "No focused window available")
            return
        }

        guard let screenFrame = NSScreen.main?.visibleFrame else {
            logAppEvent(event: "recovery.no_screen", level: .error, message: "No primary screen available")
            return
        }

        recoveryOperationCoordinator?.recoverCurrentWindow(
            windowId: focus.windowId,
            workspace: focus.workspace,
            screenFrame: screenFrame
        )
    }

    /// Recovers all windows in the focused workspace.
    ///
    /// Project workspaces receive layout-aware recovery (IDE/Chrome canonical frames).
    /// Non-project workspaces run generic window recovery for the current desktop.
    @objc private func recoverAgentPanel() {
        logAppEvent(event: "recover_agent_panel.requested")
        statusItem?.menu?.cancelTracking()

        guard let focus = menuWorkspaceCoordinator?.menuFocusCapture else {
            logAppEvent(event: "recover_agent_panel.skipped", level: .warn, message: "No focused workspace available")
            return
        }

        guard let screenFrame = NSScreen.main?.visibleFrame else {
            logAppEvent(event: "recovery.no_screen", level: .error, message: "No primary screen available")
            return
        }

        recoveryOperationCoordinator?.recoverWorkspaceWindows(focus: focus, screenFrame: screenFrame)
    }

    /// Recovers all windows across all workspaces.
    /// Project-tagged windows are moved to their project workspace before recovery.
    @objc private func recoverAllWindowsAction() {
        statusItem?.menu?.cancelTracking()

        guard let screenFrame = NSScreen.main?.visibleFrame else {
            logAppEvent(event: "recovery.no_screen", level: .error, message: "No primary screen available")
            return
        }

        // Show progress panel
        let controller = RecoveryProgressController()
        controller.onClose = { [weak self] in
            self?.recoveryController = nil
        }
        recoveryController = controller
        controller.show()

        recoveryOperationCoordinator?.recoverAllWindows(screenFrame: screenFrame)
    }

    /// Moves the focused window to the selected project's workspace.
    @objc private func addWindowToProject(_ sender: NSMenuItem) {
        guard let projectId = sender.representedObject as? String else { return }
        guard let focus = menuWorkspaceCoordinator?.menuFocusCapture else {
            logAppEvent(event: "add_window_to_project.no_focus", level: .warn)
            return
        }

        // No-op if window is already in the target project workspace
        if focus.workspace == ProjectManager.workspacePrefix + projectId { return }

        logAppEvent(
            event: "add_window_to_project.requested",
            context: ["window_id": "\(focus.windowId)", "project_id": projectId]
        )

        // Dispatch to background to avoid blocking the main thread — moveWindowToProject
        // calls AeroSpace CLI which can timeout if AeroSpace is unresponsive.
        // Thread-safe: moveWindowToProject() only reads immutable config state and calls CLI.
        let windowId = focus.windowId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.projectManager.moveWindowToProject(windowId: windowId, projectId: projectId)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.logAppEvent(
                        event: "add_window_to_project.completed",
                        context: ["window_id": "\(windowId)", "project_id": projectId]
                    )
                    // Refresh workspace state cache after the move
                    self.menuWorkspaceCoordinator?.refreshInBackground()
                case .failure(let error):
                    self.logAppEvent(
                        event: "add_window_to_project.failed",
                        level: .error,
                        message: "\(error)"
                    )
                }
            }
        }
    }

    /// Moves the focused window out of its project workspace to the default workspace.
    @objc private func removeWindowFromProject(_ sender: NSMenuItem) {
        guard let focus = menuWorkspaceCoordinator?.menuFocusCapture else {
            logAppEvent(event: "remove_window_from_project.no_focus", level: .warn)
            return
        }

        // No-op if window is not in a project workspace
        guard focus.workspace.hasPrefix(ProjectManager.workspacePrefix) else { return }

        logAppEvent(
            event: "remove_window_from_project.requested",
            context: ["window_id": "\(focus.windowId)", "workspace": focus.workspace]
        )

        let windowId = focus.windowId
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.projectManager.moveWindowFromProject(windowId: windowId)
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.logAppEvent(
                        event: "remove_window_from_project.completed",
                        context: ["window_id": "\(windowId)"]
                    )
                    self.menuWorkspaceCoordinator?.refreshInBackground()
                case .failure(let error):
                    self.logAppEvent(
                        event: "remove_window_from_project.failed",
                        level: .error,
                        message: "\(error)"
                    )
                }
            }
        }
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    /// Updates dynamic menu items each time the menu opens.
    ///
    /// Uses cached workspace state and focus to avoid blocking the main thread
    /// with AeroSpace CLI calls. The cache is refreshed in the background after
    /// Doctor runs, switcher sessions end, and each menu open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menuItems else { return }

        // Reflect Launch at Login state
        menuItems.launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let hasFocus = menuWorkspaceCoordinator?.menuFocusCapture != nil
        // Use cached focus (updated by background refreshes, not a live CLI call)
        menuItems.recoverCurrentWindow.isEnabled = hasFocus
        menuItems.recoverAgentPanel.isEnabled = hasFocus

        // Populate "Move Current Window" submenu from cached workspace state
        let submenu = menuItems.addWindowToProject.submenu ?? NSMenu()

        let isVisible = menuWorkspaceCoordinator?.populateMoveWindowSubmenu(
            submenu,
            addWindowTarget: self,
            addWindowAction: #selector(addWindowToProject(_:)),
            removeWindowTarget: self,
            removeWindowAction: #selector(removeWindowFromProject(_:))
        ) ?? false

        menuItems.addWindowToProject.submenu = submenu
        menuItems.addWindowToProject.isHidden = !isVisible

        // Refresh cache in background for next menu open
        menuWorkspaceCoordinator?.refreshInBackground()
    }
}
