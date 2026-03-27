import Foundation
import XCTest
@testable import ProjectSwitcherCore

/// Tests targeting uncovered branches in ProjectManager for coverage improvement.
/// Covers: selectProject move branches, Chrome fallback launch failure, captureCurrentFocus failure,
/// focusWorkspace failure, fallbackToNonProjectWorkspace edge cases, resolveInitialURLs snapshot
/// load failure and git remote, captureWindowPositions screen mode failure and save failure,
/// positionWindows IDE/Chrome set failures, fuzzy search id/name matching, saveRecency encode/directory
/// failures.
final class ProjectManagerEdgeCaseTests: XCTestCase {

    // MARK: - selectProject: Chrome window needs moving to workspace

    func testSelectProjectMovesWindowsToWorkspaceWhenNotAlreadyThere() async {
        let projectId = "proj"
        let workspace = "ps-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: "other", windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "other", windowTitle: "PS:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        // After moves, focusedWindow should report the target workspace for dual-signal verification
        let ideInTarget = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                   workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")
        aero.focusedWindowResult = .success(ideInTarget)
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Both windows should have been moved
        XCTAssertTrue(aero.movedWindows.contains { $0.windowId == 100 && $0.workspace == workspace })
        XCTAssertTrue(aero.movedWindows.contains { $0.windowId == 101 && $0.workspace == workspace })
    }

    // MARK: - selectProject: Chrome move fails

