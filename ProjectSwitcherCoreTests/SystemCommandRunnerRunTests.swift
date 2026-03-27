import XCTest
import Foundation
import Darwin
@testable import ProjectSwitcherCore

final class SystemCommandRunnerRunTests: XCTestCase {

    // MARK: - PsSystemCommandRunner.run

    func testRunRespectsWorkingDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkingDirTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let runner = PsSystemCommandRunner(executableResolver: ExecutableResolver(loginShellFallbackEnabled: false))
        let result = runner.run(
            executable: "pwd",
            arguments: [],
            timeoutSeconds: 5,
            workingDirectory: tempDir.path
        )

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error.message)")
        case .success(let output):
            XCTAssertEqual(output.exitCode, 0)
            let actual = (output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).resolvingSymlinksInPath
            let expected = (tempDir.path as NSString).resolvingSymlinksInPath
            XCTAssertEqual(actual, expected)
        }
    }

    func testRunReturnsFailureWhenResolvedExecutableCannotBeLaunched() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchFailureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let resolver = ExecutableResolver(
            fileSystem: AlwaysExecutableFileSystem(),
            searchPaths: [tempDir.path],
            loginShellFallbackEnabled: false
        )
        let runner = PsSystemCommandRunner(executableResolver: resolver)
        let result = runner.run(executable: "nope", arguments: [], timeoutSeconds: 1)

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Failed to launch"))
        }
    }

    func testRunReturnsFailureWhenStdoutIsNotUTF8() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BadStdoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let exeURL = binDir.appendingPathComponent("badstdout", isDirectory: false)
        let script = "#!/bin/sh\nprintf '\\377'\nexit 0\n"
        try script.write(to: exeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exeURL.path)

        let resolver = ExecutableResolver(searchPaths: [binDir.path], loginShellFallbackEnabled: false)
        let runner = PsSystemCommandRunner(executableResolver: resolver)

        let result = runner.run(executable: "badstdout", arguments: [], timeoutSeconds: 5, workingDirectory: nil)
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("UTF-8") && error.message.contains("stdout"))
        }
    }

    func testRunReturnsFailureWhenStderrIsNotUTF8() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BadStderrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binDir = tempDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let exeURL = binDir.appendingPathComponent("badstderr", isDirectory: false)
        let script = "#!/bin/sh\nprintf '\\377' 1>&2\nexit 0\n"
        try script.write(to: exeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exeURL.path)

        let resolver = ExecutableResolver(searchPaths: [binDir.path], loginShellFallbackEnabled: false)
        let runner = PsSystemCommandRunner(executableResolver: resolver)

        let result = runner.run(executable: "badstderr", arguments: [], timeoutSeconds: 5, workingDirectory: nil)
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("UTF-8") && error.message.contains("stderr"))
        }
    }
}
