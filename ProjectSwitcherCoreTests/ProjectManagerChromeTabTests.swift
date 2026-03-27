import XCTest
@testable import ProjectSwitcherCore

// MARK: - Close Project Tab Capture Tests

final class ProjectManagerChromeTabCloseTests: XCTestCase {

    // MARK: - Close captures and saves ALL tabs verbatim

    func testCloseProjectCapturesAndSavesAllTabs() async {
        let tabCapture = PMTabCaptureStub()
        tabCapture.captureResult = .success(["https://pinned.com", "https://regular.com", "https://other.com"])

        let chromeTabsDir = tempDir("close-save")
        let manager = makeManager(
            chromeTabsDir: chromeTabsDir,
            chromeTabCapture: tabCapture
        )

        let config = Config(
            projects: [testProject()],
            chrome: ChromeConfig(pinnedTabs: ["https://pinned.com"])
        )
        manager.loadTestConfig(config)

        switch await manager.closeProject(projectId: "test") {
        case .success(let result):
            XCTAssertNil(result.tabCaptureWarning)
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }

        // Verify tab capture was called with correct window title
        XCTAssertEqual(tabCapture.capturedWindowTitles, ["PS:test"])

        // Verify ALL URLs are saved (no filtering — snapshot is complete truth)
        let store = ChromeTabStore(directory: chromeTabsDir)
        switch store.load(projectId: "test") {
        case .success(let snapshot):
            XCTAssertNotNil(snapshot)
            XCTAssertEqual(snapshot?.urls, ["https://pinned.com", "https://regular.com", "https://other.com"])
        case .failure(let error):
            XCTFail("Failed to load snapshot: \(error.message)")
        }
    }

    // MARK: - Close saves all tabs including project pinned

    func testCloseProjectSavesAllTabsIncludingProjectPinned() async {
        let tabCapture = PMTabCaptureStub()
        tabCapture.captureResult = .success(["https://global-pinned.com", "https://project-pinned.com", "https://regular.com"])

        let chromeTabsDir = tempDir("close-all")
        let manager = makeManager(
            chromeTabsDir: chromeTabsDir,
            chromeTabCapture: tabCapture
        )

        let config = Config(
            projects: [testProject(chromePinnedTabs: ["https://project-pinned.com"])],
            chrome: ChromeConfig(pinnedTabs: ["https://global-pinned.com"])
        )
        manager.loadTestConfig(config)

        switch await manager.closeProject(projectId: "test") {
        case .success(let result):
            XCTAssertNil(result.tabCaptureWarning)
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }

        // ALL URLs saved verbatim (no pinned/always-open filtering)
        let store = ChromeTabStore(directory: chromeTabsDir)
        switch store.load(projectId: "test") {
        case .success(let snapshot):
            XCTAssertEqual(snapshot?.urls, ["https://global-pinned.com", "https://project-pinned.com", "https://regular.com"])
        case .failure(let error):
            XCTFail("Failed to load snapshot: \(error.message)")
        }
    }

    // MARK: - Close produces warning when capture fails but preserves snapshot

