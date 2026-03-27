import Foundation

extension ProjectManager {
    // MARK: - Transient Window Op Retry

    /// Executes `operation` with retry on transient window-token errors, falling back
    /// to `fallback` when retries are exhausted.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of attempts before falling back.
    ///   - retryInterval: Delay in seconds between retry attempts.
    ///   - operation: The primary operation to attempt (called synchronously each attempt).
    ///   - fallback: A fallback operation invoked when retries are exhausted on a transient error.
    /// - Returns: A tuple of the final `Result`, the number of attempts made, and whether the fallback was invoked.
    func retryTransientWindowOp<T>(
        maxRetries: Int,
        retryInterval: TimeInterval,
        operation: () -> Result<T, PsCoreError>,
        fallback: () -> Result<T, PsCoreError>
    ) async -> (result: Result<T, PsCoreError>, attempts: Int, usedFallback: Bool) {
        var attempt = 0
        while true {
            attempt += 1
            switch operation() {
            case .success(let value):
                return (.success(value), attempt, false)
            case .failure(let error):
                let isTransient = error.isWindowTokenNotFound
                if isTransient && attempt < maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
                    continue
                }
                if isTransient {
                    return (fallback(), attempt, true)
                }
                return (.failure(error), attempt, false)
            }
        }
    }

    // MARK: - Window Positioning

    /// Positions IDE and Chrome windows after activation.
    ///
    /// Non-fatal: returns a warning string on failure, nil on success.
    /// Requires windowPositioner, screenModeDetector, and windowPositionStore to all be set.
    /// If only some positioning dependencies are wired, returns a diagnostic warning.
    func positionWindows(projectId: String) async -> String? {
        // All three positioning deps must be present. If only some are wired, surface a warning.
        let hasPositioner = windowPositioner != nil
        let hasDetector = screenModeDetector != nil
        let hasStore = windowPositionStore != nil
        let hasAny = hasPositioner || hasDetector || hasStore
        let hasAll = hasPositioner && hasDetector && hasStore

        if hasAny && !hasAll {
            let missing = [
                hasPositioner ? nil : "windowPositioner",
                hasDetector ? nil : "screenModeDetector",
                hasStore ? nil : "windowPositionStore"
            ].compactMap { $0 }
            logEvent("position.partial_deps", level: .warn, message: "Missing: \(missing.joined(separator: ", "))")
            return "Window positioning disabled: missing \(missing.joined(separator: ", "))"
        }

        guard let positioner = windowPositioner,
              let detector = screenModeDetector,
              let store = windowPositionStore,
              let config = withState({ config }) else {
            return nil
        }

        var warnings: [String] = []

        // Read IDE frame to determine which monitor the windows are on.
        // VS Code updates its window title asynchronously after launch, so the AX title
        // token may not be ready on the first attempt. Retry briefly to reduce failures.
        let ideFrame: CGRect
        let maxFrameRetries = 10
        let frameRetryInterval = windowPollInterval // ~0.1s default, injectable for tests
        let minimumZeroWindowProbeFailuresForFastFail = 2
        // Require multiple consecutive zero-window confirmations plus roughly half
        // the token retry budget so slower VS Code startups can still recover.
        let minimumZeroWindowRetryAttemptsForFastFail = 6
        var frameAttempt = 0
        var consecutiveZeroWindowProbeFailures = 0

        ideFrameLoop: while true {
            frameAttempt += 1
            switch positioner.getPrimaryWindowFrame(bundleId: PsVSCodeLauncher.bundleId, projectId: projectId) {
            case .success(let frame):
                if frameAttempt > 1 {
                    logEvent("position.ide_frame_read_retried", context: [
                        "project_id": projectId,
                        "attempts": "\(frameAttempt)"
                    ])
                }
                ideFrame = frame
            case .failure(let error):
                // Only retry transient "window not found" errors (title not yet updated).
                // Permanent errors (AX permission denied, app not running, etc.) fail immediately.
                let isTransient = error.isWindowTokenNotFound
                if isTransient && frameAttempt < maxFrameRetries {
                    // Probe for a permanent zero-window condition, but require multiple
                    // confirmations plus minimum retry confidence before fast-failing.
                    let shouldProbeForZeroWindows = frameAttempt == 1 || consecutiveZeroWindowProbeFailures > 0
                    if shouldProbeForZeroWindows {
                        switch positioner.getFallbackWindowFrame(bundleId: PsVSCodeLauncher.bundleId) {
                        case .success:
                            consecutiveZeroWindowProbeFailures = 0
                            // Probe success confirms windows exist. Continue token retries.
                            // Do not use the probe frame here: this path is only for fast-failing
                            // the permanent zero-window condition.
                            break
                        case .failure(let probeError):
                            if probeError.isWindowInventoryEmpty {
                                consecutiveZeroWindowProbeFailures += 1
                                if consecutiveZeroWindowProbeFailures >= minimumZeroWindowProbeFailuresForFastFail,
                                   frameAttempt >= minimumZeroWindowRetryAttemptsForFastFail {
                                    logEvent("position.ide_no_windows", level: .warn,
                                             message: probeError.message,
                                             context: [
                                                "project_id": projectId,
                                                "attempts": "\(frameAttempt)",
                                                "probe_failures": "\(consecutiveZeroWindowProbeFailures)"
                                             ])
                                    return "Window positioning skipped: \(probeError.message)"
                                }
                            } else {
                                consecutiveZeroWindowProbeFailures = 0
                            }
                            // Ambiguous or other error — continue retry loop (token may resolve)
                        }
                    }
                    try? await Task.sleep(nanoseconds: UInt64(frameRetryInterval * 1_000_000_000))
                    continue
                }
                // Retry exhausted or permanent error — try fallback to focused/only window
                if isTransient {
                    switch positioner.getFallbackWindowFrame(bundleId: PsVSCodeLauncher.bundleId) {
                    case .success(let fallbackFrame):
                        logEvent("position.ide_fallback_used", level: .warn, context: [
                            "project_id": projectId,
                            "attempts": "\(frameAttempt)"
                        ])
                        ideFrame = fallbackFrame
                        break ideFrameLoop
                    case .failure(let fallbackError):
                        logEvent("position.ide_frame_read_failed", level: .warn,
                                 message: "Token retry exhausted and fallback failed: \(fallbackError.message)",
                                 context: ["project_id": projectId, "attempts": "\(frameAttempt)"])
                        return "Window positioning skipped: \(fallbackError.message)"
                    }
                } else {
                    logEvent("position.ide_frame_read_failed", level: .warn, message: error.message, context: [
                        "project_id": projectId,
                        "attempts": "\(frameAttempt)"
                    ])
                    return "Window positioning skipped: \(error.message)"
                }
            }
            break ideFrameLoop
        }

        // Detect screen mode (use center of IDE frame as reference point).
        // If the center point references a disconnected display (e.g., after undocking),
        // fall back to the primary display for all screen queries.
        let centerPoint = CGPoint(x: ideFrame.midX, y: ideFrame.midY)
        let effectiveCenterPoint: CGPoint
        let screenVisibleFrame: CGRect
        if let frame = detector.screenVisibleFrame(containingPoint: centerPoint) {
            effectiveCenterPoint = centerPoint
            screenVisibleFrame = frame
        } else if let primaryFrame = detector.primaryScreenVisibleFrame() {
            effectiveCenterPoint = CGPoint(x: primaryFrame.midX, y: primaryFrame.midY)
            screenVisibleFrame = primaryFrame
            logEvent("position.screen_fallback_to_primary", level: .warn,
                     message: "Window center references disconnected display; using primary display",
                     context: ["stored_center": "(\(centerPoint.x), \(centerPoint.y))"])
        } else {
            logEvent("position.screen_frame_not_found", level: .warn)
            return "Window positioning skipped: no displays available"
        }

        let screenMode: ScreenMode
        let physicalWidth: Double
        switch detector.detectMode(containingPoint: effectiveCenterPoint, threshold: config.layout.smallScreenThreshold) {
        case .success(let mode):
            screenMode = mode
        case .failure(let error):
            // EDID failure: log WARN, use .wide as explicit fallback
            logEvent("position.screen_mode_detection_failed", level: .warn, message: error.message)
            screenMode = .wide
        }

        switch detector.physicalWidthInches(containingPoint: effectiveCenterPoint) {
        case .success(let width):
            physicalWidth = width
        case .failure(let error):
            logEvent("position.physical_width_detection_failed", level: .warn, message: error.message)
            physicalWidth = 32.0
            warnings.append("Display physical width unknown (using 32\" fallback); layout may be imprecise")
        }

        // Determine target frames (saved or computed)
        let targetLayout: WindowLayout
        switch store.load(projectId: projectId, mode: screenMode) {
        case .success(let savedFrames):
            if let frames = savedFrames {
                // Validate and clamp saved IDE frame to current screen
                let ideTarget = WindowLayoutEngine.clampToScreen(frame: frames.ide.cgRect, screenVisibleFrame: screenVisibleFrame)

                // Chrome: use saved frame if available, otherwise fall back to computed
                let chromeTarget: CGRect
                if let savedChrome = frames.chrome {
                    chromeTarget = WindowLayoutEngine.clampToScreen(frame: savedChrome.cgRect, screenVisibleFrame: screenVisibleFrame)
                    logEvent("position.using_saved_frames", context: ["project_id": projectId, "mode": screenMode.rawValue])
                } else {
                    let computed = WindowLayoutEngine.computeLayout(
                        screenVisibleFrame: screenVisibleFrame,
                        screenPhysicalWidthInches: physicalWidth,
                        screenMode: screenMode,
                        config: config.layout
                    )
                    chromeTarget = computed.chromeFrame
                    logEvent("position.using_saved_ide_computed_chrome", level: .warn,
                             message: "Saved layout has no Chrome frame — using computed Chrome (investigate if recurring)",
                             context: ["project_id": projectId, "mode": screenMode.rawValue])
                }

                targetLayout = WindowLayout(ideFrame: ideTarget, chromeFrame: chromeTarget)
            } else {
                targetLayout = WindowLayoutEngine.computeLayout(
                    screenVisibleFrame: screenVisibleFrame,
                    screenPhysicalWidthInches: physicalWidth,
                    screenMode: screenMode,
                    config: config.layout
                )
                logEvent("position.using_computed_frames", context: ["project_id": projectId, "mode": screenMode.rawValue])
            }
        case .failure(let error):
            logEvent("position.store_load_failed", level: .warn, message: error.message)
            targetLayout = WindowLayoutEngine.computeLayout(
                screenVisibleFrame: screenVisibleFrame,
                screenPhysicalWidthInches: physicalWidth,
                screenMode: screenMode,
                config: config.layout
            )
        }

        // Compute cascade offset in points: 0.5 inches * (screen points / screen inches)
        let cascadeOffsetPoints = CGFloat(0.5 * (Double(screenVisibleFrame.width) / physicalWidth))

        // Position IDE windows (retry briefly — IDE title may not be visible to AX immediately)
        let (ideSetResult, ideSetAttempts, ideUsedFallback) = await retryTransientWindowOp(
            maxRetries: 5,
            retryInterval: frameRetryInterval,
            operation: {
                positioner.setWindowFrames(
                    bundleId: PsVSCodeLauncher.bundleId,
                    projectId: projectId,
                    primaryFrame: targetLayout.ideFrame,
                    cascadeOffsetPoints: cascadeOffsetPoints
                )
            },
            fallback: {
                positioner.setFallbackWindowFrames(
                    bundleId: PsVSCodeLauncher.bundleId,
                    primaryFrame: targetLayout.ideFrame,
                    cascadeOffsetPoints: cascadeOffsetPoints
                )
            }
        )
        switch ideSetResult {
        case .success(let result):
            if ideUsedFallback {
                logEvent("position.ide_set_fallback_used", level: .warn, context: [
                    "project_id": projectId,
                    "attempts": "\(ideSetAttempts)"
                ])
            } else if ideSetAttempts > 1 {
                logEvent("position.ide_set_retried", context: [
                    "project_id": projectId,
                    "attempts": "\(ideSetAttempts)"
                ])
            }
            if result.positioned < 1 {
                logEvent("position.ide_set_none", level: .warn)
                warnings.append("IDE: no windows were positioned")
            } else if result.hasPartialFailure {
                logEvent("position.ide_partial", level: .warn, context: ["positioned": "\(result.positioned)", "matched": "\(result.matched)"])
                warnings.append("IDE: positioned \(result.positioned) of \(result.matched) windows")
            } else {
                logEvent("position.ide_positioned", context: ["count": "\(result.positioned)"])
            }
        case .failure(let error):
            let ideFailMsg = ideUsedFallback
                ? "Token retry exhausted and fallback failed: \(error.message)"
                : error.message
            logEvent("position.ide_set_failed", level: .warn, message: ideFailMsg,
                     context: ["project_id": projectId, "attempts": "\(ideSetAttempts)"])
            warnings.append("IDE positioning failed: \(error.message)")
        }

        // Position Chrome windows (retry briefly — Chrome title may not be visible to AX immediately)
        let (chromeSetResult, chromeSetAttempts, chromeUsedFallback) = await retryTransientWindowOp(
            maxRetries: 5,
            retryInterval: frameRetryInterval,
            operation: {
                positioner.setWindowFrames(
                    bundleId: PsChromeLauncher.bundleId,
                    projectId: projectId,
                    primaryFrame: targetLayout.chromeFrame,
                    cascadeOffsetPoints: cascadeOffsetPoints
                )
            },
            fallback: {
                positioner.setFallbackWindowFrames(
                    bundleId: PsChromeLauncher.bundleId,
                    primaryFrame: targetLayout.chromeFrame,
                    cascadeOffsetPoints: cascadeOffsetPoints
                )
            }
        )
        switch chromeSetResult {
        case .success(let result):
            if chromeUsedFallback {
                logEvent("position.chrome_set_fallback_used", level: .warn, context: [
                    "project_id": projectId,
                    "attempts": "\(chromeSetAttempts)"
                ])
            } else if chromeSetAttempts > 1 {
                logEvent("position.chrome_set_retried", context: [
                    "project_id": projectId,
                    "attempts": "\(chromeSetAttempts)"
                ])
            }
            if result.positioned < 1 {
                logEvent("position.chrome_set_none", level: .warn)
                warnings.append("Chrome: no windows were positioned")
            } else if result.hasPartialFailure {
                var chromePartialContext: [String: String] = [
                    "positioned": "\(result.positioned)",
                    "matched": "\(result.matched)"
                ]
                if !result.failures.isEmpty {
                    chromePartialContext["failures"] = result.failures.joined(separator: "; ")
                }
                logEvent("position.chrome_partial", level: .warn, context: chromePartialContext)
                warnings.append("Chrome: positioned \(result.positioned) of \(result.matched) windows")
            } else {
                logEvent("position.chrome_positioned", context: ["count": "\(result.positioned)"])
            }
        case .failure(let error):
            let chromeFailMsg = chromeUsedFallback
                ? "Token retry exhausted and fallback failed: \(error.message)"
                : error.message
            logEvent("position.chrome_set_failed", level: .warn, message: chromeFailMsg,
                     context: ["project_id": projectId, "attempts": "\(chromeSetAttempts)"])
            warnings.append("Chrome positioning failed: \(error.message)")
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: "; ")
    }
}
