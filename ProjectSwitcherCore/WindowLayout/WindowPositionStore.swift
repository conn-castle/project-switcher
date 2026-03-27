import Foundation

/// Saved window frames for IDE and Chrome in NSScreen coordinate space.
///
/// `chrome` remains optional for backward compatibility with historical snapshots
/// that persisted IDE-only layouts. Current capture behavior writes complete
/// IDE+Chrome frames and skips save when Chrome is unavailable.
public struct SavedWindowFrames: Codable, Equatable, Sendable {
    public let ide: SavedFrame
    public let chrome: SavedFrame?

    public init(ide: SavedFrame, chrome: SavedFrame?) {
        self.ide = ide
        self.chrome = chrome
    }
}

/// A single saved window frame (origin + size) in NSScreen coordinate space.
public struct SavedFrame: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Converts to CGRect.
    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Creates from CGRect.
    public init(rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.width)
        self.height = Double(rect.height)
    }
}

// MARK: - Persistence File Schema

/// Top-level JSON schema for window-layouts.json.
struct WindowLayoutsFile: Codable, Equatable {
    let version: Int
    var projects: [String: ProjectModeFrames]

    init(version: Int = 1, projects: [String: ProjectModeFrames] = [:]) {
        self.version = version
        self.projects = projects
    }
}

/// Per-project frames keyed by screen mode.
struct ProjectModeFrames: Codable, Equatable {
    var small: SavedWindowFrames?
    var wide: SavedWindowFrames?
}

// MARK: - WindowPositionStore

/// Persistence layer for window position history.
///
/// Stores IDE and Chrome window frames per project per screen mode in a single
/// JSON file. Existing IDE-only historical snapshots are still readable.
/// Follows the `ChromeTabStore` Result-based API pattern.
struct WindowPositionStore: WindowPositionStoring {
    private let filePath: URL
    private let fileSystem: FileSystem

    /// Creates a window position store.
    /// - Parameters:
    ///   - filePath: Path to the window-layouts.json file.
    ///   - fileSystem: File system abstraction for testability.
    init(filePath: URL, fileSystem: FileSystem = DefaultFileSystem()) {
        self.filePath = filePath
        self.fileSystem = fileSystem
    }

    /// Loads saved window frames for a project and screen mode.
    ///
    /// - Returns:
    ///   - `.success(frames)` if saved frames exist for the project+mode.
    ///   - `.success(nil)` if no file exists or the project/mode has no saved frames.
    ///   - `.failure(error)` if the file exists but is corrupt or unreadable.
    func load(projectId: String, mode: ScreenMode) -> Result<SavedWindowFrames?, PsCoreError> {
        guard fileSystem.fileExists(at: filePath) else {
            return .success(nil)
        }

        let layoutsFile: WindowLayoutsFile
        switch readFile() {
        case .success(let file):
            layoutsFile = file
        case .failure(let error):
            return .failure(error)
        }

        guard let projectFrames = layoutsFile.projects[projectId] else {
            return .success(nil)
        }

        switch mode {
        case .small:
            return .success(projectFrames.small)
        case .wide:
            return .success(projectFrames.wide)
        }
    }

    /// Saves window frames for a project and screen mode.
    ///
    /// Reads the existing file (if any), updates the relevant entry, and writes back.
    /// Creates the parent directory and file if they don't exist.
    func save(projectId: String, mode: ScreenMode, frames: SavedWindowFrames) -> Result<Void, PsCoreError> {
        var layoutsFile: WindowLayoutsFile

        if fileSystem.fileExists(at: filePath) {
            switch readFile() {
            case .success(let file):
                layoutsFile = file
            case .failure(let error):
                return .failure(error)
            }
        } else {
            layoutsFile = WindowLayoutsFile()
        }

        var projectFrames = layoutsFile.projects[projectId] ?? ProjectModeFrames()
        switch mode {
        case .small:
            projectFrames.small = frames
        case .wide:
            projectFrames.wide = frames
        }
        layoutsFile.projects[projectId] = projectFrames

        return writeFile(layoutsFile)
    }

    // MARK: - Private

    private func readFile() -> Result<WindowLayoutsFile, PsCoreError> {
        let data: Data
        do {
            data = try fileSystem.readFile(at: filePath)
        } catch {
            return .failure(fileSystemError(
                "Failed to read window layouts file",
                detail: error.localizedDescription
            ))
        }

        do {
            let file = try JSONDecoder().decode(WindowLayoutsFile.self, from: data)
            return .success(file)
        } catch {
            return .failure(parseError(
                "Failed to decode window layouts file",
                detail: error.localizedDescription
            ))
        }
    }

    private func writeFile(_ file: WindowLayoutsFile) -> Result<Void, PsCoreError> {
        // Ensure parent directory exists
        let directory = filePath.deletingLastPathComponent()
        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            return .failure(fileSystemError(
                "Failed to create window layouts directory",
                detail: error.localizedDescription
            ))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(file)
        } catch {
            return .failure(fileSystemError(
                "Failed to encode window layouts file",
                detail: error.localizedDescription
            ))
        }

        do {
            try fileSystem.writeFile(at: filePath, data: data)
        } catch {
            return .failure(fileSystemError(
                "Failed to write window layouts file",
                detail: error.localizedDescription
            ))
        }

        return .success(())
    }
}