    func testSelectProjectFailsWhenChromeMoveToWorkspaceFails() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: "other", windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.moveFailWindowIds = [100]

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected failure from Chrome move") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "move failed"))
        }
    }

    // MARK: - selectProject: IDE move fails

    func testSelectProjectFailsWhenIDEMoveToWorkspaceFails() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "other", windowTitle: "PS:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.moveFailWindowIds = [101]

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected failure from IDE move") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "move failed"))
        }
    }

    // MARK: - selectProject: workspace focus timeout

    func testSelectProjectFailsWhenWorkspaceFocusTimesOut() async {
        let projectId = "proj"
        let workspace = "ps-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        // Workspace is never focused
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: false)
        ])

        // Use short timeout to avoid 10s wait in test suite
        let manager = makeManager(aerospace: aero, windowPollTimeout: 0.3, windowPollInterval: 0.05)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected workspace focus failure") }
        if case .failure(let error) = result {
            if case .aeroSpaceError(let detail) = error {
                XCTAssertTrue(detail.contains("could not be focused"), "Detail: \(detail)")
            } else {
                XCTFail("Expected aeroSpaceError, got: \(error)")
            }
        }
    }

    // MARK: - ensureWorkspaceFocused: always calls focusWorkspace before accepting verification

    /// Even when the workspace appears focused in listWorkspacesWithFocus, activation must
    /// still call focusWorkspace at least once (summon-workspace) before accepting success.
    func testSelectProjectAlwaysCallsFocusWorkspaceEvenWhenAlreadyFocused() async {
        let projectId = "proj"
        let workspace = "ps-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        // Workspace appears focused immediately
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
        // focusedWindow reports correct workspace
        aero.focusedWindowResult = .success(ideWindow)

        let manager = makeManager(aerospace: aero)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // focusWorkspace must have been called at least once (summon path)
        XCTAssertTrue(
            aero.focusedWorkspaces.contains(workspace),
            "focusWorkspace must be called at least once even when workspace appears already focused"
        )
    }

    /// When listWorkspacesWithFocus says focused but focusedWindow reports a different workspace,
    /// ensureWorkspaceFocused must keep retrying rather than accepting the stale signal.
    func testSelectProjectFailsWhenFocusedWindowWorkspaceMismatchesTarget() async {
        let projectId = "proj"
        let workspace = "ps-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")

        aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        // listWorkspacesWithFocus says workspace is focused…
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])
        // …but focusedWindow reports a DIFFERENT workspace (stale/wrong space)
        let staleWindow = PsWindow(windowId: 200, appBundleId: "com.other.App",
                                   workspace: "other-ws", windowTitle: "Other App")
        aero.focusedWindowResult = .success(staleWindow)

        // Use short timeout to avoid 10s wait in test suite
        let manager = makeManager(aerospace: aero, windowPollTimeout: 0.3, windowPollInterval: 0.05)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        // Should fail because dual-signal verification never passes
        if case .success = result { XCTFail("Expected failure: focusedWindow workspace does not match target") }
        if case .failure(let error) = result {
            if case .aeroSpaceError(let detail) = error {
                XCTAssertTrue(detail.contains("could not be focused"), "Detail: \(detail)")
            } else {
                XCTFail("Expected aeroSpaceError, got: \(error)")
            }
        }
    }

    // MARK: - selectProject: Chrome launch fails with empty URLs (no retry)

    func testSelectProjectFailsWhenChromeLaunchFailsWithNoURLs() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()
        // No existing Chrome window — needs launch
        aero.windowsByBundleId["com.google.Chrome"] = []
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]

        let failingChrome = EdgeChromeLauncherFailingStub()
        failingChrome.alwaysFail = true

        let manager = makeManager(aerospace: aero, chromeLauncher: failingChrome)
        // No chrome config → no default tabs → empty URL launch
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected Chrome launch failure") }
        if case .failure(let error) = result {
            if case .chromeLaunchFailed = error {
                // expected
            } else {
                XCTFail("Expected chromeLaunchFailed, got: \(error)")
            }
        }
    }

    // MARK: - selectProject: Chrome retry also fails

    func testSelectProjectFailsWhenChromeFallbackRetryAlsoFails() async {
        let projectId = "proj"
        let aero = EdgeAeroSpaceStub()
        aero.windowsByBundleId["com.google.Chrome"] = []
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]

        let failingChrome = EdgeChromeLauncherFailingStub()
        failingChrome.alwaysFail = true

        let manager = makeManager(aerospace: aero, chromeLauncher: failingChrome)
        // Config has default tabs → first launch with URLs fails → retry with empty also fails
        loadConfig(manager, projectId: projectId,
                   chrome: ChromeConfig(defaultTabs: ["https://example.com"]))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .success = result { XCTFail("Expected Chrome fallback launch failure") }
        if case .failure(let error) = result {
            if case .chromeLaunchFailed = error {
                // expected
            } else {
                XCTFail("Expected chromeLaunchFailed, got: \(error)")
            }
        }
    }

    // MARK: - captureCurrentFocus: AeroSpace failure

    func testCaptureCurrentFocusReturnsNilWhenAeroSpaceFails() {
        let aero = EdgeAeroSpaceStub()
        aero.focusedWindowResult = .failure(PsCoreError(message: "no window"))

        let manager = makeManager(aerospace: aero)
        XCTAssertNil(manager.captureCurrentFocus())
    }

    // MARK: - captureCurrentFocus: retry on transient failure

    func testCaptureCurrentFocusRetriesOnTransientFailureAndSucceeds() {
        let aero = EdgeAeroSpaceStub()
        let window = PsWindow(windowId: 42, appBundleId: "com.apple.Safari",
                              workspace: "main", windowTitle: "Safari")
        // First call fails (non-breaker), second call succeeds.
        aero.focusedWindowResults = [
            .failure(PsCoreError(category: .command, message: "transient")),
            .success(window)
        ]

        let manager = makeManager(aerospace: aero)

        // Retry requires off-main-thread (Thread.sleep guard).
        let expectation = expectation(description: "capture completes")
        var captured: CapturedFocus?
        DispatchQueue.global().async {
            captured = manager.captureCurrentFocus()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertNotNil(captured, "Should succeed on retry after transient failure")
        XCTAssertEqual(captured?.windowId, 42)
        XCTAssertEqual(captured?.appBundleId, "com.apple.Safari")
    }

    func testCaptureCurrentFocusDoesNotRetryOnBreakerOpenError() {
        let aero = EdgeAeroSpaceStub()
        let window = PsWindow(windowId: 42, appBundleId: "com.apple.Safari",
                              workspace: "main", windowTitle: "Safari")
        // Breaker-open error should not retry, even though a second call would succeed.
        aero.focusedWindowResults = [
            .failure(PsCoreError(category: .command, message: "breaker", reason: .circuitBreakerOpen)),
            .success(window)
        ]

        let manager = makeManager(aerospace: aero)
        let captured = manager.captureCurrentFocus()

        XCTAssertNil(captured, "Should not retry when circuit breaker is open")
    }

    func testCaptureCurrentFocusReturnsNilWhenBothAttemptsFail() {
        let aero = EdgeAeroSpaceStub()
        // Both calls fail (non-breaker).
        aero.focusedWindowResults = [
            .failure(PsCoreError(category: .command, message: "fail1")),
            .failure(PsCoreError(category: .command, message: "fail2"))
        ]

        let manager = makeManager(aerospace: aero)

        // Retry requires off-main-thread (Thread.sleep guard).
        let expectation = expectation(description: "capture completes")
        var captured: CapturedFocus?
        DispatchQueue.global().async {
            captured = manager.captureCurrentFocus()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertNil(captured, "Should return nil when both attempts fail")
    }

    // MARK: - focusWorkspace: failure

    func testFocusWorkspaceReturnsFalseOnFailure() {
        let aero = EdgeAeroSpaceStub()
        aero.focusWorkspaceResult = .failure(PsCoreError(message: "ws gone"))

        let manager = makeManager(aerospace: aero)
        XCTAssertFalse(manager.focusWorkspace(name: "main"))
    }

    // MARK: - fallbackToNonProjectWorkspace: focus failure on candidate

    func testFallbackToNonProjectWorkspaceFocusFailsReturnsNoPreviousWindow() async {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true),
            PsWorkspaceSummary(workspace: "main", isFocused: false)
        ])
        // listWindowsWorkspace returns windows for "main"
        aero.windowsByWorkspace["main"] = [
            PsWindow(windowId: 10, appBundleId: "com.app", workspace: "main", windowTitle: "App")
        ]
        // But focusing "main" fails
        aero.focusWorkspaceResult = .failure(PsCoreError(message: "focus failed"))

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        // exit should fall through all fallback paths and fail
        let result = await manager.exitToNonProjectWindow()
        if case .success = result { XCTFail("Expected noPreviousWindow failure") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .noPreviousWindow)
        }
    }

    // MARK: - fallbackToNonProjectWorkspace: all non-project workspaces empty

    func testFallbackToNonProjectFocusesEmptyWorkspaceWhenNoWindowsAvailable() async {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-test", isFocused: true),
            PsWorkspaceSummary(workspace: "empty-ws", isFocused: false)
        ])
        // No windows in the non-project workspace
        aero.windowsByWorkspace["empty-ws"] = []
        aero.focusWorkspaceResult = .success(())

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        // exit should succeed by falling back to the empty non-project workspace
        let result = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result {
            XCTFail("Expected success via empty workspace fallback, got \(error)")
        }
        XCTAssertTrue(
            aero.focusedWorkspaces.contains("empty-ws"),
            "Should focus the empty non-project workspace as fallback"
        )
    }

    // MARK: - resolveInitialURLs: snapshot load failure falls back to cold start

    func testSelectProjectUsesConfigURLsWhenSnapshotLoadFails() async {
        let projectId = "proj"
        let workspace = "ps-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        // Chrome not found — needs launch
        aero.windowsByBundleId["com.google.Chrome"] = []
        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let recordingChrome = EdgeRecordingChromeLauncher()
        recordingChrome.onLaunch = {
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        }

        // Use a corrupt tab store directory so snapshot load fails
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let corruptTabsDir = tmp.appendingPathComponent("corrupt-tabs-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: corruptTabsDir, withIntermediateDirectories: true)
        // Write a corrupt file for this project
        let corruptFile = corruptTabsDir.appendingPathComponent("\(projectId).json")
        try? Data("not json".utf8).write(to: corruptFile, options: .atomic)

        let manager = makeManager(aerospace: aero, chromeLauncher: recordingChrome,
                                  chromeTabsDir: corruptTabsDir)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue",
                                     useAgentLayer: false)],
            chrome: ChromeConfig(defaultTabs: ["https://fallback.com"])
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Chrome should have been launched with cold-start URLs
        XCTAssertEqual(recordingChrome.calls.count, 1)
        XCTAssertTrue(recordingChrome.calls[0].urls.contains("https://fallback.com"))
    }

    // MARK: - resolveInitialURLs: git remote resolution

    func testSelectProjectIncludesGitRemoteURLWhenConfigured() async {
        let projectId = "proj"
        let workspace = "ps-\(projectId)"
        let aero = EdgeAeroSpaceStub()

        aero.windowsByBundleId["com.google.Chrome"] = []
        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let recordingChrome = EdgeRecordingChromeLauncher()
        recordingChrome.onLaunch = {
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        }

        let gitResolver = EdgeGitRemoteStub()
        gitResolver.result = "https://github.com/test/repo"

        let manager = makeManager(aerospace: aero, chromeLauncher: recordingChrome,
                                  gitRemoteResolver: gitResolver)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue",
                                     useAgentLayer: false)],
            chrome: ChromeConfig(openGitRemote: true)
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        XCTAssertTrue(recordingChrome.calls[0].urls.contains("https://github.com/test/repo"))
    }

    // MARK: - captureWindowPositions: screen mode failure falls back to .wide

    func testCaptureWindowPositionsFallsBackToWideOnScreenModeFailure() async {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(CGRect(x: 1400, y: 100, width: 1100, height: 800))

        struct FailingModeDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> {
                .failure(PsCoreError(category: .system, message: "EDID broken"))
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, PsCoreError> { .success(27.0) }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                CGRect(x: 0, y: 0, width: 2560, height: 1415)
            }
        }

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: FailingModeDetector())
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        _ = await manager.closeProject(projectId: projectId)

        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls[0].mode, .wide, "Should fall back to .wide on detection failure")
    }

    // MARK: - captureWindowPositions: save failure is non-fatal

    func testCaptureWindowPositionsSaveFailureDoesNotBlockClose() async {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        store.saveResult = .failure(PsCoreError(category: .fileSystem, message: "disk full"))
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(CGRect(x: 1400, y: 100, width: 1100, height: 800))

        let detector = EdgeStubScreenModeDetector()

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: detector)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        let result = await manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Close should succeed despite save failure: \(error)") }
    }

    // MARK: - positionWindows: IDE set failure

    func testPositionWindowsReturnsWarningWhenIDESetFails() async {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        let detector = EdgeStubScreenModeDetector()
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.setFrameResults["com.microsoft.VSCode|\(projectId)"] = .failure(PsCoreError(category: .window, message: "AX denied"))

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: detector)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("IDE positioning failed") == true)
        }
    }

    // MARK: - positionWindows: Chrome set failure

    func testPositionWindowsReturnsWarningWhenChromeSetFails() async {
        let projectId = "proj"
        let positioner = EdgeRecordingPositioner()
        let store = EdgeRecordingPositionStore()
        let detector = EdgeStubScreenModeDetector()
        let aero = EdgeSimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(CGRect(x: 100, y: 100, width: 1200, height: 800))
        positioner.setFrameResults["com.google.Chrome|\(projectId)"] = .failure(PsCoreError(category: .window, message: "AX denied"))

        let manager = makeManager(aerospace: aero, windowPositioner: positioner,
                                  windowPositionStore: store, screenModeDetector: detector)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Proj", path: "/tmp/proj", color: "blue", useAgentLayer: false)]
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("Chrome positioning failed") == true)
        }
    }

    // MARK: - Fuzzy search: id and name matching

    func testSortedProjectsMatchesIdInfix() {
        let manager = makeManager(aerospace: EdgeAeroSpaceStub())
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "my-calico-project", name: "Calico", path: "/test", color: "blue", useAgentLayer: false),
            ProjectConfig(id: "nomatch", name: "NoMatch", path: "/test2", color: "red", useAgentLayer: false)
        ]))

        // "calico" matches name prefix "Calico" and id substring "my-calico-project"
        // Only one project matches; the non-matching project is filtered out
        let sorted = manager.sortedProjects(query: "calico")
        XCTAssertEqual(sorted.count, 1)
        XCTAssertEqual(sorted[0].id, "my-calico-project")
    }

    // MARK: - closeProject: close workspace fails

    func testCloseProjectFailsWhenCloseWorkspaceFails() async {
        let aero = EdgeAeroSpaceStub()
        aero.closeWorkspaceResult = .failure(PsCoreError(message: "ws close failed"))

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        let result = await manager.closeProject(projectId: "test")
        if case .success = result { XCTFail("Expected failure from workspace close") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "ws close failed"))
        }
    }

    // MARK: - closeProject: project not found

    func testCloseProjectFailsWhenProjectNotFound() async {
        let manager = makeManager(aerospace: EdgeAeroSpaceStub())
        manager.loadTestConfig(Config(projects: [
            ProjectConfig(id: "test", name: "Test", path: "/test", color: "blue", useAgentLayer: false)
        ]))

        let result = await manager.closeProject(projectId: "nonexistent")
        if case .success = result { XCTFail("Expected failure for unknown project") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .projectNotFound(projectId: "nonexistent"))
        }
    }

    // MARK: - exitToNonProjectWindow: workspaceState failure

    func testExitFailsWhenWorkspaceStateQueryFails() async {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .failure(PsCoreError(message: "aero down"))

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: []))

        let result = await manager.exitToNonProjectWindow()
        if case .success = result { XCTFail("Expected failure") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .aeroSpaceError(detail: "aero down"))
        }
    }

    // MARK: - exitToNonProjectWindow: no active project

    func testExitFailsWhenNoProjectFocused() async {
        let aero = EdgeAeroSpaceStub()
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "main", isFocused: true)
        ])

        let manager = makeManager(aerospace: aero)
        manager.loadTestConfig(Config(projects: []))

        let result = await manager.exitToNonProjectWindow()
        if case .success = result { XCTFail("Expected noActiveProject") }
        if case .failure(let error) = result {
            XCTAssertEqual(error, .noActiveProject)
        }
    }

    // MARK: - findWindowByToken: listWindowsForApp fails

    func testSelectProjectLaunchesWindowWhenListWindowsFails() async {
        let projectId = "proj"
        let workspace = "ps-\(projectId)"
        let aero = EdgeAeroSpaceStub()
        aero.listWindowsForAppFailBundleIds = ["com.google.Chrome"]

        let chromeWindow = PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                                    workspace: workspace, windowTitle: "PS:\(projectId) - Chrome")
        let ideWindow = PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                                 workspace: workspace, windowTitle: "PS:\(projectId) - VS Code")
        aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
        aero.windowsByWorkspace[workspace] = [chromeWindow, ideWindow]
        aero.focusWindowResult = .success(())
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let recordingChrome = EdgeRecordingChromeLauncher()
        recordingChrome.onLaunch = {
            // Remove failure and add window on second call
            aero.listWindowsForAppFailBundleIds.remove("com.google.Chrome")
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
        }

        let manager = makeManager(aerospace: aero, chromeLauncher: recordingChrome)
        loadConfig(manager, projectId: projectId)

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }
        XCTAssertEqual(recordingChrome.calls.count, 1, "Chrome should have been launched")
    }

    // MARK: - Helpers

    private func makeManager(
        aerospace: AeroSpaceProviding,
        chromeLauncher: ChromeLauncherProviding = EdgeChromeLauncherStub(),
        chromeTabsDir: URL? = nil,
        gitRemoteResolver: GitRemoteResolving = EdgeGitRemoteStub(),
        windowPositioner: WindowPositioning? = nil,
        windowPositionStore: WindowPositionStoring? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        windowPollTimeout: TimeInterval = 10.0,
        windowPollInterval: TimeInterval = 0.1
    ) -> ProjectManager {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let effectiveTabsDir = chromeTabsDir ?? tmp.appendingPathComponent("edge-tabs-\(UUID().uuidString)", isDirectory: true)
        let recencyPath = tmp.appendingPathComponent("edge-recency-\(UUID().uuidString).json")
        let focusHistoryPath = tmp.appendingPathComponent("edge-focus-\(UUID().uuidString).json")
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: EdgeIdeLauncherStub(),
            agentLayerIdeLauncher: EdgeIdeLauncherStub(),
            chromeLauncher: chromeLauncher,
            chromeTabStore: ChromeTabStore(directory: effectiveTabsDir),
            chromeTabCapture: EdgeTabCaptureStub(),
            gitRemoteResolver: gitRemoteResolver,
            logger: EdgeLoggerStub(),
            recencyFilePath: recencyPath,
            focusHistoryFilePath: focusHistoryPath,
            windowPositioner: windowPositioner,
            windowPositionStore: windowPositionStore,
            screenModeDetector: screenModeDetector,
            windowPollTimeout: windowPollTimeout,
            windowPollInterval: windowPollInterval
        )
    }

    private func loadConfig(_ manager: ProjectManager, projectId: String,
                            chrome: ChromeConfig = ChromeConfig()) {
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: projectId.capitalized,
                                     path: "/tmp/\(projectId)", color: "blue", useAgentLayer: false)],
            chrome: chrome
        ))
    }
}

