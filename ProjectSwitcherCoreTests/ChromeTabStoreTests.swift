import XCTest
@testable import ProjectSwitcherCore

final class ChromeTabStoreTests: XCTestCase {

    // MARK: - Save and load round-trip

    func testSaveAndLoadRoundTrip() {
        let fs = InMemoryFileSystem()
        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )
        let snapshot = ChromeTabSnapshot(
            urls: ["https://example.com", "https://docs.swift.org"],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let saveResult = store.save(snapshot: snapshot, projectId: "my-project")
        if case .failure(let error) = saveResult {
            XCTFail("Expected save success but got: \(error.message)")
        }

        switch store.load(projectId: "my-project") {
        case .success(let loaded):
            XCTAssertNotNil(loaded)
            XCTAssertEqual(loaded?.urls, ["https://example.com", "https://docs.swift.org"])
            XCTAssertEqual(loaded?.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }
    }

    // MARK: - Load returns nil when no file exists

    func testLoadReturnsNilWhenNoFile() {
        let fs = InMemoryFileSystem()
        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )

        switch store.load(projectId: "nonexistent") {
        case .success(let loaded):
            XCTAssertNil(loaded)
        case .failure(let error):
            XCTFail("Expected nil success but got: \(error.message)")
        }
    }

    // MARK: - Delete removes file

    func testDeleteRemovesFile() {
        let fs = InMemoryFileSystem()
        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )
        let snapshot = ChromeTabSnapshot(
            urls: ["https://example.com"],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        _ = store.save(snapshot: snapshot, projectId: "proj")

        let deleteResult = store.delete(projectId: "proj")
        if case .failure(let error) = deleteResult {
            XCTFail("Expected delete success but got: \(error.message)")
        }

        switch store.load(projectId: "proj") {
        case .success(let loaded):
            XCTAssertNil(loaded)
        case .failure(let error):
            XCTFail("Expected nil after delete but got: \(error.message)")
        }
    }

    // MARK: - Delete is no-op when file does not exist

    func testDeleteNoOpWhenNoFile() {
        let fs = InMemoryFileSystem()
        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )

