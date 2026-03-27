import XCTest

@testable import ProjectSwitcherAppKit

final class AccessibilityStartupPromptGateTests: XCTestCase {
    func testShouldPromptOnFirstLaunchWhenAccessibilityIsNotTrusted() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let gate = AccessibilityStartupPromptGate(
            defaults: defaults,
            promptedBuildKey: "tests.accessibility.prompted_build"
        )

        let shouldPrompt = gate.shouldPromptOnFirstLaunchOfCurrentBuild(
            currentBuild: "9",
            isAccessibilityTrusted: false
        )

        XCTAssertTrue(shouldPrompt)
        XCTAssertEqual(defaults.string(forKey: "tests.accessibility.prompted_build"), "9")
    }

    func testShouldNotPromptAgainForSameBuild() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let gate = AccessibilityStartupPromptGate(
            defaults: defaults,
            promptedBuildKey: "tests.accessibility.prompted_build"
        )

        _ = gate.shouldPromptOnFirstLaunchOfCurrentBuild(
            currentBuild: "9",
            isAccessibilityTrusted: false
        )
        let shouldPromptAgain = gate.shouldPromptOnFirstLaunchOfCurrentBuild(
            currentBuild: "9",
            isAccessibilityTrusted: false
        )

        XCTAssertFalse(shouldPromptAgain)
    }

    func testShouldNotPromptWhenAccessibilityAlreadyTrusted() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let gate = AccessibilityStartupPromptGate(
            defaults: defaults,
            promptedBuildKey: "tests.accessibility.prompted_build"
        )

        let shouldPrompt = gate.shouldPromptOnFirstLaunchOfCurrentBuild(
            currentBuild: "9",
            isAccessibilityTrusted: true
        )

        XCTAssertFalse(shouldPrompt)
        XCTAssertEqual(defaults.string(forKey: "tests.accessibility.prompted_build"), "9")
    }

    func testShouldPromptForNewBuildWhenAccessibilityNotTrusted() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("9", forKey: "tests.accessibility.prompted_build")

        let gate = AccessibilityStartupPromptGate(
            defaults: defaults,
            promptedBuildKey: "tests.accessibility.prompted_build"
        )

        let shouldPrompt = gate.shouldPromptOnFirstLaunchOfCurrentBuild(
            currentBuild: "10",
            isAccessibilityTrusted: false
        )

        XCTAssertTrue(shouldPrompt)
        XCTAssertEqual(defaults.string(forKey: "tests.accessibility.prompted_build"), "10")
    }

    private func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.projectswitcher.tests.accessibility-startup-prompt.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite: \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
