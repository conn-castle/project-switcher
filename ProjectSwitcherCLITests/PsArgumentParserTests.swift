import XCTest
@testable import ProjectSwitcherCLICore

final class PsArgumentParserTests: XCTestCase {

    func testRootHelpFlag() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["--help"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .help(.root))
        }
    }

    func testVersionFlag() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["--version"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .version)
        }
    }

    func testDoctorHelp() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["doctor", "--help"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .help(.doctor))
        }
    }

    func testDoctorCommand() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["doctor"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .doctor)
        }
    }

    func testDoctorUnexpectedArgumentsReportsUsage() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["doctor", "extra"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "unexpected arguments: extra")
            XCTAssertEqual(error.usageTopic, .doctor)
        }
    }

    func testShowConfigCommand() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["show-config"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .showConfig)
        }
    }

    func testListProjectsNoQuery() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["list-projects"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .listProjects(nil))
        }
    }

    func testListProjectsWithQuery() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["list-projects", "foo"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .listProjects("foo"))
        }
    }

    func testListProjectsHelpFlag() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["list-projects", "--help"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .help(.listProjects))
        }
    }

    func testListProjectsUnexpectedArgumentsReportsUsage() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["list-projects", "a", "b"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "unexpected arguments: a b")
            XCTAssertEqual(error.usageTopic, .listProjects)
        }
    }

    func testSelectProjectCommand() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["select-project", "my-project"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .selectProject("my-project"))
        }
    }

    func testSelectProjectMissingArgument() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["select-project"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "missing argument")
            XCTAssertEqual(error.usageTopic, .selectProject)
        }
    }

    func testSelectProjectUnexpectedArgumentsReportsUsage() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["select-project", "a", "b"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "unexpected arguments: a b")
            XCTAssertEqual(error.usageTopic, .selectProject)
        }
    }

    func testCloseProjectCommand() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["close-project", "my-project"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .closeProject("my-project"))
        }
    }

    func testReturnCommand() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["return"]) {
        case .failure(let error):
            XCTFail("Unexpected parse error: \(error.message)")
        case .success(let command):
            XCTAssertEqual(command, .returnToWindow)
        }
    }

    func testUnknownCommandReportsUsage() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: ["nope"]) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "unknown command: nope")
            XCTAssertEqual(error.usageTopic, .root)
        }
    }

    func testMissingCommandReportsUsage() {
        let parser = PsArgumentParser()

        switch parser.parse(arguments: []) {
        case .success(let command):
            XCTFail("Expected parse error, got \(command)")
        case .failure(let error):
            XCTAssertEqual(error.message, "missing command")
            XCTAssertEqual(error.usageTopic, .root)
        }
    }
}
