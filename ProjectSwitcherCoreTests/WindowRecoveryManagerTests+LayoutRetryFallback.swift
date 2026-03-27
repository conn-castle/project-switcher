import XCTest

@testable import ProjectSwitcherCore

extension WindowRecoveryManagerTests {
    // MARK: - Layout Recovery Retry + Fallback Tests

    func testRecoverLayout_retriesTransientTokenMissAndSucceeds() async {
        let aerospace = StubAeroSpace()
        let projectId = "retry-proj"
        let workspace = "ps-\(projectId)"

        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:\(projectId) - VS Code")
        let chromeWindow = makeWindow(id: 2, bundleId: "com.google.Chrome", workspace: workspace,
                                      title: "PS:\(projectId) - Chrome")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow, chromeWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        let tokenMiss = PsCoreError(
            category: .window,
            message: "Window title token is still propagating",
            reason: .windowTokenNotFound
        )
        // IDE: fail once then succeed
        positioner.setFrameSequences["com.microsoft.VSCode"] = [
            .failure(tokenMiss),
            .success(WindowPositionResult(positioned: 1, matched: 1))
        ]

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // IDE retried and succeeded, Chrome succeeded on first attempt
        let ideCalls = positioner.setFrameCalls.filter { $0.bundleId == "com.microsoft.VSCode" }
        XCTAssertEqual(ideCalls.count, 2, "IDE should have been called twice (1 retry + 1 success)")
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Fallback not needed")
        XCTAssertEqual(recovery.windowsRecovered, 2, "Both IDE and Chrome should be recovered")
    }

    func testRecoverLayout_usesFallbackAfterRetryExhaustion() async {
        let aerospace = StubAeroSpace()
        let projectId = "fb-proj"
        let workspace = "ps-\(projectId)"

        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:\(projectId) - VS Code")
        // Extra VS Code window in workspace (without token in title)
        let ideWindow2 = makeWindow(id: 10, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                    title: "Untitled - VS Code")
        let chromeWindow = makeWindow(id: 2, bundleId: "com.google.Chrome", workspace: workspace,
                                      title: "PS:\(projectId) - Chrome")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow, ideWindow2, chromeWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        let tokenMiss = PsCoreError(
            category: .window,
            message: "Window title token is still propagating",
            reason: .windowTokenNotFound
        )
        // IDE: all 3 retries fail
        positioner.setFrameSequences["com.microsoft.VSCode"] = Array(repeating: .failure(tokenMiss), count: 3)
        // IDE fallback succeeds
        positioner.setFallbackFrameResults["com.microsoft.VSCode"] =
            .success(WindowPositionResult(positioned: 1, matched: 1))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Fallback was used for IDE
        XCTAssertEqual(positioner.setFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.setFallbackFrameCalls[0].bundleId, "com.microsoft.VSCode")
        XCTAssertTrue(aerospace.focusWindowCalls.contains(ideWindow.windowId),
                      "Fallback should anchor focus to a deterministic workspace window")

        // Only the fallback-anchor window is handled by layout; extra VS Code windows remain
        // eligible for generic recovery.
        let genericBundleIds = positioner.recoverCalls.map { $0.bundleId }
        XCTAssertEqual(genericBundleIds, ["com.microsoft.VSCode"],
                       "Non-anchor VS Code windows should still receive generic recovery")

        XCTAssertTrue(recovery.errors.isEmpty, "Fallback succeeded — no errors expected")
        // Fallback positioned 1 IDE + 1 Chrome via normal path = 2 total
        XCTAssertEqual(recovery.windowsRecovered, 2,
                       "Fallback anchor + Chrome should be counted as recovered")
    }

