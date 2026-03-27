//
//  SwitcherDismissPolicy.swift
//  ProjectSwitcherCore
//
//  Pure policy logic for switcher panel dismiss and focus-restore decisions.
//  No AppKit dependency — testable from ProjectSwitcherCoreTests.
//

import Foundation

// MARK: - Dismiss Reason

/// Reason the switcher panel was dismissed.
public enum SwitcherDismissReason: String, CaseIterable, Sendable {
    case toggle           // User pressed hotkey while panel visible
    case escape           // User pressed Escape key
    case projectSelected  // Project activation succeeded
    case projectClosed    // User closed a project (after selecting it)
    case exitedToNonProject // User pressed Shift+Return to exit project space
    case windowClose      // Panel window closed or lost key focus
    case unknown          // Catchall for other dismissals
}

// MARK: - Dismiss Decision

/// Result of evaluating whether to dismiss on resign-key.
public enum DismissDecision: Equatable, Sendable {
    case dismiss
    case suppress(reason: String)
}

// MARK: - Dismiss Policy

/// Pure policy for switcher panel dismiss and focus-restore decisions.
/// Stateless — all inputs are parameters, all outputs are return values.
public struct SwitcherDismissPolicy: Sendable {

    /// Whether to dismiss the panel when it loses key window status.
    ///
    /// Suppresses dismiss when a project activation is in progress
    /// (Chrome/VS Code launch can steal focus from the panel), or when
    /// a focus-transition action is in progress (for example, exiting to
    /// the previous non-project window).
    /// Also suppresses when the panel is not visible (nothing to dismiss).
    public static func shouldDismissOnResignKey(
        isActivating: Bool,
        isVisible: Bool,
        isExternalFocusTransitionInProgress: Bool = false
    ) -> DismissDecision {
        guard isVisible else {
            return .suppress(reason: "panel_not_visible")
        }
        guard !isActivating else {
            return .suppress(reason: "activation_in_progress")
        }
        guard !isExternalFocusTransitionInProgress else {
            return .suppress(reason: "external_focus_transition_in_progress")
        }
        return .dismiss
    }

    /// Whether to restore focus to the previously active window/app on dismiss.
    ///
    /// Returns `false` for dismiss reasons where the action itself handles focus
    /// (project activation positions and focuses the IDE; exit-to-non-project
    /// restores focus via the focus stack).
    public static func shouldRestoreFocus(
        reason: SwitcherDismissReason
    ) -> Bool {
        switch reason {
        case .projectSelected, .exitedToNonProject:
            return false
        case .toggle, .escape, .projectClosed, .windowClose, .unknown:
            return true
        }
    }
}
