import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

// MARK: - MenuWorkspaceStateCoordinator Tests

@MainActor
final class MenuWorkspaceStateCoordinatorTests: XCTestCase {

    // MARK: - Helpers

    private func makeProjectManager(
        aerospace: CoordinatorTestAeroSpaceStub,
        logger: CoordinatorTestRecordingLogger
    ) -> ProjectManager {
        let fileSystem = CoordinatorTestInMemoryFileSystem()
        let recencyFilePath = URL(fileURLWithPath: "/recency.json", isDirectory: false)
        let focusHistoryFilePath = URL(fileURLWithPath: "/focus-history.json", isDirectory: false)
        let chromeTabsDir = URL(fileURLWithPath: "/chrome-tabs", isDirectory: true)

        let manager = ProjectManager(
            aerospace: aerospace,
            ideLauncher: CoordinatorTestIdeLauncherStub(),
            agentLayerIdeLauncher: CoordinatorTestIdeLauncherStub(),
            chromeLauncher: CoordinatorTestChromeLauncherStub(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir, fileSystem: fileSystem),
            chromeTabCapture: CoordinatorTestTabCaptureStub(),
            gitRemoteResolver: CoordinatorTestGitRemoteStub(),
            logger: logger,
            recencyFilePath: recencyFilePath,
            focusHistoryFilePath: focusHistoryFilePath,
            fileSystem: fileSystem,
            windowPollTimeout: 0.5,
            windowPollInterval: 0.05
        )
        manager.loadTestConfig(Config(
            projects: [
                ProjectConfig(id: "proj-a", name: "Project A", path: "/tmp/a", color: "blue", useAgentLayer: false),
                ProjectConfig(id: "proj-b", name: "Project B", path: "/tmp/b", color: "red", useAgentLayer: false)
            ],
            chrome: ChromeConfig()
        ))
        return manager
    }