    func testRecoverLayout_fallbackRequiresUniqueWorkspaceWindow() async {
        let aerospace = StubAeroSpace()
        let projectId = "fb-ambiguous"
        let workspace = "ps-\(projectId)"

        let chromeWindow1 = makeWindow(id: 2, bundleId: "com.google.Chrome", workspace: workspace,
                                       title: "Window A")
        let chromeWindow2 = makeWindow(id: 3, bundleId: "com.google.Chrome", workspace: workspace,
                                       title: "Window B")
        aerospace.windowsByWorkspace[workspace] = .success([chromeWindow1, chromeWindow2])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        let tokenMiss = PsCoreError(
            category: .window,
            message: "Window title token is still propagating",
            reason: .windowTokenNotFound
        )
        positioner.setFrameSequences["com.google.Chrome"] = Array(repeating: .failure(tokenMiss), count: 3)

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)
        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Ambiguous fallback must not execute")
        XCTAssertTrue(recovery.errors.contains {
            $0.contains("fallback requires exactly one workspace window")
        })

        // Ambiguous fallback leaves both windows for generic recovery.
        let genericBundleIds = positioner.recoverCalls.map { $0.bundleId }
        XCTAssertEqual(genericBundleIds, ["com.google.Chrome", "com.google.Chrome"])

