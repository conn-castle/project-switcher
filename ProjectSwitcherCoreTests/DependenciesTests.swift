import XCTest

@testable import ProjectSwitcherCore

final class DependenciesTests: XCTestCase {
    private final class FileManagerMissingSizeAttribute: FileManager {
        override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
            // Intentionally omit `.size` to exercise DefaultFileSystem's error branch.
            [.creationDate: Date()]
        }
    }

    private final class ControlledSearchRootsFileManager: FileManager {
        private let appRoots: [URL]
        private let homeURL: URL

        private(set) var urlsCallCount: Int = 0

        init(appRoots: [URL], homeURL: URL) {
            self.appRoots = appRoots
            self.homeURL = homeURL
            super.init()
        }

        override var homeDirectoryForCurrentUser: URL { homeURL }

        override func urls(
            for directory: FileManager.SearchPathDirectory,
            in domainMask: FileManager.SearchPathDomainMask
        ) -> [URL] {
            urlsCallCount += 1
            guard directory == .applicationDirectory else { return [] }
            // Include at least one default fallback root so applicationSearchRoots() exercises its
            // de-duplication logic without requiring the test to scan real system directories.
            return appRoots
        }

        override func fileExists(
            atPath path: String,
            isDirectory: UnsafeMutablePointer<ObjCBool>?
        ) -> Bool {
            // Only allow real filesystem probing under our temp roots; otherwise short-circuit to
            // avoid scanning the host system.
            if appRoots.contains(where: { path.hasPrefix($0.path) }) || path.hasPrefix(homeURL.path) {
                return super.fileExists(atPath: path, isDirectory: isDirectory)
            }
            if let isDirectory { isDirectory.pointee = false }
            return false
        }

        override func contentsOfDirectory(
            at url: URL,
            includingPropertiesForKeys keys: [URLResourceKey]?,
            options mask: FileManager.DirectoryEnumerationOptions
        ) throws -> [URL] {
            // Only enumerate under the temp roots; everything else is treated as empty.
            if appRoots.contains(where: { url.path.hasPrefix($0.path) }) || url.path.hasPrefix(homeURL.path) {
                return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
            }
            return []
        }
    }

    func testCapturedFocusEquatable() {
        let a = CapturedFocus(windowId: 1, appBundleId: "com.example.app", workspace: "main")
        let b = CapturedFocus(windowId: 1, appBundleId: "com.example.app", workspace: "main")
        let c = CapturedFocus(windowId: 2, appBundleId: "com.example.app", workspace: "main")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testDefaultFileSystemWriteReadExistsAndSize() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try fs.createDirectory(at: tmp)
        XCTAssertTrue(fs.fileExists(at: tmp))

        let fileURL = tmp.appendingPathComponent("file.txt")
        let data = Data("hello".utf8)
        try fs.writeFile(at: fileURL, data: data)

        XCTAssertTrue(fs.fileExists(at: fileURL))
        XCTAssertEqual(try fs.readFile(at: fileURL), data)
        XCTAssertEqual(try fs.fileSize(at: fileURL), UInt64(data.count))
    }

    func testDefaultFileSystemFileSizeThrowsWhenSizeAttributeMissing() {
        let fs = DefaultFileSystem(fileManager: FileManagerMissingSizeAttribute())
        let fileURL = URL(fileURLWithPath: "/tmp/project-switcher-tests-nonexistent-\(UUID().uuidString)")

        XCTAssertThrowsError(try fs.fileSize(at: fileURL)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "DefaultFileSystem")
            XCTAssertEqual(nsError.code, 1)
            XCTAssertTrue(nsError.localizedDescription.contains("File size unavailable"))
        }
    }

    func testDefaultFileSystemAppendCreatesFileWhenMissing() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let fileURL = tmp.appendingPathComponent("append.txt")
        XCTAssertFalse(fs.fileExists(at: fileURL))

        try fs.appendFile(at: fileURL, data: Data("a".utf8))
        try fs.appendFile(at: fileURL, data: Data("b".utf8))

        XCTAssertEqual(String(decoding: try fs.readFile(at: fileURL), as: UTF8.self), "ab")
    }

    func testDefaultFileSystemAppendAppendsWhenExisting() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let fileURL = tmp.appendingPathComponent("append-existing.txt")
        try fs.writeFile(at: fileURL, data: Data("x".utf8))

        try fs.appendFile(at: fileURL, data: Data("y".utf8))

        XCTAssertEqual(String(decoding: try fs.readFile(at: fileURL), as: UTF8.self), "xy")
    }

    func testDefaultFileSystemMoveAndRemove() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let src = tmp.appendingPathComponent("src.txt")
        let dst = tmp.appendingPathComponent("dst.txt")
        try fs.writeFile(at: src, data: Data("data".utf8))

        try fs.moveItem(at: src, to: dst)
        XCTAssertFalse(fs.fileExists(at: src))
        XCTAssertTrue(fs.fileExists(at: dst))

        try fs.removeItem(at: dst)
        XCTAssertFalse(fs.fileExists(at: dst))
    }

    func testDefaultFileSystemIsExecutableFileReflectsPermissions() throws {
        let fs = DefaultFileSystem()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try fs.createDirectory(at: tmp)

        let fileURL = tmp.appendingPathComponent("tool")
        try fs.writeFile(at: fileURL, data: Data("#!/bin/sh\necho hi\n".utf8))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
        XCTAssertFalse(fs.isExecutableFile(at: fileURL))

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
        XCTAssertTrue(fs.isExecutableFile(at: fileURL))
    }

    func testLaunchServicesAppDiscoveryApplicationURLBundleIdentifierUnknownReturnsNil() {
        let discovery = LaunchServicesAppDiscovery()
        XCTAssertNil(discovery.applicationURL(bundleIdentifier: "com.projectswitcher.tests.nonexistent.bundle"))
    }

    func testLaunchServicesAppDiscoveryWithoutOverrideUsesApplicationSearchRootsAndFindsDirectMatch() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let appURL = tmp.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let fm = ControlledSearchRootsFileManager(appRoots: [tmp, URL(fileURLWithPath: "/Applications", isDirectory: true)], homeURL: tmp)
        let discovery = LaunchServicesAppDiscovery(fileManager: fm, searchRootsOverride: nil)

        let found = discovery.applicationURL(named: "Foo")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
        XCTAssertEqual(fm.urlsCallCount, 1)
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedFindsDirectMatchAtRoot() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let appURL = tmp.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        let found = discovery.applicationURL(named: "Foo")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedFindsDirectMatchInUtilities() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let utilitiesURL = tmp.appendingPathComponent("Utilities", isDirectory: true)
        try FileManager.default.createDirectory(at: utilitiesURL, withIntermediateDirectories: true)
        let appURL = utilitiesURL.appendingPathComponent("Bar.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        let found = discovery.applicationURL(named: "Bar")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedFindsViaShallowSearch() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let nested = tmp.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let appURL = nested.appendingPathComponent("Baz.app", isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        let found = discovery.applicationURL(named: "Baz")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.resolvingSymlinksInPath().path, appURL.resolvingSymlinksInPath().path)
    }

    func testLaunchServicesAppDiscoveryApplicationURLNamedReturnsNilWhenNotFound() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        XCTAssertNil(discovery.applicationURL(named: "DoesNotExist"))
    }

    func testLaunchServicesAppDiscoveryBundleIdentifierReturnsNilForNonBundleDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let discovery = LaunchServicesAppDiscovery(searchRootsOverride: [tmp])
        XCTAssertNil(discovery.bundleIdentifier(forApplicationAt: tmp))
    }

    func testCarbonHotkeyCheckerReturnsConsistentShape() {
        let checker = CarbonHotkeyChecker()
        let result = checker.checkCommandShiftSpace()

        // Deterministic invariant: success implies nil errorCode; failure implies non-nil errorCode.
        if result.isAvailable {
            XCTAssertNil(result.errorCode)
        } else {
            XCTAssertNotNil(result.errorCode)
        }
    }

    func testSystemDateProviderNowIsCloseToCurrentTime() {
        let provider = SystemDateProvider()
        let before = Date()
        let now = provider.now()
        let after = Date()

        XCTAssertGreaterThanOrEqual(now.timeIntervalSince1970, before.timeIntervalSince1970)
        XCTAssertLessThanOrEqual(now.timeIntervalSince1970, after.timeIntervalSince1970)
    }

    func testProcessEnvironmentReadsValues() {
        setenv("PROJECT_SWITCHER_TEST_ENV", "value", 1)

        let env = ProcessEnvironment()
        XCTAssertEqual(env.value(forKey: "PROJECT_SWITCHER_TEST_ENV"), "value")
        XCTAssertEqual(env.allValues()["PROJECT_SWITCHER_TEST_ENV"], "value")
    }
}

// MARK: - Shared Test Doubles

final class MockALCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    var calls: [Call] = []
    var results: [Result<PsCommandResult, PsCoreError>] = []

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        calls.append(Call(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        guard !results.isEmpty else {
            return .failure(PsCoreError(message: "MockALCommandRunner: no results left"))
        }
        return results.removeFirst()
    }
}

struct ALSelectiveFileSystem: FileSystem {
    let executablePaths: Set<String>

    func fileExists(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}

struct FailingWorkspaceFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { true }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
}

final class SharedVSCodeCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String?
    }

    var calls: [Call] = []
    var results: [Result<PsCommandResult, PsCoreError>] = []

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        calls.append(Call(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        guard !results.isEmpty else {
            return .failure(PsCoreError(message: "SharedVSCodeCommandRunner: no results left"))
        }
        return results.removeFirst()
    }
}

struct FailingSettingsFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { true }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Disk full"])
    }
}
