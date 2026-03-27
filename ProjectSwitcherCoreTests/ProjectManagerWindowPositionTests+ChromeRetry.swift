import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerWindowPositionTests {
    // MARK: - Chrome Set Retry + Fallback Tests

    func testChromeSetRetriesAndSucceeds() async {
        let projectId = "cs-retry-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = PsCoreError(
            category: .window,
            message: "Chrome title token is still propagating",
            reason: .windowTokenNotFound
        )
        // Fail twice, then succeed
        positioner.setFrameSequences[chromeKey] = [
            .failure(tokenMiss),
            .failure(tokenMiss),
            .success(WindowPositionResult(positioned: 1, matched: 1))
        ]

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CSR", path: "/tmp/csr", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNil(success.layoutWarning, "Retry succeeded — no warning")
        }

        // IDE set + 3 Chrome set attempts
        let chromeCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.google.Chrome" }
        XCTAssertEqual(chromeCalls.count, 3)
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Fallback not needed")
    }

    func testChromeSetFallbackUsedAfterRetryExhaustion() async {
        let projectId = "cs-fb-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = PsCoreError(
            category: .window,
            message: "Chrome title token is still propagating",
            reason: .windowTokenNotFound
        )
        // All 5 retries fail
        positioner.setFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback succeeds
        positioner.setFallbackFrameResults["com.google.Chrome"] =
            .success(WindowPositionResult(positioned: 1, matched: 1))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CSFB", path: "/tmp/csfb", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            // Fallback succeeded — no warning about Chrome failure
            XCTAssertNil(success.layoutWarning)
        }

        XCTAssertEqual(positioner.setFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.setFallbackFrameCalls[0].bundleId, "com.google.Chrome")
    }

    func testChromeSetFallbackFailureAddsWarning() async {
        let projectId = "cs-fb-2"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = PsCoreError(
            category: .window,
            message: "Chrome title token is still propagating",
            reason: .windowTokenNotFound
        )
        positioner.setFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback also fails
        positioner.setFallbackFrameResults["com.google.Chrome"] =
            .failure(PsCoreError(category: .window, message: "Ambiguous: 2 windows"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector,
            windowPollInterval: 0.001
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CSFB2", path: "/tmp/csfb2", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("Ambiguous") == true)
        }
    }

    func testChromeSetPermanentErrorSkipsFallback() async {
        let projectId = "cs-perm-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)
        aerospace.allWindows = [
            PsWindow(windowId: 42, appBundleId: "com.other", workspace: "main", windowTitle: "Other")
        ]

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        // Permanent error (not "No window found with token")
        let chromeKey = "com.google.Chrome|\(projectId)"
        positioner.setFrameResults[chromeKey] =
            .failure(PsCoreError(category: .window, message: "AX permission denied"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CSPerm", path: "/tmp/csperm", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let preFocus = CapturedFocus(windowId: 1, appBundleId: "other", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        switch result {
        case .failure(let error):
            XCTFail("Expected success: \(error)")
        case .success(let success):
            XCTAssertNotNil(success.layoutWarning)
            XCTAssertTrue(success.layoutWarning?.contains("AX permission denied") == true)
        }

        // Permanent error: no fallback attempted, only one Chrome set call
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Permanent error should not trigger fallback")
        let chromeCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.google.Chrome" }
        XCTAssertEqual(chromeCalls.count, 1, "Should only try once for permanent error")
    }

    // MARK: - Capture Retry + Fallback + Skip-Save Tests

    func testCaptureRetriesChromeReadAndSaves() async {
        let projectId = "cap-retry-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = PsCoreError(
            category: .window,
            message: "Chrome title token is still propagating",
            reason: .windowTokenNotFound
        )
        // Fail twice, succeed on third
        positioner.getFrameSequences[chromeKey] = [
            .failure(tokenMiss),
            .failure(tokenMiss),
            .success(defaultChromeFrame)
        ]

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapR", path: "/tmp/capr", color: "blue", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = await manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Save should have happened with both IDE and Chrome frames
        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertNotNil(store.saveCalls[0].frames.chrome)
        // Chrome read was called 3 times (2 failures + 1 success)
        let chromeGetCalls = positioner.getFrameCalls.filter { $0.bundleId == "com.google.Chrome" }
        XCTAssertEqual(chromeGetCalls.count, 3)
    }

    func testCaptureUsesChromeReadFallbackAndSaves() async {
        let projectId = "cap-fb-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = PsCoreError(
            category: .window,
            message: "Chrome title token is still propagating",
            reason: .windowTokenNotFound
        )
        // All 5 retries fail
        positioner.getFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback succeeds
        positioner.getFallbackFrameResults["com.google.Chrome"] = .success(defaultChromeFrame)

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapFB", path: "/tmp/capfb", color: "red", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = await manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Save should have happened with fallback Chrome frame
        XCTAssertEqual(store.saveCalls.count, 1)
        XCTAssertNotNil(store.saveCalls[0].frames.chrome)
        XCTAssertEqual(positioner.getFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.getFallbackFrameCalls[0], "com.google.Chrome")
    }

    func testCaptureSkipsSaveWhenChromeRetryAndFallbackFail() async {
        let projectId = "cap-skip-1"
        let positioner = RecordingWindowPositioner()
        let store = RecordingPositionStore()
        let detector = StubScreenModeDetector()
        let aerospace = SimpleAeroSpaceStub(projectId: projectId)

        positioner.getFrameResults["com.microsoft.VSCode|\(projectId)"] = .success(defaultIdeFrame)

        let chromeKey = "com.google.Chrome|\(projectId)"
        let tokenMiss = PsCoreError(
            category: .window,
            message: "Chrome title token is still propagating",
            reason: .windowTokenNotFound
        )
        // All 5 retries fail
        positioner.getFrameSequences[chromeKey] = Array(repeating: .failure(tokenMiss), count: 5)
        // Fallback also fails
        positioner.getFallbackFrameResults["com.google.Chrome"] =
            .failure(PsCoreError(category: .window, message: "Ambiguous: 2 windows"))

        let manager = makeManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            windowPositionStore: store,
            screenModeDetector: detector
        )
        manager.loadTestConfig(Config(
            projects: [ProjectConfig(id: projectId, name: "CapSkip", path: "/tmp/capskip", color: "green", useAgentLayer: false)],
            chrome: ChromeConfig()
        ))

        let result = await manager.closeProject(projectId: projectId)
        if case .failure(let error) = result { XCTFail("Expected success: \(error)") }

        // Skip save entirely — preserves previous complete layout
        XCTAssertTrue(store.saveCalls.isEmpty, "Should skip save when Chrome unavailable after retry+fallback")
    }
}
