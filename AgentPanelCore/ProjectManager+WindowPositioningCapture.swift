import Foundation

extension ProjectManager {
    /// Captures current window positions for a project before closing or exiting.
    ///
    /// Non-fatal: failures are logged but do not block the caller.
    func captureWindowPositions(projectId: String) async {
        guard let positioner = windowPositioner,
              let detector = screenModeDetector,
              let store = windowPositionStore,
              let config = withState({ config }) else {
            return
        }

        // Read IDE primary frame
        let ideFrame: CGRect
        switch positioner.getPrimaryWindowFrame(bundleId: ApVSCodeLauncher.bundleId, projectId: projectId) {
        case .success(let frame):
            ideFrame = frame
        case .failure(let error):
            logEvent("capture_position.ide_read_failed", level: .warn, message: error.message)
            return
        }

        // Read Chrome primary frame with bounded retry + fallback.
        // Chrome title is set synchronously via AppleScript but AX visibility can lag.
        let captureRetryInterval = windowPollInterval // ~0.1s default, injectable for tests
        let chromeFrame: CGRect?
        let (chromeCaptureResult, chromeCaptureAttempts, chromeCaptureUsedFallback) = await retryTransientWindowOp(
            maxRetries: 5,
            retryInterval: captureRetryInterval,
            operation: {
                positioner.getPrimaryWindowFrame(bundleId: ApChromeLauncher.bundleId, projectId: projectId)
            },
            fallback: {
                positioner.getFallbackWindowFrame(bundleId: ApChromeLauncher.bundleId)
            }
        )
        switch chromeCaptureResult {
        case .success(let frame):
            if chromeCaptureUsedFallback {
                logEvent("capture_position.chrome_fallback_used", level: .warn, context: [
                    "project_id": projectId,
                    "attempts": "\(chromeCaptureAttempts)"
                ])
            } else if chromeCaptureAttempts > 1 {
                logEvent("capture_position.chrome_read_retried", context: [
                    "project_id": projectId,
                    "attempts": "\(chromeCaptureAttempts)"
                ])
            }
            chromeFrame = frame
        case .failure(let error):
            let captureFailMsg = chromeCaptureUsedFallback
                ? "Token retry exhausted and fallback failed: \(error.message)"
                : "Chrome frame unavailable: \(error.message)"
            logEvent("capture_position.chrome_read_failed", level: .warn,
                     message: captureFailMsg,
                     context: ["project_id": projectId, "attempts": "\(chromeCaptureAttempts)"])
            chromeFrame = nil
        }

        // Skip save when Chrome frame is unavailable — preserve previous complete capture as canonical
        guard let resolvedChromeFrame = chromeFrame else {
            logEvent("capture_position.skipped_partial", level: .warn,
                     message: "Skipping layout save — Chrome frame unavailable, preserving previous saved layout",
                     context: ["project_id": projectId])
            return
        }

        // Detect screen mode.
        // If the center point references a disconnected display (e.g., after undocking),
        // fall back to the primary display for screen mode detection.
        let centerPoint = CGPoint(x: ideFrame.midX, y: ideFrame.midY)
        let effectiveCenterPoint: CGPoint
        if detector.screenVisibleFrame(containingPoint: centerPoint) != nil {
            effectiveCenterPoint = centerPoint
        } else if let primaryFrame = detector.primaryScreenVisibleFrame() {
            effectiveCenterPoint = CGPoint(x: primaryFrame.midX, y: primaryFrame.midY)
            logEvent("capture_position.screen_fallback_to_primary", level: .warn,
                     message: "Window center references disconnected display; using primary display for mode detection",
                     context: ["stored_center": "(\(centerPoint.x), \(centerPoint.y))"])
        } else {
            logEvent("capture_position.screen_not_found", level: .warn,
                     message: "No display found and no primary display available; skipping capture")
            return
        }

        let screenMode: ScreenMode
        switch detector.detectMode(containingPoint: effectiveCenterPoint, threshold: config.layout.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            logEvent("capture_position.screen_mode_failed", level: .warn, message: error.message)
            screenMode = .wide
        }

        // Save complete frames (both IDE and Chrome available)
        let frames = SavedWindowFrames(
            ide: SavedFrame(rect: ideFrame),
            chrome: SavedFrame(rect: resolvedChromeFrame)
        )
        switch store.save(projectId: projectId, mode: screenMode, frames: frames) {
        case .success:
            logEvent("capture_position.saved", context: [
                "project_id": projectId, "mode": screenMode.rawValue
            ])
        case .failure(let error):
            logEvent("capture_position.save_failed", level: .warn, message: error.message)
        }
    }

}
