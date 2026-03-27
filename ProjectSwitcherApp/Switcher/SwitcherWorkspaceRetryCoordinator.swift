//
//  SwitcherWorkspaceRetryCoordinator.swift
//  ProjectSwitcher
//
//  Manages the workspace-state retry loop for the switcher.
//  Schedules periodic retries when AeroSpace workspace queries fail
//  (e.g., circuit breaker open during recovery) and reports results
//  back to the controller via closures.
//

import Foundation

import ProjectSwitcherCore

/// Coordinates workspace-state retry logic for the switcher panel.
///
/// Extracted from `SwitcherPanelController` to reduce controller size.
/// The coordinator owns retry state (timer, count, session guard) and
/// reports results through callbacks. The controller remains responsible
/// for UI updates and filter application.
final class SwitcherWorkspaceRetryCoordinator {

    // MARK: - Configuration

    static let defaultMaxAttempts = 5
    static let defaultRetryIntervalSeconds: TimeInterval = 2.0

    let maxAttempts: Int
    let retryIntervalSeconds: TimeInterval

    // MARK: - Dependencies

    private let projectManager: ProjectManager
    private let session: SwitcherSession

    // MARK: - Callbacks

    /// Called on the main thread when a retry succeeds.
    /// Parameter: the workspace state snapshot.
    var onRetrySucceeded: ((ProjectWorkspaceState) -> Void)?

    /// Called on the main thread when all retries are exhausted.
    /// Parameter: the last error encountered.
    var onRetryExhausted: ((ProjectError) -> Void)?

    // MARK: - State

    private let stateLock = NSLock()
    private var retryTimer: DispatchSourceTimer?
    private var retryCount: Int = 0
    private var retryGeneration: UInt64 = 0

    // MARK: - Init

    /// Creates a workspace retry coordinator.
    ///
    /// - Parameters:
    ///   - projectManager: Manager used to query workspace state.
    ///   - session: Switcher session for structured logging.
    ///   - maxAttempts: Maximum retry attempts before exhaustion. Defaults to `defaultMaxAttempts`.
    ///   - retryIntervalSeconds: Seconds between retries. Defaults to `defaultRetryIntervalSeconds`.
    init(
        projectManager: ProjectManager,
        session: SwitcherSession,
        maxAttempts: Int = defaultMaxAttempts,
        retryIntervalSeconds: TimeInterval = defaultRetryIntervalSeconds
    ) {
        self.projectManager = projectManager
        self.session = session
        self.maxAttempts = maxAttempts
        self.retryIntervalSeconds = retryIntervalSeconds
    }

    deinit {
        cancelRetryForTeardown()
    }

    // MARK: - Public API

    /// Schedules a repeating timer to retry workspace state queries.
    ///
    /// Used when the circuit breaker is open and background AeroSpace recovery
    /// is in progress. Each tick retries `workspaceState()`; on success the
    /// `onRetrySucceeded` callback is invoked and the timer is canceled.
    /// After `maxAttempts` the `onRetryExhausted` callback is invoked.
    func scheduleRetry() {
        precondition(Thread.isMainThread, "scheduleRetry() must be called on the main thread.")
        cancelRetry()
        retryCount = 0
        let generation = withStateLock { () -> UInt64 in
            retryGeneration &+= 1
            return retryGeneration
        }

        let timerSessionId = session.sessionId

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInteractive))
        timer.schedule(
            deadline: .now() + retryIntervalSeconds,
            repeating: retryIntervalSeconds
        )
        timer.setEventHandler { [weak self] in
            self?.handleRetryTick(expectedSessionId: timerSessionId, expectedGeneration: generation)
        }
        withStateLock {
            retryTimer = timer
        }
        timer.resume()

        session.logEvent(
            event: "switcher.workspace_retry.scheduled",
            context: ["max_attempts": "\(maxAttempts)"]
        )
    }

    /// Cancels the retry timer and invalidates in-flight tick callbacks.
    func cancelRetry() {
        precondition(Thread.isMainThread, "cancelRetry() must be called on the main thread.")
        cancelRetryStateFromAnyThread()
    }

    /// Cancels retries in teardown/off-main contexts without crashing on preconditions.
    /// The teardown path avoids synchronous main-thread hops to prevent deadlocks.
    func cancelRetryForTeardown() {
        cancelRetryStateFromAnyThread()
    }

    /// Invalidates generation and cancels any existing timer from any thread.
    private func cancelRetryStateFromAnyThread() {
        let timerToCancel = withStateLock { () -> DispatchSourceTimer? in
            retryGeneration &+= 1
            let timer = retryTimer
            retryTimer = nil
            return timer
        }
        timerToCancel?.cancel()
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    // MARK: - Private

    /// Handles a single tick of the retry timer.
    ///
    /// The workspace query runs on the timer's background queue; generation/timer
    /// identity is synchronized with `stateLock`, while retry count and callbacks
    /// are processed on the main thread.
    private func handleRetryTick(expectedSessionId: String?, expectedGeneration: UInt64) {
        let result = projectManager.workspaceState()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let currentGeneration = self.withStateLock { self.retryGeneration }
            guard expectedSessionId == self.session.sessionId,
                  expectedGeneration == currentGeneration else { return }
            self.retryCount += 1

            switch result {
            case .success(let state):
                self.cancelRetry()
                self.session.logEvent(
                    event: "switcher.workspace_retry.succeeded",
                    context: ["attempt": "\(self.retryCount)"]
                )
                self.onRetrySucceeded?(state)

            case .failure(let error):
                if self.retryCount >= maxAttempts {
                    self.cancelRetry()
                    self.session.logEvent(
                        event: "switcher.workspace_retry.exhausted",
                        level: .warn,
                        message: "\(error)",
                        context: ["attempts": "\(self.retryCount)"]
                    )
                    self.onRetryExhausted?(error)
                } else {
                    self.session.logEvent(
                        event: "switcher.workspace_retry.pending",
                        context: [
                            "attempt": "\(self.retryCount)",
                            "remaining": "\(maxAttempts - self.retryCount)"
                        ]
                    )
                }
            }
        }
    }
}
