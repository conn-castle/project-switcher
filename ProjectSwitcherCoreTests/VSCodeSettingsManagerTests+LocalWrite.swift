import XCTest

@testable import ProjectSwitcherCore

extension VSCodeSettingsManagerTests {

    // MARK: - writeLocalSettings: errors on unreadable file

    func testWriteLocalSettingsReturnsErrorWhenFileExistsButUnreadable() throws {
        let unreadableFS = SettingsUnreadableFileSystem()
        let manager = PsVSCodeSettingsManager(fileSystem: unreadableFS)

        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Failed to read existing .vscode/settings.json"))
        } else {
            XCTFail("Expected failure when file exists but is unreadable")
        }
    }

    // MARK: - writeLocalSettings: creates .vscode directory

    func testWriteLocalSettingsCreatesVSCodeDirectory() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let manager = PsVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let vscodeDir = tempDir.appendingPathComponent(".vscode")
        var isDir = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: vscodeDir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    // MARK: - writeLocalSettings: preserves existing content

    func testWriteLocalSettingsPreservesExistingContent() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let vscodeDir = tempDir.appendingPathComponent(".vscode")
        try FileManager.default.createDirectory(at: vscodeDir, withIntermediateDirectories: true)
        let settingsURL = vscodeDir.appendingPathComponent("settings.json")
        try """
        {
          "editor.fontSize": 14
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let manager = PsVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let content = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(content.contains("// >>> project-switcher"))
        XCTAssertTrue(content.contains("\"editor.fontSize\": 14"))
    }

    // MARK: - writeLocalSettings: creates new file when missing

    func testWriteLocalSettingsCreatesNewFileWhenMissing() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let manager = PsVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "new-proj")

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let settingsURL = tempDir.appendingPathComponent(".vscode/settings.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: settingsURL.path))

        let content = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(content.contains("PS:new-proj"))
    }

    // MARK: - writeLocalSettings: handles empty existing file

    func testWriteLocalSettingsHandlesEmptyExistingFile() throws {
        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        // Create an empty settings.json (0 bytes)
        let vscodeDir = tempDir.appendingPathComponent(".vscode", isDirectory: true)
        try FileManager.default.createDirectory(at: vscodeDir, withIntermediateDirectories: true)
        let settingsURL = vscodeDir.appendingPathComponent("settings.json")
        XCTAssertTrue(FileManager.default.createFile(atPath: settingsURL.path, contents: Data()))

        let manager = PsVSCodeSettingsManager()
        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "empty-file-proj")

        if case .failure(let error) = result {
            XCTFail("Expected success for empty file, got: \(error.message)")
            return
        }

        let content = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertTrue(content.contains("// >>> project-switcher"), "Should inject block into empty file")
        XCTAssertTrue(content.contains("PS:empty-file-proj"), "Should contain project id")
    }

    // MARK: - writeLocalSettings: returns error on write failure

    func testWriteLocalSettingsReturnsErrorOnWriteFailure() throws {
        let failingFS = SettingsFailingFileSystem()
        let manager = PsVSCodeSettingsManager(fileSystem: failingFS)

        let tempDir = try makeTempDir()
        defer { cleanup(tempDir) }

        let result = manager.writeLocalSettings(projectPath: tempDir.path, identifier: "test")

        if case .success = result {
            XCTFail("Expected failure")
        }
        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Failed to write .vscode/settings.json"))
        }
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsMgrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
