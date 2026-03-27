import Foundation

extension ProjectManager {
    private func isFocusRestoreCandidateStale(capturedAt: Date) -> Bool {
        Date().timeIntervalSince(capturedAt) > Self.focusRestoreRetryMaxAge
    }

    private func preserveFocusHistoryForRetry(_ focus: CapturedFocus, capturedAt: Date, method: String) {
        if isFocusRestoreCandidateStale(capturedAt: capturedAt) {
            invalidateFocusHistory(windowId: focus.windowId, reason: "retry_stale")
            return
        }
        let retryAttempt = withState {
            let nextAttempt = (focusRestoreRetryAttemptsByWindowId[focus.windowId] ?? 0) + 1
            focusRestoreRetryAttemptsByWindowId[focus.windowId] = nextAttempt
            return nextAttempt
        }
        guard retryAttempt <= Self.focusRestoreMaxRetryAttempts else {
            invalidateFocusHistory(windowId: focus.windowId, reason: "retry_limit")
            return
        }

        let entry = FocusHistoryEntry(focus: focus, capturedAt: capturedAt)
        let snapshot = withState {
            focusStack.push(entry)
            mostRecentNonProjectFocus = entry
            return FocusHistorySnapshot(
                stackCount: focusStack.count,
                recentWindowId: mostRecentNonProjectFocus?.windowId
            )
        }
        persistFocusHistory()
        let context = focusHistoryContext(
            windowId: focus.windowId,
            workspace: focus.workspace,
            appBundleId: focus.appBundleId,
            method: method,
            reason: "focus_unstable",
            snapshot: snapshot
        )
        var enrichedContext = context
        enrichedContext["retry_attempt"] = "\(retryAttempt)"
        enrichedContext["retry_limit"] = "\(Self.focusRestoreMaxRetryAttempts)"
        logEvent("focus.history.restore_preserved", level: .warn, context: enrichedContext.isEmpty ? nil : enrichedContext)
    }

    private struct FocusRestoreCandidate {
        let focus: CapturedFocus
        let capturedAt: Date
    }

    private func resolveNonProjectFocusCandidate(
        _ candidate: FocusHistoryEntry,
        windowLookup: [Int: PsWindow]?
    ) -> FocusRestoreCandidate? {
        if let windowLookup {
            guard let window = windowLookup[candidate.windowId] else {
                invalidateFocusHistory(windowId: candidate.windowId, reason: "window_missing")
                return nil
            }
            guard !window.workspace.hasPrefix(Self.workspacePrefix) else {
                invalidateFocusHistory(windowId: candidate.windowId, reason: "project_workspace")
                return nil
            }
            guard window.appBundleId == candidate.appBundleId else {
                invalidateFocusHistory(windowId: candidate.windowId, reason: "app_mismatch")
                return nil
            }
            return FocusRestoreCandidate(
                focus: CapturedFocus(
                    windowId: window.windowId,
                    appBundleId: window.appBundleId,
                    workspace: window.workspace
                ),
                capturedAt: candidate.capturedAt
            )
        }

        guard !candidate.workspace.hasPrefix(Self.workspacePrefix) else {
            invalidateFocusHistory(windowId: candidate.windowId, reason: "project_workspace")
            return nil
        }
        return FocusRestoreCandidate(focus: candidate.focus, capturedAt: candidate.capturedAt)
    }

