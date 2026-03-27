import XCTest
@testable import ProjectSwitcherCore

final class ChromeTabCaptureTests: XCTestCase {

    // MARK: - captureTabURLs

    func testCaptureReturnsURLsFromStdout() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(
                exitCode: 0,
                stdout: "https://a.com\nhttps://b.com\n",
                stderr: ""
            ))
        ]
        let controller = PsChromeTabController(commandRunner: runner)

        switch controller.captureTabURLs(windowTitle: "PS:test") {
        case .success(let urls):
            XCTAssertEqual(urls, ["https://a.com", "https://b.com"])
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls[0].executable, "osascript")
    }

    func testCaptureReturnsEmptyWhenWindowNotFound() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let controller = PsChromeTabController(commandRunner: runner)

        switch controller.captureTabURLs(windowTitle: "PS:missing") {
        case .success(let urls):
            XCTAssertEqual(urls, [])
        case .failure(let error):
            XCTFail("Expected empty success but got: \(error.message)")
        }
    }

    func testCaptureReturnsErrorOnNonZeroExit() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "script error"))
        ]
        let controller = PsChromeTabController(commandRunner: runner)

        switch controller.captureTabURLs(windowTitle: "PS:test") {
        case .success:
            XCTFail("Expected failure on non-zero exit")
        case .failure:
            break
        }
    }

    func testCaptureReturnsErrorOnCommandFailure() {
        let runner = MockCommandRunner()
        runner.results = [
            .failure(PsCoreError(category: .command, message: "timeout"))
        ]
        let controller = PsChromeTabController(commandRunner: runner)

        switch controller.captureTabURLs(windowTitle: "PS:test") {
        case .success:
            XCTFail("Expected failure on command error")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("timeout"))
        }
    }

    func testCaptureFiltersEmptyLines() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(
                exitCode: 0,
                stdout: "https://a.com\n\n\nhttps://b.com\n\n",
                stderr: ""
            ))
        ]
        let controller = PsChromeTabController(commandRunner: runner)

        switch controller.captureTabURLs(windowTitle: "PS:test") {
        case .success(let urls):
            XCTAssertEqual(urls, ["https://a.com", "https://b.com"])
        case .failure(let error):
            XCTFail("Expected success but got: \(error.message)")
        }
    }

    // MARK: - AppleScript escaping

    func testCaptureEscapesWindowTitle() {
        let runner = MockCommandRunner()
        runner.results = [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        ]
        let controller = PsChromeTabController(commandRunner: runner)

        _ = controller.captureTabURLs(windowTitle: "PS:test\"quote")

        // The script arguments should contain the escaped title
        let allArgs = runner.calls[0].arguments.joined(separator: " ")
        XCTAssertTrue(allArgs.contains("PS:test\\\"quote"))
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