    func testCloseProjectWarnsOnCaptureFailureAndPreservesSnapshot() async {
        let chromeTabsDir = tempDir("close-warn")

        // Pre-populate a snapshot
        let store = ChromeTabStore(directory: chromeTabsDir)
        let existingSnapshot = ChromeTabSnapshot(urls: ["https://existing.com"], capturedAt: Date())
        _ = store.save(snapshot: existingSnapshot, projectId: "test")

        let tabCapture = PMTabCaptureStub()
        tabCapture.captureResult = .failure(PsCoreError(category: .command, message: "Chrome not running"))

        let manager = makeManager(
            chromeTabsDir: chromeTabsDir,
            chromeTabCapture: tabCapture
        )

        let config = Config(projects: [testProject()])
        manager.loadTestConfig(config)

        switch await manager.closeProject(projectId: "test") {
        case .success(let result):
            XCTAssertNotNil(result.tabCaptureWarning)
            XCTAssertTrue(result.tabCaptureWarning!.contains("Chrome not running"))
        case .failure(let error):
            XCTFail("Expected success (non-fatal) but got: \(error)")
        }

        // Snapshot should be PRESERVED on capture failure (transient error shouldn't destroy valid data)
        switch store.load(projectId: "test") {
        case .success(let snapshot):
            XCTAssertNotNil(snapshot, "Snapshot should be preserved when capture fails with an error")
            XCTAssertEqual(snapshot?.urls, ["https://existing.com"])
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    func testCloseProjectWarnsWhenSnapshotSaveFails() async {
        let tabCapture = PMTabCaptureStub()
        tabCapture.captureResult = .success(["https://one.com", "https://two.com"])

        let chromeTabsDir = tempDir("close-save-fail")
        let failingStore = ChromeTabStore(
            directory: chromeTabsDir,
            fileSystem: PMSnapshotWriteFailingFileSystem()
        )
        let manager = makeManager(
            chromeTabsDir: chromeTabsDir,
            chromeTabCapture: tabCapture,
            chromeTabStore: failingStore
        )

        let config = Config(projects: [testProject()])
        manager.loadTestConfig(config)

        switch await manager.closeProject(projectId: "test") {
        case .success(let result):
            XCTAssertEqual(result.tabCaptureWarning, "Tab save failed: Failed to write tab snapshot for test")
        case .failure(let error):
            XCTFail("Expected non-fatal tab save warning, got: \(error)")
        }
    }

    // MARK: - Close with empty capture deletes stale snapshot

    func testCloseProjectEmptyCaptureDeletesSnapshot() async {
        let chromeTabsDir = tempDir("close-empty")

        // Pre-populate a stale snapshot
        let store = ChromeTabStore(directory: chromeTabsDir)
        let staleSnapshot = ChromeTabSnapshot(urls: ["https://stale.com"], capturedAt: Date())
        _ = store.save(snapshot: staleSnapshot, projectId: "test")

        let tabCapture = PMTabCaptureStub()
        tabCapture.captureResult = .success([])

        let manager = makeManager(
            chromeTabsDir: chromeTabsDir,
            chromeTabCapture: tabCapture
        )

        let config = Config(projects: [testProject()])
        manager.loadTestConfig(config)

        switch await manager.closeProject(projectId: "test") {
        case .success(let result):
            XCTAssertNil(result.tabCaptureWarning)
        case .failure(let error):
            XCTFail("Expected success but got: \(error)")
        }

        // Stale snapshot should be deleted when capture is empty (window gone)
        switch store.load(projectId: "test") {
        case .success(let snapshot):
            XCTAssertNil(snapshot, "Stale snapshot should be deleted when capture returns empty")
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    // MARK: - Close without config (no-op for tabs)

    func testCloseProjectWithoutConfigSkipsTabs() async {
        let tabCapture = PMTabCaptureStub()
        tabCapture.captureResult = .success(["https://a.com"])

        let manager = makeManager(
            chromeTabsDir: tempDir("close-noconfig"),
            chromeTabCapture: tabCapture
        )
        // Don't load config

        switch await manager.closeProject(projectId: "test") {
        case .success:
            XCTFail("Expected failure (config not loaded)")
        case .failure(let error):
            XCTAssertEqual(error, .configNotLoaded)
        }

        // Tab capture should not have been called
        XCTAssertEqual(tabCapture.capturedWindowTitles, [])
    }

    // MARK: - Helpers

    private func testProject(
        chromePinnedTabs: [String] = [],
        chromeDefaultTabs: [String] = []
    ) -> ProjectConfig {
        ProjectConfig(
            id: "test",
            name: "Test",
            path: "/test",
            color: "blue",
            useAgentLayer: false,
            chromePinnedTabs: chromePinnedTabs,
            chromeDefaultTabs: chromeDefaultTabs
        )
    }

    private func tempDir(_ label: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-chrome-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeManager(
        chromeTabsDir: URL,
        chromeTabCapture: PMTabCaptureStub = PMTabCaptureStub(),
        gitRemoteResolver: PMGitRemoteStub = PMGitRemoteStub(),
        chromeTabStore: ChromeTabStore? = nil
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-chrome-recency-\(UUID().uuidString).json")
        let focusHistoryFilePath = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pm-chrome-focus-\(UUID().uuidString).json")
        return ProjectManager(
            aerospace: PMAeroSpaceStub(),
            ideLauncher: PMIdeLauncherStub(),
            agentLayerIdeLauncher: PMIdeLauncherStub(),
            chromeLauncher: PMChromeLauncherStub(),
            chromeTabStore: chromeTabStore ?? ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: chromeTabCapture,
            gitRemoteResolver: gitRemoteResolver,
            logger: PMLoggerStub(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath
        )
    }
}

// MARK: - Test Doubles

private final class PMTabCaptureStub: ChromeTabCapturing {
    var captureResult: Result<[String], PsCoreError> = .success([])
    private(set) var capturedWindowTitles: [String] = []

    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> {
        capturedWindowTitles.append(windowTitle)
        return captureResult
    }
}

private struct PMGitRemoteStub: GitRemoteResolving {
    var result: String?

    func resolve(projectPath: String) -> String? {
        result
    }
}

private final class PMAeroSpaceStub: AeroSpaceProviding {
    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { .success([]) }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }
    func focusedWindow() -> Result<PsWindow, PsCoreError> {
        .failure(PsCoreError(category: .command, message: "stub"))
    }
    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> { .success(()) }
    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
}

private struct PMIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> { .success(()) }
}

private struct PMChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> { .success(()) }
}

private struct PMLoggerStub: ProjectSwitcherLogging {
    func log(
        event: String,
        level: LogLevel,
        message: String?,
        context: [String: String]?
    ) -> Result<Void, LogWriteError> {
        .success(())
    }
}

private struct PMSnapshotWriteFailingFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { Data() }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {
        throw NSError(domain: "PMSnapshotWriteFailingFileSystem", code: 1, userInfo: nil)
    }
}
