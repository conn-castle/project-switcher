//
//  WindowCycler.swift
//  ProjectSwitcherCore
//
//  Cycles focus between windows in the focused workspace.
//  Uses AeroSpace to enumerate windows and focus the next/previous window
//  in list order, wrapping at boundaries.
//

import Foundation

/// Direction for window cycling.
public enum CycleDirection: Sendable {
    case next
    case previous
}

/// Snapshot of a candidate window displayed in the Option-Tab overlay.
public struct WindowCycleCandidate: Equatable, Sendable {
    /// AeroSpace window ID.
    public let windowId: Int
    /// App bundle identifier for icon resolution in the App layer.
    public let appBundleId: String
    /// Window title as reported by AeroSpace.
    public let windowTitle: String

    init(windowId: Int, appBundleId: String, windowTitle: String) {
        self.windowId = windowId
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
    }
}

/// Cycles focus between windows in the focused AeroSpace workspace.
public struct WindowCycler {
    /// Session snapshot used for overlay-based window cycling.
    public struct CycleSession: Equatable, Sendable {
        /// Ordered cycle candidates in the focused workspace.
        public let candidates: [WindowCycleCandidate]
        /// Initially focused window ID before cycling started.
        public let initialWindowId: Int
        /// Selected candidate index in `candidates`.
        public let selectedIndex: Int

        /// The currently selected candidate.
        public var selectedCandidate: WindowCycleCandidate {
            candidates[selectedIndex]
        }

        init(
            candidates: [WindowCycleCandidate],
            initialWindowId: Int,
            selectedIndex: Int
        ) {
            self.candidates = candidates
            self.initialWindowId = initialWindowId
            self.selectedIndex = selectedIndex
        }

        /// Returns a copy with a new selected index.
        func withSelectedIndex(_ selectedIndex: Int) -> CycleSession {
            CycleSession(
                candidates: candidates,
                initialWindowId: initialWindowId,
                selectedIndex: selectedIndex
            )
        }
    }

    private let aerospace: AeroSpaceProviding

    /// Creates a window cycler with default dependencies.
    /// - Parameter processChecker: Process checker for AeroSpace auto-recovery. Pass nil to disable.
    public init(processChecker: RunningApplicationChecking? = nil) {
        self.aerospace = PsAeroSpace(processChecker: processChecker)
    }

    /// Creates a window cycler with injected dependencies (for testing).
    init(aerospace: AeroSpaceProviding) {
        self.aerospace = aerospace
    }

    /// Starts a cycle session from the currently focused window.
    ///
    /// - Parameter direction: Initial selection direction.
    /// - Returns:
    ///   - `.success(session)` when at least 2 windows are available.
    ///   - `.success(nil)` when no session is needed (0/1 windows or focused window not found in list).
    ///   - `.failure` when AeroSpace queries fail.
    public func startSession(direction: CycleDirection) -> Result<CycleSession?, PsCoreError> {
        // Get the currently focused window (includes workspace name)
        let focused: PsWindow
        switch aerospace.focusedWindow() {
        case .success(let w):
            focused = w
        case .failure(let error):
            return .failure(error)
        }

        // List all windows in the focused window's workspace
        let windows: [PsWindow]
        switch aerospace.listWindowsWorkspace(workspace: focused.workspace) {
        case .success(let w):
            windows = w
        case .failure(let error):
            return .failure(error)
        }

        // Nothing to cycle if 0 or 1 windows
        guard windows.count > 1 else {
            return .success(nil)
        }

        // Find the focused window in the list
        guard let currentIndex = windows.firstIndex(where: { $0.windowId == focused.windowId }) else {
            return .success(nil)
        }

        let candidates = windows.map {
            WindowCycleCandidate(windowId: $0.windowId, appBundleId: $0.appBundleId, windowTitle: $0.windowTitle)
        }

        let selectedIndex = Self.wrappedIndex(
            from: currentIndex,
            direction: direction,
            count: candidates.count
        )

        return .success(
            CycleSession(
                candidates: candidates,
                initialWindowId: focused.windowId,
                selectedIndex: selectedIndex
            )
        )
    }

    /// Advances selection within a cycle session.
    ///
    /// - Parameters:
    ///   - session: Active cycle session.
    ///   - direction: Selection direction.
    /// - Returns: Updated session with wrapped selection.
    public func advanceSelection(session: CycleSession, direction: CycleDirection) -> CycleSession {
        guard !session.candidates.isEmpty else {
            return session
        }
        let nextIndex = Self.wrappedIndex(
            from: session.selectedIndex,
            direction: direction,
            count: session.candidates.count
        )
        return session.withSelectedIndex(nextIndex)
    }

    /// Commits the selected window in a cycle session.
    ///
    /// - Parameter session: Active cycle session.
    /// - Returns: `.success(())` on success, `.failure` when AeroSpace focus fails.
    public func commitSelection(session: CycleSession) -> Result<Void, PsCoreError> {
        aerospace.focusWindow(windowId: session.selectedCandidate.windowId)
    }

    /// Cancels a cycle session and restores the initially focused window.
    ///
    /// - Parameter session: Active cycle session.
    /// - Returns: `.success(())` on success, `.failure` when AeroSpace focus fails.
    public func cancelSession(session: CycleSession) -> Result<Void, PsCoreError> {
        aerospace.focusWindow(windowId: session.initialWindowId)
    }

    /// Cycles focus to the next or previous window in the focused workspace.
    ///
    /// - Parameter direction: `.next` for forward cycling, `.previous` for backward.
    /// - Returns: `.success(candidate)` with the focused candidate on success,
    ///   `.success(nil)` if no cycling was needed (0/1 windows),
    ///   or `.failure` if AeroSpace returned an error.
    public func cycleFocus(direction: CycleDirection) -> Result<WindowCycleCandidate?, PsCoreError> {
        switch startSession(direction: direction) {
        case .failure(let error):
            return .failure(error)
        case .success(nil):
            return .success(nil)
        case .success(let session?):
            switch commitSelection(session: session) {
            case .success:
                return .success(session.selectedCandidate)
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    /// Computes wrapped forward/backward index movement.
    private static func wrappedIndex(from currentIndex: Int, direction: CycleDirection, count: Int) -> Int {
        switch direction {
        case .next:
            return (currentIndex + 1) % count
        case .previous:
            return (currentIndex - 1 + count) % count
        }
    }
}
