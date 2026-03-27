import Darwin
import Foundation

// MARK: - File System

/// File system access protocol for testability.
///
/// This protocol includes only the methods actually used by Core components:
/// - Logger: createDirectory, appendFile, fileExists, fileSize, removeItem, moveItem, withExclusiveFileLock
/// - ExecutableResolver: isExecutableFile
/// - StateStore: fileExists, readFile, createDirectory, writeFile
protocol FileSystem {
    func fileExists(at url: URL) -> Bool
    func directoryExists(at url: URL) -> Bool
    func isExecutableFile(at url: URL) -> Bool
    func readFile(at url: URL) throws -> Data
    func createDirectory(at url: URL) throws
    func fileSize(at url: URL) throws -> UInt64
    func removeItem(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func appendFile(at url: URL, data: Data) throws
    func writeFile(at url: URL, data: Data) throws
    func contentsOfDirectory(at url: URL) throws -> [String]
    func withExclusiveFileLock<T>(at url: URL, body: () throws -> T) throws -> T
}

extension FileSystem {
    /// Default directory listing.
    ///
    /// Returns an empty array by default. Override in production or test implementations
    /// that need real directory enumeration.
    func contentsOfDirectory(at url: URL) throws -> [String] {
        []
    }

    /// Default file-lock behavior for in-memory/test file systems.
    ///
    /// Real file-system implementations should override this to coordinate access
    /// across process boundaries.
    func withExclusiveFileLock<T>(at url: URL, body: () throws -> T) throws -> T {
        _ = url
        return try body()
    }
}

/// Default file system implementation backed by FileManager.
struct DefaultFileSystem: FileSystem {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func isExecutableFile(at url: URL) -> Bool {
        fileManager.isExecutableFile(atPath: url.path)
    }

    func readFile(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber else {
            throw NSError(
                domain: "DefaultFileSystem",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File size unavailable for \(url.path)"]
            )
        }
        return size.uint64Value
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    func withExclusiveFileLock<T>(at url: URL, body: () throws -> T) throws -> T {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = open(url.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            throw makePOSIXError(function: "open", path: url.path)
        }
        defer { _ = close(fd) }

        guard flock(fd, LOCK_EX) == 0 else {
            throw makePOSIXError(function: "flock(LOCK_EX)", path: url.path)
        }
        defer { _ = flock(fd, LOCK_UN) }

        return try body()
    }

    func writeFile(at url: URL, data: Data) throws {
        try data.write(to: url, options: .atomic)
    }

    func contentsOfDirectory(at url: URL) throws -> [String] {
        try fileManager.contentsOfDirectory(atPath: url.path)
    }

    private func makePOSIXError(function: String, path: String) -> NSError {
        let code = errno
        let detail = String(cString: strerror(code))
        return NSError(
            domain: "DefaultFileSystem",
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey: "\(function) failed for \(path): \(detail)"
            ]
        )
    }
}
