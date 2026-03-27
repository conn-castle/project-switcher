import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerWindowPositionTests {
    // MARK: - Capture-on-Switch Tests (project-to-project)

    func testSelectProjectCapturesSourceProjectPositionsOnSwitch() async {
        let sourceId = "alpha"
        let targetId = "beta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()

        // Stub supports target project for activation
        let aerospace = SimpleAeroSpaceStub(projectId: targetId)

        // Configure positioner for source project capture (IDE + Chrome reads)
        positioner.getFrameResults["com.microsoft.VSCode|\(sourceId)"] = .success(defaultIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(sourceId)"] = .success(defaultChromeFrame)
        // Configure positioner for target project positioning
        positioner.getFrameResults["com.microsoft.VSCode|\(targetId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [
                ProjectConfig(id: sourceId, name: "Alpha", path: "/tmp/alpha", color: "blue", useAgentLayer: false),
                ProjectConfig(id: targetId, name: "Beta", path: "/tmp/beta", color: "red", useAgentLayer: false)
            ],
            chrome: ChromeConfig()
        ))

        // Pre-captured focus is from source project workspace (ps-alpha)
        let preFocus = CapturedFocus(windowId: 50, appBundleId: "com.microsoft.VSCode", workspace: "ps-\(sourceId)")
        let result = await manager.selectProject(projectId: targetId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify source project positions were captured before switching
        XCTAssertEqual(store.saveCalls.count, 1, "Should capture source project positions on switch")
        XCTAssertEqual(store.saveCalls[0].projectId, sourceId)
        XCTAssertEqual(store.saveCalls[0].frames.ide.x, Double(defaultIdeFrame.origin.x), accuracy: 1)
        XCTAssertEqual(store.saveCalls[0].frames.chrome!.x, Double(defaultChromeFrame.origin.x), accuracy: 1)
    }

    func testSelectProjectDoesNotCaptureWhenSourceIsNonProjectWorkspace() async {
        let targetId = "gamma"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: targetId)

        positioner.getFrameResults["com.microsoft.VSCode|\(targetId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: targetId, name: "Gamma", path: "/tmp/gamma", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        // Pre-captured focus is from a non-project workspace (e.g., "main")
        let preFocus = CapturedFocus(windowId: 1, appBundleId: "com.apple.finder", workspace: "main")
        let result = await manager.selectProject(projectId: targetId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // No capture should have happened — source is not a project workspace
        XCTAssertTrue(store.saveCalls.isEmpty, "Should not capture when source is non-project workspace")
    }

    // MARK: - Partial Restore Tests (saved IDE + computed Chrome)

    func testSelectProjectUsesSavedIDEAndComputedChromeWhenChromeIsNil() async {
        let projectId = "delta"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Saved frames with IDE only (Chrome is nil — partial save from earlier)
        let ideOnlyFrames = SavedWindowFrames(
            ide: SavedFrame(x: 50, y: 50, width: 1000, height: 700),
            chrome: nil
        )
        store.loadResults["\(projectId)|wide"] = .success(ideOnlyFrames)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Delta", path: "/tmp/delta", color: "yellow", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify both IDE and Chrome were positioned
        XCTAssertEqual(positioner.setFrameCalls.count, 2)

        // IDE should use saved frame (clamped)
        let ideCall = positioner.setFrameCalls[0]
        XCTAssertEqual(ideCall.bundleId, "com.microsoft.VSCode")
        XCTAssertEqual(ideCall.primaryFrame.origin.x, 50, accuracy: 1)

        // Chrome should use computed frame (not saved, since chrome was nil)
        let chromeCall = positioner.setFrameCalls[1]
        XCTAssertEqual(chromeCall.bundleId, "com.google.Chrome")
        // Computed frame should NOT be at x=50 (that was the saved IDE position)
        // It should be from WindowLayoutEngine.computeLayout
        XCTAssertNotEqual(chromeCall.primaryFrame.origin.x, 50, accuracy: 1,
                          "Chrome should use computed layout, not saved IDE position")
    }

}
