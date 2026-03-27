import XCTest
import Foundation
import Darwin
@testable import ProjectSwitcherCore

final class SystemCommandRunnerAugmentedEnvironmentTests: XCTestCase {

    // MARK: - buildAugmentedEnvironment

    func testAugmentedEnvironmentContainsStandardPaths() {
        // Resolver with login shell disabled — only standard paths + current process PATH
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = PsSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present in augmented environment")
            return
        }

        let components = path.split(separator: ":").map(String.init)

        // Standard paths should appear at the start (in order)
        for standardPath in ExecutableResolver.standardSearchPaths {
            XCTAssertTrue(
                components.contains(standardPath),
                "Standard path \(standardPath) should be in augmented PATH"
            )
        }

        // First entries should be the standard search paths
        for (index, standardPath) in ExecutableResolver.standardSearchPaths.enumerated() {
            guard index < components.count else {
                XCTFail("Not enough PATH entries to match standard paths")
                return
            }
            XCTAssertEqual(
                components[index],
                standardPath,
                "Standard path at index \(index) should be \(standardPath)"
            )
        }
    }

    func testAugmentedEnvironmentPreservesProcessPATH() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = PsSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let augmentedPath = env["PATH"] else {
            XCTFail("PATH should be present")
            return
        }

        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let currentComponents = currentPath.split(separator: ":").map(String.init)
        let augmentedComponents = Set(augmentedPath.split(separator: ":").map(String.init))

        // All non-empty entries from the current process PATH should be in the augmented PATH
        for component in currentComponents where !component.isEmpty {
            XCTAssertTrue(
                augmentedComponents.contains(component),
                "Current process PATH entry '\(component)' should be preserved in augmented PATH"
            )
        }
    }

    func testAugmentedEnvironmentDeduplicatesPaths() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = PsSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present")
            return
        }

        let components = path.split(separator: ":").map(String.init)
        let unique = Set(components)

        // Every entry should be unique (no duplicates)
        XCTAssertEqual(
            components.count,
            unique.count,
            "Augmented PATH should have no duplicate entries"
        )
    }

    func testAugmentedEnvironmentHasNoConsecutiveColons() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = PsSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present")
            return
        }

        // Consecutive colons (::) indicate empty PATH entries, which cause
        // shells to interpret "" as the current directory — a security concern.
        XCTAssertFalse(path.contains("::"), "PATH should not contain consecutive colons (empty entries)")
        XCTAssertFalse(path.hasPrefix(":"), "PATH should not start with a colon")
        XCTAssertFalse(path.hasSuffix(":"), "PATH should not end with a colon")
    }

    func testAugmentedEnvironmentPreservesNonPATHVariables() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = PsSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        // HOME should be preserved from the process environment
        let expectedHome = ProcessInfo.processInfo.environment["HOME"]
        XCTAssertEqual(env["HOME"], expectedHome, "Non-PATH environment variables should be preserved")
    }

    func testAugmentedEnvironmentWorksWhenProcessPATHIsMissing() {
        shellEnvLock.lock()
        defer { shellEnvLock.unlock() }

        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        defer {
            if let originalPath {
                setenv("PATH", originalPath, 1)
            } else {
                unsetenv("PATH")
            }
        }

        unsetenv("PATH")

        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let env = PsSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

        guard let path = env["PATH"] else {
            XCTFail("PATH should be present in augmented environment")
            return
        }
        XCTAssertFalse(path.isEmpty)
        XCTAssertFalse(path.contains("::"))
    }

    func testAugmentedEnvironmentIncludesLoginShellPATHWhenAvailable() throws {
        let expectedShellPath = "/custom/bin:/usr/bin:/bin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AugmentedPATHShellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\necho \"\(expectedShellPath)\"\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let env = PsSystemCommandRunner.buildAugmentedEnvironment(resolver: resolver)

            guard let path = env["PATH"] else {
                XCTFail("PATH should be present")
                return
            }

            let components = path.split(separator: ":").map(String.init)
            XCTAssertTrue(components.contains("/custom/bin"))
        }
    }
}
