import Foundation

/// ProjectSwitcher version and identifiers.
public enum ProjectSwitcher {
    private static let bundleIdentifierPrefix = "com.projectswitcher.ProjectSwitcher"
    private static let bundleIdentifierPrefixWithDot = "\(bundleIdentifierPrefix)."

    /// Build-time version constant. Must match MARKETING_VERSION in project.yml.
    /// CI preflight verifies these stay in sync.
    static let buildVersion = "0.2.1"

    /// A human-readable app display name for user-facing guidance.
    ///
    /// Returns the current app bundle display name when running as ProjectSwitcher/ProjectSwitcher Dev.
    /// Falls back to `ProjectSwitcher` for CLI and non-app contexts.
    public static var displayName: String {
        resolveDisplayName(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            infoDictionary: Bundle.main.infoDictionary
        )
    }

    /// A human-readable version identifier for diagnostic output.
    /// Reads from the app bundle when available (e.g., running as the .app),
    /// falls back to the build-time constant (e.g., running as the CLI tool).
    public static var version: String {
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundleVersion.isEmpty {
            return bundleVersion
        }
        return buildVersion
    }

    /// Resolves a user-facing app name from bundle metadata.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier of the current executable context.
    ///   - infoDictionary: Bundle metadata containing `CFBundleDisplayName` and `CFBundleName`.
    /// - Returns: The app display name for ProjectSwitcher app bundles, or `ProjectSwitcher` fallback.
    static func resolveDisplayName(
        bundleIdentifier: String?,
        infoDictionary: [String: Any]?
    ) -> String {
        guard let bundleIdentifier,
              bundleIdentifier == bundleIdentifierPrefix
                  || bundleIdentifier.hasPrefix(bundleIdentifierPrefixWithDot) else {
            return "ProjectSwitcher"
        }

        if let displayName = (infoDictionary?["CFBundleDisplayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }

        if let bundleName = (infoDictionary?["CFBundleName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleName.isEmpty {
            return bundleName
        }

        return "ProjectSwitcher"
    }
}