        let result = store.delete(projectId: "nonexistent")
        if case .failure(let error) = result {
            XCTFail("Expected delete success but got: \(error.message)")
        }
    }

    // MARK: - Save overwrites existing snapshot

    func testSaveOverwritesExistingSnapshot() {
        let fs = InMemoryFileSystem()
        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )
        let snapshot1 = ChromeTabSnapshot(
            urls: ["https://a.com"],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let snapshot2 = ChromeTabSnapshot(
            urls: ["https://b.com", "https://c.com"],
            capturedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )

        _ = store.save(snapshot: snapshot1, projectId: "proj")
        _ = store.save(snapshot: snapshot2, projectId: "proj")

        switch store.load(projectId: "proj") {
        case .success(let loaded):
            XCTAssertEqual(loaded?.urls, ["https://b.com", "https://c.com"])
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }
    }

    // MARK: - Multiple projects are independent

    func testMultipleProjectsAreIndependent() {
        let fs = InMemoryFileSystem()
        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )
        let snapshotA = ChromeTabSnapshot(
            urls: ["https://a.com"],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let snapshotB = ChromeTabSnapshot(
            urls: ["https://b.com"],
            capturedAt: Date(timeIntervalSince1970: 1_700_001_000)
        )

        _ = store.save(snapshot: snapshotA, projectId: "proj-a")
        _ = store.save(snapshot: snapshotB, projectId: "proj-b")

        switch store.load(projectId: "proj-a") {
        case .success(let loaded):
            XCTAssertEqual(loaded?.urls, ["https://a.com"])
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }

        switch store.load(projectId: "proj-b") {
        case .success(let loaded):
            XCTAssertEqual(loaded?.urls, ["https://b.com"])
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    // MARK: - Save empty URLs

    func testSaveEmptyURLs() {
        let fs = InMemoryFileSystem()
        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )
        let snapshot = ChromeTabSnapshot(
            urls: [],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        _ = store.save(snapshot: snapshot, projectId: "empty")

        switch store.load(projectId: "empty") {
        case .success(let loaded):
            XCTAssertNotNil(loaded)
            XCTAssertEqual(loaded?.urls, [])
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    // MARK: - Load corrupt data returns error

    func testLoadCorruptDataReturnsError() {
        let fs = InMemoryFileSystem()
        let dir = URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true)
        let store = ChromeTabStore(directory: dir, fileSystem: fs)

        // Write corrupt JSON directly
        let corruptData = "not valid json".data(using: .utf8)!
        let fileURL = dir.appendingPathComponent("corrupt.json", isDirectory: false)
        try! fs.writeFile(at: fileURL, data: corruptData)

        switch store.load(projectId: "corrupt") {
        case .success:
            XCTFail("Expected failure for corrupt data")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("decode"), "Error should mention decoding: \(error.message)")
        }
    }

    // MARK: - Creates directory on save

    func testCreatesDirectoryOnSave() {
        let fs = InMemoryFileSystem()
        let dir = URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true)
        let store = ChromeTabStore(directory: dir, fileSystem: fs)

        XCTAssertFalse(fs.directories.contains(dir.path))

        let snapshot = ChromeTabSnapshot(
            urls: ["https://test.com"],
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        _ = store.save(snapshot: snapshot, projectId: "test")

        XCTAssertTrue(fs.directories.contains(dir.path))
    }

    // MARK: - Error branches

    func testSaveReturnsErrorWhenCreateDirectoryFails() {
        let fs = ConfigurableChromeTabFileSystem()
        fs.createDirectoryError = NSError(domain: "test", code: 1)

        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )
        let snapshot = ChromeTabSnapshot(urls: ["https://example.com"], capturedAt: Date(timeIntervalSince1970: 1))

        switch store.save(snapshot: snapshot, projectId: "p") {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertTrue(error.message.contains("Failed to create chrome-tabs directory"))
        }
    }

    func testSaveReturnsErrorWhenWriteFails() throws {
        let fs = ConfigurableChromeTabFileSystem()
        fs.writeFileError = NSError(domain: "test", code: 2)

        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )
        let snapshot = ChromeTabSnapshot(urls: ["https://example.com"], capturedAt: Date(timeIntervalSince1970: 1))

        switch store.save(snapshot: snapshot, projectId: "p") {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertTrue(error.message.contains("Failed to write tab snapshot"))
        }
    }

    func testLoadReturnsErrorWhenReadFails() {
        let fs = ConfigurableChromeTabFileSystem()
        fs.fileExistsValue = true
        fs.readFileError = NSError(domain: "test", code: 3)

        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )

        switch store.load(projectId: "p") {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertTrue(error.message.contains("Failed to read tab snapshot"))
        }
    }

    func testDeleteReturnsErrorWhenRemoveFails() {
        let fs = ConfigurableChromeTabFileSystem()
        fs.fileExistsValue = true
        fs.removeItemError = NSError(domain: "test", code: 4)

        let store = ChromeTabStore(
            directory: URL(fileURLWithPath: "/tmp/chrome-tabs", isDirectory: true),
            fileSystem: fs
        )

        switch store.delete(projectId: "p") {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertTrue(error.message.contains("Failed to delete tab snapshot"))
        }
    }
}

// MARK: - Test Doubles

private final class ConfigurableChromeTabFileSystem: FileSystem {
    var fileExistsValue: Bool = false

    var createDirectoryError: Error?
    var readFileError: Error?
    var removeItemError: Error?
    var writeFileError: Error?

    func fileExists(at url: URL) -> Bool { fileExistsValue }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        if let readFileError { throw readFileError }
        return Data()
    }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError { throw createDirectoryError }
    }

    func fileSize(at url: URL) throws -> UInt64 { 0 }

    func removeItem(at url: URL) throws {
        if let removeItemError { throw removeItemError }
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}

    func appendFile(at url: URL, data: Data) throws {}

    func writeFile(at url: URL, data: Data) throws {
        if let writeFileError { throw writeFileError }
    }
}

private final class InMemoryFileSystem: FileSystem {
    enum FSError: Error {
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
            throw FSError.missing(url.path)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = files[url.path] else {
            throw FSError.missing(url.path)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url.path)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        guard let data = files.removeValue(forKey: sourceURL.path) else {
            throw FSError.missing(sourceURL.path)
        }
        files[destinationURL.path] = data
    }

    func appendFile(at url: URL, data: Data) throws {
        if var existing = files[url.path] {
            existing.append(data)
            files[url.path] = existing
        } else {
            files[url.path] = data
        }
    }

    func writeFile(at url: URL, data: Data) throws {
        files[url.path] = data
    }
}
