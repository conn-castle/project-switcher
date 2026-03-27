//
//  Errors.swift
//  ProjectSwitcherCore
//
//  Typed error system for ProjectSwitcherCore operations.
//  Provides categorized errors with optional command details,
//  and helper functions for common error patterns.
//

import Foundation

/// Categories of errors from ProjectSwitcherCore operations.
public enum PsCoreErrorCategory: String, Sendable {
    /// External command execution failures.
    case command
    /// Input validation failures.
    case validation
    /// File system operation failures.
    case fileSystem
    /// Configuration loading/parsing failures.
    case configuration
    /// Output parsing failures.
    case parse
    /// Window management failures (AX positioning, window resolution).
    case window
    /// System-level failures (display detection, permissions).
    case system
}

/// Structured reason codes for `PsCoreError`.
public enum PsCoreErrorReason: String, Sendable {
    /// Error was returned because the AeroSpace circuit breaker is currently open.
    case circuitBreakerOpen
    /// Error was returned because a command exceeded its timeout.
    case commandTimeout
    /// Error was returned because a window title token could not be matched yet.
    case windowTokenNotFound
    /// Error was returned because window enumeration confirmed the app has zero windows.
    case windowInventoryEmpty
}

/// Errors emitted by ProjectSwitcherCore operations.
public struct PsCoreError: Error, Equatable, Sendable {
    /// Error category for programmatic handling.
    let category: PsCoreErrorCategory
    /// Human-readable error message.
    public let message: String
    /// Additional detail (e.g., stderr output).
    let detail: String?
    /// Command that was executed, if applicable.
    let command: String?
    /// Exit code from command execution, if applicable.
    let exitCode: Int32?
    /// Structured reason for programmatic branching, when available.
    public let reason: PsCoreErrorReason?

    /// Creates a new PsCoreError with full details.
    /// - Parameters:
    ///   - category: Error category.
    ///   - message: Human-readable error message.
    ///   - detail: Additional detail such as stderr output.
    ///   - command: Command that was executed.
    ///   - exitCode: Exit code from the command.
    public init(
        category: PsCoreErrorCategory,
        message: String,
        detail: String? = nil,
        command: String? = nil,
        exitCode: Int32? = nil,
        reason: PsCoreErrorReason? = nil
    ) {
        self.category = category
        self.message = message
        self.detail = detail
        self.command = command
        self.exitCode = exitCode
        self.reason = reason
    }

    /// Whether this error represents a circuit-breaker-open condition.
    ///
    /// When true, callers should log at `.info` rather than `.warn` since the
    /// transport layer already logged the canonical `circuit_breaker.tripped` warning
    /// when the breaker first opened. Subsequent per-call warnings are noise.
    public var isBreakerOpen: Bool {
        if reason == .circuitBreakerOpen {
            return true
        }
        return message.range(of: "circuit breaker open", options: .caseInsensitive) != nil
    }

    /// Whether this error represents a command timeout.
    ///
    /// Prefers the structured reason when available. Message-prefix matching is
    /// retained for compatibility with legacy call sites and test fixtures that
    /// still produce unstructured timeout errors.
    public var isCommandTimeout: Bool {
        if reason == .commandTimeout {
            return true
        }
        return message.hasPrefix("Command timed out")
    }

    /// Whether this error represents a transient token-miss during window lookup.
    ///
    /// Prefers the structured reason when available. Message-prefix matching is
    /// retained for compatibility with legacy fixtures and stub errors that still
    /// model this condition as text only.
    public var isWindowTokenNotFound: Bool {
        if reason == .windowTokenNotFound {
            return true
        }
        return message.hasPrefix("No window found with token")
    }

    /// Whether this error originates from a stale AeroSpace tree-node state.
    ///
    /// AeroSpace may leave floating window tree nodes in an unbound state after a
    /// monitor-configuration change (e.g., undocking). A subsequent `focus` command
    /// then crashes internally with "already unbound". This property detects that
    /// condition from the error detail (stderr output) so callers can retry or
    /// fall through to AX-only recovery.
    public var isAeroSpaceTreeNodeError: Bool {
        guard let detail else { return false }
        return detail.contains("already unbound")
    }

