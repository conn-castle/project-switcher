import XCTest
@testable import ProjectSwitcherCore

final class WindowPositionStoreTests: XCTestCase {

    private var tempDir: URL!
    private var filePath: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ps-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        filePath = tempDir.appendingPathComponent("window-layouts.json", isDirectory: false)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeStore() -> WindowPositionStore {
        WindowPositionStore(filePath: filePath)
    }

    private let sampleFrames = SavedWindowFrames(
        ide: SavedFrame(x: 100, y: 200, width: 900, height: 800),
        chrome: SavedFrame(x: 1050, y: 200, width: 900, height: 800)
    )

    private let otherFrames = SavedWindowFrames(
        ide: SavedFrame(x: 0, y: 25, width: 1440, height: 875),
        chrome: SavedFrame(x: 0, y: 25, width: 1440, height: 875)
    )

    // MARK: - Load

    func testLoadMissingFileReturnsNil() {
        let store = makeStore()
        let result = store.load(projectId: "test", mode: .wide)

        if case .success(let frames) = result {
            XCTAssertNil(frames)
        } else {
            XCTFail("Expected .success(nil), got \(result)")
        }
    }

    func testLoadMissingProjectReturnsNil() {
        let store = makeStore()
        _ = store.save(projectId: "other", mode: .wide, frames: sampleFrames)

        let result = store.load(projectId: "nonexistent", mode: .wide)
        if case .success(let frames) = result {
            XCTAssertNil(frames)
        } else {
            XCTFail("Expected .success(nil), got \(result)")
        }
    }

    func testLoadWrongModeReturnsNil() {
        let store = makeStore()
        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)

