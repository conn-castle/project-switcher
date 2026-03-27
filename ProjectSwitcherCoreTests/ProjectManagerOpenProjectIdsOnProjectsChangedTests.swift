import Foundation
import XCTest
@testable import ProjectSwitcherCore

// MARK: - onProjectsChanged Tests

final class ProjectManagerOnProjectsChangedTests: XCTestCase {

    func testOnProjectsChangedFiresOnFirstLoad() {
        var received: [ProjectConfig]?
        let project = ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false)
        let manager = makeManager(configLoader: {
            .success(ConfigLoadSuccess(config: Config(projects: [project])))
        })

        manager.onProjectsChanged = { projects in
            received = projects
        }

        _ = manager.loadConfig()

        XCTAssertEqual(received?.map(\.id), ["a"])
    }

    func testOnProjectsChangedFiresWhenProjectsChange() {
        var callCount = 0
        var loadCount = 0
        let projectA = ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false)
        let projectB = ProjectConfig(id: "b", name: "Beta", path: "/tmp/b", color: "red", useAgentLayer: false)
        let manager = makeManager(configLoader: {
            loadCount += 1
            if loadCount == 1 {
                return .success(ConfigLoadSuccess(config: Config(projects: [projectA])))
            } else {
                return .success(ConfigLoadSuccess(config: Config(projects: [projectA, projectB])))
            }
        })

        manager.onProjectsChanged = { _ in callCount += 1 }

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 1)

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 2)
    }

    func testOnProjectsChangedDoesNotFireWhenProjectsUnchanged() {
        var callCount = 0
        let project = ProjectConfig(id: "a", name: "Alpha", path: "/tmp/a", color: "blue", useAgentLayer: false)
        let manager = makeManager(configLoader: {
            .success(ConfigLoadSuccess(config: Config(projects: [project])))
        })

        manager.onProjectsChanged = { _ in callCount += 1 }

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 1, "Should fire on first load (nil → projects)")

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 1, "Should NOT fire again when projects are the same")
    }

    func testOnProjectsChangedDoesNotFireOnLoadFailure() {
        var received: [ProjectConfig]?
        let manager = makeManager(configLoader: {
            .failure(.parseFailed(detail: "bad toml"))
        })

        manager.onProjectsChanged = { projects in
            received = projects
        }

        _ = manager.loadConfig()

        XCTAssertNil(received, "Should not fire callback on config load failure")
    }

    func testOnProjectsChangedDoesNotFireForEmptyToEmpty() {
        var callCount = 0
        let manager = makeManager(configLoader: {
            .success(ConfigLoadSuccess(config: Config(projects: [])))
        })

        manager.onProjectsChanged = { _ in callCount += 1 }

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 0, "Empty to empty is not a change")

        _ = manager.loadConfig()
        XCTAssertEqual(callCount, 0, "Still empty to empty")
    }

    private func makeManager(
        configLoader: @escaping () -> Result<ConfigLoadSuccess, ConfigLoadError>
    ) -> ProjectManager {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let recencyPath = tempDir.appendingPathComponent("pm-callback-recency-\(UUID().uuidString).json")
        let focusHistoryPath = tempDir.appendingPathComponent("pm-callback-focus-\(UUID().uuidString).json")
        let chromeTabsDir = tempDir.appendingPathComponent("pm-callback-tabs-\(UUID().uuidString)", isDirectory: true)

        return ProjectManager(
            aerospace: RecordingFocusAeroSpaceStub(),
            ideLauncher: WorkspaceStateIdeLauncherStub(),
            agentLayerIdeLauncher: WorkspaceStateIdeLauncherStub(),
            chromeLauncher: WorkspaceStateChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: WorkspaceStateTabCaptureStub(),
            gitRemoteResolver: WorkspaceStateGitRemoteStub(),
            logger: WorkspaceStateLoggerStub(),
            recencyFilePath: recencyPath,
            focusHistoryFilePath: focusHistoryPath,
            configLoader: configLoader
        )
    }
}
