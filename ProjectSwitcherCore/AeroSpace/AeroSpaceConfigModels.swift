import Foundation

/// Status of the AeroSpace configuration file.
public enum AeroSpaceConfigStatus: String, Sendable {
    /// No config file exists.
    case missing
    /// Config exists and is managed by ProjectSwitcher.
    case managedByProjectSwitcher
    /// Config exists but was created externally (not by ProjectSwitcher).
    case externalConfig
    /// Could not determine config status.
    case unknown
}

/// Result of an `ensureUpToDate()` config update check.
public enum ConfigUpdateResult: Equatable, Sendable {
    /// No config existed; a fresh install was written.
    case freshInstall
    /// The config was updated from one version to another.
    case updated(fromVersion: Int, toVersion: Int)
    /// The config is already at the latest version.
    case alreadyCurrent
    /// The config is not managed by ProjectSwitcher; skipped.
    case skippedExternal
}
