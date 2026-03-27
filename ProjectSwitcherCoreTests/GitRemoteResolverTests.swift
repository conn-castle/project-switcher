import XCTest
@testable import ProjectSwitcherCore

final class GitRemoteResolverTests: XCTestCase {

    // MARK: - Successful resolution

    func testResolvesGitRemoteURL() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(
                exitCode: 0,
                stdout: "https://github.com/user/repo.git\n",
                stderr: ""
            ))
        ]
        let resolver = GitRemoteResolver(commandRunner: runner)

        let url = resolver.resolve(projectPath: "/path/to/project")

        XCTAssertEqual(url, "https://github.com/user/repo.git")
        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "git")
        XCTAssertEqual(runner.calls[0].arguments, ["-C", "/path/to/project", "remote", "get-url", "origin"])
    }

    // MARK: - Non-zero exit returns nil

    func testNonZeroExitReturnsNil() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 128, stdout: "", stderr: "fatal: not a git repository"))
        ]
        let resolver = GitRemoteResolver(commandRunner: runner)

        let url = resolver.resolve(projectPath: "/not/a/repo")

        XCTAssertNil(url)
    }

    // MARK: - Empty stdout returns nil

    func testEmptyStdoutReturnsNil() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "  \n  ", stderr: ""))
        ]
        let resolver = GitRemoteResolver(commandRunner: runner)

        let url = resolver.resolve(projectPath: "/path")

        XCTAssertNil(url)
    }

    // MARK: - Command failure returns nil

    func testCommandFailureReturnsNil() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "timeout"))
        ]
        let resolver = GitRemoteResolver(commandRunner: runner)

        let url = resolver.resolve(projectPath: "/path")

        XCTAssertNil(url)
    }

    // MARK: - Trims whitespace from URL

    func testTrimsWhitespaceFromURL() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(
                exitCode: 0,
                stdout: "  https://github.com/user/repo  \n",
                stderr: ""
            ))
        ]
        let resolver = GitRemoteResolver(commandRunner: runner)

        let url = resolver.resolve(projectPath: "/path")

        XCTAssertEqual(url, "https://github.com/user/repo")
    }

    // MARK: - SSH remote URL

    func testResolvesSSHRemoteURL() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(
                exitCode: 0,
                stdout: "git@github.com:user/repo.git\n",
                stderr: ""
            ))
        ]
        let resolver = GitRemoteResolver(commandRunner: runner)

        let url = resolver.resolve(projectPath: "/path")

        XCTAssertEqual(url, "git@github.com:user/repo.git")
    }
}

// MARK: - Test Doubles

private final class MockCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    var calls: [Call] = []
    var results: [Result<PsCommandResult, PsCoreError>] = []

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        calls.append(Call(executable: executable, arguments: arguments))
        guard !results.isEmpty else {
            return .failure(PsCoreError(category: .command, message: "MockCommandRunner: no results left"))
        }
        return results.removeFirst()
    }
}
