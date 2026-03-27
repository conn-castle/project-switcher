import XCTest
@testable import ProjectSwitcherCore

/// Tests that PsVSCodeLauncher correctly manages VS Code configuration.
///
/// Local projects: verifies settings.json injection with PS:<id> block.
/// SSH projects: verifies SSH read/write command arguments and that SSH failures fail loudly.
/// The command runner is mocked, so VS Code is never actually launched.
final class VSCodeSSHWorkspaceTests: XCTestCase {

    private var tempDir: URL!
    private var projectDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VSCodeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        projectDir = tempDir.appendingPathComponent("project", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Local project: settings.json injection

    func testLocalPathInjectsSettingsJSON() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))  // code --new-window
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "local-project",
            projectPath: projectDir.path
        )

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        let content = readSettingsJSON(projectPath: projectDir.path)
        XCTAssertNotNil(content, "settings.json should exist")
        XCTAssertTrue(content?.contains("// >>> project-switcher") == true)
        XCTAssertTrue(content?.contains("PS:local-project") == true)
    }

    func testLocalPathOpensCodeWithProjectPath() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))  // code --new-window
        ]
        let launcher = makeLauncher(commandRunner: runner)

        _ = launcher.openNewWindow(
            identifier: "local-project",
            projectPath: projectDir.path
        )

        XCTAssertEqual(runner.calls.count, 1)
        let codeCall = runner.calls[0]
        XCTAssertEqual(codeCall.executable, "code")
        XCTAssertEqual(codeCall.arguments, ["--new-window", projectDir.path])
    }

    func testLocalPathPreservesExistingSettings() {
        // Pre-populate settings.json
        let vscodeDir = URL(fileURLWithPath: projectDir.path).appendingPathComponent(".vscode")
        try! FileManager.default.createDirectory(at: vscodeDir, withIntermediateDirectories: true)
        let settingsURL = vscodeDir.appendingPathComponent("settings.json")
        try! """
        {
          \"editor.fontSize\": 14
        }
        """.write(to: settingsURL, atomically: true, encoding: .utf8)

        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = makeLauncher(commandRunner: runner)

        _ = launcher.openNewWindow(identifier: "local", projectPath: projectDir.path)

        let content = readSettingsJSON(projectPath: projectDir.path)
        XCTAssertTrue(content?.contains("// >>> project-switcher") == true)
        XCTAssertTrue(content?.contains("\"editor.fontSize\": 14") == true)
    }

    // MARK: - SSH project: successful remote write

    func testSSHProjectSuccessfulRemoteWrite() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),  // SSH read
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),      // SSH write
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))       // code --new-window
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "remote-ml",
            projectPath: "/Users/nconn/project",
            remoteAuthority: "ssh-remote+nconn@happy-mac.local"
        )

        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        XCTAssertEqual(runner.calls.count, 3)

        // SSH read command
        let readCall = runner.calls[0]
        XCTAssertEqual(readCall.executable, "ssh")
        XCTAssertTrue(readCall.arguments.contains("--"))
        XCTAssertTrue(readCall.arguments.contains("nconn@happy-mac.local"))
        XCTAssertTrue(readCall.arguments.last?.contains("cat") == true)

        // SSH write command
        let writeCall = runner.calls[1]
        XCTAssertEqual(writeCall.executable, "ssh")
        XCTAssertTrue(writeCall.arguments.contains("--"))
        XCTAssertTrue(writeCall.arguments.contains("nconn@happy-mac.local"))
        XCTAssertTrue(writeCall.arguments.last?.contains("base64 -d") == true)

        // VS Code launch with --remote
        let codeCall = runner.calls[2]
        XCTAssertEqual(codeCall.executable, "code")
        XCTAssertEqual(codeCall.arguments, [
            "--new-window",
            "--remote", "ssh-remote+nconn@happy-mac.local",
            "/Users/nconn/project"
        ])
    }

    // MARK: - SSH project: failures fail loudly

    func testSSHProjectReadFailureReturnsErrorAndDoesNotLaunchCode() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .failure(PsCoreError(message: "SSH connection failed"))
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "remote-ml",
            projectPath: "/Users/nconn/project",
            remoteAuthority: "ssh-remote+nconn@happy-mac.local"
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("SSH read failed"))
        }

        XCTAssertEqual(runner.calls.count, 1, "Should not attempt code launch on SSH read failure")
        XCTAssertEqual(runner.calls[0].executable, "ssh")
    }

    func testSSHProjectWriteFailureReturnsErrorAndDoesNotLaunchCode() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "Permission denied"))
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "remote-ml",
            projectPath: "/Users/nconn/project",
            remoteAuthority: "ssh-remote+nconn@happy-mac.local"
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("SSH write failed"))
        }

        XCTAssertEqual(runner.calls.count, 2, "Should not attempt code launch on SSH write failure")
        XCTAssertEqual(runner.calls[0].executable, "ssh")
        XCTAssertEqual(runner.calls[1].executable, "ssh")
    }

    // MARK: - SSH command safety

    func testSSHCommandIncludesOptionTerminator() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = makeLauncher(commandRunner: runner)

        _ = launcher.openNewWindow(
            identifier: "test",
            projectPath: "/remote/path",
            remoteAuthority: "ssh-remote+user@host"
        )

        // Both SSH calls should include "--"
        for i in 0..<2 {
            let args = runner.calls[i].arguments
            XCTAssertTrue(args.contains("--"), "SSH call \(i) should include '--' terminator: \(args)")
        }
    }

    // MARK: - openNewWindow command execution behavior

    func testOpenNewWindowFailsWhenProjectPathNil() {
        let runner = SharedVSCodeCommandRunner()
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "no-path", projectPath: nil)

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Project path is required"))
        }

        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testOpenNewWindowFailsWhenCodeExitNonZeroAndStderrEmpty() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 2, stdout: "", stderr: ""))  // code fails
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "exit-empty-stderr",
            projectPath: projectDir.path
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "code failed with exit code 2.")
        }
    }

    func testOpenNewWindowFailsWhenCodeExitNonZeroAndStderrIncluded() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 3, stdout: "", stderr: "boom"))
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "exit-with-stderr",
            projectPath: projectDir.path
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("exit code 3"))
            XCTAssertTrue(error.message.contains("\nboom"))
        }
    }

    func testOpenNewWindowSucceedsWhenCodeExitZero() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "exit-zero",
            projectPath: projectDir.path
        )

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error.message)")
        case .success:
            break
        }
    }

    func testOpenNewWindowTrimsRemoteAuthorityAndProjectPath() {
        let runner = SharedVSCodeCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "{}\n", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = makeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(
            identifier: "trim-test",
            projectPath: " /Users/test/project ",
            remoteAuthority: "  ssh-remote+u@h  "
        )
        if case .failure(let error) = result {
            XCTFail("Expected success, got: \(error.message)")
            return
        }

        // Verify SSH target was trimmed
        let readCall = runner.calls[0]
        XCTAssertTrue(readCall.arguments.contains("u@h"))
        XCTAssertTrue(readCall.arguments.last?.contains("/Users/test/project") == true)
        XCTAssertFalse(readCall.arguments.last?.contains(" /Users/test/project ") == true)
    }

    func testOpenNewWindowReturnsErrorWhenSettingsWriteFails() {
        let failingFS = FailingSettingsFileSystem()
        let failingSettings = PsVSCodeSettingsManager(fileSystem: failingFS)
        let runner = SharedVSCodeCommandRunner()
        let launcher = PsVSCodeLauncher(
            commandRunner: runner,
            fileSystem: failingFS,
            settingsManager: failingSettings
        )

        let result = launcher.openNewWindow(
            identifier: "settings-write-fails",
            projectPath: projectDir.path
        )

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Failed to write .vscode/settings.json"))
        }
    }

    // MARK: - Helpers

    private func makeLauncher(commandRunner: SharedVSCodeCommandRunner) -> PsVSCodeLauncher {
        PsVSCodeLauncher(commandRunner: commandRunner)
    }

    private func readSettingsJSON(projectPath: String) -> String? {
        let settingsURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".vscode/settings.json")
        return try? String(contentsOf: settingsURL, encoding: .utf8)
    }
}
