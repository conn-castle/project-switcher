import Foundation

// MARK: - Focus Operations

/// Represents a captured window focus state for restoration.
///
/// Used to save the currently focused window before showing UI (like the switcher)
/// and restore it when the UI is dismissed without a selection.
public struct CapturedFocus: Sendable, Equatable {
    /// AeroSpace window ID.
    public let windowId: Int

    /// App bundle identifier of the focused window.
    public let appBundleId: String

    /// AeroSpace workspace name the window was on (e.g., "main", "ps-myproject").
    public let workspace: String

    /// Creates a captured focus state.
    init(windowId: Int, appBundleId: String, workspace: String) {
        self.windowId = windowId
        self.appBundleId = appBundleId
        self.workspace = workspace
    }
}

// MARK: - Running Application Checking

/// Running application lookup interface for Doctor policies.
public protocol RunningApplicationChecking {
    /// Returns true when an application with the given bundle identifier is running.
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}

/// Running application termination interface for recovery policies.
public protocol RunningApplicationTerminating {
    /// Terminates all processes matching the given bundle identifier.
    ///
    /// Attempts graceful termination first, then force-kills if needed.
    /// Returns true when the process is no longer running (including when
    /// it was already dead — vacuously successful).
    /// Conformers must implement this explicitly; no default fallback exists.
    ///
    /// - Parameter bundleIdentifier: Bundle identifier of the application to terminate.
    /// - Returns: True if the process is no longer running after this call.
    func terminateApplication(bundleIdentifier: String) -> Bool
}

// MARK: - Hotkey Status

/// Current registration status for the global switcher hotkey.
public enum HotkeyRegistrationStatus: Equatable, Sendable {
    case registered
    case failed(osStatus: Int32)
}

/// Provides the last known hotkey registration status.
public protocol HotkeyStatusProviding {
    /// Returns the current hotkey registration status, or nil if unknown.
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus?
}

/// Registration status for focus-cycle hotkeys (Option-Tab / Option-Shift-Tab).
public enum FocusCycleRegistrationStatus: Equatable, Sendable {
    /// Both Option-Tab and Option-Shift-Tab registered successfully.
    case registered
    /// Registration failed for one or both hotkeys.
    case failed(osStatus: Int32)
}

/// Provides the last known focus-cycle hotkey registration status.
public protocol FocusCycleStatusProviding {
    /// Returns the current focus-cycle registration status, or nil if unknown.
    func focusCycleRegistrationStatus() -> FocusCycleRegistrationStatus?
}

// MARK: - AeroSpace Health Checking

/// Result of an AeroSpace installation check.
struct AeroSpaceInstallStatus: Equatable, Sendable {
    /// True if AeroSpace.app is installed.
    let isInstalled: Bool
    /// Path to AeroSpace.app, if installed.
    let appPath: String?

    init(isInstalled: Bool, appPath: String?) {
        self.isInstalled = isInstalled
        self.appPath = appPath
    }
}

/// Result of an AeroSpace compatibility check.
enum AeroSpaceCompatibility: Equatable, Sendable {
    /// AeroSpace CLI is compatible.
    case compatible
    /// AeroSpace CLI is not available.
    case cliUnavailable
    /// AeroSpace CLI is missing required commands or flags.
    case incompatible(detail: String)
}

/// Intent-based protocol for AeroSpace health checks and actions.
///
/// Used by Doctor to check AeroSpace status and perform remediation actions.
/// This protocol hides AeroSpace implementation details from Doctor.
///
/// Method names use a `health` prefix to avoid collision with the existing
/// `Result`-returning methods on PsAeroSpace (e.g., `healthStart()` vs `start()`).
protocol AeroSpaceHealthChecking {
    // MARK: - Health Checks

    /// Returns the installation status of AeroSpace.
    func installStatus() -> AeroSpaceInstallStatus

    /// Returns true when the aerospace CLI is available.
    func isCliAvailable() -> Bool

