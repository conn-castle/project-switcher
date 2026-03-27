import Foundation

// MARK: - Chrome Tab Snapshot

/// Persisted snapshot of ALL Chrome tab URLs for a project.
///
/// The snapshot is the complete truth — every URL visible in the Chrome window
/// at close time, including pinned and always-open tabs. On restore, URLs are
/// passed verbatim to the Chrome launcher with no filtering.
public struct ChromeTabSnapshot: Codable, Equatable, Sendable {
    /// All tab URLs captured from the project's Chrome window.
    public let urls: [String]
    /// UTC timestamp of when the snapshot was captured.
    public let capturedAt: Date

    public init(urls: [String], capturedAt: Date) {
        self.urls = urls
        self.capturedAt = capturedAt
    }
}

// MARK: - Chrome Tab Store

/// Persistence layer for Chrome tab snapshots.
///
/// Saves, loads, and deletes per-project JSON snapshot files
/// in the chrome-tabs state directory.
struct ChromeTabStore {
    private let directory: URL
    private let fileSystem: FileSystem

    /// Creates a tab store rooted at the provided directory.
    /// - Parameters:
    ///   - directory: Directory for snapshot files.
    ///   - fileSystem: File system abstraction for testability.
    init(directory: URL, fileSystem: FileSystem = DefaultFileSystem()) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    /// Saves a tab snapshot for a project, creating the directory if needed.
    /// - Parameters:
    ///   - snapshot: The snapshot to save.
    ///   - projectId: Project identifier.
    /// - Returns: Success or a file system error.
    func save(snapshot: ChromeTabSnapshot, projectId: String) -> Result<Void, PsCoreError> {
        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            return .failure(fileSystemError(
                "Failed to create chrome-tabs directory",
                detail: error.localizedDescription
            ))
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(snapshot)
        } catch {
            return .failure(fileSystemError(
                "Failed to encode tab snapshot for \(projectId)",
                detail: error.localizedDescription
            ))
        }

        let fileURL = fileURL(for: projectId)
        do {
            try fileSystem.writeFile(at: fileURL, data: data)
        } catch {
            return .failure(fileSystemError(
                "Failed to write tab snapshot for \(projectId)",
                detail: error.localizedDescription
            ))
        }

        return .success(())
    }

    /// Loads the saved tab snapshot for a project.
    /// - Parameter projectId: Project identifier.
    /// - Returns: The snapshot if it exists, nil if no file, or an error.
    func load(projectId: String) -> Result<ChromeTabSnapshot?, PsCoreError> {
        let fileURL = fileURL(for: projectId)

        guard fileSystem.fileExists(at: fileURL) else {
            return .success(nil)
        }

        let data: Data
        do {
            data = try fileSystem.readFile(at: fileURL)
        } catch {
            return .failure(fileSystemError(
                "Failed to read tab snapshot for \(projectId)",
                detail: error.localizedDescription
            ))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let snapshot = try decoder.decode(ChromeTabSnapshot.self, from: data)
            return .success(snapshot)
        } catch {
            return .failure(parseError(
                "Failed to decode tab snapshot for \(projectId)",
                detail: error.localizedDescription
            ))
        }
    }

    /// Deletes the saved tab snapshot for a project.
    /// - Parameter projectId: Project identifier.
    /// - Returns: Success or a file system error.
    func delete(projectId: String) -> Result<Void, PsCoreError> {
        let fileURL = fileURL(for: projectId)

        guard fileSystem.fileExists(at: fileURL) else {
            return .success(())
        }

        do {
            try fileSystem.removeItem(at: fileURL)
        } catch {
            return .failure(fileSystemError(
                "Failed to delete tab snapshot for \(projectId)",
                detail: error.localizedDescription
            ))
        }

        return .success(())
    }

    private func fileURL(for projectId: String) -> URL {
        directory.appendingPathComponent("\(projectId).json", isDirectory: false)
    }
}

// MARK: - Chrome Tab Resolver

/// Resolved tab set for a project activation.
public struct ResolvedTabs: Equatable, Sendable {
    /// URLs that are always opened as leftmost tabs.
    public let alwaysOpenURLs: [String]
    /// URLs from history or defaults (non-always-open).
    public let regularURLs: [String]

    /// Ordered URL list: always-open first (leftmost), then regular.
    public var orderedURLs: [String] {
        alwaysOpenURLs + regularURLs
    }
}

