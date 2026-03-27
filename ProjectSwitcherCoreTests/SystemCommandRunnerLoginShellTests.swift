import XCTest
import Foundation
import Darwin
@testable import ProjectSwitcherCore

final class SystemCommandRunnerLoginShellTests: XCTestCase {

    // MARK: - resolveLoginShellPath

    func testResolveLoginShellPathReturnsNonNilPathWhenEnabled() throws {
        // Avoid relying on the developer's real shell init files (which may be slow or fail).
        // Instead, point $SHELL at a tiny script that prints a deterministic PATH.
        let expectedPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\necho \"\(expectedPath)\"\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        let originalShell = ProcessInfo.processInfo.environment["SHELL"]
        defer {
            if let originalShell {
                setenv("SHELL", originalShell, 1)
            } else {
                unsetenv("SHELL")
            }
            try? FileManager.default.removeItem(at: tempDir)
        }
        setenv("SHELL", shellURL.path, 1)

        let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
        let path = resolver.resolveLoginShellPath()
        XCTAssertEqual(path, expectedPath)
    }

    func testResolveLoginShellPathReturnsNilWhenDisabled() {
        let resolver = ExecutableResolver(loginShellFallbackEnabled: false)
        let path = resolver.resolveLoginShellPath()

        XCTAssertNil(path, "Login shell PATH should be nil when fallback is disabled")
    }

    func testResolveLoginShellPathUsesFallbackWhenShellEnvIsNotAbsolute() throws {
        withShell("zsh") {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let path = resolver.resolveLoginShellPath()

            XCTAssertNotNil(path)
            XCTAssertFalse(path?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    func testResolveLoginShellPathReturnsNilWhenShellExecutableMissing() throws {
        withShell("/this/does/not/exist") {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolveLoginShellPath())
        }
    }

    func testResolveLoginShellPathReturnsNilWhenShellExitsNonZero() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellNonZeroTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\nexit 1\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolveLoginShellPath())
        }
    }

    func testResolveLoginShellPathReturnsNilWhenShellOutputsEmptyString() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellEmptyOutputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\nexit 0\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolveLoginShellPath())
        }
    }

    // MARK: - Fish shell PATH resolution

    func testIsFishShellReturnsTrueWhenShellIsFish() {
        withShell("/usr/local/bin/fish") {
            XCTAssertTrue(ExecutableResolver.isFishShell)
        }
    }

    func testIsFishShellReturnsFalseForZsh() {
        withShell("/bin/zsh") {
            XCTAssertFalse(ExecutableResolver.isFishShell)
        }
    }

    func testIsFishShellReturnsFalseForBash() {
        withShell("/bin/bash") {
            XCTAssertFalse(ExecutableResolver.isFishShell)
        }
    }

    func testIsFishShellReturnsFalseForNonAbsolutePath() {
        // Non-absolute SHELL falls back to /bin/zsh, which is not fish
        withShell("fish") {
            XCTAssertFalse(ExecutableResolver.isFishShell)
        }
    }

    func testResolveLoginShellPathUsesStringJoinForFish() throws {
        // Simulate a fish shell that receives "string join : $PATH" and emits colon-separated output.
        // The stub script gates on the command argument: only succeeds if it contains "string join".
        // This ensures a regression back to "echo $PATH" would cause a test failure.
        let expectedPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FishShellPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Name the stub "fish" so loginShellPath.hasSuffix("/fish") is true
        let shellURL = tempDir.appendingPathComponent("fish", isDirectory: false)
        // The stub receives: -l -c "<command>"
        // $3 is the command. Only succeed if it contains "string join" (fish-specific).
        let script = """
            #!/bin/sh
            case "$3" in
              *"string join"*) echo "\(expectedPath)" ;;
              *) exit 1 ;;
            esac
            """
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            XCTAssertTrue(ExecutableResolver.isFishShell, "Shell path should be detected as fish")
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let path = resolver.resolveLoginShellPath()
            XCTAssertEqual(path, expectedPath)
        }
    }

    func testAugmentedEnvironmentIncludesFishShellPATH() throws {
        let expectedShellPath = "/fish/custom/bin:/usr/bin:/bin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FishAugmentedPATHTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("fish", isDirectory: false)
        // Gate on "string join" to catch regressions
        let script = """
            #!/bin/sh
            case "$3" in
              *"string join"*) echo "\(expectedShellPath)" ;;
              *) exit 1 ;;
            esac
            """
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
            XCTAssertTrue(components.contains("/fish/custom/bin"),
                          "Augmented PATH should include fish shell's custom path")
        }
    }

    func testResolveLoginShellPathUsesEchoForNonFishShell() throws {
        // With a non-fish shell, resolveLoginShellPath should use "echo $PATH" (default behavior).
        // The stub gates on "echo" to catch regressions that send fish commands to non-fish shells.
        let expectedPath = "/usr/bin:/bin:/usr/sbin:/sbin"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonFishShellPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("zsh", isDirectory: false)
        // Gate on "echo" — only succeed if the command contains "echo" (non-fish path)
        let script = """
            #!/bin/sh
            case "$3" in
              *"echo"*) echo "\(expectedPath)" ;;
              *) exit 1 ;;
            esac
            """
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            XCTAssertFalse(ExecutableResolver.isFishShell, "Shell path should not be detected as fish")
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            let path = resolver.resolveLoginShellPath()
            XCTAssertEqual(path, expectedPath)
        }
    }

    func testResolveViaLoginShellReturnsNilWhenShellCommandTimesOut() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellTimeoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        let script = "#!/bin/sh\nsleep 10\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            // Use a short timeout (1s) to avoid ~6.6s wait with the default 5s timeout.
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true, loginShellTimeoutSeconds: 1.0)
            // Force the login-shell fallback path; the stub shell never completes, so it should time out.
            XCTAssertNil(resolver.resolve("this-executable-should-not-exist-abcdef"))
        }
    }

    func testResolveViaLoginShellReturnsNilWhenShellOutputIsNotUTF8() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoginShellBadUTF8Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let shellURL = tempDir.appendingPathComponent("shell.sh", isDirectory: false)
        // Print a single invalid UTF-8 byte (0xFF) then exit 0.
        let script = "#!/bin/sh\nprintf '\\377'\nexit 0\n"
        try script.write(to: shellURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shellURL.path)

        withShell(shellURL.path) {
            let resolver = ExecutableResolver(loginShellFallbackEnabled: true)
            XCTAssertNil(resolver.resolve("this-executable-should-not-exist-badutf8"))
        }
    }
}
