import XCTest
@testable import ProjectSwitcherCore

final class DataPathsTests: XCTestCase {

    func testPathsAreDerivedFromHomeDirectory() {
        let home = URL(fileURLWithPath: "/Users/testuser", isDirectory: true)
        let store = DataPaths(homeDirectory: home)

        XCTAssertEqual(store.configFile.path, "/Users/testuser/.config/project-switcher/config.toml")

        XCTAssertEqual(store.logsDirectory.path, "/Users/testuser/.local/state/project-switcher/logs")
        XCTAssertEqual(store.primaryLogFile.path, "/Users/testuser/.local/state/project-switcher/logs/project-switcher.log")
        XCTAssertEqual(store.logLockFile.path, "/Users/testuser/.local/state/project-switcher/logs/project-switcher.log.lock")

        XCTAssertEqual(store.stateFile.path, "/Users/testuser/.local/state/project-switcher/state.json")
        XCTAssertEqual(store.recentProjectsFile.path, "/Users/testuser/.local/state/project-switcher/recent-projects.json")

        XCTAssertEqual(store.chromeTabsDirectory.path, "/Users/testuser/.local/state/project-switcher/chrome-tabs")
        XCTAssertEqual(
            store.chromeTabsFile(projectId: "my-project").path,
            "/Users/testuser/.local/state/project-switcher/chrome-tabs/my-project.json"
        )
    }

    func testHomeDirectoryIsStandardized() {
        let home = URL(fileURLWithPath: "/Users/testuser/../testuser", isDirectory: true)
        let store = DataPaths(homeDirectory: home)

        XCTAssertEqual(store.configFile.path, "/Users/testuser/.config/project-switcher/config.toml")
    }
}
