import Foundation

/// Snapshot of a non-project focus event persisted to disk.
struct FocusHistoryEntry: Codable, Equatable, Sendable {
    let windowId: Int
    let appBundleId: String
    let workspace: String
    let capturedAt: Date

    init(windowId: Int, appBundleId: String, workspace: String, capturedAt: Date) {
        self.windowId = windowId
        self.appBundleId = appBundleId
        self.workspace = workspace
        self.capturedAt = capturedAt
    }

    init(focus: CapturedFocus, capturedAt: Date) {
        self.windowId = focus.windowId
        self.appBundleId = focus.appBundleId
        self.workspace = focus.workspace
        self.capturedAt = capturedAt
    }

    var focus: CapturedFocus {
        CapturedFocus(windowId: windowId, appBundleId: appBundleId, workspace: workspace)
    }
}

/// Versioned focus history state persisted for cross-process focus restoration.
struct FocusHistoryState: Codable, Equatable, Sendable {
    let version: Int
    let stack: [FocusHistoryEntry]
    let mostRecent: FocusHistoryEntry?

    init(version: Int, stack: [FocusHistoryEntry], mostRecent: FocusHistoryEntry?) {
        self.version = version
        self.stack = stack
        self.mostRecent = mostRecent
    }
}

/// Load result with pruning details for diagnostics.
struct FocusHistoryLoadOutcome: Equatable, Sendable {
    let state: FocusHistoryState
    let prunedCount: Int
    let droppedMostRecent: Bool
}

/// Persistence layer for focus history (stack + most recent entry).
struct FocusHistoryStore {
    static let currentVersion = 1

    private let fileURL: URL
    private let fileSystem: FileSystem
    private let maxAge: TimeInterval
    private let maxEntries: Int

    /// Creates a focus history store.
    /// - Parameters:
    ///   - fileURL: Location of the focus history JSON file.
    ///   - fileSystem: File system abstraction for testability.
    ///   - maxAge: Maximum age (seconds) for entries before pruning.
    ///   - maxEntries: Maximum number of entries to retain in the stack.
    init(
        fileURL: URL,
        fileSystem: FileSystem = DefaultFileSystem(),
        maxAge: TimeInterval,
        maxEntries: Int
    ) {
        precondition(maxAge > 0, "maxAge must be positive")
        precondition(maxEntries > 0, "maxEntries must be positive")
        self.fileURL = fileURL
        self.fileSystem = fileSystem
        self.maxAge = maxAge
        self.maxEntries = maxEntries
    }

    /// Loads persisted focus history and applies pruning.
    /// - Parameter now: Current time used to prune stale entries.
    /// - Returns: Pruned focus history or nil if no file exists.
    func load(now: Date = Date()) -> Result<FocusHistoryLoadOutcome?, PsCoreError> {
        guard fileSystem.fileExists(at: fileURL) else {
            return .success(nil)
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: fileURL)
        } catch {
            return .failure(fileSystemError(
                "Failed to read focus history",
                detail: error.localizedDescription
            ))
        }

        let decoder = Self.makeDecoder()
        let state: FocusHistoryState
        do {
            state = try decoder.decode(FocusHistoryState.self, from: data)
        } catch {
            return .failure(parseError(
                "Failed to decode focus history",
                detail: error.localizedDescription
            ))
        }

        guard state.version == Self.currentVersion else {
            return .failure(parseError(
                "Unsupported focus history version",
                detail: "version=\(state.version)"
            ))
        }

        return .success(prune(state: state, now: now))
    }

    /// Saves focus history to disk.
    /// - Parameter state: Focus history state to persist.
    /// - Returns: Success or a file system error.
    func save(state: FocusHistoryState) -> Result<Void, PsCoreError> {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            return .failure(fileSystemError(
                "Failed to create focus history directory",
                detail: error.localizedDescription
            ))
        }

        let encoder = Self.makeEncoder()
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            return .failure(parseError(
                "Failed to encode focus history",
                detail: error.localizedDescription
            ))
        }

        do {
            try fileSystem.writeFile(at: fileURL, data: data)
        } catch {
            return .failure(fileSystemError(
                "Failed to write focus history",
                detail: error.localizedDescription
            ))
        }

        return .success(())
    }

    private func prune(state: FocusHistoryState, now: Date) -> FocusHistoryLoadOutcome {
        let cutoff = now.addingTimeInterval(-maxAge)

        let ageFiltered = state.stack.filter { $0.capturedAt >= cutoff }
        let agePrunedCount = state.stack.count - ageFiltered.count

        let trimmed: [FocusHistoryEntry]
        let sizePrunedCount: Int
        if ageFiltered.count > maxEntries {
            sizePrunedCount = ageFiltered.count - maxEntries
            trimmed = Array(ageFiltered.suffix(maxEntries))
        } else {
            sizePrunedCount = 0
            trimmed = ageFiltered
        }

        let totalPruned = agePrunedCount + sizePrunedCount

        var mostRecent = state.mostRecent
        var droppedMostRecent = false
        if let recent = mostRecent, recent.capturedAt < cutoff {
            mostRecent = nil
            droppedMostRecent = true
        }

        return FocusHistoryLoadOutcome(
            state: FocusHistoryState(version: state.version, stack: trimmed, mostRecent: mostRecent),
            prunedCount: totalPruned,
            droppedMostRecent: droppedMostRecent
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.makeTimestampFormatter().string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.makeTimestampFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 timestamp: \(string)"
            )
        }
        return decoder
    }

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
