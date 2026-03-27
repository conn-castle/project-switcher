import XCTest
import Foundation
import Darwin
@testable import ProjectSwitcherCore

final class ChromeLauncherTests: XCTestCase {

    func testOpenNewWindowRejectsEmptyIdentifier() {
        let runner = ChromeLauncherCommandRunnerStub(result: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")))
        let launcher = PsChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "  ")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("Identifier cannot be empty"))
            XCTAssertNil(runner.lastExecutable)
        }
    }

    func testOpenNewWindowRejectsIdentifierWithSlash() {
        let runner = ChromeLauncherCommandRunnerStub(result: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")))
        let launcher = PsChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "a/b")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("cannot contain"))
            XCTAssertNil(runner.lastExecutable)
        }
    }

    func testOpenNewWindowBuildsAppleScriptWithWindowTitleAndURLs() {
        let runner = ChromeLauncherCommandRunnerStub(result: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")))
        let launcher = PsChromeLauncher(commandRunner: runner)

        let urls = [
            "https://example.com?q=\"x\"",
            "https://two.com/path\\\\x"
        ]
        let result = launcher.openNewWindow(identifier: "my-proj", initialURLs: urls)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got: \(error)")
        case .success:
            break
        }

        XCTAssertEqual(runner.lastExecutable, "osascript")
        guard let args = runner.lastArguments else {
            XCTFail("Expected osascript args")
            return
        }

        // The arguments should be a sequence of: -e <line>
        XCTAssertTrue(args.count >= 2)
        XCTAssertEqual(args[0], "-e")
        XCTAssertTrue(args.contains("tell application \"Google Chrome\""))
        XCTAssertTrue(args.contains("set newWindow to make new window"))

        // URL lines should include escaped quotes/backslashes.
        let urlLine = args.first { $0.contains("set URL of active tab") }
        XCTAssertNotNil(urlLine)
        XCTAssertTrue(urlLine!.contains("https://example.com?q=\\\"x\\\""))

        let secondTabLine = args.first { $0.contains("make new tab") }
        XCTAssertNotNil(secondTabLine)
        XCTAssertTrue(secondTabLine!.contains("https://two.com/path\\\\\\\\x"))

        // Window title should include PS: token.
        let titleLine = args.first { $0.contains("set given name of newWindow") }
        XCTAssertNotNil(titleLine)
        XCTAssertTrue(titleLine!.contains("PS:my-proj"))
    }

    func testOpenNewWindowNonZeroExitReturnsFailureWithStderr() {
        let runner = ChromeLauncherCommandRunnerStub(
            result: .success(PsCommandResult(exitCode: 2, stdout: "", stderr: "boom"))
        )
        let launcher = PsChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "x")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("exit code 2"))
            XCTAssertTrue(error.message.contains("boom"))
        }
    }

    func testOpenNewWindowRunnerFailureIsPropagated() {
        let runner = ChromeLauncherCommandRunnerStub(
            result: .failure(PsCoreError(message: "runner failed"))
        )
        let launcher = PsChromeLauncher(commandRunner: runner)

        let result = launcher.openNewWindow(identifier: "x")

        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "runner failed")
        }
    }
}
