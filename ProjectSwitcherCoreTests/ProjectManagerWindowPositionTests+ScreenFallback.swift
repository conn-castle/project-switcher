import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerWindowPositionTests {
    // MARK: - Screen Fallback (stale coordinates after undocking)

    /// When the IDE frame center references a disconnected display, positioning should
    /// fall back to the primary display instead of skipping entirely.
    func testPositionWindows_centerPointOffScreen_fallsToPrimaryDisplay() async {
        let projectId = "stale"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()

        // IDE frame with center point referencing a disconnected external monitor
        let staleIdeFrame = CGRect(x: 2091, y: -910, width: 1000, height: 800)
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(staleIdeFrame)

        // Detector: no screen contains the stale center, but primary display is available
        var detector = StubScreenModeDetector()
        detector.visibleFrame = nil // stale center is off all screens
        detector.primaryVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        detector.mode = .small
        detector.physicalWidth = 14.2

        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Stale", path: "/tmp/stale", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let success):
            // Should NOT return "screen not found" — should fall back to primary
            XCTAssertNil(success.layoutWarning, "Should succeed using primary display fallback")
        }

        // Verify setWindowFrames was called (positioning not skipped)
        XCTAssertEqual(positioner.setFrameCalls.count, 2,
                       "Both IDE and Chrome should be positioned via primary display fallback")
    }

    /// When the center point is off-screen AND no primary display is available,
    /// positioning should return a warning (graceful skip).
    func testPositionWindows_centerPointOffScreen_noPrimaryDisplay_returnsWarning() async {
        let projectId = "noprimary"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()

        let staleIdeFrame = CGRect(x: 5000, y: -500, width: 1000, height: 800)
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(staleIdeFrame)

        // No screen contains the point AND no primary display
        var detector = StubScreenModeDetector()
        detector.visibleFrame = nil
        detector.primaryVisibleFrame = nil

        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "NoPrimary", path: "/tmp/np", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Activation should succeed even when positioning fails: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have a layout warning when no display available")
        }

        // Positioning should be skipped entirely
        XCTAssertTrue(positioner.setFrameCalls.isEmpty)
    }

    // MARK: - Capture Screen Fallback

    /// When capturing positions and the IDE center is off-screen, capture should
    /// fall back to the primary display for screen mode detection.
    func testCapturePositions_centerPointOffScreen_fallsToPrimaryDisplay() async {
        let projectId = "capstale"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()

        // IDE and Chrome frames at stale external monitor coordinates
        let staleIdeFrame = CGRect(x: 2091, y: -910, width: 1000, height: 800)
        let staleChromeFrame = CGRect(x: 3200, y: -910, width: 900, height: 800)
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(staleIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(staleChromeFrame)

        // Detector: stale center off all screens, primary display available
        var detector = StubScreenModeDetector()
        detector.visibleFrame = nil
        detector.primaryVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        detector.mode = .small

        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapStale", path: "/tmp/cs", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        await manager.captureWindowPositions(projectId: projectId)

        // Should save using the primary display's screen mode
        XCTAssertEqual(store.saveCalls.count, 1, "Should save positions using primary display fallback")
        XCTAssertEqual(store.saveCalls.first?.mode, .small, "Should detect small mode from primary display")
    }

    /// When capturing positions and no display is available at all, capture should skip.
    func testCapturePositions_centerPointOffScreen_noPrimaryDisplay_skipsCapture() async {
        let projectId = "capnone"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()

        let staleIdeFrame = CGRect(x: 5000, y: -500, width: 1000, height: 800)
        let staleChromeFrame = CGRect(x: 6000, y: -500, width: 900, height: 800)
        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(staleIdeFrame)
        positioner.getFrameResults["com.google.Chrome|\(projectId)"] = .success(staleChromeFrame)

        var detector = StubScreenModeDetector()
        detector.visibleFrame = nil
        detector.primaryVisibleFrame = nil

        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapNone", path: "/tmp/cn", color: "orange", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        await manager.captureWindowPositions(projectId: projectId)

        // Should NOT save when no display is available
        XCTAssertTrue(store.saveCalls.isEmpty, "Should skip capture when no display available")
    }
}
