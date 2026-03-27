import XCTest
@testable import ProjectSwitcherCore

final class CommandTimeoutTests: XCTestCase {

    func testCommandTimesOut() {
        let runner = PsSystemCommandRunner()

        // Sleep for 5 seconds but timeout after 0.5
        let result = runner.run(
            executable: "sleep",
            arguments: ["5"],
            timeoutSeconds: 0.5
        )

        switch result {
        case .success:
            XCTFail("Expected timeout error")
        case .failure(let error):
            XCTAssertEqual(error.reason, .commandTimeout, "Timeout errors should include a structured reason")
            XCTAssertTrue(error.isCommandTimeout, "Timeout errors should set isCommandTimeout")
            XCTAssertTrue(error.message.contains("timed out"), "Error message should mention timeout: \(error.message)")
        }
    }

    func testCommandCompletesBeforeTimeout() {
        let runner = PsSystemCommandRunner()

        let result = runner.run(
            executable: "echo",
            arguments: ["hello"],
            timeoutSeconds: 5
        )

        switch result {
        case .success(let output):
            XCTAssertEqual(output.exitCode, 0)
            XCTAssertTrue(output.stdout.contains("hello"))
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    func testNoTimeoutWaitsForCompletion() {
        let runner = PsSystemCommandRunner()

        // Quick command with no timeout
        let result = runner.run(
            executable: "echo",
            arguments: ["test"],
            timeoutSeconds: nil
        )

        switch result {
        case .success(let output):
            XCTAssertEqual(output.exitCode, 0)
            XCTAssertTrue(output.stdout.contains("test"))
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    func testCommandCapturesStderr() {
        let runner = PsSystemCommandRunner()

        // Use sh to write to stderr
        let result = runner.run(
            executable: "sh",
            arguments: ["-c", "echo error >&2"],
            timeoutSeconds: 5
        )

        switch result {
        case .success(let output):
            XCTAssertEqual(output.exitCode, 0)
            XCTAssertTrue(output.stderr.contains("error"))
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    func testCommandCapturesNonZeroExitCode() {
        let runner = PsSystemCommandRunner()

        let result = runner.run(
            executable: "sh",
            arguments: ["-c", "exit 42"],
            timeoutSeconds: 5
        )

        switch result {
        case .success(let output):
            XCTAssertEqual(output.exitCode, 42)
        case .failure(let error):
            XCTFail("Unexpected error: \(error.message)")
        }
    }

    func testExecutableNotFound() {
        let runner = PsSystemCommandRunner()

        let result = runner.run(
            executable: "this-executable-does-not-exist-12345",
            arguments: [],
            timeoutSeconds: 5
        )

        switch result {
        case .success:
            XCTFail("Expected executable not found error")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("not found"), "Error should mention not found: \(error.message)")
        }
    }
}