    private func waitUntil(
        description: String,
        timeout: TimeInterval = 2.0,
        condition: @escaping () -> Bool
    ) {
        let predicate = NSPredicate { _, _ in
            condition()
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: NSObject())
        let waiter = XCTWaiter()
        let result = waiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "Timed out waiting for \(description)")
    }

    // MARK: - Test 1: refreshInBackground updates workspace state and focus

    func testRefreshInBackgroundUpdatesWorkspaceStateAndFocus() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        // Configure a focused window on a project workspace so captureCurrentFocus() succeeds
        let focusedWindow = PsWindow(
            windowId: 10,
            appBundleId: "com.apple.Terminal",
            workspace: "ps-proj-a",
            windowTitle: "Terminal"
        )
        aerospace.focusedWindowResult = .success(focusedWindow)

        // Configure workspacesWithFocus so workspaceState() returns open projects
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-proj-a", isFocused: true)
        ])

        let manager = makeProjectManager(aerospace: aerospace, logger: logger)
        let coordinator = MenuWorkspaceStateCoordinator(projectManager: manager)

        // Precondition: both are nil
        XCTAssertNil(coordinator.cachedWorkspaceState)
        XCTAssertNil(coordinator.menuFocusCapture)

        coordinator.refreshInBackground()
        waitUntil(description: "workspace state + focus capture refresh") {
            coordinator.cachedWorkspaceState != nil && coordinator.menuFocusCapture != nil
        }

        // Verify workspace state was populated
        XCTAssertNotNil(coordinator.cachedWorkspaceState)
        XCTAssertEqual(coordinator.cachedWorkspaceState?.openProjectIds, Set(["proj-a"]))
        XCTAssertEqual(coordinator.cachedWorkspaceState?.activeProjectId, "proj-a")

        // Verify focus capture was populated
        XCTAssertNotNil(coordinator.menuFocusCapture)
        XCTAssertEqual(coordinator.menuFocusCapture?.windowId, focusedWindow.windowId)
        XCTAssertEqual(coordinator.menuFocusCapture?.appBundleId, focusedWindow.appBundleId)
        XCTAssertEqual(coordinator.menuFocusCapture?.workspace, focusedWindow.workspace)
    }

    // MARK: - Test 2: updateFocusCapture sets focus

    func testUpdateFocusCaptureSetsFocus() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()
        let manager = makeProjectManager(aerospace: aerospace, logger: logger)
        let coordinator = MenuWorkspaceStateCoordinator(projectManager: manager)

        // Precondition
        XCTAssertNil(coordinator.menuFocusCapture)

        let focus = CapturedFocus(windowId: 42, appBundleId: "com.apple.Safari", workspace: "main")
        coordinator.updateFocusCapture(focus)

        XCTAssertEqual(coordinator.menuFocusCapture, focus)
    }

    // MARK: - Test 3: updateFocusCapture not overwritten by stale refresh

    func testUpdateFocusCaptureNotOverwrittenByStaleRefresh() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        // Configure aerospace so the background refresh will capture a different focus
        let backgroundWindow = PsWindow(
            windowId: 100,
            appBundleId: "com.microsoft.VSCode",
            workspace: "ps-proj-b",
            windowTitle: "VS Code"
        )
        aerospace.focusedWindowResult = .success(backgroundWindow)
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-proj-b", isFocused: true)
        ])

        let workspaceQueryStarted = expectation(description: "workspace query started")
        let allowWorkspaceQueryReturn = DispatchSemaphore(value: 0)
        aerospace.onListWorkspacesWithFocus = {
            workspaceQueryStarted.fulfill()
        }
        aerospace.listWorkspacesWithFocusWaitSemaphore = allowWorkspaceQueryReturn

        let manager = makeProjectManager(aerospace: aerospace, logger: logger)
        let coordinator = MenuWorkspaceStateCoordinator(projectManager: manager)

        // Start background refresh (dispatches to background queue)
        coordinator.refreshInBackground()
        wait(for: [workspaceQueryStarted], timeout: 2.0)

        // Immediately set an explicit focus -- this bumps the generation counter
        let explicitFocus = CapturedFocus(windowId: 999, appBundleId: "com.apple.Finder", workspace: "main")
        coordinator.updateFocusCapture(explicitFocus)
        allowWorkspaceQueryReturn.signal()

        waitUntil(description: "workspace state refresh completion") {
            coordinator.cachedWorkspaceState?.openProjectIds == Set(["proj-b"])
        }

        // The explicit focus should NOT have been overwritten by the stale background capture
        XCTAssertEqual(coordinator.menuFocusCapture, explicitFocus,
            "Explicit updateFocusCapture() should not be overwritten by a stale background refresh")

        // Workspace state should still have been updated (it is always updated regardless of generation)
        XCTAssertNotNil(coordinator.cachedWorkspaceState)
        XCTAssertEqual(coordinator.cachedWorkspaceState?.openProjectIds, Set(["proj-b"]))
    }

    // MARK: - Test 4: populateMoveWindowSubmenu with open projects

    func testPopulateMoveWindowSubmenuWithOpenProjects() {
        let logger = CoordinatorTestRecordingLogger()
        let aerospace = CoordinatorTestAeroSpaceStub()

        // Configure workspaces with both projects open, proj-a focused
        let focusedWindow = PsWindow(
            windowId: 50,
            appBundleId: "com.apple.Terminal",
            workspace: "ps-proj-a",
            windowTitle: "Terminal"
        )
        aerospace.focusedWindowResult = .success(focusedWindow)
        aerospace.workspacesWithFocusResult = .success([
            PsWorkspaceSummary(workspace: "ps-proj-a", isFocused: true),
            PsWorkspaceSummary(workspace: "ps-proj-b", isFocused: false)
        ])

        let manager = makeProjectManager(aerospace: aerospace, logger: logger)
        let coordinator = MenuWorkspaceStateCoordinator(projectManager: manager)

        // Refresh to populate cached state
        coordinator.refreshInBackground()
        waitUntil(description: "workspace state + focus capture refresh for submenu") {
            coordinator.cachedWorkspaceState != nil && coordinator.menuFocusCapture != nil
        }

        // Verify state is populated before testing submenu
        XCTAssertNotNil(coordinator.cachedWorkspaceState)
        XCTAssertNotNil(coordinator.menuFocusCapture)

        // Create submenu and dummy target
        let submenu = NSMenu()
        let target = DummyTarget()
        let addAction = #selector(DummyTarget.addWindow(_:))
        let removeAction = #selector(DummyTarget.removeWindow(_:))

        let shouldShow = coordinator.populateMoveWindowSubmenu(
            submenu,
            addWindowTarget: target,
            addWindowAction: addAction,
            removeWindowTarget: target,
            removeWindowAction: removeAction
        )

        XCTAssertTrue(shouldShow, "Submenu should be visible when there are open projects")

        // Should have items for each open project + separator + "No Project"
        // Items: "Project A", "Project B", separator, "No Project"
        let items = submenu.items
        XCTAssertEqual(items.count, 4,
            "Expected 2 project items + 1 separator + 1 'No Project' item, got \(items.count)")

        // First two items should be the project names
        let projectItems = items.filter { !$0.isSeparatorItem && $0.title != "No Project" }
        let projectTitles = Set(projectItems.map(\.title))
        XCTAssertEqual(projectTitles, Set(["Project A", "Project B"]))

        // Verify represented objects are project IDs
        let projectIds = Set(projectItems.compactMap { $0.representedObject as? String })
        XCTAssertEqual(projectIds, Set(["proj-a", "proj-b"]))

        // The current workspace is "ps-proj-a", so Project A should be checked (.on)
        let projAItem = projectItems.first(where: { ($0.representedObject as? String) == "proj-a" })
        XCTAssertEqual(projAItem?.state, .on, "Project A should be checked since it is the current workspace")

        let projBItem = projectItems.first(where: { ($0.representedObject as? String) == "proj-b" })
        XCTAssertNotEqual(projBItem?.state, .on, "Project B should not be checked")

        // Verify "No Project" item exists and is not checked (since focus is in a project workspace)
        let noProjectItem = items.first(where: { $0.title == "No Project" })
        XCTAssertNotNil(noProjectItem, "'No Project' item should exist")
        XCTAssertNotEqual(noProjectItem?.state, .on,
            "'No Project' should not be checked when focus is in a project workspace")

        // Verify separator exists
        let separators = items.filter(\.isSeparatorItem)
        XCTAssertEqual(separators.count, 1, "Should have exactly one separator")
    }
}

// MARK: - Dummy Target for Submenu Tests

private class DummyTarget: NSObject {
    @objc func addWindow(_ sender: Any?) {}
    @objc func removeWindow(_ sender: Any?) {}
}
