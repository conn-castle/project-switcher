import XCTest

@testable import ProjectSwitcherCore

extension WindowRecoveryManagerTests {
    // MARK: - Layout-aware Recovery Tests

    func testRecoverWorkspace_projectWorkspace_appliesLayoutForIDEAndChrome() async {
        let aerospace = StubAeroSpace()
        let projectId = "myproj"
        let workspace = "ps-\(projectId)"

        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:\(projectId) - VS Code")
        let chromeWindow = makeWindow(id: 2, bundleId: "com.google.Chrome", workspace: workspace,
                                      title: "PS:\(projectId) - Chrome")
        let otherWindow = makeWindow(id: 3, bundleId: "com.other.App", workspace: workspace,
                                     title: "Other App")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow, chromeWindow, otherWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Layout phase should have called setWindowFrames for VS Code and Chrome
        let setBundleIds = positioner.setFrameCalls.map { $0.bundleId }
        XCTAssertTrue(setBundleIds.contains("com.microsoft.VSCode"),
                      "Layout phase should position VS Code windows")
        XCTAssertTrue(setBundleIds.contains("com.google.Chrome"),
                      "Layout phase should position Chrome windows")

        // All setWindowFrames calls should use the correct projectId
        XCTAssertTrue(positioner.setFrameCalls.allSatisfy { $0.projectId == projectId },
                      "All layout calls should use derived projectId")

        // Generic recovery should only run for non-layout windows (the "other" app)
        let genericBundleIds = positioner.recoverCalls.map { $0.bundleId }
        XCTAssertEqual(genericBundleIds, ["com.other.App"],
                      "Generic recovery should skip IDE/Chrome (handled by layout)")

        // Processed = all workspace windows, recovered = layout (2 default) + generic (0 unchanged)
        XCTAssertEqual(recovery.windowsProcessed, 3)
        XCTAssertEqual(recovery.windowsRecovered, 2, "Layout phase positioned 2 windows (default stub result)")
    }

    func testRecoverWorkspace_projectWorkspace_partialLayoutAllowsGenericRecoveryForTokenWindows() async {
        let aerospace = StubAeroSpace()
        let projectId = "partial"
        let workspace = "ps-\(projectId)"

        let ideWindow1 = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                    title: "PS:\(projectId) - VS Code")
        let ideWindow2 = makeWindow(id: 2, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                    title: "PS:\(projectId) - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow1, ideWindow2])

        let positioner = StubWindowPositioner()
        // Simulate partial AX write success for layout positioning.
        positioner.setFrameResults["com.microsoft.VSCode"] = .success(WindowPositionResult(positioned: 1, matched: 2))

        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)
        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Partial layout must not hide token windows from generic recovery.
        let genericBundleIds = positioner.recoverCalls.map { $0.bundleId }
        XCTAssertEqual(genericBundleIds, ["com.microsoft.VSCode", "com.microsoft.VSCode"])

