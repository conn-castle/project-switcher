import XCTest
@testable import ProjectSwitcherCore

final class DataPathsTests: XCTestCase {
    private let fileManager = FileManager.default

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

    func testDefaultUsesLegacyConfigWhenRenamedConfigIsMissing() throws {
        let home = try makeTemporaryHomeDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let legacyConfigDirectory = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("agent-panel", isDirectory: true)
        try fileManager.createDirectory(at: legacyConfigDirectory, withIntermediateDirectories: true)
        let legacyConfigFile = legacyConfigDirectory.appendingPathComponent("config.toml", isDirectory: false)
        try """
        [[project]]
        name = "Legacy"
        path = "/tmp/legacy"
        color = "blue"
        """.write(to: legacyConfigFile, atomically: true, encoding: .utf8)

        let store = DataPaths.default(homeDirectory: home, fileManager: fileManager)

        XCTAssertEqual(store.configFile.path, legacyConfigFile.path)
    }

    func testDefaultUsesLegacyConfigWhenRenamedConfigIsStarterTemplate() throws {
        let home = try makeTemporaryHomeDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let legacyConfigDirectory = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("agent-panel", isDirectory: true)
        let currentConfigDirectory = home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("project-switcher", isDirectory: true)
        try fileManager.createDirectory(at: legacyConfigDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: currentConfigDirectory, withIntermediateDirectories: true)

        let legacyConfigFile = legacyConfigDirectory.appendingPathComponent("config.toml", isDirectory: false)
        let currentConfigFile = currentConfigDirectory.appendingPathComponent("config.toml", isDirectory: false)
        try """
        [[project]]
        name = "Legacy"
        path = "/tmp/legacy"
        color = "blue"
        """.write(to: legacyConfigFile, atomically: true, encoding: .utf8)
        try ConfigLoader.starterConfigTemplate.write(to: currentConfigFile, atomically: true, encoding: .utf8)

        let store = DataPaths.default(homeDirectory: home, fileManager: fileManager)

        XCTAssertEqual(store.configFile.path, legacyConfigFile.path)
    }

    func testDefaultUsesLegacyStateWhenRenamedStateOnlyHasFreshLogs() throws {
        let home = try makeTemporaryHomeDirectory()
        defer { try? fileManager.removeItem(at: home) }

        let legacyStateDirectory = home
            .appendingPathComponent(".local/state/agent-panel", isDirectory: true)
        let currentLogsDirectory = home
            .appendingPathComponent(".local/state/project-switcher/logs", isDirectory: true)
        try fileManager.createDirectory(at: legacyStateDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: currentLogsDirectory, withIntermediateDirectories: true)

        let legacyStateFile = legacyStateDirectory.appendingPathComponent("state.json", isDirectory: false)
        try "{}".write(to: legacyStateFile, atomically: true, encoding: .utf8)
        let currentLogFile = currentLogsDirectory.appendingPathComponent("project-switcher.log", isDirectory: false)
        try "".write(to: currentLogFile, atomically: true, encoding: .utf8)

        let store = DataPaths.default(homeDirectory: home, fileManager: fileManager)

        XCTAssertEqual(store.stateFile.path, legacyStateFile.path)
        XCTAssertEqual(
            store.primaryLogFile.path,
            legacyStateDirectory.appendingPathComponent("logs/agent-panel.log", isDirectory: false).path
        )
    }

    private func makeTemporaryHomeDirectory() throws -> URL {
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("DataPathsTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        return temporaryDirectory
    }
}