    /// Checks whether the installed aerospace CLI is compatible.
    func healthCheckCompatibility() -> AeroSpaceCompatibility

    // MARK: - Actions

    /// Installs AeroSpace via Homebrew.
    /// - Returns: True if installation succeeded.
    func healthInstallViaHomebrew() -> Bool

    /// Starts AeroSpace.
    /// - Returns: True if start succeeded.
    func healthStart() -> Bool

    /// Reloads the AeroSpace configuration.
    /// - Returns: True if reload succeeded.
    func healthReloadConfig() -> Bool
}

// MARK: - Internal Protocols (for testability)

/// Internal protocol for AeroSpace operations.
protocol AeroSpaceProviding {
    // Workspace queries
    func getWorkspaces() -> Result<[String], PsCoreError>
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError>
    func listWorkspacesFocused() -> Result<[String], PsCoreError>
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError>
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError>
    func closeWorkspace(name: String) -> Result<Void, PsCoreError>

    // Window queries — global search with fallback to focused monitor
    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError>
    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError>
    func listAllWindows() -> Result<[PsWindow], PsCoreError>
    func focusedWindow() -> Result<PsWindow, PsCoreError>

    // Window actions
    func focusWindow(windowId: Int) -> Result<Void, PsCoreError>
    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError>

    // Workspace actions
    func focusWorkspace(name: String) -> Result<Void, PsCoreError>

    // Maintenance
    func reloadConfig() -> Result<Void, PsCoreError>
}

/// Internal protocol for IDE launching.
protocol IdeLauncherProviding {
    /// Opens a new VS Code window with a tagged title for precise identification.
    /// - Parameters:
    ///   - identifier: Project identifier embedded in the window title as `PS:<identifier>`.
    ///   - projectPath: Optional path to the project folder.
    ///     - Local projects: local absolute path.
    ///     - SSH projects: remote absolute path.
    ///   - remoteAuthority: Optional VS Code SSH remote authority (e.g., `ssh-remote+user@host`).
    ///     When set, the workspace folder is opened via a `vscode-remote://` folder URI.
    ///   - color: Optional project color for VS Code color customizations.
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError>
}

/// Internal protocol for Chrome launching.
protocol ChromeLauncherProviding {
    /// Opens a new Chrome window tagged with the provided identifier.
    /// - Parameters:
    ///   - identifier: Project identifier embedded in the window title token.
    ///   - initialURLs: URLs to open in the new window. First URL becomes the active tab,
    ///     remaining URLs open as additional tabs. If empty, opens Chrome's default new tab page.
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError>
}

/// Internal protocol for Chrome tab capture.
protocol ChromeTabCapturing {
    /// Captures the URLs of all tabs in the Chrome window matching the given title.
    /// - Parameter windowTitle: The window title to match.
    /// - Returns: Array of tab URLs on success, or an error.
    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError>
}

/// Internal protocol for git remote URL resolution.
protocol GitRemoteResolving {
    /// Resolves the git remote origin URL at the given path.
    /// - Parameter projectPath: Absolute path to the project directory.
    /// - Returns: The remote URL if one exists, nil otherwise.
    func resolve(projectPath: String) -> String?
}

// Default no-op so that only recovery-aware call sites need to override.
extension AeroSpaceProviding {
    func reloadConfig() -> Result<Void, PsCoreError> { .success(()) }
}

extension PsAeroSpace: AeroSpaceProviding {}
extension PsVSCodeLauncher: IdeLauncherProviding {}
extension PsAgentLayerVSCodeLauncher: IdeLauncherProviding {}
extension PsChromeLauncher: ChromeLauncherProviding {}

// MARK: - Window Positioning

