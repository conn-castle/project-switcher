import Foundation

/// SSH utilities shared across config validation, Doctor checks, and remote settings writes.
///
/// This keeps Remote-SSH authority parsing and shell escaping consistent across the codebase.
enum PsSSHHelpers {
    /// Prefix used by VS Code Remote-SSH authorities.
    static let remoteAuthorityPrefix = "ssh-remote+"

    /// Validation errors for VS Code Remote-SSH authority strings.
    enum RemoteAuthorityError: Error, Equatable, Sendable {
        case missingPrefix
        case containsWhitespace
        case missingTarget
        case targetStartsWithDash
    }

    /// Parses a VS Code Remote-SSH authority and returns the SSH target (`user@host`).
    ///
    /// - Parameter remoteAuthority: Remote authority string (e.g., `ssh-remote+user@host`).
    /// - Returns: `user@host` on success, or a typed validation error.
    static func parseRemoteAuthority(_ remoteAuthority: String) -> Result<String, RemoteAuthorityError> {
        guard remoteAuthority.hasPrefix(remoteAuthorityPrefix) else { return .failure(.missingPrefix) }

        // Remote authorities must not contain whitespace (including leading/trailing).
        guard !remoteAuthority.contains(where: { $0.isWhitespace }) else { return .failure(.containsWhitespace) }

        let target = String(remoteAuthority.dropFirst(remoteAuthorityPrefix.count))
        guard !target.isEmpty else { return .failure(.missingTarget) }
        guard !target.hasPrefix("-") else { return .failure(.targetStartsWithDash) }
        return .success(target)
    }

    /// Extracts the `user@host` SSH target from a VS Code Remote-SSH authority.
    ///
    /// - Parameter remoteAuthority: Remote authority string (e.g., `ssh-remote+user@host`).
    /// - Returns: The SSH target (e.g., `user@host`), or nil if the authority is malformed.
    static func extractTarget(from remoteAuthority: String) -> String? {
        switch parseRemoteAuthority(remoteAuthority) {
        case .success(let target):
            return target
        case .failure:
            return nil
        }
    }

    /// Single-quote shell escaping for use in SSH remote commands.
    ///
    /// Wraps the value in single quotes. Any embedded single quotes are escaped
    /// using the `'\''` pattern (end quote, escaped quote, start quote).
    ///
    /// - Parameter value: The string to escape.
    /// - Returns: Shell-safe quoted string.
    static func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