        let result = store.load(projectId: "test", mode: .small)
        if case .success(let frames) = result {
            XCTAssertNil(frames)
        } else {
            XCTFail("Expected .success(nil), got \(result)")
        }
    }

    func testLoadCorruptFileReturnsFailure() {
        try! "not valid json".data(using: .utf8)!.write(to: filePath)

        let store = makeStore()
        let result = store.load(projectId: "test", mode: .wide)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("decode"), "Error: \(error.message)")
        } else {
            XCTFail("Expected .failure for corrupt file, got \(result)")
        }
    }

    // MARK: - Save and Load Round-Trip

    func testSaveAndLoadRoundTrip() {
        let store = makeStore()

        let saveResult = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        if case .failure(let error) = saveResult {
            XCTFail("Save failed: \(error)")
            return
        }

        let loadResult = store.load(projectId: "test", mode: .wide)
        if case .success(let frames) = loadResult {
            XCTAssertEqual(frames, sampleFrames)
        } else {
            XCTFail("Expected .success(frames), got \(loadResult)")
        }
    }

    func testSaveSmallAndWideModesIndependent() {
        let store = makeStore()

        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        _ = store.save(projectId: "test", mode: .small, frames: otherFrames)

        if case .success(let wideFrames) = store.load(projectId: "test", mode: .wide) {
            XCTAssertEqual(wideFrames, sampleFrames)
        } else {
            XCTFail("Wide load failed")
        }

        if case .success(let smallFrames) = store.load(projectId: "test", mode: .small) {
            XCTAssertEqual(smallFrames, otherFrames)
        } else {
            XCTFail("Small load failed")
        }
    }

    func testSaveMultipleProjectsIndependent() {
        let store = makeStore()

        _ = store.save(projectId: "project-a", mode: .wide, frames: sampleFrames)
        _ = store.save(projectId: "project-b", mode: .wide, frames: otherFrames)

        if case .success(let aFrames) = store.load(projectId: "project-a", mode: .wide) {
            XCTAssertEqual(aFrames, sampleFrames)
        } else {
            XCTFail("Project A load failed")
        }

        if case .success(let bFrames) = store.load(projectId: "project-b", mode: .wide) {
            XCTAssertEqual(bFrames, otherFrames)
        } else {
            XCTFail("Project B load failed")
        }
    }

    func testSaveOverwritesPrevious() {
        let store = makeStore()

        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        _ = store.save(projectId: "test", mode: .wide, frames: otherFrames)

        if case .success(let frames) = store.load(projectId: "test", mode: .wide) {
            XCTAssertEqual(frames, otherFrames)
        } else {
            XCTFail("Load after overwrite failed")
        }
    }

    // MARK: - Nil Chrome Frame (Partial Save)

    func testSaveAndLoadWithNilChromeRoundTrip() {
        let store = makeStore()
        let ideOnly = SavedWindowFrames(
            ide: SavedFrame(x: 100, y: 200, width: 900, height: 800),
            chrome: nil
        )

        let saveResult = store.save(projectId: "partial", mode: .wide, frames: ideOnly)
        if case .failure(let error) = saveResult {
            XCTFail("Save failed: \(error)")
            return
        }

        let loadResult = store.load(projectId: "partial", mode: .wide)
        if case .success(let frames) = loadResult {
            XCTAssertEqual(frames, ideOnly)
            XCTAssertNil(frames?.chrome, "Chrome should be nil after round-trip")
            XCTAssertEqual(frames!.ide.x, 100, accuracy: 0.001)
        } else {
            XCTFail("Expected .success(frames), got \(loadResult)")
        }
    }

    func testSaveNilChromeThenFullFramesOverwrites() {
        let store = makeStore()
        let ideOnly = SavedWindowFrames(
            ide: SavedFrame(x: 100, y: 200, width: 900, height: 800),
            chrome: nil
        )
        _ = store.save(projectId: "test", mode: .wide, frames: ideOnly)

        // Now save with both frames — should overwrite the partial save
        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)

        if case .success(let frames) = store.load(projectId: "test", mode: .wide) {
            XCTAssertEqual(frames, sampleFrames)
            XCTAssertNotNil(frames?.chrome, "Chrome should be present after full overwrite")
        } else {
            XCTFail("Load after overwrite failed")
        }
    }

    // MARK: - Save Errors

    func testSaveToUnwritablePathFails() {
        let store = WindowPositionStore(
            filePath: URL(fileURLWithPath: "/nonexistent/dir/layouts.json"),
            fileSystem: StubUnwritableFileSystem()
        )

        let result = store.save(projectId: "test", mode: .wide, frames: sampleFrames)
        if case .failure = result {
            // Expected
        } else {
            XCTFail("Expected .failure for unwritable path")
        }
    }

    func testLoadReadFailureReturnsFailure() {
        let fileSystem = ConfigurableWindowPositionFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readError = NSError(domain: "WindowPositionStoreTests", code: 10, userInfo: [
            NSLocalizedDescriptionKey: "read failed"
        ])
        let store = WindowPositionStore(
            filePath: URL(fileURLWithPath: "/tmp/layouts.json"),
            fileSystem: fileSystem
        )

        let result = store.load(projectId: "test", mode: .wide)

        switch result {
        case .success:
            XCTFail("Expected read failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertEqual(error.message, "Failed to read window layouts file")
            XCTAssertEqual(error.detail, "read failed")
        }
    }

    func testSaveExistingFileReadFailureReturnsFailure() {
        let fileSystem = ConfigurableWindowPositionFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readError = NSError(domain: "WindowPositionStoreTests", code: 11, userInfo: [
            NSLocalizedDescriptionKey: "read existing failed"
        ])
        let store = WindowPositionStore(
            filePath: URL(fileURLWithPath: "/tmp/layouts.json"),
            fileSystem: fileSystem
        )

        let result = store.save(projectId: "test", mode: .wide, frames: sampleFrames)

        switch result {
        case .success:
            XCTFail("Expected read-existing failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertEqual(error.message, "Failed to read window layouts file")
            XCTAssertEqual(error.detail, "read existing failed")
        }
    }

    func testSaveFailsWhenEncodingNonFiniteFrame() {
        let fileSystem = ConfigurableWindowPositionFileSystem()
        let store = WindowPositionStore(
            filePath: URL(fileURLWithPath: "/tmp/layouts.json"),
            fileSystem: fileSystem
        )
        let nonFiniteFrames = SavedWindowFrames(
            ide: SavedFrame(x: .nan, y: 0, width: 800, height: 600),
            chrome: nil
        )

        let result = store.save(projectId: "test", mode: .wide, frames: nonFiniteFrames)

        switch result {
        case .success:
            XCTFail("Expected encode failure for NaN frame values")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertEqual(error.message, "Failed to encode window layouts file")
        }
    }

    func testSaveWriteFailureReturnsFailure() {
        let fileSystem = ConfigurableWindowPositionFileSystem()
        fileSystem.writeError = NSError(domain: "WindowPositionStoreTests", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "write failed"
        ])
        let store = WindowPositionStore(
            filePath: URL(fileURLWithPath: "/tmp/layouts.json"),
            fileSystem: fileSystem
        )

        let result = store.save(projectId: "test", mode: .wide, frames: sampleFrames)

        switch result {
        case .success:
            XCTFail("Expected write failure")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
            XCTAssertEqual(error.message, "Failed to write window layouts file")
            XCTAssertEqual(error.detail, "write failed")
        }
    }

    // MARK: - SavedFrame Conversion

    func testSavedFrameCGRectRoundTrip() {
        let rect = CGRect(x: 123.5, y: 456.7, width: 800.0, height: 600.0)
        let frame = SavedFrame(rect: rect)
        let converted = frame.cgRect

        XCTAssertEqual(converted.origin.x, rect.origin.x, accuracy: 0.001)
        XCTAssertEqual(converted.origin.y, rect.origin.y, accuracy: 0.001)
        XCTAssertEqual(converted.width, rect.width, accuracy: 0.001)
        XCTAssertEqual(converted.height, rect.height, accuracy: 0.001)
    }

    // MARK: - File Schema Version

    func testFileContainsVersionField() {
        let store = makeStore()
        _ = store.save(projectId: "test", mode: .wide, frames: sampleFrames)

        let data = try! Data(contentsOf: filePath)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["version"] as? Int, 1)
    }
}

// MARK: - Test Stubs

private struct StubUnwritableFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "Test", code: 1) }
    func createDirectory(at url: URL) throws { throw NSError(domain: "Test", code: 1) }
    func fileSize(at url: URL) throws -> UInt64 { throw NSError(domain: "Test", code: 1) }
    func removeItem(at url: URL) throws { throw NSError(domain: "Test", code: 1) }
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws { throw NSError(domain: "Test", code: 1) }
    func appendFile(at url: URL, data: Data) throws { throw NSError(domain: "Test", code: 1) }
    func writeFile(at url: URL, data: Data) throws { throw NSError(domain: "Test", code: 1) }
}

private final class ConfigurableWindowPositionFileSystem: FileSystem {
    var fileExistsValue = false
    var readData: Data?
    var readError: Error?
    var createDirectoryError: Error?
    var writeError: Error?

    func fileExists(at url: URL) -> Bool { fileExistsValue }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        if let readError {
            throw readError
        }
        return readData ?? Data()
    }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError {
            throw createDirectoryError
        }
    }

    func fileSize(at url: URL) throws -> UInt64 { UInt64(readData?.count ?? 0) }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}

    func writeFile(at url: URL, data: Data) throws {
        if let writeError {
            throw writeError
        }
        readData = data
    }
}
