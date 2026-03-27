import Foundation

@testable import ProjectSwitcherCore

final class LoggerInMemoryFileSystem: FileSystem {
    enum InMemoryError: Error {
        case missing(String)
    }

    private(set) var directories: Set<String> = []
    private var files: [String: Data] = [:]

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        false
    }

    func readFile(at url: URL) throws -> Data {
        guard let data = files[url.path] else {
            throw InMemoryError.missing(url.path)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw InMemoryError.missing(url.path)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files[sourceURL.path] else {
            throw InMemoryError.missing(sourceURL.path)
        }
        files[destinationURL.path] = data
        files.removeValue(forKey: sourceURL.path)
    }

    func appendFile(at url: URL, data: Data) throws {
        if let existing = files[url.path] {
            var merged = existing
            merged.append(data)
            files[url.path] = merged
        } else {
            files[url.path] = data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        files[url.path] = data
    }
}

final class LoggerConfigurableFileSystem: FileSystem {
    enum ConfigurableError: Error {
        case injected
    }

    private let base = LoggerInMemoryFileSystem()

    var createDirectoryError: Error?
    var fileSizeError: Error?
    var removeItemError: Error?
    var moveItemError: Error?
    var appendFileError: Error?
    var fileLockError: Error?

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func directoryExists(at url: URL) -> Bool { base.directoryExists(at: url) }
    func isExecutableFile(at url: URL) -> Bool { base.isExecutableFile(at: url) }
    func readFile(at url: URL) throws -> Data { try base.readFile(at: url) }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError { throw createDirectoryError }
        try base.createDirectory(at: url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        if let fileSizeError { throw fileSizeError }
        return try base.fileSize(at: url)
    }

    func removeItem(at url: URL) throws {
        if let removeItemError { throw removeItemError }
        try base.removeItem(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if let moveItemError { throw moveItemError }
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        if let appendFileError { throw appendFileError }
        try base.appendFile(at: url, data: data)
    }

    func withExclusiveFileLock<T>(at url: URL, body: () throws -> T) throws -> T {
        _ = url
        if let fileLockError { throw fileLockError }
        return try body()
    }

    func writeFile(at url: URL, data: Data) throws { try base.writeFile(at: url, data: data) }
}

/// File system test double that deterministically interleaves concurrent append operations.
///
/// When two callers append to the same file concurrently, the second caller writes its full payload
/// while the first caller is paused between writing its first and second halves. This reproduces
/// byte-level write interleaving that can corrupt JSONL when the logger is not single-writer.
final class LoggerInterleavingAppendFileSystem: FileSystem {
    enum InterleavingError: Error {
        case missing(String)
    }

    private let interleaveDelaySeconds: TimeInterval
    private let lock = NSLock()
    private var directories: Set<String> = []
    private var files: [String: Data] = [:]
    private var appendInProgress: Bool = false

    init(interleaveDelaySeconds: TimeInterval) {
        self.interleaveDelaySeconds = interleaveDelaySeconds
    }

    func fileExists(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return files[url.path] != nil
    }

    func directoryExists(at url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return directories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool {
        false
    }

    func readFile(at url: URL) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let data = files[url.path] else {
            throw InterleavingError.missing(url.path)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        lock.lock()
        directories.insert(url.path)
        lock.unlock()
    }

    func fileSize(at url: URL) throws -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        guard let data = files[url.path] else {
            throw InterleavingError.missing(url.path)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        files.removeValue(forKey: url.path)
        directories.remove(url.path)
        lock.unlock()
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        lock.lock()
        guard let data = files[sourceURL.path] else {
            lock.unlock()
            throw InterleavingError.missing(sourceURL.path)
        }
        files[destinationURL.path] = data
        files.removeValue(forKey: sourceURL.path)
        lock.unlock()
    }

    func appendFile(at url: URL, data: Data) throws {
        let shouldInterleave: Bool
        lock.lock()
        shouldInterleave = appendInProgress
        if !appendInProgress {
            appendInProgress = true
        }
        lock.unlock()

        if shouldInterleave {
            appendChunk(data, to: url)
            return
        }

        defer {
            lock.lock()
            appendInProgress = false
            lock.unlock()
        }

        let splitIndex = max(1, data.count / 2)
        let firstHalf = Data(data.prefix(splitIndex))
        let secondHalf = Data(data.suffix(data.count - splitIndex))

        appendChunk(firstHalf, to: url)
        Thread.sleep(forTimeInterval: interleaveDelaySeconds)
        appendChunk(secondHalf, to: url)
    }

    func withExclusiveFileLock<T>(at url: URL, body: () throws -> T) throws -> T {
        _ = url
        return try body()
    }

    func writeFile(at url: URL, data: Data) throws {
        lock.lock()
        files[url.path] = data
        lock.unlock()
    }

    private func appendChunk(_ chunk: Data, to url: URL) {
        lock.lock()
        if let existing = files[url.path] {
            var merged = existing
            merged.append(chunk)
            files[url.path] = merged
        } else {
            files[url.path] = chunk
        }
        lock.unlock()
    }
}
