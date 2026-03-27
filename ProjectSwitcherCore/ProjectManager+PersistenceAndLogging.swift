import Foundation

extension ProjectManager {
    // MARK: - Focus History Persistence

    func loadFocusHistory() {
        // Read from persistence directly (without withPersistence) to avoid
        // lock-ordering inversion: persistFocusHistory() acquires stateQueue
        // then persistenceQueue, so acquiring them in reverse order here would
        // risk AB-BA deadlock. This is safe because loadFocusHistory() is only
        // called during init(), so there is no concurrent persistence access.
        let loadResult = focusHistoryStore.load(now: Date())
        switch loadResult {
        case .success(nil):
            withState {
                focusStack = FocusStack(maxSize: Self.focusHistoryMaxEntries)
                mostRecentNonProjectFocus = nil
                focusRestoreRetryAttemptsByWindowId = [:]
            }
        case .success(let outcome?):
            withState {
                focusStack = FocusStack(entries: outcome.state.stack, maxSize: Self.focusHistoryMaxEntries)
                mostRecentNonProjectFocus = outcome.state.mostRecent
                focusRestoreRetryAttemptsByWindowId = [:]
            }
            if outcome.prunedCount > 0 || outcome.droppedMostRecent {
                var context: [String: String] = [
                    "stack_pruned": "\(outcome.prunedCount)"
                ]
                if outcome.droppedMostRecent {
                    context["most_recent_dropped"] = "true"
                }
                logEvent("focus.history.pruned", context: context)
                persistFocusHistory()
            }
        case .failure(let error):
            logEvent(
                "focus.history.load_failed",
                level: .warn,
                message: error.message,
                context: ["detail": error.detail ?? ""]
            )
            withState {
                focusStack = FocusStack(maxSize: Self.focusHistoryMaxEntries)
                mostRecentNonProjectFocus = nil
                focusRestoreRetryAttemptsByWindowId = [:]
            }
        }
    }

    private func focusHistoryStateSnapshot() -> FocusHistoryState {
        withState {
            FocusHistoryState(
                version: FocusHistoryStore.currentVersion,
                stack: focusStack.snapshot(),
                mostRecent: mostRecentNonProjectFocus
            )
        }
    }

    func persistFocusHistory() {
        let snapshot = focusHistoryStateSnapshot()
        let saveResult = withPersistence {
            focusHistoryStore.save(state: snapshot)
        }
        switch saveResult {
        case .success:
            break
        case .failure(let error):
            logEvent(
                "focus.history.save_failed",
                level: .warn,
                message: error.message,
                context: ["detail": error.detail ?? ""]
            )
        }
    }

    // MARK: - Recency Tracking

    func recordActivation(projectId: String) {
        // Remove existing entry if present
        withState {
            recentProjectIds.removeAll { $0 == projectId }
            // Add to front
            recentProjectIds.insert(projectId, at: 0)
            // Trim to max
            if recentProjectIds.count > Self.maxRecentProjects {
                recentProjectIds = Array(recentProjectIds.prefix(Self.maxRecentProjects))
            }
        }
        saveRecency()
    }

    func loadRecency() {
        let loadResult: Result<[String]?, Error> = withPersistence {
            guard fileSystem.fileExists(at: recencyFilePath) else {
                return .success(nil)
            }

            do {
                let data = try fileSystem.readFile(at: recencyFilePath)
                let ids = try JSONDecoder().decode([String].self, from: data)
                return .success(ids)
            } catch {
                return .failure(error)
            }
        }

        switch loadResult {
        case .success(nil):
            withState { recentProjectIds = [] }
        case .success(let ids?):
            withState { recentProjectIds = ids }
        case .failure(let error):
            withState { recentProjectIds = [] }
            logEvent(
                "recency.load_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": recencyFilePath.path]
            )
        }
    }

    private func saveRecency() {
        let data: Data
        do {
            let snapshot = withState { recentProjectIds }
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logEvent(
                "recency.encode_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": recencyFilePath.path]
            )
            return
        }

        let directory = recencyFilePath.deletingLastPathComponent()
        let directoryResult: Result<Void, Error> = withPersistence {
            do {
                try fileSystem.createDirectory(at: directory)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        if case .failure(let error) = directoryResult {
            logEvent(
                "recency.directory_create_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": directory.path]
            )
            return
        }

        let writeResult: Result<Void, Error> = withPersistence {
            do {
                try fileSystem.writeFile(at: recencyFilePath, data: data)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        if case .failure(let error) = writeResult {
            logEvent(
                "recency.write_failed",
                level: .warn,
                message: String(describing: error),
                context: ["path": recencyFilePath.path]
            )
        }
    }

    // MARK: - Logging

    func logEvent(_ event: String, level: LogLevel = .info, message: String? = nil, context: [String: String]? = nil) {
        _ = logger.log(event: "project_manager.\(event)", level: level, message: message, context: context)
    }

    /// Builds an activation event name from a stable source key and action.
    ///
    /// Example: `select.chrome_found`, `select.vscode_launch_failed`.
    static func activationWindowEventName(source: String, action: String) -> String {
        "select.\(source)_\(action)"
    }
}
