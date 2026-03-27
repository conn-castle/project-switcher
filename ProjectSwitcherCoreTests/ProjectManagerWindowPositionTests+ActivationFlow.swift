import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerWindowPositionTests {
    // MARK: - selectProject Tests

    func testSelectProjectPositionsWindowsWithComputedLayout() async {
        let projectId = "alpha"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        // Configure positioner: getPrimaryWindowFrame succeeds for IDE (used to determine monitor)
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning, "No layout warning expected for successful positioning")
            XCTAssertEqual(success.ideWindowId, 101)
        }

        // Verify setWindowFrames was called for both IDE and Chrome
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
        XCTAssertEqual(positioner.setFrameCalls[0].bundleId, "com.microsoft.VSCode")
        XCTAssertEqual(positioner.setFrameCalls[1].bundleId, "com.google.Chrome")
    }

    func testSelectProjectUsesSavedFramesWhenAvailable() async {
        let projectId = "beta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let savedFrames = SavedWindowFrames(
            ide: SavedFrame(x: 50, y: 50, width: 1000, height: 700),
            chrome: SavedFrame(x: 1100, y: 50, width: 900, height: 700)
        )
        store.loadResults["\(projectId)|wide"] = .success(savedFrames)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Beta", path: "/tmp/beta", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success, got: \(error)") }

        // Verify the IDE was positioned using saved (clamped) frame, not computed
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
        let ideCall = positioner.setFrameCalls[0]
        XCTAssertEqual(ideCall.primaryFrame.origin.x, 50, accuracy: 1)
    }

    func testSelectProjectReturnsLayoutWarningOnIDEFrameReadFailure() async {
        let projectId = "gamma"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        // IDE frame read fails
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .failure(PsCoreError(category: .window, message: "AX timeout"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Gamma", path: "/tmp/gamma", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Activation should succeed even when positioning fails: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have a layout warning")
            XCTAssertTrue(success.layoutWarning?.contains("AX timeout") == true)
        }
    }

    func testSelectProjectSkipsPositioningWhenNoPositioner() async {
        let projectId = "delta"
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        // No positioner/detector/store → positioning disabled
        let manager = makeManager(aerospace: aerospace)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Delta", path: "/tmp/delta", color: "yellow", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning)
        }
    }

    // MARK: - closeProject Tests

    func testCloseProjectCapturesWindowPositions() async {
        let projectId = "epsilon"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Epsilon", path: "/tmp/epsilon", color: "purple", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = await manager.closeProject(projectId: projectId)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify positions were saved
        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls[0].projectId, projectId)
        XCTAssertEqual(store.saveCalls[0].mode, .wide)
        XCTAssertEqual(store.saveCalls[0].frames.ide.x, Double(defaultIdeFrame.origin.x), accuracy: 1)
        XCTAssertEqual(store.saveCalls[0].frames.chrome!.x, Double(defaultChromeFrame.origin.x), accuracy: 1)
    }

    func testCloseProjectSkipsSaveWhenIDEFrameReadFails() async {
        let projectId = "zeta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        // IDE frame read fails — should not save
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .failure(PsCoreError(category: .window, message: "gone"))
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Zeta", path: "/tmp/zeta", color: "orange", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = await manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        XCTAssertTrue(store.saveCalls.isEmpty, "Should not save when IDE frame unreadable")
    }

    func testCloseProjectSkipsSaveWhenChromeFramePermanentlyFails() async {
        let projectId = "eta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // Permanent error (not "No window found with token") — skips save to preserve prior layout
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] =
            .failure(PsCoreError(category: .window, message: "gone"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Eta", path: "/tmp/eta", color: "cyan", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = await manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Skip save entirely when Chrome frame unavailable — preserves previous complete layout
        XCTAssertTrue(store.saveCalls.isEmpty, "Should skip save when Chrome frame permanently unavailable")
    }

    // MARK: - exitToNonProjectWindow Tests

    func testExitCapturesWindowPositionsBeforeFocusRestore() async {
        let projectId = "theta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Theta", path: "/tmp/theta", color: "pink", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Push a non-project focus entry for exit to restore
        manager.pushFocusForTest(CapturedFocus(windowId: 42, appBundleId: "com.other", workspace: "main"))

        let result = await manager.exitToNonProjectWindow()

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertEqual(store.saveCalls[0].projectId, projectId)
    }

    func testExitSkipsCaptureWhenNoPositioner() async {
        let projectId = "iota"
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        let manager = makeManager(aerospace: aerospace)
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Iota", path: "/tmp/iota", color: "white", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Push a non-project focus entry
        manager.pushFocusForTest(CapturedFocus(windowId: 42, appBundleId: "com.other", workspace: "main"))

        let result = await manager.exitToNonProjectWindow()
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }
        // No crash = positioning gracefully skipped
    }

}
