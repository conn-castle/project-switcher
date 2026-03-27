import Foundation

extension ProjectManager {
    // MARK: - Chrome Tab Operations

    /// Resolves the initial URLs for a fresh Chrome window.
    ///
    /// If a saved snapshot exists, uses it verbatim (complete tab state from last session).
    /// If no snapshot exists (cold start), uses always-open + defaults from config.
    ///
    /// - Parameters:
    ///   - project: Project configuration.
    ///   - projectId: Project identifier.
    /// - Returns: Ordered list of URLs to open, or empty if none.
    func resolveInitialURLs(project: ProjectConfig, projectId: String) -> [String] {
        guard let config = withState({ config }) else { return [] }

        // Load saved tab snapshot
        let snapshot: ChromeTabSnapshot?
        switch chromeTabStore.load(projectId: projectId) {
        case .success(let loaded):
            snapshot = loaded
        case .failure(let error):
            logEvent("select.tab_snapshot_load_failed", level: .warn, message: error.message)
            snapshot = nil
        }

        // If snapshot exists, restore it verbatim (it IS the complete tab state)
        if let snapshot, !snapshot.urls.isEmpty {
            return snapshot.urls
        }

        // Cold start: use always-open + defaults from config
        let gitRemoteURL: String?
        if config.chrome.openGitRemote, !project.isSSH {
            gitRemoteURL = gitRemoteResolver.resolve(projectPath: project.path)
        } else {
            gitRemoteURL = nil
        }

        let resolvedTabs = ChromeTabResolver.resolve(
            config: config.chrome,
            project: project,
            gitRemoteURL: gitRemoteURL
        )
        return resolvedTabs.orderedURLs
    }

    /// Captures Chrome tab URLs before closing a project.
    ///
    /// Saves ALL captured URLs verbatim (no filtering). If the Chrome window is gone
    /// (empty capture), deletes any stale snapshot from disk.
    ///
    /// - Returns: Warning message if capture failed, nil on success.
    func performTabCapture(projectId: String) -> String? {
        guard withState({ config != nil }) else { return nil }

        let windowTitle = "\(PsIdeToken.prefix)\(projectId)"

        // Capture current tab URLs
        let capturedURLs: [String]
        switch chromeTabCapture.captureTabURLs(windowTitle: windowTitle) {
        case .success(let urls):
            capturedURLs = urls
        case .failure(let error):
            logEvent("close.tab_capture_failed", level: .warn, message: error.message)
            // Don't delete snapshot on command failure (timeout, etc.) — only delete
            // on empty success (window confirmed gone). A transient error shouldn't
            // destroy a valid snapshot.
            return "Tab capture failed: \(error.message)"
        }

        // If no tabs captured (window not found or empty), delete stale snapshot
        guard !capturedURLs.isEmpty else {
            _ = chromeTabStore.delete(projectId: projectId)
            return nil
        }

        // Save ALL captured URLs verbatim (snapshot = complete truth)
        let snapshot = ChromeTabSnapshot(urls: capturedURLs, capturedAt: Date())
        switch chromeTabStore.save(snapshot: snapshot, projectId: projectId) {
        case .success:
            logEvent("close.tabs_captured", context: [
                "project_id": projectId,
                "tab_count": "\(capturedURLs.count)"
            ])
            return nil
        case .failure(let error):
            logEvent("close.tab_save_failed", level: .warn, message: error.message)
            return "Tab save failed: \(error.message)"
        }
    }

}
