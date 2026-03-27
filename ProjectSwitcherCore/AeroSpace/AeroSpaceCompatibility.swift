import Foundation

// MARK: - Compatibility Fallback Detection

extension PsAeroSpace {

    /// Returns true when a primary command result should trigger a compatibility fallback.
    ///
    /// Fallback is attempted only for non-zero command exits whose output suggests a
    /// CLI version or flag incompatibility (e.g. "unknown option", "unrecognized command").
    /// Hard command-run failures (for example executable resolution failures) do not fall back,
    /// and neither do non-zero exits caused by operational errors (workspace not found, etc.).
    ///
    /// - Parameter result: The result from a primary command attempt.
    /// - Returns: True if the error output contains compatibility-related indicators.
    static func shouldAttemptCompatibilityFallback(_ result: Result<PsCommandResult, PsCoreError>) -> Bool {
        switch result {
        case .success(let output):
            guard output.exitCode != 0 else {
                return false
            }
            let diagnosticText = (output.stderr + "\n" + output.stdout).lowercased()
            let compatibilityIndicators = [
                "unknown option",
                "unknown flag",
                "unknown command",
                "unknown subcommand",
                "unrecognized option",
                "unrecognised option",
                "unrecognized command",
                "invalid option",
                "no such option",
                "no such command",
                "mandatory option is not specified"
            ]
            return compatibilityIndicators.contains { diagnosticText.contains($0) }
        case .failure:
            return false
        }
    }
}
