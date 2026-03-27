import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerWindowPositionTests {
    // MARK: - Screen Mode Fallback Tests

    func testPositioningFallsToWideOnScreenModeDetectionFailure() async {
        let projectId = "kappa"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Detector that fails on mode detection
        struct FailingDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> {
                .failure(PsCoreError(category: .system, message: "EDID broken"))
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, PsCoreError> {
                .failure(PsCoreError(category: .system, message: "EDID broken"))
            }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                CGRect(x: 0, y: 0, width: 2560, height: 1415)
            }
        }

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: FailingDetector()
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Kappa", path: "/tmp/kappa", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        // Should succeed (non-fatal) — used .wide fallback
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Verify it still positioned windows (using .wide mode and 32.0 inch fallback)
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
    }

    func testPositioningSkippedWhenScreenNotFound() async {
        let projectId = "lambda"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Detector that returns nil for screen
        struct NoScreenDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> {
                .success(.wide)
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, PsCoreError> {
                .success(27.0)
            }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                nil
            }
        }

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: NoScreenDetector()
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Lambda", path: "/tmp/lambda", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("no displays available") == true)
        }

        // No setWindowFrames calls since positioning was skipped
        XCTAssertTrue(positioner.setFrameCalls.isEmpty)
    }

    // MARK: - Store Load Failure Fallback

    func testPositioningUsesComputedLayoutOnStoreLoadFailure() async {
        let projectId = "mu"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Store load fails
        store.loadResults["\(projectId)|wide"] = .failure(PsCoreError(category: .fileSystem, message: "corrupt"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Mu", path: "/tmp/mu", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Should still have positioned using computed layout
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
    }

    // MARK: - Partial Write Failure Tests

    func testPartialIDEWriteFailureProducesWarning() async {
        let projectId = "nu"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // IDE: 1 of 3 positioned (partial failure)
        positioner.setFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .success(WindowPositionResult(positioned: 1, matched: 3))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Nu", path: "/tmp/nu", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have a layout warning for partial failure")
            XCTAssertTrue(success.layoutWarning?.contains("1 of 3") == true,
                          "Warning should mention positioned/matched counts: \(success.layoutWarning ?? "")")
        }
    }

    func testPartialChromeWriteFailureProducesWarning() async {
        let projectId = "xi"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // Chrome: 2 of 5 positioned (partial failure)
        positioner.setFrameResults["com.google.Chrome|\(projectId)"] =
            .success(WindowPositionResult(positioned: 2, matched: 5))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Xi", path: "/tmp/xi", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should have a layout warning for partial Chrome failure")
            XCTAssertTrue(success.layoutWarning?.contains("2 of 5") == true,
                          "Warning should mention Chrome partial failure: \(success.layoutWarning ?? "")")
        }
    }

    func testZeroPositionedProducesWarning() async {
        let projectId = "omicron"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)
        // IDE: 0 of 0 (no matching windows found, but set returned success)
        positioner.setFrameResults["com.microsoft.VSCode|\(projectId)"] =
            .success(WindowPositionResult(positioned: 0, matched: 0))
        positioner.setFrameResults["com.google.Chrome|\(projectId)"] =
            .success(WindowPositionResult(positioned: 0, matched: 0))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Omicron", path: "/tmp/omicron", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn when zero windows positioned")
            XCTAssertTrue(success.layoutWarning?.contains("no windows") == true,
                          "Warning should mention zero positioned: \(success.layoutWarning ?? "")")
        }
    }

    // MARK: - Partial Dependency Wiring Tests

    func testPartialDependencyWiringProducesWarning() async {
        let projectId = "pi"
        let positioner = RecordingWindowPositioner()
        // Provide positioner + detector but NO store → partial deps
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: nil,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Pi", path: "/tmp/pi", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn about partial dependency wiring")
            XCTAssertTrue(success.layoutWarning?.contains("windowPositionStore") == true,
                          "Warning should name the missing dependency: \(success.layoutWarning ?? "")")
        }

        // setWindowFrames should NOT have been called (positioning disabled)
        XCTAssertTrue(positioner.setFrameCalls.isEmpty)
    }

    func testPartialDependencyWiringOnlyStoreProducesWarning() async {
        let projectId = "rho"
        let store = RecordingPositionStore()
        // Only store — no positioner or detector
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: nil,
            windowPositionStore: store,
            screenModeDetector: nil
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Rho", path: "/tmp/rho", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn about partial deps")
            XCTAssertTrue(success.layoutWarning?.contains("windowPositioner") == true)
            XCTAssertTrue(success.layoutWarning?.contains("screenModeDetector") == true)
        }
    }

    // MARK: - Physical Width Fallback Tests

    func testPhysicalWidthFallbackProducesWarning() async {
        let projectId = "sigma"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Detector that fails on physicalWidthInches but succeeds on everything else
        struct PhysicalWidthFailingDetector: ScreenModeDetecting {
            func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> {
                .success(.wide)
            }
            func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, PsCoreError> {
                .failure(PsCoreError(category: .system, message: "EDID not available"))
            }
            func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
                CGRect(x: 0, y: 0, width: 2560, height: 1415)
            }
        }

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: PhysicalWidthFailingDetector()
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "Sigma", path: "/tmp/sigma", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning, "Should warn about physical width fallback")
            XCTAssertTrue(success.layoutWarning?.contains("32\"") == true,
                          "Warning should mention 32\" fallback: \(success.layoutWarning ?? "")")
        }

        // Should still have positioned windows despite fallback
        XCTAssertEqual(positioner.setFrameCalls.count, 2)
    }

}