    private func attemptRestoreFocusCandidate(
        _ candidate: FocusRestoreCandidate,
        method: String,
        snapshot: FocusHistorySnapshot,
        attemptedWindowIds: inout Set<Int>
    ) -> CapturedFocus? {
        let resolved = candidate.focus
        if attemptedWindowIds.contains(resolved.windowId) {
            return nil
        }
        attemptedWindowIds.insert(resolved.windowId)

        let attemptContext = focusHistoryContext(
            windowId: resolved.windowId,
            workspace: resolved.workspace,
            appBundleId: resolved.appBundleId,
            method: method,
            snapshot: snapshot
        )
        logEvent("focus.history.restore_attempt", context: attemptContext.isEmpty ? nil : attemptContext)

        if focusWindowStableSync(
            windowId: resolved.windowId,
            timeout: windowPollTimeout,
            pollInterval: windowPollInterval
        ) {
            recoverFocusedWindowIfNeeded(bundleId: resolved.appBundleId)
            updateMostRecentNonProjectFocus(resolved)
            let successSnapshot = focusHistorySnapshot()
            let successContext = focusHistoryContext(
                windowId: resolved.windowId,
                workspace: resolved.workspace,
                appBundleId: resolved.appBundleId,
                method: method,
                snapshot: successSnapshot
            )
            logEvent("focus.history.restore_success", context: successContext.isEmpty ? nil : successContext)
            return resolved
        }

        // Before preserving for retry, check if the window still exists.
        // If the window is gone, invalidate immediately instead of wasting future retry attempts.
        let windowStillExists: Bool
        if let freshLookup = listAllWindowsById() {
            windowStillExists = freshLookup[resolved.windowId] != nil
        } else {
            logEvent("focus.history.window_lookup_unavailable", level: .warn,
                     message: "AeroSpace unreachable during focus restore; assuming window exists",
                     context: ["window_id": "\(resolved.windowId)", "method": method])
            windowStillExists = true
        }

        let failureSnapshot = focusHistorySnapshot()
        let failureContext = focusHistoryContext(
            windowId: resolved.windowId,
            workspace: resolved.workspace,
            appBundleId: resolved.appBundleId,
            method: method,
            reason: windowStillExists ? "focus_failed" : "window_gone_after_focus",
            snapshot: failureSnapshot
        )
        logEvent("focus.history.restore_failed", level: .warn, message: "Focus did not stabilize", context: failureContext)
        if windowStillExists {
            preserveFocusHistoryForRetry(resolved, capturedAt: candidate.capturedAt, method: method)
        } else {
            invalidateFocusHistory(windowId: resolved.windowId, reason: "window_gone_after_focus")
        }
        return nil
    }

    func restoreNonProjectFocus(windowLookup: [Int: PsWindow]?) -> CapturedFocus? {
        var attemptedWindowIds: Set<Int> = []
        if let focus = restoreNonProjectFocusFromStack(
            windowLookup: windowLookup,
            attemptedWindowIds: &attemptedWindowIds
        ) {
            return focus
        }
        if let focus = restoreMostRecentNonProjectFocus(
            windowLookup: windowLookup,
            attemptedWindowIds: &attemptedWindowIds
        ) {
            return focus
        }
        let snapshot = focusHistorySnapshot()
        let context = focusHistoryContext(reason: "exhausted", snapshot: snapshot)
        logEvent("focus.history.exhausted", level: .warn, context: context.isEmpty ? nil : context)
        return nil
    }

    /// Maximum number of resolved stack candidates to focus-attempt before giving up.
    /// Only candidates that pass `resolveNonProjectFocusCandidate` (non-nil) count
    /// toward this limit; stale/unresolvable entries are popped and skipped cheaply.
    private static let restoreMaxCandidates = 5
    /// Total wall-clock budget for the restore-from-stack loop (seconds).
    private static let restoreBudgetSeconds: TimeInterval = 30

    private func restoreNonProjectFocusFromStack(
        windowLookup: [Int: PsWindow]?,
        attemptedWindowIds: inout Set<Int>
    ) -> CapturedFocus? {
        let method = windowLookup == nil ? "stack-no-lookup" : "stack"
        let restoreDeadline = Date().addingTimeInterval(Self.restoreBudgetSeconds)
        var candidatesAttempted = 0
        while Date() < restoreDeadline,
              candidatesAttempted < Self.restoreMaxCandidates,
              let (candidate, snapshot) = popNextFocusStackEntry() {
            guard let resolved = resolveNonProjectFocusCandidate(candidate, windowLookup: windowLookup) else {
                continue
            }
            candidatesAttempted += 1
            if let result = attemptRestoreFocusCandidate(
                resolved,
                method: method,
                snapshot: snapshot,
                attemptedWindowIds: &attemptedWindowIds
            ) {
                return result
            }
        }
        return nil
    }

    private func restoreMostRecentNonProjectFocus(
        windowLookup: [Int: PsWindow]?,
        attemptedWindowIds: inout Set<Int>
    ) -> CapturedFocus? {
        guard let candidateEntry = withState({ mostRecentNonProjectFocus }),
              let resolved = resolveNonProjectFocusCandidate(candidateEntry, windowLookup: windowLookup) else {
            return nil
        }
        let attemptSnapshot = focusHistorySnapshot()
        return attemptRestoreFocusCandidate(
            resolved,
            method: windowLookup == nil ? "recent-no-lookup" : "recent",
            snapshot: attemptSnapshot,
            attemptedWindowIds: &attemptedWindowIds
        )
    }

}