// MARK: - Test Doubles

private final class EdgeAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<PsWindow, PsCoreError> = .failure(PsCoreError(message: "stub"))
    /// Sequential results for `focusedWindow()`. Each call shifts the first element.
    /// When empty or nil, falls back to `focusedWindowResult`.
    var focusedWindowResults: [Result<PsWindow, PsCoreError>]?
    private var focusedWindowCallCount = 0
    var focusWindowResult: Result<Void, PsCoreError> = .success(())
    var workspacesWithFocusResult: Result<[PsWorkspaceSummary], PsCoreError> = .success([])
    var focusWorkspaceResult: Result<Void, PsCoreError> = .success(())
    var closeWorkspaceResult: Result<Void, PsCoreError> = .success(())
    var windowsByBundleId: [String: [PsWindow]] = [:]
    var windowsByWorkspace: [String: [PsWindow]] = [:]
    var moveFailWindowIds: Set<Int> = []
    var listWindowsForAppFailBundleIds: Set<String> = []
    private(set) var movedWindows: [(windowId: Int, workspace: String)] = []
    private(set) var focusedWindowIds: [Int] = []
    private(set) var focusedWorkspaces: [String] = []

    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { closeWorkspaceResult }

    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> {
        if listWindowsForAppFailBundleIds.contains(bundleId) {
            return .failure(PsCoreError(message: "list failed"))
        }
        return .success(windowsByBundleId[bundleId] ?? [])
    }

    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }

    func focusedWindow() -> Result<PsWindow, PsCoreError> {
        if let sequence = focusedWindowResults, focusedWindowCallCount < sequence.count {
            let result = sequence[focusedWindowCallCount]
            focusedWindowCallCount += 1
            return result
        }
        return focusedWindowResult
    }

    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
        focusedWindowIds.append(windowId)
        if case .success = focusWindowResult {
            if case .success(let focused) = focusedWindowResult, focused.windowId == windowId {
                return focusWindowResult
            }
            focusedWindowResult = .success(PsWindow(
                windowId: windowId,
                appBundleId: "com.stub.app",
                workspace: "main",
                windowTitle: "Stub"
            ))
        }
        return focusWindowResult
    }

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> {
        movedWindows.append((windowId, workspace))
        if moveFailWindowIds.contains(windowId) {
            return .failure(PsCoreError(message: "move failed"))
        }
        return .success(())
    }

    func focusWorkspace(name: String) -> Result<Void, PsCoreError> {
        focusedWorkspaces.append(name)
        return focusWorkspaceResult
    }
}

