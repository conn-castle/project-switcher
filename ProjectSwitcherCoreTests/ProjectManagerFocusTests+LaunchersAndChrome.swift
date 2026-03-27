import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerFocusTests {
    // MARK: - Launcher selection (useAgentLayer)

    func testSelectProjectUsesAgentLayerLauncherWhenUseAgentLayerTrue() async {
        let aero = FocusAeroSpaceStub()
        let directLauncher = FocusIdeLauncherStub()
        // AL launcher injects VS Code window into aero when called (simulates launch)
        let alLauncher = FocusIdeLauncherStub()
        alLauncher.onLaunch = { identifier in
            let workspace = "ps-\(identifier)"
            let ideWindow = PsWindow(
                windowId: 101, appBundleId: "com.microsoft.VSCode",
                workspace: workspace, windowTitle: "PS:\(identifier) - VS Code"
            )
            aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [ideWindow]
        }

        let manager = makeFocusManagerWithSeparateLaunchers(
            aerospace: aero,
            ideLauncher: directLauncher,
            agentLayerIdeLauncher: alLauncher
        )

        let project = ProjectConfig(
            id: "al-project",
            name: "AL Project",
            path: "/Users/test/al-project",
            color: "blue",
            useAgentLayer: true,
            chromePinnedTabs: [],
            chromeDefaultTabs: []
        )
        loadTestConfig(manager: manager, projects: [project])
        // Only set up Chrome window — VS Code must be launched via AL launcher
        configureForActivationChromeOnly(aero: aero, projectId: "al-project")

        let focus = CapturedFocus(windowId: 50, appBundleId: "com.apple.Finder", workspace: "main")
        let result = await manager.selectProject(projectId: "al-project", preCapturedFocus: focus)

        XCTAssertTrue(alLauncher.called, "Agent Layer launcher should have been called")
        XCTAssertFalse(directLauncher.called, "Direct launcher should NOT have been called")
        if case .failure(let error) = result {
            XCTFail("Expected activation to succeed, got: \(error)")
        }
    }

    func testSelectProjectUsesDirectLauncherWhenUseAgentLayerFalse() async {
        let aero = FocusAeroSpaceStub()
        let alLauncher = FocusIdeLauncherStub()
        // Direct launcher injects VS Code window into aero when called (simulates launch)
        let directLauncher = FocusIdeLauncherStub()
        directLauncher.onLaunch = { identifier in
            let workspace = "ps-\(identifier)"
            let ideWindow = PsWindow(
                windowId: 101, appBundleId: "com.microsoft.VSCode",
                workspace: workspace, windowTitle: "PS:\(identifier) - VS Code"
            )
            aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [ideWindow]
        }

        let manager = makeFocusManagerWithSeparateLaunchers(
            aerospace: aero,
            ideLauncher: directLauncher,
            agentLayerIdeLauncher: alLauncher
        )

        let project = testProject(id: "normal-project")
        loadTestConfig(manager: manager, projects: [project])
        // Only set up Chrome window — VS Code must be launched via direct launcher
        configureForActivationChromeOnly(aero: aero, projectId: "normal-project")

        let focus = CapturedFocus(windowId: 50, appBundleId: "com.apple.Finder", workspace: "main")
        let result = await manager.selectProject(projectId: "normal-project", preCapturedFocus: focus)

        XCTAssertTrue(directLauncher.called, "Direct launcher should have been called")
        XCTAssertFalse(alLauncher.called, "Agent Layer launcher should NOT have been called")
        if case .failure(let error) = result {
            XCTFail("Expected activation to succeed, got: \(error)")
        }
    }

    // MARK: - Chrome initial URLs (cold start)

    func testSelectProjectLaunchesChromeWithColdStartURLsWhenNoSnapshotExists() async {
        let aero = FocusAeroSpaceStub()
        let chromeLauncher = FocusChromeLauncherRecordingStub()

        let ideLauncher = FocusIdeLauncherStub()

        let projectId = "test"
        let workspace = "ps-\(projectId)"
        let chromeWindow = PsWindow(
            windowId: 100,
            appBundleId: "com.google.Chrome",
            workspace: workspace,
            windowTitle: "PS:\(projectId) - Chrome"
        )
        let ideWindow = PsWindow(
            windowId: 101,
            appBundleId: "com.microsoft.VSCode",
            workspace: workspace,
            windowTitle: "PS:\(projectId) - VS Code"
        )

        chromeLauncher.onLaunch = { identifier in
            aero.windowsByBundleId["com.google.Chrome"] = [chromeWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [chromeWindow]
        }
        ideLauncher.onLaunch = { identifier in
            aero.windowsByBundleId["com.microsoft.VSCode"] = [ideWindow]
            aero.windowsByWorkspace[workspace] = (aero.windowsByWorkspace[workspace] ?? []) + [ideWindow]
        }

        aero.focusWindowSuccessIds.formUnion([100, 101])
        aero.focusedWindowResult = .success(ideWindow)
        aero.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: workspace, isFocused: true)
        ])

        let manager = makeFocusManagerWithSeparateLaunchers(
            aerospace: aero,
            ideLauncher: ideLauncher,
            agentLayerIdeLauncher: ideLauncher,
            chromeLauncher: chromeLauncher
        )

        let project = ProjectConfig(
            id: projectId,
            name: "Test",
            path: "/test",
            color: "blue",
            useAgentLayer: false,
            chromePinnedTabs: ["https://project-pinned.com"],
            chromeDefaultTabs: ["https://project-default.com"]
        )
        let config = Config(
            projects: [project],
            chrome: ChromeConfig(
                pinnedTabs: ["https://global-pinned.com"],
                defaultTabs: ["https://global-default.com"],
                openGitRemote: false
            )
        )
        manager.loadTestConfig(config)

        let preFocus = CapturedFocus(windowId: 50, appBundleId: "com.apple.Finder", workspace: "main")
        let result = await manager.selectProject(projectId: projectId, preCapturedFocus: preFocus)

        if case .failure(let error) = result {
            XCTFail("Expected activation success but got: \(error)")
        }

        XCTAssertEqual(chromeLauncher.calls.count, 1)
        XCTAssertEqual(chromeLauncher.calls[0].identifier, projectId)
        XCTAssertEqual(chromeLauncher.calls[0].initialURLs, [
            "https://global-pinned.com",
            "https://project-pinned.com",
            "https://global-default.com",
            "https://project-default.com"
        ])
    }

}