    /// Whether this error represents a confirmed zero-window inventory result.
    ///
    /// Prefers the structured reason when available. Message parsing is retained
    /// for compatibility with existing fixtures until all producers are updated.
    public var isWindowInventoryEmpty: Bool {
        if reason == .windowInventoryEmpty {
            return true
        }
        return Self.messageIndicatesEmptyWindowInventory(message)
    }

    /// Creates a new PsCoreError with just a message.
    /// Defaults to `.command` category for backward compatibility.
    /// - Parameter message: Error message.
    init(message: String) {
        self.category = .command
        self.message = message
        self.detail = nil
        self.command = nil
        self.exitCode = nil
        self.reason = nil
    }

    private static func messageIndicatesEmptyWindowInventory(_ message: String) -> Bool {
        let normalized = message.lowercased()
        if normalized.contains("no windows") || normalized.contains("zero windows") {
            return true
        }
        return normalized.range(
            of: #"\b(?:enumerated|found|matched|listed)?\s*0\s+windows?\b"#,
            options: .regularExpression
        ) != nil
    }
}

/// Context for an operational error that may trigger an auto-Doctor run.
///
/// Used to pass error information from call sites to the Doctor trigger logic.
/// The `isCritical` property determines whether the error should skip debounce
/// and auto-show the Doctor window.
public struct ErrorContext: Equatable, Sendable {
    /// Error category from the original error.
    public let category: PsCoreErrorCategory
    /// Human-readable error message.
    public let message: String
    /// What operation triggered the error (e.g., "activation", "configLoad").
    public let trigger: String

    public init(category: PsCoreErrorCategory, message: String, trigger: String) {
        self.category = category
        self.message = message
        self.trigger = trigger
    }

    /// Whether this error is critical enough to skip debounce and auto-show Doctor.
    ///
    /// Critical errors are activation failures and config load failures — operations
    /// where the user's intent was blocked and diagnostic help is immediately valuable.
    public var isCritical: Bool {
        (category == .command && trigger == "activation")
            || (category == .configuration && trigger == "configLoad")
    }
}

/// Builds an PsCoreError from a failed command result.
///
/// Extracts stderr output (trimmed) as the detail field and formats a consistent error message.
///
/// - Parameters:
///   - commandDescription: Human-readable description of the command (e.g., "aerospace list-workspaces --all").
///   - result: The command result containing exit code and stderr.
/// - Returns: A properly formatted PsCoreError.
func commandError(_ commandDescription: String, result: PsCommandResult) -> PsCoreError {
    let trimmed = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    let detail = trimmed.isEmpty ? nil : trimmed
    return PsCoreError(
        category: .command,
        message: "\(commandDescription) failed with exit code \(result.exitCode).",
        detail: detail,
        command: commandDescription,
        exitCode: result.exitCode
    )
}

/// Builds an PsCoreError for validation failures.
///
/// - Parameters:
///   - message: Description of what validation failed.
/// - Returns: A validation category PsCoreError.
func validationError(_ message: String) -> PsCoreError {
    PsCoreError(
        category: .validation,
        message: message
    )
}

/// Builds an PsCoreError for file system failures.
///
/// - Parameters:
///   - message: Description of what file operation failed.
///   - detail: Additional detail about the failure.
/// - Returns: A fileSystem category PsCoreError.
func fileSystemError(_ message: String, detail: String? = nil) -> PsCoreError {
    PsCoreError(
        category: .fileSystem,
        message: message,
        detail: detail
    )
}

/// Builds an PsCoreError for parse failures.
///
/// - Parameters:
///   - message: Description of what parsing failed.
///   - detail: The content that failed to parse.
/// - Returns: A parse category PsCoreError.
func parseError(_ message: String, detail: String? = nil) -> PsCoreError {
    PsCoreError(
        category: .parse,
        message: message,
        detail: detail
    )
}
