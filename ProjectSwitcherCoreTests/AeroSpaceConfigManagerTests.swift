import XCTest

@testable import ProjectSwitcherCore

final class AeroSpaceConfigManagerTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testConfigStatusMissingWhenNoFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent(".aerospace.toml").path
        let backupPath = dir.appendingPathComponent(".aerospace.toml.backup").path
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configPath,
            backupPath: backupPath,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .missing)
    }

    func testConfigStatusManagedByProjectSwitcherWhenMarkerPresent() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "\(AeroSpaceConfigManager.managedByMarker)\nfoo = 1\n".write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .managedByProjectSwitcher)
    }

    func testConfigStatusExternalConfigWhenMarkerMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "foo = 1\n".write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .externalConfig)
    }

    func testConfigStatusUnknownWhenConfigReadFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point configPath at a directory so reading as a file fails.
        let configDirURL = dir.appendingPathComponent(".aerospace.toml", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configDirURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configStatus(), .unknown)
    }

    func testWriteSafeConfigFailsWhenTemplateMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent(".aerospace.toml").path
        let backupPath = dir.appendingPathComponent(".backup").path
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configPath,
            backupPath: backupPath,
            safeConfigLoader: { nil }
        )

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when safe config template is missing")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testWriteSafeConfigFailsWhenTemplateMissingUsingDefaultBundleLoader() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configPath = dir.appendingPathComponent(".aerospace.toml").path
        let backupPath = dir.appendingPathComponent(".backup").path

        // Do not use `AeroSpaceConfigManager()` here; its default config path points at the user's home.
        // This test uses a temp config path but exercises the default bundle-loader closure.
        let manager = AeroSpaceConfigManager(fileManager: .default, configPath: configPath, backupPath: backupPath)

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when safe config template is missing from bundle")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testWriteSafeConfigFailsWhenTemplateMissingUsingPublicInit() {
        // Safety: AeroSpaceConfigManager() points at ~/.aerospace.toml. This test is only safe if the
        // safe template is missing from the test bundle, causing writeSafeConfig() to return early
        // without reading or writing the config file.
        XCTAssertNil(
            Bundle.main.url(forResource: "aerospace-safe", withExtension: "toml"),
            "This test assumes aerospace-safe.toml is missing from the test bundle; if it's present, rewrite the test to avoid touching the user's home directory."
        )

        let manager = AeroSpaceConfigManager()
        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when safe config template is missing from bundle")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testWriteSafeConfigWritesConfigWhenMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let backupURL = dir.appendingPathComponent(".backup")
        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nfoo = 1\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: backupURL.path,
            safeConfigLoader: { safeConfig }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))

        switch manager.writeSafeConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), safeConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testWriteSafeConfigBacksUpExternalConfigAndOverwrites() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let backupURL = dir.appendingPathComponent(".backup")

        let external = "external = true\n"
        try external.write(to: configURL, atomically: true, encoding: .utf8)
        try "old backup".write(to: backupURL, atomically: true, encoding: .utf8)

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nmanaged = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: backupURL.path,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), safeConfig)
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), external)
    }

    func testWriteSafeConfigDoesNotBackUpWhenAlreadyManaged() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let backupURL = dir.appendingPathComponent(".backup")

        try "\(AeroSpaceConfigManager.managedByMarker)\nold = true\n".write(to: configURL, atomically: true, encoding: .utf8)
        try "keep backup".write(to: backupURL, atomically: true, encoding: .utf8)

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nnew = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: backupURL.path,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), safeConfig)
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), "keep backup")
    }

    func testWriteSafeConfigFailsWhenBackupCopyFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "external = true\n".write(to: configURL, atomically: true, encoding: .utf8)

        // Destination directory does not exist, so copyItem should fail.
        let badBackupPath = dir.appendingPathComponent("missing-dir/backup.toml").path

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nmanaged = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: badBackupPath,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when backup copy fails")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    // MARK: - configContents()

    func testConfigContentsReturnsContentsWhenFileExists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let expected = "\(AeroSpaceConfigManager.managedByMarker)\nalt-tab = 'focus'\n"
        try expected.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertEqual(manager.configContents(), expected)
    }

    func testConfigContentsReturnsNilWhenFileMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: dir.appendingPathComponent(".aerospace.toml").path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertNil(manager.configContents())
    }

    func testConfigContentsReturnsNilWhenFileUnreadable() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point configPath at a directory so reading as a file fails.
        let configDirURL = dir.appendingPathComponent(".aerospace.toml", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configDirURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        XCTAssertNil(manager.configContents())
    }

    // MARK: - writeSafeConfig failure cases

    func testWriteSafeConfigFailsWhenWritingConfigFails() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point configPath at a directory so writing as a file fails.
        let configDirURL = dir.appendingPathComponent(".aerospace.toml", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)

        let safeConfig = "\(AeroSpaceConfigManager.managedByMarker)\nmanaged = true\n"
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configDirURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { safeConfig }
        )

        switch manager.writeSafeConfig() {
        case .success:
            XCTFail("Expected failure when writing config fails")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    // MARK: - parseConfigVersion

    func testParseConfigVersionFromValidConfig() {
        let content = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 3
        config-version = 2
        """
        XCTAssertEqual(AeroSpaceConfigManager.parseConfigVersion(from: content), 3)
    }

    func testParseConfigVersionMissingLine() {
        let content = """
        \(AeroSpaceConfigManager.managedByMarker)
        # Purpose: old config without version
        config-version = 2
        """
        XCTAssertNil(AeroSpaceConfigManager.parseConfigVersion(from: content))
    }

    func testParseConfigVersionInvalidFormat() {
        let content = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: abc
        """
        XCTAssertNil(AeroSpaceConfigManager.parseConfigVersion(from: content))
    }

    // MARK: - extractUserSection

    func testExtractUserSectionWithContent() {
        let content = """
        [mode.main.binding]
        alt-tab = 'focus dfs-next'
        # >>> user-keybindings
        alt-a = 'workspace 1'
        alt-b = 'workspace 2'
        # <<< user-keybindings
        """
        let section = AeroSpaceConfigManager.extractUserSection(
            from: content,
            startMarker: AeroSpaceConfigManager.userKeybindingsStart,
            endMarker: AeroSpaceConfigManager.userKeybindingsEnd
        )
        XCTAssertEqual(section, "alt-a = 'workspace 1'\nalt-b = 'workspace 2'")
    }

    func testExtractUserSectionEmpty() {
        let content = """
        # >>> user-keybindings
        # Add your custom keybindings below. ProjectSwitcher preserves this section across updates.
        # <<< user-keybindings
        """
        let section = AeroSpaceConfigManager.extractUserSection(
            from: content,
            startMarker: AeroSpaceConfigManager.userKeybindingsStart,
            endMarker: AeroSpaceConfigManager.userKeybindingsEnd
        )
        XCTAssertEqual(section, "# Add your custom keybindings below. ProjectSwitcher preserves this section across updates.")
    }

    func testExtractUserSectionMissing() {
        let content = """
        \(AeroSpaceConfigManager.managedByMarker)
        config-version = 2
        """
        let section = AeroSpaceConfigManager.extractUserSection(
            from: content,
            startMarker: AeroSpaceConfigManager.userKeybindingsStart,
            endMarker: AeroSpaceConfigManager.userKeybindingsEnd
        )
        XCTAssertNil(section)
    }

    func testExtractUserSectionFromNilContent() {
        let section = AeroSpaceConfigManager.extractUserSection(
            from: nil,
            startMarker: AeroSpaceConfigManager.userKeybindingsStart,
            endMarker: AeroSpaceConfigManager.userKeybindingsEnd
        )
        XCTAssertNil(section)
    }

    // MARK: - replaceUserSection

    func testReplaceUserSectionInsertsContent() {
        let template = """
        [mode.main.binding]
        alt-tab = 'focus dfs-next'
        # >>> user-keybindings
        # Add your custom keybindings below. ProjectSwitcher preserves this section across updates.
        # <<< user-keybindings
        """
        let result = AeroSpaceConfigManager.replaceUserSection(
            in: template,
            startMarker: AeroSpaceConfigManager.userKeybindingsStart,
            endMarker: AeroSpaceConfigManager.userKeybindingsEnd,
            with: "alt-a = 'workspace 1'\nalt-b = 'workspace 2'"
        )
        XCTAssertTrue(result.contains("alt-a = 'workspace 1'"))
        XCTAssertTrue(result.contains("alt-b = 'workspace 2'"))
        XCTAssertTrue(result.contains(AeroSpaceConfigManager.userKeybindingsStart))
        XCTAssertTrue(result.contains(AeroSpaceConfigManager.userKeybindingsEnd))
        XCTAssertFalse(result.contains("Add your custom keybindings"))
    }

    func testReplaceUserSectionNoMarkersReturnsOriginal() {
        let content = "no markers here\n"
        let result = AeroSpaceConfigManager.replaceUserSection(
            in: content,
            startMarker: AeroSpaceConfigManager.userKeybindingsStart,
            endMarker: AeroSpaceConfigManager.userKeybindingsEnd,
            with: "new content"
        )
        XCTAssertEqual(result, content)
    }

    // MARK: - templateVersion / currentConfigVersion

    func testTemplateVersionReturnsVersionFromLoader() {
        let template = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 5
        config-version = 2
        """
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: "/nonexistent",
            backupPath: "/nonexistent",
            safeConfigLoader: { template }
        )
        XCTAssertEqual(manager.templateVersion(), 5)
    }

    func testTemplateVersionReturnsNilWhenLoaderReturnsNil() {
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: "/nonexistent",
            backupPath: "/nonexistent",
            safeConfigLoader: { nil }
        )
        XCTAssertNil(manager.templateVersion())
    }

    func testCurrentConfigVersionReturnsVersionFromFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let content = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 2
        config-version = 2
        """
        try content.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )
        XCTAssertEqual(manager.currentConfigVersion(), 2)
    }

    func testCurrentConfigVersionReturnsNilWhenFileMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: dir.appendingPathComponent(".aerospace.toml").path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )
        XCTAssertNil(manager.currentConfigVersion())
    }

    // MARK: - updateManagedConfig

    func testUpdateManagedConfigPreservesUserSections() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let oldConfig = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 1
        [mode.main.binding]
        alt-tab = 'old command'
        # >>> user-keybindings
        alt-a = 'workspace 1'
        # <<< user-keybindings
        [[on-window-detected]]
        run = 'layout floating'
        # >>> user-config
        [gaps]
        inner.horizontal = 10
        # <<< user-config
        """
        try oldConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let template = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 2
        [mode.main.binding]
        alt-tab = 'new command'
        # >>> user-keybindings
        # placeholder
        # <<< user-keybindings
        [[on-window-detected]]
        run = 'layout floating'
        # >>> user-config
        # placeholder
        # <<< user-config
        """
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { template }
        )

        switch manager.updateManagedConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        let updated = try String(contentsOf: configURL, encoding: .utf8)
        // Template content should be present
        XCTAssertTrue(updated.contains("ps-config-version: 2"))
        XCTAssertTrue(updated.contains("alt-tab = 'new command'"))
        // User keybindings should be preserved
        XCTAssertTrue(updated.contains("alt-a = 'workspace 1'"))
        // User config should be preserved
        XCTAssertTrue(updated.contains("inner.horizontal = 10"))
        // Template placeholder should be gone
        XCTAssertFalse(updated.contains("# placeholder"))
    }

    func testUpdateManagedConfigHandlesPreMigrationConfig() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        // Old config without markers or version
        let oldConfig = """
        \(AeroSpaceConfigManager.managedByMarker)
        [mode.main.binding]
        alt-tab = 'old command'
        """
        try oldConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let template = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 1
        [mode.main.binding]
        alt-tab = 'new command'
        # >>> user-keybindings
        # default placeholder
        # <<< user-keybindings
        # >>> user-config
        # default placeholder
        # <<< user-config
        """
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { template }
        )

        switch manager.updateManagedConfig() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        let updated = try String(contentsOf: configURL, encoding: .utf8)
        // Should have the new template content
        XCTAssertTrue(updated.contains("ps-config-version: 1"))
        XCTAssertTrue(updated.contains("alt-tab = 'new command'"))
        // Default placeholders should be in place since old config had no markers
        XCTAssertTrue(updated.contains("# default placeholder"))
    }

    func testUpdateManagedConfigFailsWhenTemplateMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "\(AeroSpaceConfigManager.managedByMarker)\nold\n".write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        switch manager.updateManagedConfig() {
        case .success:
            XCTFail("Expected failure when template is missing")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    // MARK: - ensureUpToDate

    func testEnsureUpToDateWritesFreshOnMissing() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let template = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 1
        config-version = 2
        """
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { template }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))

        switch manager.ensureUpToDate() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let result):
            XCTAssertEqual(result, .freshInstall)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testEnsureUpToDateSkipsCurrentVersion() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let content = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 1
        config-version = 2
        """
        try content.write(to: configURL, atomically: true, encoding: .utf8)

        let template = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 1
        config-version = 2
        new-template-content = true
        """
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { template }
        )

        switch manager.ensureUpToDate() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let result):
            XCTAssertEqual(result, .alreadyCurrent)
        }

        // File should be unchanged
        let actual = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertEqual(actual, content)
    }

    func testEnsureUpToDateUpdatesStaleVersion() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let oldContent = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 1
        [mode.main.binding]
        alt-tab = 'old'
        # >>> user-keybindings
        alt-x = 'custom'
        # <<< user-keybindings
        # >>> user-config
        # <<< user-config
        """
        try oldContent.write(to: configURL, atomically: true, encoding: .utf8)

        let template = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 2
        [mode.main.binding]
        alt-tab = 'new'
        # >>> user-keybindings
        # placeholder
        # <<< user-keybindings
        # >>> user-config
        # placeholder
        # <<< user-config
        """
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { template }
        )

        switch manager.ensureUpToDate() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let result):
            XCTAssertEqual(result, .updated(fromVersion: 1, toVersion: 2))
        }

        let updated = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("ps-config-version: 2"))
        XCTAssertTrue(updated.contains("alt-tab = 'new'"))
        XCTAssertTrue(updated.contains("alt-x = 'custom'"))
    }

    func testEnsureUpToDateSkipsExternalConfig() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        let external = "external config\n"
        try external.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { "\(AeroSpaceConfigManager.managedByMarker)\n# ps-config-version: 1\n" }
        )

        switch manager.ensureUpToDate() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let result):
            XCTAssertEqual(result, .skippedExternal)
        }

        // File should be unchanged
        XCTAssertEqual(try String(contentsOf: configURL, encoding: .utf8), external)
    }

    func testEnsureUpToDateUpdatesConfigWithNoVersion() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        // Managed config but no version line (pre-migration)
        let oldContent = """
        \(AeroSpaceConfigManager.managedByMarker)
        config-version = 2
        """
        try oldContent.write(to: configURL, atomically: true, encoding: .utf8)

        let template = """
        \(AeroSpaceConfigManager.managedByMarker)
        # ps-config-version: 1
        config-version = 2
        # >>> user-keybindings
        # placeholder
        # <<< user-keybindings
        # >>> user-config
        # placeholder
        # <<< user-config
        """
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { template }
        )

        switch manager.ensureUpToDate() {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success(let result):
            XCTAssertEqual(result, .updated(fromVersion: 0, toVersion: 1))
        }
    }

    func testEnsureUpToDateFailsWhenTemplateHasNoVersion() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "\(AeroSpaceConfigManager.managedByMarker)\nold\n".write(to: configURL, atomically: true, encoding: .utf8)

        // Template without a version line — broken bundle
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { "\(AeroSpaceConfigManager.managedByMarker)\nno version\n" }
        )

        switch manager.ensureUpToDate() {
        case .success:
            XCTFail("Expected failure when template has no version")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testEnsureUpToDateFailsWhenTemplateLoaderReturnsNil() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appendingPathComponent(".aerospace.toml")
        try "\(AeroSpaceConfigManager.managedByMarker)\nold\n".write(to: configURL, atomically: true, encoding: .utf8)

        // Template loader returns nil — template missing from bundle
        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { nil }
        )

        switch manager.ensureUpToDate() {
        case .success:
            XCTFail("Expected failure when template is missing")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

    func testEnsureUpToDateFailsOnUnknownConfigStatus() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point configPath at a directory so reading as a file fails → .unknown status
        let configDirURL = dir.appendingPathComponent(".aerospace.toml", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirURL, withIntermediateDirectories: true)

        let manager = AeroSpaceConfigManager(
            fileManager: .default,
            configPath: configDirURL.path,
            backupPath: dir.appendingPathComponent(".backup").path,
            safeConfigLoader: { "\(AeroSpaceConfigManager.managedByMarker)\n# ps-config-version: 1\n" }
        )

        XCTAssertEqual(manager.configStatus(), .unknown)

        switch manager.ensureUpToDate() {
        case .success:
            XCTFail("Expected failure for .unknown config status")
        case .failure(let error):
            XCTAssertEqual(error.category, .fileSystem)
        }
    }

}
