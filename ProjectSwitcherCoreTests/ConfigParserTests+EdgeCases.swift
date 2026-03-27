import XCTest

@testable import ProjectSwitcherCore

extension ConfigParserTests {

    // MARK: - Config Edge Cases

    func testNameNormalizesToEmptyFails() {
        let toml = """
        [[project]]
        name = "---"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("cannot derive an id")
        })
    }

    func testInvalidColorFails() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "not-a-color"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("color is invalid")
        })
    }

    func testChromeNotATableFails() {
        let toml = """
        chrome = "not-a-table"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("[chrome] must be a table")
        })
    }

    func testNameWrongTypeFails() {
        let toml = """
        [[project]]
        name = 123
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("must be a string")
        })
    }

    func testProjectKeyNotAnArrayFails() {
        let toml = """
        [project]
        name = "Test"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project must be an array")
        })
    }

    func testMissingProjectKeyFails() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://example.com"]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("No [[project]] entries")
        })
    }

    func testEmptyProjectArrayFails() {
        let toml = """
        project = []
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("No [[project]] entries")
        })
    }

    func testProjectArrayElementNotATableFails() {
        let toml = """
        project = [1]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project[0] must be a table")
        })
    }

    func testOptionalRemoteWrongTypeFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = 123
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project[0].remote must be a string")
        })
    }

    func testOptionalRemoteEmptyFails() {
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = ""
        path = "/remote/path"
        color = "teal"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project[0].remote is empty")
        })
    }

    func testChromePinnedTabsWrongTypeFails() {
        let toml = """
        [chrome]
        pinnedTabs = "not-an-array"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.pinnedTabs must be an array of strings")
        })
    }

    func testChromePinnedTabsElementWrongTypeFails() {
        let toml = """
        [chrome]
        pinnedTabs = [123]

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.pinnedTabs[0] must be a string")
        })
    }

    func testAgentLayerEnabledWrongTypeFails() {
        let toml = """
        [agentLayer]
        enabled = "yes"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("agentLayer.enabled must be a boolean")
        })
    }

    func testChromeOpenGitRemoteWrongTypeFails() {
        let toml = """
        [chrome]
        openGitRemote = "true"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.openGitRemote must be a boolean")
        })
    }

    // MARK: - Unrecognized Config Key Tests

    func testUnrecognizedTopLevelKey() {
        let toml = """
        bogusKey = "unexpected"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized top-level config key: bogusKey")
        })
    }

    func testUnrecognizedChromeKey() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://example.com"]
        bogusOption = true

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized [chrome] config key: bogusOption")
        })
    }

    func testUnrecognizedAgentLayerKey() {
        let toml = """
        [agentLayer]
        enabled = true
        unknownSetting = "value"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        useAgentLayer = true
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized [agentLayer] config key: unknownSetting")
        })
    }

    func testUnrecognizedProjectKey() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        typoField = "oops"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when unrecognized keys produce FAIL findings")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized [[project]] config key: typoField")
        })
    }

    func testMultipleUnrecognizedKeysAreSorted() {
        let toml = """
        [chrome]
        zebra = true
        alpha = "test"
        pinnedTabs = ["https://example.com"]

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        let unknownFindings = result.findings.filter {
            $0.severity == .fail && $0.title.contains("Unrecognized [chrome] config key")
        }
        XCTAssertEqual(unknownFindings.count, 2)
        XCTAssertTrue(unknownFindings[0].title.contains("alpha"))
        XCTAssertTrue(unknownFindings[1].title.contains("zebra"))
    }

    func testValidConfigHasNoUnrecognizedKeyFindings() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://example.com"]
        defaultTabs = ["https://docs.example.com"]
        openGitRemote = true

        [agentLayer]
        enabled = false

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        useAgentLayer = false
        remote = "ssh-remote+user@host"
        chromePinnedTabs = ["https://api.example.com"]
        chromeDefaultTabs = ["https://jira.example.com"]
        """

        let result = ConfigParser.parse(toml: toml)

        let unknownFindings = result.findings.filter {
            $0.title.contains("Unrecognized")
        }
        XCTAssertTrue(unknownFindings.isEmpty, "Valid config should have no unrecognized key findings, got: \(unknownFindings)")
    }

    func testUnrecognizedKeyFixIncludesKnownKeys() {
        let toml = """
        [agentLayer]
        enabeld = true

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        let finding = result.findings.first {
            $0.title.contains("Unrecognized [agentLayer] config key: enabeld")
        }
        XCTAssertNotNil(finding)
        XCTAssertTrue(finding?.fix?.contains("enabled") == true, "Fix should list known keys")
    }
}
