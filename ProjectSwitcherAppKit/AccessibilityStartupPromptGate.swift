import Foundation

/// Determines whether Accessibility permission should be requested at app startup.
///
/// The gate prompts at most once per app build (CFBundleVersion). It records the
/// current build on first launch, regardless of permission state, so subsequent
/// launches of the same build do not re-prompt.
public struct AccessibilityStartupPromptGate {
    /// Default UserDefaults key storing the last prompted build identifier.
    public static let defaultPromptedBuildKey = "com.projectswitcher.accessibility.prompted_build"

    private let defaults: UserDefaults
    private let promptedBuildKey: String

    /// Creates a startup prompt gate.
    /// - Parameters:
    ///   - defaults: Persistent store used for prompt markers.
    ///   - promptedBuildKey: Key storing the last prompted build.
    public init(
        defaults: UserDefaults = .standard,
        promptedBuildKey: String = Self.defaultPromptedBuildKey
    ) {
        self.defaults = defaults
        self.promptedBuildKey = promptedBuildKey
    }

    /// Returns true when startup should trigger an Accessibility permission prompt.
    ///
    /// Rules:
    /// 1. If `currentBuild` was already seen, return false.
    /// 2. Otherwise mark the build as seen.
    /// 3. Return true only when permission is not currently trusted.
    ///
    /// - Parameters:
    ///   - currentBuild: Build identifier for the current app install (CFBundleVersion).
    ///   - isAccessibilityTrusted: Current Accessibility trust status.
    /// - Returns: `true` if startup should call `promptForAccessibility()`.
    public func shouldPromptOnFirstLaunchOfCurrentBuild(
        currentBuild: String,
        isAccessibilityTrusted: Bool
    ) -> Bool {
        let normalizedBuild = currentBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBuild.isEmpty else {
            // Missing CFBundleVersion — skip prompt rather than crash.
            return false
        }

        if defaults.string(forKey: promptedBuildKey) == normalizedBuild {
            return false
        }

        defaults.set(normalizedBuild, forKey: promptedBuildKey)
        return !isAccessibilityTrusted
    }
}