/// Window frame read/write operations via macOS Accessibility APIs.
///
/// Result of a `setWindowFrames` call, reporting how many windows matched and how many
/// were successfully positioned.
public struct WindowPositionResult: Equatable, Sendable {
    /// Number of windows successfully positioned.
    public let positioned: Int
    /// Total number of windows that matched the title token.
    public let matched: Int
    /// Per-window error messages for windows that failed to be positioned.
    public let failures: [String]

    public init(positioned: Int, matched: Int, failures: [String] = []) {
        self.positioned = positioned
        self.matched = matched
        self.failures = failures
    }

    /// True when some matched windows failed to be positioned.
    public var hasPartialFailure: Bool { positioned < matched }
}

/// Outcome of a single window recovery attempt.
public enum RecoveryOutcome: Equatable, Sendable {
    /// Window was resized and/or moved to fit the screen.
    case recovered
    /// Window already fits on screen; no changes made.
    case unchanged
    /// No matching window was found (app not running, window closed, etc.).
    case notFound
}

/// All frames use NSScreen coordinate space (origin bottom-left, Y up).
/// Implementations handle coordinate conversion to/from AX space internally.
public protocol WindowPositioning {
    /// Returns the current frame of the primary matched window for the given app.
    ///
    /// Matches windows whose title contains `PS:<projectId>`. If multiple windows match,
    /// uses the first (title-sorted) match.
    ///
    /// - Returns: `.failure` if no running app, no matching window, or AX calls fail/timeout.
    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError>

    /// Sets window frames for all windows matching `PS:<projectId>`.
    ///
    /// Match index 0 gets `primaryFrame`. Match index N>0 gets cascaded by
    /// `N * cascadeOffsetPoints` down-right in NSScreen space.
    ///
    /// - Returns: `.success` with positioned/matched counts, or `.failure` if no windows
    ///   could be positioned (e.g., no running app, AX permission denied).
    func setWindowFrames(
        bundleId: String,
        projectId: String,
        primaryFrame: CGRect,
        cascadeOffsetPoints: CGFloat
    ) -> Result<WindowPositionResult, PsCoreError>

    /// Recovers a window by bundle ID and title.
    ///
    /// The caller should focus the target window (via AeroSpace) before calling this method
    /// so that the implementation can prefer the focused window when multiple windows share
    /// the same title. Reads the window's current frame; if wider or taller than
    /// `screenVisibleFrame`, or if the window center is off-screen, shrinks to fit and centers.
    ///
    /// - Parameters:
    ///   - bundleId: Bundle identifier of the owning application.
    ///   - windowTitle: Expected window title (used for verification/fallback matching).
    ///   - screenVisibleFrame: Screen visible frame to constrain within.
    /// - Returns: `.recovered` if resized/moved, `.unchanged` if already fits,
    ///   `.notFound` if no matching window, or `.failure` on AX error.
    func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError>

    /// Recovers the currently focused window of the given application if off-screen.
    ///
    /// Must be called after AeroSpace has focused the target window. Reads the app's
    /// AX focused window directly (no title match needed), checks its frame against
    /// `screenVisibleFrame`, and shrinks/centers if off-screen or oversized.
    ///
    /// - Parameters:
    ///   - bundleId: Bundle identifier of the owning application.
    ///   - screenVisibleFrame: Screen visible frame to constrain within.
    /// - Returns: `.recovered` if resized/moved, `.unchanged` if already fits,
    ///   `.notFound` if no focused window, or `.failure` on AX error.
    func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError>

    /// Returns true if macOS Accessibility permission is granted.
    func isAccessibilityTrusted() -> Bool

    /// Prompts the user for Accessibility permission if not already granted.
    /// Shows the macOS system Accessibility permission dialog.
    /// - Returns: true if permission is already granted (no prompt shown).
    func promptForAccessibility() -> Bool

