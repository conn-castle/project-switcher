import XCTest
@testable import ProjectSwitcherCore

final class ExecutableResolverTests: XCTestCase {

    func testResolveStandardExecutable() {
        let resolver = ExecutableResolver()

        // /bin/echo should always exist
        let result = resolver.resolve("echo")

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("/echo") ?? false)
    }

    func testResolveAbsolutePath() {
        let resolver = ExecutableResolver()

        // Absolute path should be returned as-is if executable
        let result = resolver.resolve("/bin/echo")

        XCTAssertEqual(result, "/bin/echo")
    }

    func testResolveNonExistentAbsolutePath() {
        let resolver = ExecutableResolver()

        let result = resolver.resolve("/this/path/does/not/exist/foo")

        XCTAssertNil(result)
    }

    func testResolveNonExistentExecutable() {
        let resolver = ExecutableResolver()

        let result = resolver.resolve("this-executable-definitely-does-not-exist-12345")

        XCTAssertNil(result)
    }

    func testResolveHomebrewExecutable() {
        let resolver = ExecutableResolver()

        // If brew is installed, it should be found
        let result = resolver.resolve("brew")

        // This test may pass or fail depending on the environment
        // If brew is installed, it should be found in /opt/homebrew/bin or /usr/local/bin
        if result != nil {
            XCTAssertTrue(
                result!.contains("/brew"),
                "Brew path should contain /brew: \(result!)"
            )
        }
    }

    func testResolveWithCustomSearchPaths() {
        // Create resolver with only /bin in search path
        let resolver = ExecutableResolver(
            searchPaths: ["/bin"]
        )

        // echo should still be found in /bin
        let result = resolver.resolve("echo")

        XCTAssertEqual(result, "/bin/echo")
    }

    func testResolveWithMockFileSystem() {
        // Test with mock file system to verify search order
        let mockFS = MockFileSystem(
            executablePaths: [
                "/usr/local/bin/testcmd",
                "/opt/homebrew/bin/testcmd"
            ]
        )
        let resolver = ExecutableResolver(fileSystem: mockFS)

        let result = resolver.resolve("testcmd")

        // Should find in first matching path (/opt/homebrew/bin comes first in default order)
        XCTAssertEqual(result, "/opt/homebrew/bin/testcmd")
    }

    func testStandardSearchPathsOrder() {
        // Verify standard paths are in expected order (Homebrew first for Apple Silicon)
        let paths = ExecutableResolver.standardSearchPaths

        XCTAssertTrue(paths.count >= 4)
        XCTAssertEqual(paths[0], "/opt/homebrew/bin")
        XCTAssertEqual(paths[1], "/usr/local/bin")
        XCTAssertEqual(paths[2], "/usr/bin")
        XCTAssertEqual(paths[3], "/bin")
    }
    // MARK: - Login Shell Timeout Validation

    func testIsValidLoginShellTimeoutAcceptsPositiveFiniteValues() {
        XCTAssertTrue(ExecutableResolver.isValidLoginShellTimeout(0.001))
        XCTAssertTrue(ExecutableResolver.isValidLoginShellTimeout(1.0))
        XCTAssertTrue(ExecutableResolver.isValidLoginShellTimeout(5.0))
        XCTAssertTrue(ExecutableResolver.isValidLoginShellTimeout(100.0))
    }

    func testIsValidLoginShellTimeoutRejectsZero() {
        XCTAssertFalse(ExecutableResolver.isValidLoginShellTimeout(0))
    }

    func testIsValidLoginShellTimeoutRejectsNegativeValues() {
        XCTAssertFalse(ExecutableResolver.isValidLoginShellTimeout(-1.0))
        XCTAssertFalse(ExecutableResolver.isValidLoginShellTimeout(-0.001))
    }

    func testIsValidLoginShellTimeoutRejectsInfinity() {
        XCTAssertFalse(ExecutableResolver.isValidLoginShellTimeout(.infinity))
        XCTAssertFalse(ExecutableResolver.isValidLoginShellTimeout(-.infinity))
    }

    func testIsValidLoginShellTimeoutRejectsNaN() {
        XCTAssertFalse(ExecutableResolver.isValidLoginShellTimeout(.nan))
    }
}

// MARK: - Test Doubles

private struct MockFileSystem: FileSystem {
    let executablePaths: Set<String>

    init(executablePaths: [String]) {
        self.executablePaths = Set(executablePaths)
    }

    func fileExists(at url: URL) -> Bool {
        executablePaths.contains(url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        false
    }

    func isExecutableFile(at url: URL) -> Bool {
        executablePaths.contains(url.path)
    }

    func readFile(at url: URL) throws -> Data {
        throw NSError(domain: "MockFileSystem", code: 1, userInfo: nil)
    }

    func createDirectory(at url: URL) throws {}

    func fileSize(at url: URL) throws -> UInt64 {
        0
    }

    func removeItem(at url: URL) throws {}

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}

    func appendFile(at url: URL, data: Data) throws {}

    func writeFile(at url: URL, data: Data) throws {}
}