private struct EdgeIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> { .success(()) }
}

private struct EdgeChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> { .success(()) }
}

private final class EdgeChromeLauncherFailingStub: ChromeLauncherProviding {
    var alwaysFail = false

    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> {
        if alwaysFail { return .failure(PsCoreError(message: "chrome launch failed")) }
        return .success(())
    }
}

private final class EdgeRecordingChromeLauncher: ChromeLauncherProviding {
    private(set) var calls: [(identifier: String, urls: [String])] = []
    var onLaunch: (() -> Void)?

    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> {
        calls.append((identifier, initialURLs))
        onLaunch?()
        return .success(())
    }
}

private struct EdgeTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> { .success([]) }
}

private final class EdgeGitRemoteStub: GitRemoteResolving {
    var result: String?
    func resolve(projectPath: String) -> String? { result }
}

private struct EdgeLoggerStub: ProjectSwitcherLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> { .success(()) }
}

private final class EdgeRecordingPositioner: WindowPositioning {
    var getFrameResults: [String: Result<CGRect, PsCoreError>] = [:]
    /// Sequential results: each call shifts the first element. When empty, falls back to getFrameResults.
    var getFrameSequences: [String: [Result<CGRect, PsCoreError>]] = [:]
    var setFrameResults: [String: Result<WindowPositionResult, PsCoreError>] = [:]
    /// Sequential results for setWindowFrames.
    var setFrameSequences: [String: [Result<WindowPositionResult, PsCoreError>]] = [:]
    var trusted: Bool = true
    private(set) var setFrameCalls: [(bundleId: String, projectId: String)] = []

