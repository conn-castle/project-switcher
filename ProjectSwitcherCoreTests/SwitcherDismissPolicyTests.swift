//
//  SwitcherDismissPolicyTests.swift
//  ProjectSwitcherCoreTests
//
//  Tests for SwitcherDismissPolicy — pure logic, no AppKit.
//

import XCTest

@testable import ProjectSwitcherCore

final class SwitcherDismissPolicyTests: XCTestCase {

    // MARK: - shouldDismissOnResignKey

    func testResignKeySuppressedWhenActivating() {
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: true,
            isVisible: true
        )
        XCTAssertEqual(decision, .suppress(reason: "activation_in_progress"))
    }

    func testResignKeySuppressedWhenExternalFocusTransitionInProgress() {
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: false,
            isVisible: true,
            isExternalFocusTransitionInProgress: true
        )
        XCTAssertEqual(decision, .suppress(reason: "external_focus_transition_in_progress"))
    }

    func testResignKeyDismissesWhenNotActivatingAndVisible() {
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: false,
            isVisible: true
        )
        XCTAssertEqual(decision, .dismiss)
    }

    func testResignKeySuppressedWhenNotVisible() {
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: false,
            isVisible: false
        )
        XCTAssertEqual(decision, .suppress(reason: "panel_not_visible"))
    }

    func testResignKeySuppressedWhenActivatingAndNotVisible() {
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: true,
            isVisible: false
        )
        // Not-visible takes priority over activating
        XCTAssertEqual(decision, .suppress(reason: "panel_not_visible"))
    }

    func testResignKeyActivatingTakesPriorityOverExternalFocusTransition() {
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: true,
            isVisible: true,
            isExternalFocusTransitionInProgress: true
        )
        // Activating check comes first; both should never be true simultaneously
        // but if they are, activation_in_progress wins.
        XCTAssertEqual(decision, .suppress(reason: "activation_in_progress"))
    }

    func testResignKeySuppressedWhenExternalFocusTransitionAndNotVisible() {
        let decision = SwitcherDismissPolicy.shouldDismissOnResignKey(
            isActivating: false,
            isVisible: false,
            isExternalFocusTransitionInProgress: true
        )
        // Not-visible takes priority over in-flight focus transitions.
        XCTAssertEqual(decision, .suppress(reason: "panel_not_visible"))
    }

    // MARK: - shouldRestoreFocus

    func testFocusRestoreSkippedForProjectSelected() {
        XCTAssertFalse(SwitcherDismissPolicy.shouldRestoreFocus(reason: .projectSelected))
    }

    func testFocusRestoreSkippedForExitedToNonProject() {
        XCTAssertFalse(SwitcherDismissPolicy.shouldRestoreFocus(reason: .exitedToNonProject))
    }

    func testFocusRestorePerformedForEscape() {
        XCTAssertTrue(SwitcherDismissPolicy.shouldRestoreFocus(reason: .escape))
    }

    func testFocusRestorePerformedForToggle() {
        XCTAssertTrue(SwitcherDismissPolicy.shouldRestoreFocus(reason: .toggle))
    }

    func testFocusRestorePerformedForWindowClose() {
        XCTAssertTrue(SwitcherDismissPolicy.shouldRestoreFocus(reason: .windowClose))
    }

    func testFocusRestorePerformedForUnknown() {
        XCTAssertTrue(SwitcherDismissPolicy.shouldRestoreFocus(reason: .unknown))
    }

    func testFocusRestorePerformedForProjectClosed() {
        XCTAssertTrue(SwitcherDismissPolicy.shouldRestoreFocus(reason: .projectClosed))
    }

    // MARK: - Exhaustiveness

    func testAllDismissReasonsHaveRestoreFocusDecision() {
        // Ensures new cases added to SwitcherDismissReason are covered
        for reason in SwitcherDismissReason.allCases {
            // Should not crash — every case is handled
            _ = SwitcherDismissPolicy.shouldRestoreFocus(reason: reason)
        }
    }
}
