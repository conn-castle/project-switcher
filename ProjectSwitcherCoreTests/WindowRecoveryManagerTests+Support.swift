import Foundation
import XCTest

@testable import ProjectSwitcherCore

extension WindowRecoveryManagerTests {
    // MARK: - Test Doubles

    struct NoopLogger: ProjectSwitcherLogging {
        func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
            .success(())
        }
    }

    final class StubAeroSpace: AeroSpaceProviding {
        enum RecordedAction: Equatable {
            case focusWindow(Int)
            case focusWorkspace(String)
            case moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool)
            case reloadConfig
        }

        var workspaces: [String] = []
        var windowsByWorkspace: [String: Result<[PsWindow], PsCoreError>] = [:]
        var focusedWindowResult: Result<PsWindow, PsCoreError> = .failure(PsCoreError(message: "no focus"))
        var focusWindowCalls: [Int] = []
        var focusWorkspaceCalls: [String] = []
        var callTrace: [RecordedAction] = []
        var moveWindowCalls: [(workspace: String, windowId: Int, focusFollows: Bool)] = []
        var moveWindowResult: Result<Void, PsCoreError> = .success(())
        var focusWindowResult: Result<Void, PsCoreError> = .success(())
        /// Per-windowId overrides for focusWindow. Checked before `focusWindowResult`.
        var focusWindowResults: [Int: Result<Void, PsCoreError>] = [:]
        /// Sequential results for focusWindow by windowId. Each call shifts the first element;
        /// when the sequence is empty, falls back to `focusWindowResults` / `focusWindowResult`.
        var focusWindowSequences: [Int: [Result<Void, PsCoreError>]] = [:]
        var focusWorkspaceResult: Result<Void, PsCoreError> = .success(())
        /// Per-workspace overrides for focusWorkspace. Checked before `focusWorkspaceResult`.
        var focusWorkspaceResults: [String: Result<Void, PsCoreError>] = [:]
        var reloadConfigCalls = 0
        var reloadConfigResult: Result<Void, PsCoreError> = .success(())

        func getWorkspaces() -> Result<[String], PsCoreError> { .success(workspaces) }
        func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(workspaces.contains(name)) }
        func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
        func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { .success([]) }
        func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
        func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> { .success([]) }

        func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
            windowsByWorkspace[workspace] ?? .success([])
        }

        func listAllWindows() -> Result<[PsWindow], PsCoreError> {
            // Aggregate from windowsByWorkspace for consistency
            var all: [PsWindow] = []
            for ws in workspaces {
                if case .success(let windows) = listWindowsWorkspace(workspace: ws) {
                    all.append(contentsOf: windows)
                }
            }
            return .success(all)
        }

        func focusedWindow() -> Result<PsWindow, PsCoreError> {
            focusedWindowResult
        }

        func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
            focusWindowCalls.append(windowId)
            callTrace.append(.focusWindow(windowId))
            if var seq = focusWindowSequences[windowId], !seq.isEmpty {
                let result = seq.removeFirst()
                focusWindowSequences[windowId] = seq
                return result
            }
            return focusWindowResults[windowId] ?? focusWindowResult
        }

        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> {
            moveWindowCalls.append((workspace, windowId, focusFollows))
            callTrace.append(.moveWindowToWorkspace(workspace: workspace, windowId: windowId, focusFollows: focusFollows))
            switch moveWindowResult {
            case .failure(let error):
                return .failure(error)
            case .success:
                break
            }

            for (sourceWorkspace, listedResult) in windowsByWorkspace {
                guard case .success(var sourceWindows) = listedResult else { continue }
                guard let index = sourceWindows.firstIndex(where: { $0.windowId == windowId }) else { continue }

                let window = sourceWindows.remove(at: index)
                windowsByWorkspace[sourceWorkspace] = .success(sourceWindows)

                let movedWindow = PsWindow(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: workspace,
                    windowTitle: window.windowTitle
                )

                if case .success(let destinationWindows) = windowsByWorkspace[workspace] {
                    windowsByWorkspace[workspace] = .success(destinationWindows + [movedWindow])
                } else if windowsByWorkspace[workspace] == nil {
                    windowsByWorkspace[workspace] = .success([movedWindow])
                }

                if !workspaces.contains(workspace) {
                    workspaces.append(workspace)
                    workspaces.sort()
                }
                return .success(())
            }

            return .success(())
        }

        func focusWorkspace(name: String) -> Result<Void, PsCoreError> {
            focusWorkspaceCalls.append(name)
            callTrace.append(.focusWorkspace(name))
            return focusWorkspaceResults[name] ?? focusWorkspaceResult
        }

        func reloadConfig() -> Result<Void, PsCoreError> {
            reloadConfigCalls += 1
            callTrace.append(.reloadConfig)
            return reloadConfigResult
        }
    }

    final class StubWindowPositioner: WindowPositioning {
        var recoverCalls: [(bundleId: String, windowTitle: String, screenFrame: CGRect)] = []
        var recoverResults: [String: Result<RecoveryOutcome, PsCoreError>] = [:] // keyed by windowTitle
        var defaultRecoverResult: Result<RecoveryOutcome, PsCoreError> = .success(.unchanged)
        var setFrameCalls: [(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffset: CGFloat)] = []
        var setFrameResults: [String: Result<WindowPositionResult, PsCoreError>] = [:] // keyed by bundleId
        /// Sequential results for setWindowFrames (keyed by bundleId). Each call shifts first element.
        var setFrameSequences: [String: [Result<WindowPositionResult, PsCoreError>]] = [:]
        var defaultSetFrameResult: Result<WindowPositionResult, PsCoreError> = .success(WindowPositionResult(positioned: 1, matched: 1))

        // Fallback method support
        var setFallbackFrameResults: [String: Result<WindowPositionResult, PsCoreError>] = [:]
        private(set) var setFallbackFrameCalls: [(bundleId: String, primaryFrame: CGRect)] = []

        func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
            recoverCalls.append((bundleId, windowTitle, screenVisibleFrame))
            return recoverResults[windowTitle] ?? defaultRecoverResult
        }

        var recoverFocusedCalls: [(bundleId: String, screenFrame: CGRect)] = []
        var defaultRecoverFocusedResult: Result<RecoveryOutcome, PsCoreError> = .success(.unchanged)
        func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
            recoverFocusedCalls.append((bundleId, screenVisibleFrame))
            return defaultRecoverFocusedResult
        }

        func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError> {
            .failure(PsCoreError(message: "not implemented"))
        }

        func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
            setFrameCalls.append((bundleId, projectId, primaryFrame, cascadeOffsetPoints))
            if var seq = setFrameSequences[bundleId], !seq.isEmpty {
                let result = seq.removeFirst()
                setFrameSequences[bundleId] = seq
                return result
            }
            return setFrameResults[bundleId] ?? defaultSetFrameResult
        }

        func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, PsCoreError> {
            .failure(PsCoreError(category: .window, message: "Fallback not available"))
        }

        func setFallbackWindowFrames(bundleId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
            setFallbackFrameCalls.append((bundleId, primaryFrame))
            return setFallbackFrameResults[bundleId] ?? .failure(PsCoreError(category: .window, message: "Fallback not available"))
        }

        func isAccessibilityTrusted() -> Bool { true }
        func promptForAccessibility() -> Bool { true }
    }

    struct StubScreenModeDetector: ScreenModeDetecting {
        var mode: Result<ScreenMode, PsCoreError> = .success(.wide)
        var physicalWidth: Result<Double, PsCoreError> = .success(27.0)
        var visibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        var primaryVisibleFrame: CGRect?

        func detectMode(containingPoint: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> { mode }
        func physicalWidthInches(containingPoint: CGPoint) -> Result<Double, PsCoreError> { physicalWidth }
        func screenVisibleFrame(containingPoint: CGPoint) -> CGRect? { visibleFrame }
        func primaryScreenVisibleFrame() -> CGRect? { primaryVisibleFrame }
    }

    // MARK: - Helpers

    func makeManager(
        aerospace: StubAeroSpace = StubAeroSpace(),
        positioner: StubWindowPositioner = StubWindowPositioner(),
        screenModeDetector: ScreenModeDetecting? = nil,
        layoutConfig: LayoutConfig = LayoutConfig(),
        knownProjectIds: Set<String>? = nil
    ) -> WindowRecoveryManager {
        WindowRecoveryManager(
            aerospace: aerospace,
            windowPositioner: positioner,
            screenVisibleFrame: screenFrame,
            logger: NoopLogger(),
            screenModeDetector: screenModeDetector,
            layoutConfig: layoutConfig,
            knownProjectIds: knownProjectIds
        )
    }

    func makeWindow(id: Int, bundleId: String = "com.test.app", workspace: String = "ps-test", title: String = "Test Window") -> PsWindow {
        PsWindow(windowId: id, appBundleId: bundleId, workspace: workspace, windowTitle: title)
    }

    /// Helper: sets up a StubAeroSpace with windows in workspaces (for recoverAll tests).
    func setupWorkspaceWindows(_ aerospace: StubAeroSpace, windows: [PsWindow]) {
        var byWorkspace: [String: [PsWindow]] = [:]
        var wsSet: Set<String> = []
        for window in windows {
            byWorkspace[window.workspace, default: []].append(window)
            wsSet.insert(window.workspace)
        }
        aerospace.workspaces = Array(wsSet).sorted()
        for (ws, wins) in byWorkspace {
            aerospace.windowsByWorkspace[ws] = .success(wins)
        }
    }
}
