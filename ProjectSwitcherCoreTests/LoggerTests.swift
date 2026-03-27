import XCTest
@testable import ProjectSwitcherCore

final class LoggerTests: XCTestCase {

    func testLoggerInitWithCustomDataStoreWritesToDiskAtExpectedPath() throws {
        let tmpHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-switcher-logger-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpHome) }
        try FileManager.default.createDirectory(at: tmpHome, withIntermediateDirectories: true)

        let dataStore = DataPaths(homeDirectory: tmpHome)
        let logger = ProjectSwitcherLogger(dataStore: dataStore)

        switch logger.log(event: "disk.write.test") {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: dataStore.primaryLogFile.path))
    }

    func testLoggerLogWritesWithGeneratedTimestamp() throws {
        let fileSystem = LoggerInMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        switch logger.log(event: "test.event", level: .warn, message: "hello", context: ["k": "v"]) {
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        case .success:
            break
        }

        let logData = try fileSystem.readFile(at: dataStore.primaryLogFile)
        XCTAssertEqual(logData.last, 0x0A)

        let line = String(data: logData.dropLast(), encoding: .utf8)
        XCTAssertNotNil(line)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(line!.utf8))
        XCTAssertEqual(decoded.event, "test.event")
        XCTAssertEqual(decoded.level, .warn)
        XCTAssertEqual(decoded.message, "hello")
        XCTAssertEqual(decoded.context, ["k": "v"])
        XCTAssertTrue(decoded.timestamp.contains("T"), "Expected ISO-8601 timestamp")
        XCTAssertTrue(decoded.timestamp.hasSuffix("Z"), "Expected UTC timestamp ending in Z")
    }

    func testLogEntryRejectsEmptyEvent() {
        let fileSystem = LoggerInMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "  ")
        let result = logger.log(entry: entry)

        switch result {
        case .failure(.invalidEvent):
            break
        case .failure(let error):
            XCTFail("Expected invalidEvent, got \(error)")
        case .success:
            XCTFail("Expected failure for empty event")
        }
    }

    func testLogEntryAppendsJsonLine() throws {
        let fileSystem = LoggerInMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(
            timestamp: "2024-01-01T00:00:00.000Z",
            level: .info,
            event: "test.event",
            message: "hello",
            context: ["k": "v"]
        )

        let result = logger.log(entry: entry)
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(fileSystem.directories.contains(dataStore.logsDirectory.path))

        let logData = try fileSystem.readFile(at: dataStore.primaryLogFile)
        XCTAssertEqual(logData.last, 0x0A, "Expected newline-terminated JSON line.")

        let line = String(data: logData.dropLast(), encoding: .utf8)
        XCTAssertNotNil(line)

        let decoded = try JSONDecoder().decode(LogEntry.self, from: Data(line!.utf8))
        XCTAssertEqual(decoded, entry)
    }

    func testRotationShiftsArchivesAndMovesActiveLog() throws {
        let fileSystem = LoggerInMemoryFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Small max size to force rotation deterministically.
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 20,
            maxArchives: 2
        )

        let logURL = dataStore.primaryLogFile
        let archive1 = dataStore.logsDirectory.appendingPathComponent("project-switcher.log.1")
        let archive2 = dataStore.logsDirectory.appendingPathComponent("project-switcher.log.2")

        // Existing files before rotation.
        try fileSystem.writeFile(at: logURL, data: Data(repeating: 0x41, count: 15)) // "AAAA..."
        try fileSystem.writeFile(at: archive1, data: Data("old-1".utf8))
        try fileSystem.writeFile(at: archive2, data: Data("old-2".utf8))

        // This entry should trigger rotation.
        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "rotate")
        switch logger.log(entry: entry) {
        case .success:
            break
        case .failure(let error):
            XCTFail("Unexpected error: \(error)")
        }

        // archive2 should now contain prior archive1 contents.
        let newArchive2 = try String(data: fileSystem.readFile(at: archive2), encoding: .utf8)
        XCTAssertEqual(newArchive2, "old-1")

        // archive1 should now contain prior active log contents (15 bytes of 'A').
        let newArchive1 = try fileSystem.readFile(at: archive1)
        XCTAssertEqual(newArchive1, Data(repeating: 0x41, count: 15))

        // active log should be recreated and contain the new entry.
        let newActive = try fileSystem.readFile(at: logURL)
        XCTAssertFalse(newActive.isEmpty)
        XCTAssertEqual(newActive.last, 0x0A)
    }

    func testCreateDirectoryFailureReturnsCreateDirectoryFailed() {
        let fileSystem = LoggerConfigurableFileSystem()
        fileSystem.createDirectoryError = NSError(domain: "test", code: 1)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.createDirectoryFailed):
            break
        case .failure(let error):
            XCTFail("Expected createDirectoryFailed, got: \(error)")
        }
    }

    func testFileSizeFailureReturnsFileSizeFailed() throws {
        let fileSystem = LoggerConfigurableFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Ensure log file exists so rotateIfNeeded checks size.
        try fileSystem.writeFile(at: dataStore.primaryLogFile, data: Data(repeating: 0x41, count: 10))
        fileSystem.fileSizeError = NSError(domain: "test", code: 2)

        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.fileSizeFailed):
            break
        case .failure(let error):
            XCTFail("Expected fileSizeFailed, got: \(error)")
        }
    }

    func testRotationFailureReturnsRotationFailed() throws {
        let fileSystem = LoggerConfigurableFileSystem()
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))

        // Ensure log file exists and size will exceed maxLogSizeBytes.
        try fileSystem.writeFile(at: dataStore.primaryLogFile, data: Data(repeating: 0x41, count: 10))
        fileSystem.moveItemError = NSError(domain: "test", code: 3)

        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.rotationFailed):
            break
        case .failure(let error):
            XCTFail("Expected rotationFailed, got: \(error)")
        }
    }

    func testAppendFailureReturnsWriteFailed() {
        let fileSystem = LoggerConfigurableFileSystem()
        fileSystem.appendFileError = NSError(domain: "test", code: 4)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.writeFailed):
            break
        case .failure(let error):
            XCTFail("Expected writeFailed, got: \(error)")
        }
    }

    func testLockFailureReturnsLockFailed() {
        let fileSystem = LoggerConfigurableFileSystem()
        fileSystem.fileLockError = NSError(domain: "test", code: 5)

        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024,
            maxArchives: 2
        )

        let entry = LogEntry(timestamp: "2024-01-01T00:00:00.000Z", level: .info, event: "evt")
        switch logger.log(entry: entry) {
        case .success:
            XCTFail("Expected failure")
        case .failure(.lockFailed):
            break
        case .failure(let error):
            XCTFail("Expected lockFailed, got: \(error)")
        }
    }

    func testLogWriteErrorMessageCoverage() {
        XCTAssertEqual(LogWriteError.invalidEvent.message, "Log event is empty.")
        XCTAssertTrue(LogWriteError.encodingFailed("x").message.contains("encode"))
        XCTAssertTrue(LogWriteError.createDirectoryFailed("x").message.contains("directory"))
        XCTAssertTrue(LogWriteError.lockFailed("x").message.contains("lock"))
        XCTAssertTrue(LogWriteError.fileSizeFailed("x").message.contains("size"))
        XCTAssertTrue(LogWriteError.rotationFailed("x").message.contains("rotate"))
        XCTAssertTrue(LogWriteError.writeFailed("x").message.contains("write"))
    }

}
