import XCTest
@testable import ProjectSwitcherCore

final class ConfigParserTests: XCTestCase {

    func testParseValidProject() {
        let toml = """
        [[project]]
        name = "Test Project"
        path = "/Users/test/project"
        color = "blue"
        useAgentLayer = true
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.count, 1)
        XCTAssertEqual(result.projects.first?.id, "test-project")
        XCTAssertEqual(result.projects.first?.name, "Test Project")
        XCTAssertEqual(result.projects.first?.color, "blue")
        XCTAssertEqual(result.projects.first?.useAgentLayer, true)
    }

    func testParseMultipleProjects() {
        let toml = """
        [[project]]
        name = "Project One"
        path = "/path/one"
        color = "blue"
        useAgentLayer = true

        [[project]]
        name = "Project Two"
        path = "/path/two"
        color = "red"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.count, 2)
        XCTAssertEqual(result.projects[0].id, "project-one")
        XCTAssertEqual(result.projects[1].id, "project-two")
    }

    func testParseMissingRequiredField() {
        let toml = """
        [[project]]
        name = "Test"
        # missing path and color (useAgentLayer is optional)
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains { $0.severity == .fail })
    }

    func testParseEmptyName() {
        let toml = """
        [[project]]
        name = ""
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains { $0.severity == .fail && $0.title.contains("name") })
    }

    func testParseReservedIdRejected() {
        let toml = """
        [[project]]
        name = "Inbox"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.lowercased().contains("reserved")
        })
    }

    func testParseDuplicateIdRejected() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/path/one"
        color = "blue"
        useAgentLayer = false

        [[project]]
        name = "Test"
        path = "/path/two"
        color = "red"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.lowercased().contains("duplicate")
        })
    }

    func testParseHexColor() {
        let toml = """
        [[project]]
        name = "Hex Color Test"
        path = "/test"
        color = "#FF5500"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.color, "#FF5500")
    }

    // MARK: - Agent Layer Config Defaults

    func testNoAgentLayerSectionDefaultsFalse() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.agentLayer.enabled, false)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
    }

    func testAgentLayerGlobalTrueDefaultsProjectsTrue() {
        let toml = """
        [agentLayer]
        enabled = true

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.agentLayer.enabled, true)
        XCTAssertEqual(result.projects.first?.useAgentLayer, true)
    }

    func testAgentLayerGlobalTrueProjectOverrideFalse() {
        let toml = """
        [agentLayer]
        enabled = true

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
    }

    func testAgentLayerGlobalFalseProjectOverrideTrue() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = true
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.agentLayer.enabled, false)
        XCTAssertEqual(result.projects.first?.useAgentLayer, true)
    }

    func testAgentLayerNotATableFails() {
        let toml = """
        agentLayer = "not a table"

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("[agentLayer] must be a table")
        })
    }

    func testUseAgentLayerOmittedWithGlobalFalse() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.useAgentLayer, false)
    }

}
