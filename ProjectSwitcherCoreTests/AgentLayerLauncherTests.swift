import XCTest
@testable import ProjectSwitcherCore

/// Tests for `PsAgentLayerVSCodeLauncher`.
///
/// Verifies:
/// - Settings.json injection with PS:<id> window title block
/// - Two-step launch: `al sync` (CWD = project path) then `al vscode --no-sync --new-window` (CWD = project path)
/// - Error handling: al not found, code not found, empty project path, non-zero exit, partial failure
final class AgentLayerLauncherTests: XCTestCase {

    private var tempDir: URL!
    private var projectDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ALLauncherTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        projectDir = tempDir.appendingPathComponent("project", isDirectory: true)
        try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Successful launch

    func testSuccessfulLaunchRunsAlSyncThenAlVSCodeNoSyncNewWindow() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let resolver = makeResolver()
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: resolver
        )

        let result = launcher.openNewWindow(identifier: "my-project", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTFail("Expected success, got failure: \(error.message)")
            return
        }

        XCTAssertEqual(runner.calls.count, 2)

        // Call 0: al sync with CWD = project path
        let syncCall = runner.calls[0]
        XCTAssertTrue(syncCall.executable.hasSuffix("/al"))
        XCTAssertEqual(syncCall.arguments, ["sync"])
        XCTAssertEqual(syncCall.workingDirectory, projectDir.path)

        // Call 1: al vscode --no-sync --new-window (CWD = project path)
        let vscodeCall = runner.calls[1]
        XCTAssertTrue(vscodeCall.executable.hasSuffix("/al"))
        XCTAssertEqual(vscodeCall.arguments, ["vscode", "--no-sync", "--new-window"])
        XCTAssertEqual(vscodeCall.workingDirectory, projectDir.path)
    }

    // MARK: - Settings file contents

    func testSettingsFileContainsProjectSwitcherTag() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        _ = launcher.openNewWindow(identifier: "test-proj", projectPath: projectDir.path)

        let content = readSettingsJSON()
        XCTAssertNotNil(content, "settings.json should exist")
        XCTAssertTrue(content?.contains("// >>> project-switcher") == true)
        XCTAssertTrue(content?.contains("// <<< project-switcher") == true)
        XCTAssertTrue(content?.contains("PS:test-proj") == true,
                       "Settings should contain PS:test-proj, got: \(content ?? "nil")")
    }

    // MARK: - Error: settings file write fails

    func testSettingsFileWriteFailureReturnsError() {
        let runner = MockALCommandRunner()
        let failingSettings = PsVSCodeSettingsManager(fileSystem: FailingWorkspaceFileSystem())
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver(),
            settingsManager: failingSettings
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Failed to write .vscode/settings.json"))
        } else {
            XCTFail("Expected failure when settings file cannot be written")
        }

        XCTAssertTrue(runner.calls.isEmpty, "No command should be run if settings file creation fails")
    }

    // MARK: - Error: remoteAuthority not supported

    func testRemoteAuthorityProvidedReturnsError() {
        let runner = MockALCommandRunner()
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(
            identifier: "test",
            projectPath: projectDir.path,
            remoteAuthority: "ssh-remote+u@host"
        )

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("does not support SSH remote projects"))
        } else {
            XCTFail("Expected failure when remoteAuthority is provided")
        }

        XCTAssertTrue(runner.calls.isEmpty, "No command should be run if remoteAuthority is provided")
    }

    // MARK: - Error: al not found

    func testAlNotFoundReturnsError() {
        let runner = MockALCommandRunner()
        let resolver = makeResolver(alAvailable: false)
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: resolver
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("al") && error.message.contains("not found"),
                          "Error should mention 'al' not found, got: \(error.message)")
        } else {
            XCTFail("Expected failure when al is not found")
        }

        XCTAssertTrue(runner.calls.isEmpty, "No command should be run if al is not found")
    }

    // MARK: - Error: code not found

    func testCodeNotFoundReturnsError() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let resolver = makeResolver(codeAvailable: false)
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: resolver
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("code") && error.message.contains("not found"),
                          "Error should mention 'code' not found, got: \(error.message)")
        } else {
            XCTFail("Expected failure when code is not found")
        }

        // al sync should have run, but al vscode should not
        XCTAssertEqual(runner.calls.count, 1, "Only al sync should run when code is not found")
    }

    // MARK: - Error: nil or empty project path

    func testNilProjectPathReturnsError() {
        let runner = MockALCommandRunner()
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: nil)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Project path is required"),
                          "Error should say project path is required, got: \(error.message)")
        } else {
            XCTFail("Expected failure for nil project path")
        }
    }

    func testEmptyProjectPathReturnsError() {
        let runner = MockALCommandRunner()
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: "   ")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("Project path is required"),
                          "Error should say project path is required, got: \(error.message)")
        } else {
            XCTFail("Expected failure for empty project path")
        }
    }

    // MARK: - Error: al sync non-zero exit code

    func testAlSyncNonZeroExitReturnsErrorWithStderr() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "agent layer isn't initialized"))
        ]
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("al sync failed"), "Error should mention al sync, got: \(error.message)")
            XCTAssertTrue(error.message.contains("exit code 1"), "Error should contain exit code")
            XCTAssertTrue(error.message.contains("agent layer isn't initialized"),
                          "Error should contain stderr")
        } else {
            XCTFail("Expected failure for non-zero exit code")
        }

        XCTAssertEqual(runner.calls.count, 1, "al vscode should not run after al sync failure")
    }

    func testAlSyncNonZeroExitReturnsErrorWithoutStderr() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "   "))
        ]
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("al sync failed with exit code 1."))
            XCTAssertFalse(error.message.contains("\n"))
        } else {
            XCTFail("Expected failure for non-zero exit code")
        }

        XCTAssertEqual(runner.calls.count, 1, "al vscode should not run after al sync failure")
    }

    // MARK: - Error: al sync succeeds but al vscode fails

    func testAlSyncSucceedsButAlVSCodeFailsReturnsError() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "code: command not supported"))
        ]
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("al vscode failed"), "Error should mention al vscode, got: \(error.message)")
            XCTAssertTrue(error.message.contains("exit code 1"), "Error should contain exit code")
        } else {
            XCTFail("Expected failure when al vscode exits non-zero")
        }

        XCTAssertEqual(runner.calls.count, 2, "Both al sync and al vscode should have run")
    }

    func testAlVSCodeNonZeroExitReturnsErrorWithoutStderr() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 2, stdout: "", stderr: ""))
        ]
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("al vscode failed with exit code 2."))
            XCTAssertFalse(error.message.contains("\n"))
        } else {
            XCTFail("Expected failure when al vscode exits non-zero")
        }

        XCTAssertEqual(runner.calls.count, 2, "Both al sync and al vscode should have run")
    }

    // MARK: - Error: command runner failure

    func testCommandRunnerFailureReturnsError() {
        let runner = MockALCommandRunner()
        runner.results = [
            .failure(PsCoreError(message: "Command timed out after 30.0s: al"))
        ]
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("timed out"),
                          "Error should contain runner failure message")
        } else {
            XCTFail("Expected failure from command runner")
        }
    }

    func testCodeRunnerFailureReturnsError() {
        let runner = MockALCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .failure(PsCoreError(message: "runner failed"))
        ]
        let launcher = PsAgentLayerVSCodeLauncher(
            commandRunner: runner,
            executableResolver: makeResolver()
        )

        let result = launcher.openNewWindow(identifier: "test", projectPath: projectDir.path)

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "runner failed")
        } else {
            XCTFail("Expected failure from command runner (al vscode)")
        }

        XCTAssertEqual(runner.calls.count, 2)
    }

    // MARK: - Helpers

    private func makeResolver(alAvailable: Bool = true, codeAvailable: Bool = true) -> ExecutableResolver {
        var executablePaths = Set<String>()
        if alAvailable { executablePaths.insert("/usr/local/bin/al") }
        if codeAvailable { executablePaths.insert("/usr/local/bin/code") }
        let stubFS = ALSelectiveFileSystem(executablePaths: executablePaths)
        return ExecutableResolver(
            fileSystem: stubFS,
            searchPaths: ["/usr/local/bin"],
            loginShellFallbackEnabled: false
        )
    }

    private func readSettingsJSON() -> String? {
        let settingsURL = projectDir.appendingPathComponent(".vscode/settings.json")
        return try? String(contentsOf: settingsURL, encoding: .utf8)
    }
}