    // Fallback method support
    var getFallbackFrameResults: [String: Result<CGRect, PsCoreError>] = [:]
    var setFallbackFrameResults: [String: Result<WindowPositionResult, PsCoreError>] = [:]
    private(set) var getFallbackFrameCalls: [String] = []
    private(set) var setFallbackFrameCalls: [(bundleId: String, primaryFrame: CGRect)] = []

    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError> {
        let key = "\(bundleId)|\(projectId)"
        if var seq = getFrameSequences[key], !seq.isEmpty {
            let result = seq.removeFirst()
            getFrameSequences[key] = seq
            return result
        }
        return getFrameResults[key] ?? .failure(PsCoreError(category: .window, message: "no stub"))
    }

    func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
        setFrameCalls.append((bundleId, projectId))
        let key = "\(bundleId)|\(projectId)"
        if var seq = setFrameSequences[key], !seq.isEmpty {
            let result = seq.removeFirst()
            setFrameSequences[key] = seq
            return result
        }
        return setFrameResults[key] ?? .success(WindowPositionResult(positioned: 1, matched: 1))
    }

    func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, PsCoreError> {
        getFallbackFrameCalls.append(bundleId)
        return getFallbackFrameResults[bundleId] ?? .failure(PsCoreError(category: .window, message: "Fallback not available"))
    }

    func setFallbackWindowFrames(bundleId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
        setFallbackFrameCalls.append((bundleId, primaryFrame))
        return setFallbackFrameResults[bundleId] ?? .failure(PsCoreError(category: .window, message: "Fallback not available"))
    }

    func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> { .success(.unchanged) }

    func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> { .success(.unchanged) }

    func isAccessibilityTrusted() -> Bool { trusted }

    func promptForAccessibility() -> Bool { trusted }
}

