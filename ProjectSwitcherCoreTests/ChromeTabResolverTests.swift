import XCTest
@testable import ProjectSwitcherCore

final class ChromeTabResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject(
        name: String = "Test",
        chromePinnedTabs: [String] = [],
        chromeDefaultTabs: [String] = []
    ) -> ProjectConfig {
        ProjectConfig(
            id: IdNormalizer.normalize(name),
            name: name,
            path: "/test",
            color: "blue",
            useAgentLayer: false,
            chromePinnedTabs: chromePinnedTabs,
            chromeDefaultTabs: chromeDefaultTabs
        )
    }

    // MARK: - No snapshot: defaults used

    func testNoSnapshotUsesDefaults() {
        let config = ChromeConfig(
            pinnedTabs: ["https://pinned.com"],
            defaultTabs: ["https://default.com"],
            openGitRemote: false
        )
        let project = makeProject()

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.alwaysOpenURLs, ["https://pinned.com"])
        XCTAssertEqual(result.regularURLs, ["https://default.com"])
        XCTAssertEqual(result.orderedURLs, ["https://pinned.com", "https://default.com"])
    }

    // MARK: - Git remote as always-open

    func testGitRemoteAddedWhenEnabled() {
        let config = ChromeConfig(
            pinnedTabs: ["https://pinned.com"],
            defaultTabs: [],
            openGitRemote: true
        )
        let project = makeProject()

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: "https://github.com/user/repo"
        )

        XCTAssertEqual(result.alwaysOpenURLs, ["https://pinned.com", "https://github.com/user/repo"])
    }

    func testGitRemoteNotAddedWhenDisabled() {
        let config = ChromeConfig(
            pinnedTabs: [],
            defaultTabs: [],
            openGitRemote: false
        )
        let project = makeProject()

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: "https://github.com/user/repo"
        )

        XCTAssertEqual(result.alwaysOpenURLs, [])
    }

    func testGitRemoteNilWhenEnabled() {
        let config = ChromeConfig(
            pinnedTabs: [],
            defaultTabs: [],
            openGitRemote: true
        )
        let project = makeProject()

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.alwaysOpenURLs, [])
    }

    // MARK: - Per-project pinned tabs

    func testProjectPinnedTabsMergedWithGlobal() {
        let config = ChromeConfig(
            pinnedTabs: ["https://global.com"],
            defaultTabs: [],
            openGitRemote: false
        )
        let project = makeProject(chromePinnedTabs: ["https://project.com"])

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.alwaysOpenURLs, ["https://global.com", "https://project.com"])
    }

    // MARK: - Per-project default tabs

    func testProjectDefaultTabsMergedWithGlobal() {
        let config = ChromeConfig(
            pinnedTabs: [],
            defaultTabs: ["https://global-default.com"],
            openGitRemote: false
        )
        let project = makeProject(chromeDefaultTabs: ["https://project-default.com"])

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.regularURLs, ["https://global-default.com", "https://project-default.com"])
    }

    // MARK: - Deduplication

    func testAlwaysOpenDeduplication() {
        let config = ChromeConfig(
            pinnedTabs: ["https://dup.com", "https://dup.com"],
            defaultTabs: [],
            openGitRemote: false
        )
        let project = makeProject(chromePinnedTabs: ["https://dup.com"])

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.alwaysOpenURLs, ["https://dup.com"])
    }

    func testDefaultTabsDeduplication() {
        let config = ChromeConfig(
            pinnedTabs: [],
            defaultTabs: ["https://a.com", "https://b.com"],
            openGitRemote: false
        )
        let project = makeProject(chromeDefaultTabs: ["https://b.com", "https://c.com"])

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.regularURLs, ["https://a.com", "https://b.com", "https://c.com"])
    }

    func testDefaultTabsExcludeAlwaysOpen() {
        let config = ChromeConfig(
            pinnedTabs: ["https://pinned.com"],
            defaultTabs: ["https://pinned.com", "https://default.com"],
            openGitRemote: false
        )
        let project = makeProject()

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.alwaysOpenURLs, ["https://pinned.com"])
        XCTAssertEqual(result.regularURLs, ["https://default.com"])
    }

    // MARK: - Empty config

    func testEmptyConfigProducesEmptyTabs() {
        let config = ChromeConfig()
        let project = makeProject()

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: nil
        )

        XCTAssertEqual(result.alwaysOpenURLs, [])
        XCTAssertEqual(result.regularURLs, [])
        XCTAssertEqual(result.orderedURLs, [])
    }

    // MARK: - Ordering: always-open first in orderedURLs

    func testOrderedURLsPutsAlwaysOpenFirst() {
        let config = ChromeConfig(
            pinnedTabs: ["https://pinned.com"],
            defaultTabs: ["https://default.com"],
            openGitRemote: true
        )
        let project = makeProject(chromePinnedTabs: ["https://project-pinned.com"])

        let result = ChromeTabResolver.resolve(
            config: config,
            project: project,
            gitRemoteURL: "https://github.com/repo"
        )

        XCTAssertEqual(result.orderedURLs, [
            "https://pinned.com",
            "https://project-pinned.com",
            "https://github.com/repo",
            "https://default.com"
        ])
    }
}