        // Count should include the one layout-positioned window.
        XCTAssertEqual(recovery.windowsRecovered, 1)
    }

    func testRecoverWorkspace_projectWorkspace_onlyTargetsBundleIdsInWorkspace() async {
        let aerospace = StubAeroSpace()
        let workspace = "ps-proj"

        // Only an IDE window in the workspace — no Chrome window
        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:proj - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        _ = await manager.recoverWorkspaceWindows(workspace: workspace)

        // Layout should only call setWindowFrames for VS Code (present in workspace), not Chrome
        let setBundleIds = positioner.setFrameCalls.map { $0.bundleId }
        XCTAssertEqual(setBundleIds, ["com.microsoft.VSCode"],
                      "Layout phase should only target bundle IDs present in the workspace")
        XCTAssertFalse(setBundleIds.contains("com.google.Chrome"),
                       "Chrome is not in workspace — should not be targeted")
    }

    func testRecoverWorkspace_projectWorkspace_noLayoutApps_skipsLayoutPhase() async {
        let aerospace = StubAeroSpace()
        let workspace = "ps-proj"

        // Only a non-IDE/Chrome app in the workspace
        let otherWindow = makeWindow(id: 1, bundleId: "com.other.App", workspace: workspace,
                                     title: "Other App")
        aerospace.windowsByWorkspace[workspace] = .success([otherWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // No setWindowFrames calls — no layout-eligible apps
        XCTAssertTrue(positioner.setFrameCalls.isEmpty,
                      "No IDE/Chrome in workspace — layout phase should be skipped")
        // Generic recovery should run for the other app
        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(recovery.windowsProcessed, 1)
    }

    func testRecoverWorkspace_projectWorkspace_noDetector_skipsLayoutPhase() async {
        let aerospace = StubAeroSpace()
        let workspace = "ps-proj"
        let window = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                title: "PS:proj - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([window])

        let positioner = StubWindowPositioner()
        // No screenModeDetector — layout phase should be skipped
        let manager = makeManager(aerospace: aerospace, positioner: positioner)

        _ = await manager.recoverWorkspaceWindows(workspace: workspace)

        // No setWindowFrames calls — layout phase skipped
        XCTAssertTrue(positioner.setFrameCalls.isEmpty,
                      "Without detector, layout phase should be skipped")
        // Generic recovery should still run
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }

    func testRecoverWorkspace_nonProjectWorkspace_skipsLayoutPhase() async {
        let aerospace = StubAeroSpace()
        let workspace = "main"
        let window = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                title: "VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([window])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        _ = await manager.recoverWorkspaceWindows(workspace: workspace)

        // No setWindowFrames calls — non-project workspace
        XCTAssertTrue(positioner.setFrameCalls.isEmpty,
                      "Non-project workspace should not trigger layout phase")
        // Generic recovery runs
        XCTAssertEqual(positioner.recoverCalls.count, 1)
    }

    func testRecoverWorkspace_nonProjectWorkspace_onlyRecoversRequestedWorkspaceWindows() async {
        let aerospace = StubAeroSpace()
        let workspace = "main"
        let currentDesktopWindow = makeWindow(id: 1, bundleId: "com.test.Main", workspace: workspace,
                                              title: "Current Desktop Window")
        let otherDesktopWindow = makeWindow(id: 2, bundleId: "com.test.Other", workspace: "2",
                                            title: "Other Desktop Window")
        aerospace.windowsByWorkspace[workspace] = .success([currentDesktopWindow])
        aerospace.windowsByWorkspace["2"] = .success([otherDesktopWindow])

        let positioner = StubWindowPositioner()
        positioner.recoverResults["Current Desktop Window"] = .success(.recovered)

        let manager = makeManager(aerospace: aerospace, positioner: positioner)
        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        XCTAssertEqual(recovery.windowsProcessed, 1)
        XCTAssertEqual(recovery.windowsRecovered, 1)
        XCTAssertEqual(positioner.recoverCalls.count, 1)
        XCTAssertEqual(positioner.recoverCalls[0].windowTitle, "Current Desktop Window")
    }

    func testRecoverWorkspace_detectorFailure_usesWideFallbackAndWarns() async {
        let aerospace = StubAeroSpace()
        let workspace = "ps-proj"
        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:proj - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow])

        let positioner = StubWindowPositioner()
        var detector = StubScreenModeDetector()
        detector.mode = .failure(PsCoreError(category: .system, message: "EDID broken"))
        detector.physicalWidth = .failure(PsCoreError(category: .system, message: "width unknown"))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Layout should still run (with fallback values)
        XCTAssertFalse(positioner.setFrameCalls.isEmpty,
                       "Layout phase should still run with fallback values")

        // Warnings about detection failures should be surfaced
        XCTAssertTrue(recovery.errors.contains { $0.contains("screen mode") || $0.contains("EDID") },
                      "Detection failure should surface a warning: \(recovery.errors)")
        XCTAssertTrue(recovery.errors.contains { $0.contains("physical width") || $0.contains("width") },
                      "Width failure should surface a warning: \(recovery.errors)")
    }

    func testRecoverWorkspace_projectWorkspace_nonTokenWindowGetsGenericRecovery() async {
        let aerospace = StubAeroSpace()
        let projectId = "myproj"
        let workspace = "ps-\(projectId)"

        // Token-matching VS Code window → handled by layout phase
        let tokenWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                     title: "PS:\(projectId) - VS Code")
        // Same bundle but NO token (e.g., manually added) → should get generic recovery
        let extraWindow = makeWindow(id: 2, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                     title: "Untitled - Visual Studio Code")
        aerospace.windowsByWorkspace[workspace] = .success([tokenWindow, extraWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Layout phase should have called setWindowFrames for VS Code (token window)
        let setBundleIds = positioner.setFrameCalls.map { $0.bundleId }
        XCTAssertTrue(setBundleIds.contains("com.microsoft.VSCode"),
                      "Layout phase should position token-matching VS Code window")

        // Generic recovery should run for the extra (non-token) VS Code window
        let genericBundleIds = positioner.recoverCalls.map { $0.bundleId }
        XCTAssertEqual(genericBundleIds, ["com.microsoft.VSCode"],
                       "Non-token VS Code window should get generic recovery")

        // Both windows processed
        XCTAssertEqual(recovery.windowsProcessed, 2)
    }

    func testRecoverAll_usesLayoutPhaseForProjectWorkspaces() async {
        let aerospace = StubAeroSpace()
        let w1 = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: "ps-proj",
                            title: "PS:proj - VS Code")
        setupWorkspaceWindows(aerospace, windows: [w1])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()
        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        _ = await manager.recoverAllWindows { _, _ in }

        XCTAssertEqual(positioner.setFrameCalls.count, 1)
        XCTAssertEqual(positioner.setFrameCalls[0].bundleId, "com.microsoft.VSCode")
        XCTAssertTrue(positioner.recoverCalls.isEmpty,
                      "Token-matching project windows should be handled by layout phase")
    }

}