private final class EdgeRecordingPositionStore: WindowPositionStoring {
    var loadResults: [String: Result<SavedWindowFrames?, PsCoreError>] = [:]
    private(set) var saveCalls: [(projectId: String, mode: ScreenMode, frames: SavedWindowFrames)] = []
    var saveResult: Result<Void, PsCoreError> = .success(())

    func load(projectId: String, mode: ScreenMode) -> Result<SavedWindowFrames?, PsCoreError> {
        let key = "\(projectId)|\(mode.rawValue)"
        return loadResults[key] ?? .success(nil)
    }

    func save(projectId: String, mode: ScreenMode, frames: SavedWindowFrames) -> Result<Void, PsCoreError> {
        saveCalls.append((projectId, mode, frames))
        return saveResult
    }
}

private struct EdgeStubScreenModeDetector: ScreenModeDetecting {
    func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> { .success(.wide) }
    func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, PsCoreError> { .success(27.0) }
    func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? { CGRect(x: 0, y: 0, width: 2560, height: 1415) }
}

/// Simple AeroSpace stub where all windows are already in the target workspace.
private final class EdgeSimpleAeroSpaceStub: AeroSpaceProviding {
    let projectId: String
    init(projectId: String) { self.projectId = projectId }

    private var chromeWindow: PsWindow {
        PsWindow(windowId: 100, appBundleId: "com.google.Chrome",
                 workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - Chrome")
    }
    private var ideWindow: PsWindow {
        PsWindow(windowId: 101, appBundleId: "com.microsoft.VSCode",
                 workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - VS Code")
    }

    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> {
        .success([PsWorkspaceSummary(workspace: "ps-\(projectId)", isFocused: true)])
    }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> {
        if bundleId == "com.google.Chrome" { return .success([chromeWindow]) }
        if bundleId == "com.microsoft.VSCode" { return .success([ideWindow]) }
        return .success([])
    }
    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
        .success([chromeWindow, ideWindow])
    }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> { .success([]) }
    func focusedWindow() -> Result<PsWindow, PsCoreError> { .success(ideWindow) }
    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> { .success(()) }
    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
}
