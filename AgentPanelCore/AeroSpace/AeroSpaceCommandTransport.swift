import Foundation
import os

/// Handles low-level execution of AeroSpace CLI commands with circuit-breaker integration.
///
/// This layer is responsible for running the `aerospace` executable, recording success/timeout
/// outcomes on the circuit breaker, and constructing breaker-related errors. Higher-level
/// orchestration (recovery, retry) lives in `ApAeroSpace`.
struct AeroSpaceCommandTransport {
    private static let logger = Logger(subsystem: "com.agentpanel", category: "AeroSpaceCommandTransport")
    /// Structured logger for JSON log file events (complements os.Logger for triage).
    private static let structuredLogger = AgentPanelLogger()

    let commandRunner: CommandRunning
    let circuitBreaker: AeroSpaceCircuitBreaker

    /// Returns true when the circuit breaker allows a command to proceed.
    func shouldAllow() -> Bool {
        circuitBreaker.shouldAllow()
    }

    /// Executes an aerospace command and records the outcome on the circuit breaker.
    ///
    /// On success, records a success. On timeout, records a timeout (which may trip the breaker).
    /// Non-timeout failures pass through without affecting breaker state.
    ///
    /// - Parameters:
    ///   - arguments: Arguments to pass to the `aerospace` executable.
    ///   - timeoutSeconds: Timeout in seconds.
    /// - Returns: Command result on success, or an error.
    func executeAndRecord(
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> Result<ApCommandResult, ApCoreError> {
        let result = commandRunner.run(
            executable: "aerospace",
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )

        switch result {
        case .success:
            circuitBreaker.recordSuccess()
        case .failure(let error):
            if error.isCommandTimeout {
                let wasOpen = circuitBreaker.isOpen
                circuitBreaker.recordTimeout()
                if !wasOpen {
                    Self.logger.warning("circuit_breaker.tripped command=aerospace \(arguments.joined(separator: " "), privacy: .public) timeout=\(timeoutSeconds)s")
                    _ = Self.structuredLogger.log(
                        event: "circuit_breaker.tripped",
                        level: .warn,
                        message: "AeroSpace command timed out, circuit breaker tripped",
                        context: [
                            "command": "aerospace \(arguments.joined(separator: " "))",
                            "timeout_seconds": "\(timeoutSeconds)",
                            "cooldown_seconds": "\(circuitBreaker.cooldownSeconds)"
                        ]
                    )
                }
            }
        }

        return result
    }

    /// Returns the standard error for when the circuit breaker is open.
    ///
    /// - Parameter detailOverride: Optional detail override for specific failure contexts.
    /// - Returns: An error indicating AeroSpace is unresponsive.
    func breakerOpenError(detailOverride: String? = nil) -> ApCoreError {
        let detail = detailOverride
            ?? "A previous aerospace command timed out. Failing fast to prevent cascade. Retry in \(Int(circuitBreaker.cooldownSeconds))s."
        return ApCoreError(
            category: .command,
            message: "AeroSpace is unresponsive (circuit breaker open).",
            detail: detail,
            reason: .circuitBreakerOpen
        )
    }
}
