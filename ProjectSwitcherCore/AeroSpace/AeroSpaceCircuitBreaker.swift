//
//  AeroSpaceCircuitBreaker.swift
//  ProjectSwitcherCore
//
//  Thread-safe circuit breaker for AeroSpace CLI commands.
//
//  When AeroSpace becomes unresponsive (crashes, socket dies), every subsequent
//  CLI command times out at 5s each. With 15-20 calls in a Doctor check, this
//  creates a ~90s freeze cascade. The circuit breaker detects the first timeout
//  and immediately fails subsequent calls for a cooldown period.
//

import Foundation

/// Thread-safe circuit breaker that prevents cascading timeouts when AeroSpace
/// becomes unresponsive.
///
/// States:
/// - **Closed**: Normal operation. All commands pass through.
/// - **Open**: Tripped by a timeout. All commands fail immediately until cooldown expires.
///
/// After cooldown, the breaker transitions back to closed and allows the next call
/// through as a probe. If it succeeds, normal operation resumes. If it times out
/// again, the breaker re-trips.
final class AeroSpaceCircuitBreaker {

    /// Process-wide shared instance for production use.
    static let shared = AeroSpaceCircuitBreaker()

    enum State: Equatable {
        /// Normal operation — commands pass through.
        case closed
        /// Tripped — fail fast until the specified date.
        case open(until: Date)
    }

    /// Maximum number of automatic recovery attempts before giving up.
    static let maxRecoveryAttempts = 2
    /// Safety timeout (seconds) to auto-clear a stuck recovery flag.
    private static let recoveryStuckTimeoutSeconds: TimeInterval = 60

    /// Cooldown period after a timeout trips the breaker (seconds).
    let cooldownSeconds: TimeInterval

    private var state: State = .closed
    private var recoveryAttemptCount = 0
    private var _isRecoveryInProgress = false
    private var recoveryStartedAt: Date?
    private let lock = NSLock()

    /// Creates a circuit breaker.
    /// - Parameter cooldownSeconds: How long to fail fast after a timeout. Default 30s.
    init(cooldownSeconds: TimeInterval = 30) {
        self.cooldownSeconds = cooldownSeconds
    }

    /// Returns the current breaker state (thread-safe). For testing/diagnostics.
    var currentState: State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    /// Read-only check: true when the breaker is in the open state and the
    /// cooldown has **not** yet expired. Unlike ``shouldAllow()``, this does
    /// not transition the breaker back to closed when cooldown expires.
    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .open(let until) = state, Date() < until {
            return true
        }
        return false
    }

    /// Returns true if calls should be allowed through.
    ///
    /// When the breaker is open and the cooldown has expired, it transitions
    /// back to closed (allowing the next call as a probe).
    func shouldAllow() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .closed:
            return true
        case .open(let until):
            if Date() >= until {
                state = .closed
                return true
            }
            return false
        }
    }

    /// Records a timeout failure, tripping the breaker to open state.
    ///
    /// When transitioning from closed to open (new trip), resets the recovery
    /// attempt count so auto-recovery gets a fresh budget per trip.
    func recordTimeout() {
        lock.lock()
        defer { lock.unlock() }
        if case .closed = state {
            recoveryAttemptCount = 0
        }
        state = .open(until: Date().addingTimeInterval(cooldownSeconds))
    }

    /// Records a successful call, closing the breaker and resetting recovery counts.
    func recordSuccess() {
        lock.lock()
        defer { lock.unlock() }
        state = .closed
        recoveryAttemptCount = 0
    }

    /// Resets the breaker to closed state and clears recovery tracking.
    ///
    /// Called after a fresh AeroSpace start to clear any tripped state,
    /// and by tests to ensure clean state.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = .closed
        recoveryAttemptCount = 0
        _isRecoveryInProgress = false
        recoveryStartedAt = nil
    }

    // MARK: - Recovery

    /// Whether a recovery attempt is currently in progress (thread-safe).
    var isRecoveryInProgress: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRecoveryInProgress
    }

    /// Returns true if auto-recovery should be attempted.
    ///
    /// Recovery is allowed when the breaker is open (cooldown not yet expired),
    /// recovery attempts are below the maximum, and no recovery is already in progress.
    func shouldAttemptRecovery() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .closed:
            return false
        case .open(let until):
            if Date() >= until {
                return false // Cooldown expired — let normal probe path handle it
            }
            return recoveryAttemptCount < Self.maxRecoveryAttempts && !_isRecoveryInProgress
        }
    }

    /// Atomically begins a recovery attempt if one is allowed.
    ///
    /// - Returns: `true` if recovery was started (caller should proceed with restart),
    ///   `false` if recovery is not allowed (max attempts reached or already in progress).
    func beginRecovery() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        switch state {
        case .closed:
            return false
        case .open(let until):
            if Date() >= until {
                return false
            }
            guard recoveryAttemptCount < Self.maxRecoveryAttempts else {
                return false
            }
            if _isRecoveryInProgress {
                // Safety timeout: auto-clear if recovery has been stuck longer than expected.
                // Count the stuck attempt against the budget so persistent hangs hit maxRecoveryAttempts.
                if let startedAt = recoveryStartedAt, Date().timeIntervalSince(startedAt) > Self.recoveryStuckTimeoutSeconds {
                    _isRecoveryInProgress = false
                    recoveryStartedAt = nil
                    recoveryAttemptCount += 1
                    // Re-check budget after counting the stuck attempt; the guard at the
                    // top of the .open case was evaluated before the increment.
                    guard recoveryAttemptCount < Self.maxRecoveryAttempts else {
                        return false
                    }
                } else {
                    return false
                }
            }
            _isRecoveryInProgress = true
            recoveryStartedAt = Date()
            return true
        }
    }

    /// Ends a recovery attempt.
    ///
    /// - Parameter success: Whether the recovery (AeroSpace restart) succeeded.
    ///   On success, the breaker resets to closed and counts clear.
    ///   On failure, the attempt count increments and the breaker is re-opened
    ///   to maintain fail-fast behavior (start() may have reset it to closed
    ///   before the readiness poll failed).
    func endRecovery(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isRecoveryInProgress = false
        recoveryStartedAt = nil
        if success {
            state = .closed
            recoveryAttemptCount = 0
        } else {
            recoveryAttemptCount += 1
            state = .open(until: Date().addingTimeInterval(cooldownSeconds))
        }
    }
}
