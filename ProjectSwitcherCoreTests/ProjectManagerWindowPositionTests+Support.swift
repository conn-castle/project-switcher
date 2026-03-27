import Foundation
import XCTest

@testable import ProjectSwitcherCore

extension ProjectManagerWindowPositionTests {
    // MARK: - Test Doubles

    struct NoopLogger: ProjectSwitcherLogging {
        func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> {
            .success(())
        }
    }

    struct NoopTabCapture: ChromeTabCapturing {
        func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> { .success([]) }
    }

    struct NoopGitRemoteResolver: GitRemoteResolving {
        func resolve(projectPath: String) -> String? { nil }
    }

    struct NoopIdeLauncher: IdeLauncherProviding {
        func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> { .success(()) }
    }

    struct NoopChromeLauncher: ChromeLauncherProviding {
        func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> { .success(()) }
    }

    final class RecordingWindowPositioner: WindowPositioning {
        var getFrameResults: [String: Result<CGRect, PsCoreError>] = [:]
        /// Sequential results: each call shifts the first element. When empty, falls back to getFrameResults.
        var getFrameSequences: [String: [Result<CGRect, PsCoreError>]] = [:]
        var setFrameResults: [String: Result<WindowPositionResult, PsCoreError>] = [:]
        /// Sequential results for setWindowFrames.
        var setFrameSequences: [String: [Result<WindowPositionResult, PsCoreError>]] = [:]
        var trusted: Bool = true
        private(set) var setFrameCalls: [(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffset: CGFloat)] = []
        private(set) var getFrameCalls: [(bundleId: String, projectId: String)] = []

        // Fallback method support
        var getFallbackFrameResults: [String: Result<CGRect, PsCoreError>] = [:]
        var setFallbackFrameResults: [String: Result<WindowPositionResult, PsCoreError>] = [:]
        private(set) var getFallbackFrameCalls: [String] = []
        private(set) var setFallbackFrameCalls: [(bundleId: String, primaryFrame: CGRect)] = []

        func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError> {
            getFrameCalls.append((bundleId, projectId))
            let key = "\(bundleId)|\(projectId)"
            if var seq = getFrameSequences[key], !seq.isEmpty {
                let result = seq.removeFirst()
                getFrameSequences[key] = seq
                return result
            }
            return getFrameResults[key] ?? .failure(PsCoreError(category: .window, message: "no stub for \(key)"))
        }

        func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
            setFrameCalls.append((bundleId, projectId, primaryFrame, cascadeOffsetPoints))
            let key = "\(bundleId)|\(projectId)"
            if var seq = setFrameSequences[key], !seq.isEmpty {
                let result = seq.removeFirst()
                setFrameSequences[key] = seq
                return result
            }
            return setFrameResults[key] ?? .success(WindowPositionResult(positioned: 1, matched: 1))
        }

        func getFallbackWindowFrame(bundleId: String) -> Result<CGRect, PsCoreError> {
            getFallbackFrameCalls.append(bundleId)
            return getFallbackFrameResults[bundleId] ?? .failure(PsCoreError(category: .window, message: "Fallback not available"))
        }

        func setFallbackWindowFrames(bundleId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
            setFallbackFrameCalls.append((bundleId, primaryFrame))
            return setFallbackFrameResults[bundleId] ?? .failure(PsCoreError(category: .window, message: "Fallback not available"))
        }