        // No windows recovered via layout phase (both fell through to generic)
        XCTAssertEqual(recovery.windowsRecovered, 0,
                       "Ambiguous fallback should not count any windows as recovered")
    }

    func testRecoverLayout_fallbackFailureAddsError() async {
        let aerospace = StubAeroSpace()
        let projectId = "fb-fail"
        let workspace = "ps-\(projectId)"

        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:\(projectId) - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        let tokenMiss = PsCoreError(
            category: .window,
            message: "Window title token is still propagating",
            reason: .windowTokenNotFound
        )
        // All 3 retries fail
        positioner.setFrameSequences["com.microsoft.VSCode"] = Array(repeating: .failure(tokenMiss), count: 3)
        // Fallback also fails
        positioner.setFallbackFrameResults["com.microsoft.VSCode"] =
            .failure(PsCoreError(category: .window, message: "Ambiguous: 3 windows"))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Error should be reported
        XCTAssertFalse(recovery.errors.isEmpty, "Should have error when both retry and fallback fail")
        XCTAssertTrue(recovery.errors.first?.contains("Ambiguous") == true)

        // Fallback failed — no windows recovered via layout
        XCTAssertEqual(recovery.windowsRecovered, 0,
                       "Failed fallback should not count windows as recovered")
    }

    func testRecoverLayout_fallbackPositionedZeroAddsError() async {
        let aerospace = StubAeroSpace()
        let projectId = "fb-zero"
        let workspace = "ps-\(projectId)"

        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:\(projectId) - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        let tokenMiss = PsCoreError(
            category: .window,
            message: "Window title token is still propagating",
            reason: .windowTokenNotFound
        )
        // All 3 retries fail
        positioner.setFrameSequences["com.microsoft.VSCode"] = Array(repeating: .failure(tokenMiss), count: 3)
        // Fallback succeeds but positions 0 windows
        positioner.setFallbackFrameResults["com.microsoft.VSCode"] =
            .success(WindowPositionResult(positioned: 0, matched: 0))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Fallback returned positioned: 0 — should be treated as error
        XCTAssertTrue(recovery.errors.contains { $0.contains("fallback positioned 0 windows") })
        XCTAssertEqual(recovery.windowsRecovered, 0,
                       "positioned: 0 fallback should not count as recovered")
    }

    func testRecoverLayout_fallbackAnchorFromBundleWindowWhenNoTokenMatch() async {
        let aerospace = StubAeroSpace()
        let projectId = "fb-bundle"
        let workspace = "ps-\(projectId)"

        // Single Chrome window WITHOUT the token in its title (title hasn't updated yet)
        let chromeWindow = makeWindow(id: 2, bundleId: "com.google.Chrome", workspace: workspace,
                                      title: "New Tab - Google Chrome")
        aerospace.windowsByWorkspace[workspace] = .success([chromeWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        let tokenMiss = PsCoreError(
            category: .window,
            message: "Window title token is still propagating",
            reason: .windowTokenNotFound
        )
        positioner.setFrameSequences["com.google.Chrome"] = Array(repeating: .failure(tokenMiss), count: 3)
        // Fallback succeeds
        positioner.setFallbackFrameResults["com.google.Chrome"] =
            .success(WindowPositionResult(positioned: 1, matched: 1))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // tokenMatchingWindows is empty, allBundleWindows has 1 → fallback anchor from bundle
        XCTAssertEqual(positioner.setFallbackFrameCalls.count, 1)
        XCTAssertEqual(positioner.setFallbackFrameCalls[0].bundleId, "com.google.Chrome")
        XCTAssertTrue(aerospace.focusWindowCalls.contains(chromeWindow.windowId),
                      "Should focus the lone bundle window as fallback anchor")
        XCTAssertTrue(recovery.errors.isEmpty, "Fallback succeeded — no errors expected")
        XCTAssertEqual(recovery.windowsRecovered, 1)
    }

    func testRecoverLayout_fallbackFocusFailureAddsError() async {
        let aerospace = StubAeroSpace()
        let projectId = "fb-focus-fail"
        let workspace = "ps-\(projectId)"

        let ideWindow = makeWindow(id: 1, bundleId: "com.microsoft.VSCode", workspace: workspace,
                                   title: "PS:\(projectId) - VS Code")
        aerospace.windowsByWorkspace[workspace] = .success([ideWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        let tokenMiss = PsCoreError(
            category: .window,
            message: "Window title token is still propagating",
            reason: .windowTokenNotFound
        )
        positioner.setFrameSequences["com.microsoft.VSCode"] = Array(repeating: .failure(tokenMiss), count: 3)
        // Fallback would succeed, but focus will fail first
        positioner.setFallbackFrameResults["com.microsoft.VSCode"] =
            .success(WindowPositionResult(positioned: 1, matched: 1))

        // Focus fails only for the anchor window
        aerospace.focusWindowResults[ideWindow.windowId] =
            .failure(PsCoreError(category: .window, message: "Window not found in tree"))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // Fallback was NOT called because focus failed
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty,
                      "Focus failure should prevent fallback execution")
        XCTAssertTrue(recovery.errors.contains { $0.contains("focus failed for fallback window") })
        XCTAssertEqual(recovery.windowsRecovered, 0,
                       "Focus failure should not count windows as recovered")
    }

    func testRecoverLayout_permanentErrorSkipsFallback() async {
        let aerospace = StubAeroSpace()
        let projectId = "perm-err"
        let workspace = "ps-\(projectId)"

        let chromeWindow = makeWindow(id: 2, bundleId: "com.google.Chrome", workspace: workspace,
                                      title: "PS:\(projectId) - Chrome")
        aerospace.windowsByWorkspace[workspace] = .success([chromeWindow])

        let positioner = StubWindowPositioner()
        let detector = StubScreenModeDetector()

        // Permanent error (not "No window found with token")
        positioner.setFrameResults["com.google.Chrome"] =
            .failure(PsCoreError(category: .window, message: "AX permission denied"))

        let manager = makeManager(aerospace: aerospace, positioner: positioner,
                                  screenModeDetector: detector)

        let result = await manager.recoverWorkspaceWindows(workspace: workspace)

        guard case .success(let recovery) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }

        // No retry, no fallback — permanent error reported directly
        XCTAssertEqual(positioner.setFrameCalls.count, 1, "Should only try once for permanent error")
        XCTAssertTrue(positioner.setFallbackFrameCalls.isEmpty, "Permanent error should not trigger fallback")
        XCTAssertFalse(recovery.errors.isEmpty)
        XCTAssertTrue(recovery.errors.first?.contains("AX permission denied") == true)
    }
}
