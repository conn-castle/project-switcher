import XCTest
@testable import AgentPanelCore

final class ProjectManagerFocusHistoryPersistenceTests: XCTestCase {
    func testFocusHistoryPersistsAcrossManagers() async {
        let fileSystem = FocusHistoryTestInMemoryFileSystem()
        let focusHistoryPath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)

        let manager1 = makeManager(
            aerospace: FocusHistoryTestAeroSpaceStub(),
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager1.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager1.pushFocusForTest(CapturedFocus(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main"
        ))

        let aero2 = FocusHistoryTestAeroSpaceStub()
        let window = ApWindow(windowId: 42, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")
        aero2.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        aero2.allWindows = [window]
        aero2.focusWindowSuccessIds = [42]
        aero2.focusedWindowResult = .success(window)

        let manager2 = makeManager(
            aerospace: aero2,
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager2.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        aero2.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        let result = await manager2.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success, got \(error)")
        }
        XCTAssertTrue(aero2.focusedWindowIds.contains(42))
    }

    func testFocusHistoryPrunesStaleEntries() async {
        let fileSystem = FocusHistoryTestInMemoryFileSystem()
        let focusHistoryPath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let store = FocusHistoryStore(
            fileURL: focusHistoryPath,
            fileSystem: fileSystem,
            maxAge: 7 * 24 * 60 * 60,
            maxEntries: 20
        )
        let staleDate = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        let staleEntry = FocusHistoryEntry(
            windowId: 10,
            appBundleId: "com.apple.Safari",
            workspace: "main",
            capturedAt: staleDate
        )
        let state = FocusHistoryState(
            version: FocusHistoryStore.currentVersion,
            stack: [staleEntry],
            mostRecent: staleEntry
        )
        _ = store.save(state: state)

        let aero = FocusHistoryTestAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let manager = makeManager(
            aerospace: aero,
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Exit succeeds via workspace fallback, but the stale window must not be focused.
        let result = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success via workspace fallback, got \(error)")
        }
        XCTAssertFalse(aero.focusedWindowIds.contains(10), "Stale entry should be pruned and not focused")
    }

    func testLoadFocusHistoryFailureFallsBackToEmptyHistory() async {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readError = NSError(domain: "ProjectManagerFocusHistoryPersistenceTests", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "read failed"
        ])

        let focusHistoryPath = URL(fileURLWithPath: "/focus-history-load-fail.json", isDirectory: false)
        let aero = FocusHistoryTestAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])

        let manager = makeManager(
            aerospace: aero,
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // History load failure → empty history → exit succeeds via workspace fallback.
        let result = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success via workspace fallback when history cannot be loaded, got \(error)")
        }
    }

    func testPersistFocusHistoryFailureDoesNotBreakInMemoryRestore() async {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.writeError = NSError(domain: "ProjectManagerFocusHistoryPersistenceTests", code: 11, userInfo: [
            NSLocalizedDescriptionKey: "write failed"
        ])
        let focusHistoryPath = URL(fileURLWithPath: "/focus-history-save-fail.json", isDirectory: false)

        let aero = FocusHistoryTestAeroSpaceStub()
        let window = ApWindow(windowId: 42, appBundleId: "com.apple.Terminal", workspace: "main", windowTitle: "Terminal")
        aero.workspacesWithFocusResult = .success([
            ApWorkspaceSummary(workspace: "ap-test", isFocused: true)
        ])
        aero.allWindows = [window]
        aero.focusWindowSuccessIds = [42]
        aero.focusedWindowResult = .failure(ApCoreError(message: "no focus"))

        let manager = makeManager(
            aerospace: aero,
            fileSystem: fileSystem,
            focusHistoryFilePath: focusHistoryPath
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: "test", name: "Test", path: "/tmp/test", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))
        manager.pushFocusForTest(CapturedFocus(
            windowId: 42,
            appBundleId: "com.apple.Terminal",
            workspace: "main"
        ))

        let result = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success with in-memory focus despite save failure, got \(error)")
        }
        XCTAssertGreaterThan(fileSystem.writeCallCount, 0)
        XCTAssertTrue(aero.focusedWindowIds.contains(42))
    }

    private func makeManager(
        aerospace: FocusHistoryTestAeroSpaceStub,
        fileSystem: FileSystem,
        focusHistoryFilePath: URL
    ) -> ProjectManager {
        let recencyFilePath = URL(fileURLWithPath: "/recency-\(UUID().uuidString).json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs-\(UUID().uuidString)", isDirectory: true)

        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: FocusHistoryTestIdeLauncherStub(),
            agentLayerIdeLauncher: FocusHistoryTestIdeLauncherStub(),
            chromeLauncher: FocusHistoryTestChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: FocusHistoryTestTabCaptureStub(),
            gitRemoteResolver: FocusHistoryTestGitRemoteResolver(),
            logger: FocusHistoryTestLogger(),
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            fileSystem: fileSystem,
            windowPollTimeout: 0.3,
            windowPollInterval: 0.05
        )
    }
}
