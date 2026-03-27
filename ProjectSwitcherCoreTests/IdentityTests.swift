import XCTest
@testable import ProjectSwitcherCore

final class IdentityTests: XCTestCase {
    func testResolveDisplayNameFallsBackOutsideAppBundleContext() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: "com.projectswitcher.cli",
                infoDictionary: ["CFBundleName": "pswitcher"]
            ),
            "ProjectSwitcher"
        )
    }

    func testResolveDisplayNameUsesDisplayNameForPrimaryAppBundle() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: "com.projectswitcher.ProjectSwitcher",
                infoDictionary: ["CFBundleDisplayName": "ProjectSwitcher"]
            ),
            "ProjectSwitcher"
        )
    }

    func testResolveDisplayNameUsesDisplayNameForDevAppBundle() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: "com.projectswitcher.ProjectSwitcher.dev",
                infoDictionary: ["CFBundleDisplayName": "ProjectSwitcher Dev"]
            ),
            "ProjectSwitcher Dev"
        )
    }

    func testResolveDisplayNameFallsBackForLookalikeBundleIdentifier() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: "com.projectswitcher.ProjectSwitcherCLI",
                infoDictionary: ["CFBundleDisplayName": "ProjectSwitcher CLI"]
            ),
            "ProjectSwitcher"
        )
    }

    func testResolveDisplayNameFallsBackToBundleNameWhenDisplayNameMissing() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: "com.projectswitcher.ProjectSwitcher",
                infoDictionary: ["CFBundleName": "ProjectSwitcher Test"]
            ),
            "ProjectSwitcher Test"
        )
    }

    func testResolveDisplayNameFallsBackWhenNamesAreEmpty() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: "com.projectswitcher.ProjectSwitcher.dev",
                infoDictionary: ["CFBundleDisplayName": "   ", "CFBundleName": ""]
            ),
            "ProjectSwitcher"
        )
    }

    func testResolveDisplayNameFallsBackWhenBundleIdentifierIsNil() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: nil,
                infoDictionary: ["CFBundleDisplayName": "Something"]
            ),
            "ProjectSwitcher"
        )
    }

    func testResolveDisplayNameFallsBackWhenInfoDictionaryIsNil() {
        XCTAssertEqual(
            ProjectSwitcher.resolveDisplayName(
                bundleIdentifier: "com.projectswitcher.ProjectSwitcher",
                infoDictionary: nil
            ),
            "ProjectSwitcher"
        )
    }
}