    /// Returns the frame of an unambiguous window for the given app, ignoring token matching.
    ///
    /// Used as a last-resort fallback when token-based lookup (`getPrimaryWindowFrame`) fails
    /// after retry exhaustion. Selection strategy:
    /// 1. If exactly one window exists, use it.
    /// 2. If multiple windows exist, prefer the app's AX focused window.
    /// 3. If ambiguous (multiple windows, none focused), fail with diagnostic inventory.
    ///
    /// - Parameter bundleId: Bundle identifier of the owning application.
    /// - Returns: `.success(frame)` if an unambiguous window is found, `.failure` with
    ///   window inventory diagnostics otherwise.
    func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, PsCoreError>

    /// Positions the unambiguous window for the given app, ignoring token matching.
    ///
    /// Used as a last-resort fallback when token-based positioning (`setWindowFrames`) fails
    /// after retry exhaustion. Uses the same selection strategy as `getFallbackWindowFrame`.
    ///
    /// - Parameters:
    ///   - bundleId: Bundle identifier of the owning application.
    ///   - primaryFrame: Target frame in NSScreen coordinates.
    ///   - cascadeOffsetPoints: Cascade offset (unused for single-window fallback).
    /// - Returns: `.success` with positioned count, or `.failure` with diagnostic inventory.
    func setFallbackWindowFrames(
        bundleId: String,
        primaryFrame: CGRect,
        cascadeOffsetPoints: CGFloat
    ) -> Result<WindowPositionResult, PsCoreError>
}

/// Default implementations for backward-compatible protocol additions.
extension WindowPositioning {
    public func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, PsCoreError> {
        .failure(PsCoreError(category: .window, message: "Fallback not available"))
    }

    public func setFallbackWindowFrames(
        bundleId: String,
        primaryFrame: CGRect,
        cascadeOffsetPoints: CGFloat
    ) -> Result<WindowPositionResult, PsCoreError> {
        .failure(PsCoreError(category: .window, message: "Fallback not available"))
    }
}

/// Screen mode detection based on physical monitor dimensions.
///
/// Uses only Foundation/CoreGraphics types — no NSScreen, no AppKit import.
/// Concrete implementation (`ScreenModeDetector`) lives in the AppKit module.
public protocol ScreenModeDetecting {
    /// Detects screen mode for the display containing the given point.
    ///
    /// - Returns: `.failure` if physical screen size cannot be determined (e.g., broken EDID).
    func detectMode(containingPoint: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError>

    /// Returns the physical width in inches for the display containing the given point.
    ///
    /// - Returns: `.failure` if physical screen size cannot be determined.
    func physicalWidthInches(containingPoint: CGPoint) -> Result<Double, PsCoreError>

    /// Returns the visible frame (minus dock/menu bar) of the display containing the given point.
    ///
    /// - Returns: `nil` if no display contains the point.
    func screenVisibleFrame(containingPoint: CGPoint) -> CGRect?

    /// Returns the visible frame of the primary display, or nil if no displays are available.
    ///
    /// Used as a fallback when `screenVisibleFrame(containingPoint:)` returns nil
    /// because the point references a disconnected display (e.g., after undocking).
    func primaryScreenVisibleFrame() -> CGRect?
}

/// Default so existing conformers (e.g., test stubs) are not forced to implement.
extension ScreenModeDetecting {
    public func primaryScreenVisibleFrame() -> CGRect? { nil }
}

/// Persistence for saved window positions per project per screen mode.
protocol WindowPositionStoring {
    /// Loads saved window frames for a project and screen mode.
    ///
    /// - Returns:
    ///   - `.success(frames)` if saved frames exist.
    ///   - `.success(nil)` if no saved frames (file missing or project not in file).
    ///   - `.failure(error)` on decode errors (corrupt file, schema mismatch).
    func load(projectId: String, mode: ScreenMode) -> Result<SavedWindowFrames?, PsCoreError>

    /// Saves window frames for a project and screen mode.
    ///
    /// - Returns: `.failure` on write errors.
    func save(projectId: String, mode: ScreenMode, frames: SavedWindowFrames) -> Result<Void, PsCoreError>
}