/// Pure logic for computing the cold-start tab set from config and git remote.
///
/// Used only when no snapshot exists for the project. When a snapshot is available,
/// its URLs are used verbatim (snapshot-is-truth) without going through the resolver.
struct ChromeTabResolver {
    /// Resolves the tab set for a cold-start project activation (no saved snapshot).
    /// - Parameters:
    ///   - config: Global chrome config.
    ///   - project: Project config.
    ///   - gitRemoteURL: Resolved git remote URL, if any.
    /// - Returns: Resolved tab set with always-open and regular URLs.
    static func resolve(
        config: ChromeConfig,
        project: ProjectConfig,
        gitRemoteURL: String?
    ) -> ResolvedTabs {
        // Build always-open set: global pinned + project pinned + git remote
        var alwaysOpen: [String] = []
        alwaysOpen.append(contentsOf: config.pinnedTabs)
        alwaysOpen.append(contentsOf: project.chromePinnedTabs)
        if config.openGitRemote, let remote = gitRemoteURL {
            alwaysOpen.append(remote)
        }

        // Deduplicate always-open, preserving order
        var seen = Set<String>()
        alwaysOpen = alwaysOpen.filter { url in
            let inserted = seen.insert(url).inserted
            return inserted
        }

        // Build regular set from defaults: global defaults + project defaults
        var defaults: [String] = []
        defaults.append(contentsOf: config.defaultTabs)
        defaults.append(contentsOf: project.chromeDefaultTabs)

        // Deduplicate defaults, preserving order, excluding already-always-open
        let alwaysOpenSet = Set(alwaysOpen)
        var defaultSeen = alwaysOpenSet
        let regular = defaults.filter { url in
            let inserted = defaultSeen.insert(url).inserted
            return inserted
        }

        return ResolvedTabs(alwaysOpenURLs: alwaysOpen, regularURLs: regular)
    }
}

// MARK: - Git Remote Resolver

/// Resolves the git remote URL for a project path.
struct GitRemoteResolver: GitRemoteResolving {
    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = PsSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Resolves the git remote origin URL at the given path.
    /// - Parameter projectPath: Absolute path to the project directory.
    /// - Returns: The remote URL if one exists, nil otherwise.
    func resolve(projectPath: String) -> String? {
        // Use git -C to run in the project directory without changing cwd
        let result = commandRunner.run(
            executable: "git",
            arguments: ["-C", projectPath, "remote", "get-url", "origin"],
            timeoutSeconds: 5
        )

        switch result {
        case .success(let output):
            guard output.exitCode == 0 else { return nil }
            let url = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return url.isEmpty ? nil : url
        case .failure:
            return nil
        }
    }
}

// MARK: - Chrome Tab Controller

/// AppleScript-based Chrome tab capture and restore controller.
struct PsChromeTabController: ChromeTabCapturing {
    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = PsSystemCommandRunner()) {
        self.commandRunner = commandRunner
    }

    /// Captures the URLs of all tabs in the Chrome window matching the given title.
    /// - Parameter windowTitle: The window title to match (e.g., "PS:my-project").
    /// - Returns: Array of tab URLs on success, or an error.
    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> {
        let escapedTitle = escapeForAppleScript(windowTitle)
        let script = [
            "tell application \"Google Chrome\"",
            "  set targetWindow to missing value",
            "  repeat with w in windows",
            "    if given name of w is \"\(escapedTitle)\" then",
            "      set targetWindow to w",
            "      exit repeat",
            "    end if",
            "  end repeat",
            "  if targetWindow is missing value then",
            "    return \"\"",
            "  end if",
            "  set urlList to {}",
            "  repeat with t in tabs of targetWindow",
            "    set end of urlList to URL of t",
            "  end repeat",
            "  set AppleScript's text item delimiters to \"\\n\"",
            "  return urlList as text",
            "end tell"
        ]

        let result = commandRunner.run(
            executable: "osascript",
            arguments: scriptArguments(lines: script),
            timeoutSeconds: 10
        )

        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            guard output.exitCode == 0 else {
                return .failure(commandError("osascript (capture tabs)", result: output))
            }
            let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if stdout.isEmpty {
                return .success([])
            }
            let urls = stdout.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return .success(urls)
        }
    }

    // MARK: - Private Helpers

    private func scriptArguments(lines: [String]) -> [String] {
        var args: [String] = []
        for line in lines {
            args.append("-e")
            args.append(line)
        }
        return args
    }

    private func escapeForAppleScript(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }
}
