import Foundation

/// Snapshot of config file metadata used to detect config changes between switcher openings.
public struct SwitcherConfigFingerprint: Equatable, Sendable {
    /// File size in bytes.
    public let sizeBytes: UInt64
    /// Last modification time.
    public let modificationDate: Date

    /// Creates a config fingerprint.
    /// - Parameters:
    ///   - sizeBytes: File size in bytes.
    ///   - modificationDate: Last modification time.
    public init(sizeBytes: UInt64, modificationDate: Date) {
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
    }

    /// Builds a fingerprint from file attributes.
    /// - Parameter fileAttributes: Attributes returned by FileManager.
    /// - Returns: Fingerprint when both size and modification date are present; otherwise nil.
    public static func from(fileAttributes: [FileAttributeKey: Any]) -> SwitcherConfigFingerprint? {
        guard let sizeNumber = fileAttributes[.size] as? NSNumber else {
            return nil
        }
        guard sizeNumber.int64Value >= 0 else {
            return nil
        }
        guard let modificationDate = fileAttributes[.modificationDate] as? Date else {
            return nil
        }
        return SwitcherConfigFingerprint(
            sizeBytes: UInt64(truncating: sizeNumber),
            modificationDate: modificationDate
        )
    }
}

/// Policy for deciding whether switcher config must be reloaded.
public enum SwitcherConfigReloadPolicy {
    /// Returns whether config should be reloaded based on fingerprints.
    ///
    /// Rules:
    /// - missing current fingerprint => reload (surface errors/starter-config creation)
    /// - no previous fingerprint => reload (first open)
    /// - changed fingerprint => reload
    /// - unchanged fingerprint => skip reload
    ///
    /// - Parameters:
    ///   - previous: Previous fingerprint, if any.
    ///   - current: Current fingerprint, if any.
    /// - Returns: True when reload is required.
    public static func shouldReload(
        previous: SwitcherConfigFingerprint?,
        current: SwitcherConfigFingerprint?
    ) -> Bool {
        guard let current else { return true }
        guard let previous else { return true }
        return previous != current
    }
}

/// Token source used to coalesce debounced work.
///
/// Each newly issued token invalidates all previously issued tokens.
public struct DebounceTokenSource: Equatable, Sendable {
    private var latestToken: UInt64 = 0

    /// Creates a token source.
    public init() {}

    /// Issues a new token and invalidates previous ones.
    /// - Returns: The latest token.
    public mutating func issueToken() -> UInt64 {
        latestToken &+= 1
        // Preserve "0 means no token issued" semantics on overflow.
        if latestToken == 0 {
            latestToken = 1
        }
        return latestToken
    }

    /// Checks whether a token is the latest.
    /// - Parameter token: Token to check.
    /// - Returns: True when token matches the latest token.
    public func isLatest(_ token: UInt64) -> Bool {
        token == latestToken
    }
}

/// Structural row kind used for table-reload planning.
public enum SwitcherRowKind: String, Equatable, Sendable {
    case sectionHeader
    case backAction
    case project
    case emptyState
}

/// Structural row signature used for table-reload planning.
public struct SwitcherRowSignature: Equatable, Sendable {
    /// Row kind.
    public let kind: SwitcherRowKind
    /// Stable selection key, if any.
    public let selectionKey: String?

    /// Creates a row signature.
    /// - Parameters:
    ///   - kind: Row kind.
    ///   - selectionKey: Stable selection key for the row.
    public init(kind: SwitcherRowKind, selectionKey: String?) {
        self.kind = kind
        self.selectionKey = selectionKey
    }
}

/// Table update mode selected by the reload planner.
public enum SwitcherTableReloadMode: String, Equatable, Sendable {
    /// Rebuild table structure.
    case fullReload
    /// Reload row content while preserving structure.
    case visibleRowsReload
    /// No table data update needed.
    case noReload
}

/// Plans the safest table update mode based on old/new row structure and content.
public enum SwitcherTableReloadPlanner {
    /// Returns the table update mode for old/new rows.
    ///
    /// - Parameters:
    ///   - previous: Previous structural signatures.
    ///   - next: Next structural signatures.
    ///   - contentChanged: Whether row content changed while structure stayed the same.
    /// - Returns: Planned reload mode.
    public static func plan(
        previous: [SwitcherRowSignature],
        next: [SwitcherRowSignature],
        contentChanged: Bool
    ) -> SwitcherTableReloadMode {
        guard previous.count == next.count else {
            return .fullReload
        }

        guard zip(previous, next).allSatisfy({ $0 == $1 }) else {
            return .fullReload
        }

        return contentChanged ? .visibleRowsReload : .noReload
    }
}