        var recoverWindowCalls: [(bundleId: String, windowTitle: String)] = []
        var recoverWindowResult: Result<RecoveryOutcome, PsCoreError> = .success(.unchanged)
        func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
            recoverWindowCalls.append((bundleId: bundleId, windowTitle: windowTitle))
            return recoverWindowResult
        }

        var recoverFocusedCalls: [(bundleId: String, screenFrame: CGRect)] = []
        var recoverFocusedResult: Result<RecoveryOutcome, PsCoreError> = .success(.unchanged)
        func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> {
            recoverFocusedCalls.append((bundleId, screenVisibleFrame))
            return recoverFocusedResult
        }

        func isAccessibilityTrusted() -> Bool { trusted }

        func promptForAccessibility() -> Bool { trusted }
    }

    final class RecordingPositionStore: WindowPositionStoring {
        var loadResults: [String: Result<SavedWindowFrames?, PsCoreError>] = [:]
        private(set) var saveCalls: [(projectId: String, mode: ScreenMode, frames: SavedWindowFrames)] = []
        var saveResult: Result<Void, PsCoreError> = .success(())

        func load(projectId: String, mode: ScreenMode) -> Result<SavedWindowFrames?, PsCoreError> {
            let key = "\(projectId)|\(mode.rawValue)"
            return loadResults[key] ?? .success(nil)
        }

        func save(projectId: String, mode: ScreenMode, frames: SavedWindowFrames) -> Result<Void, PsCoreError> {
            saveCalls.append((projectId, mode, frames))
            return saveResult
        }
    }

    struct StubScreenModeDetector: ScreenModeDetecting {
        var mode: ScreenMode = .wide
        var physicalWidth: Double = 27.0
        var visibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        var primaryVisibleFrame: CGRect?

        func detectMode(containingPoint point: CGPoint, threshold: Double) -> Result<ScreenMode, PsCoreError> {
            .success(mode)
        }

        func physicalWidthInches(containingPoint point: CGPoint) -> Result<Double, PsCoreError> {
            .success(physicalWidth)
        }

        func screenVisibleFrame(containingPoint point: CGPoint) -> CGRect? {
            visibleFrame
        }

        func primaryScreenVisibleFrame() -> CGRect? {
            primaryVisibleFrame
        }
    }

    /// AeroSpace stub that makes selectProject succeed with minimal ceremony.
    final class SimpleAeroSpaceStub: AeroSpaceProviding {
        let projectId: String
        let ideWindowId: Int
        let chromeWindowId: Int
        var allWindows: [PsWindow] = []
        private var focusedWindowResult: Result<PsWindow, PsCoreError>

        init(projectId: String, ideWindowId: Int = 101, chromeWindowId: Int = 100) {
            self.projectId = projectId
            self.ideWindowId = ideWindowId
            self.chromeWindowId = chromeWindowId
            self.focusedWindowResult = .success(PsWindow(
                windowId: ideWindowId,
                appBundleId: "com.microsoft.VSCode",
                workspace: "ps-\(projectId)",
                windowTitle: "PS:\(projectId) - VS Code"
            ))
        }

        private var chromeWindow: PsWindow {
            PsWindow(windowId: chromeWindowId, appBundleId: "com.google.Chrome",
                     workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - Chrome")
        }
        private var ideWindow: PsWindow {
            PsWindow(windowId: ideWindowId, appBundleId: "com.microsoft.VSCode",
                     workspace: "ps-\(projectId)", windowTitle: "PS:\(projectId) - VS Code")
        }

        func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
        func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
        func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }

        func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> {
            .success([PsWorkspaceSummary(workspace: "ps-\(projectId)", isFocused: true)])
        }

        func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
        func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }

        func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> {
            if bundleId == "com.google.Chrome" { return .success([chromeWindow]) }
            if bundleId == "com.microsoft.VSCode" { return .success([ideWindow]) }
            return .success([])
        }

        func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
            .success([chromeWindow, ideWindow])
        }
        func listAllWindows() -> Result<[PsWindow], PsCoreError> {
            if !allWindows.isEmpty {
                return .success(allWindows)
            }
            return .success([chromeWindow, ideWindow])
        }

        func focusedWindow() -> Result<PsWindow, PsCoreError> { focusedWindowResult }
        func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
            let candidates = allWindows.isEmpty ? [chromeWindow, ideWindow] : allWindows
            if let window = candidates.first(where: { $0.windowId == windowId }) {
                focusedWindowResult = .success(window)
            }
            return .success(())
        }
        func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
        func focusWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }
    }

    // MARK: - Helpers

    func makeManager(
        aerospace: AeroSpaceProviding,
        windowPositioner: WindowPositioning? = nil,
        windowPositionStore: WindowPositionStoring? = nil,
        screenModeDetector: ScreenModeDetecting? = nil,
        windowPollInterval: TimeInterval = 0.1
    ) -> ProjectManager {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let chromeTabsDir = tmp.appendingPathComponent("pm-window-tabs-\(UUID().uuidString)", isDirectory: true)
        let recencyPath = tmp.appendingPathComponent("pm-window-recency-\(UUID().uuidString).json")
        let focusHistoryPath = tmp.appendingPathComponent("pm-window-focus-\(UUID().uuidString).json")
        return ProjectManager(
            aerospace: aerospace,
            ideLauncher: NoopIdeLauncher(),
            agentLayerIdeLauncher: NoopIdeLauncher(),
            chromeLauncher: NoopChromeLauncher(),
            chromeTabStore: ChromeTabStore(directory: chromeTabsDir),
            chromeTabCapture: NoopTabCapture(),
            gitRemoteResolver: NoopGitRemoteResolver(),
            logger: NoopLogger(),
            recencyFilePath: recencyPath,
            focusHistoryFilePath: focusHistoryPath,
            windowPositioner: windowPositioner,
            windowPositionStore: windowPositionStore,
            screenModeDetector: screenModeDetector,
            windowPollInterval: windowPollInterval
        )
    }
}
