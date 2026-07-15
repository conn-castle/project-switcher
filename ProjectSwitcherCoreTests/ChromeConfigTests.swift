import XCTest
@testable import ProjectSwitcherCore

final class ChromeConfigTests: XCTestCase {

    // MARK: - [chrome] section with all fields

    func testParseChromeAllFields() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://dashboard.example.com"]
        defaultTabs = ["https://docs.example.com"]
        openGitRemote = true

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.chrome.pinnedTabs, ["https://dashboard.example.com"])
        XCTAssertEqual(result.config?.chrome.defaultTabs, ["https://docs.example.com"])
        XCTAssertEqual(result.config?.chrome.openGitRemote, true)
    }

    // MARK: - [chrome] section with missing fields (defaults)

    func testParseChromePartialFields() {
        let toml = """
        [chrome]
        openGitRemote = true

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.chrome.pinnedTabs, [])
        XCTAssertEqual(result.config?.chrome.defaultTabs, [])
        XCTAssertEqual(result.config?.chrome.openGitRemote, true)
    }

    // MARK: - Missing [chrome] section entirely (defaults)

    func testParseMissingChromeSection() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.chrome.pinnedTabs, [])
        XCTAssertEqual(result.config?.chrome.defaultTabs, [])
        XCTAssertEqual(result.config?.chrome.openGitRemote, false)
    }

    // MARK: - Per-project chrome fields

    func testParsePerProjectChromeFields() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        chromePinnedTabs = ["https://api.example.com"]
        chromeDefaultTabs = ["https://jira.example.com"]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.chromePinnedTabs, ["https://api.example.com"])
        XCTAssertEqual(result.projects.first?.chromeDefaultTabs, ["https://jira.example.com"])
    }

    func testParsePerProjectChromeFieldsDefaultEmpty() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.chromePinnedTabs, [])
        XCTAssertEqual(result.projects.first?.chromeDefaultTabs, [])
        XCTAssertEqual(result.projects.first?.openChrome, true)
    }

    func testParsePerProjectOpenChromeFalse() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        openChrome = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.projects.first?.openChrome, false)
    }

    func testParsePerProjectOpenChromeWrongTypeFails() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        openChrome = "no"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("project[0].openChrome must be a boolean")
        })
    }

    // MARK: - Invalid URL hard failures

    func testInvalidURLInGlobalPinnedTabsIsHardFailure() {
        let toml = """
        [chrome]
        pinnedTabs = ["not-a-url"]

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.pinnedTabs")
        })
    }

    func testInvalidURLInGlobalDefaultTabsIsHardFailure() {
        let toml = """
        [chrome]
        defaultTabs = ["ftp://bad.example.com"]

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.defaultTabs")
        })
    }

    func testInvalidURLInProjectPinnedTabsIsHardFailure() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        chromePinnedTabs = ["bad-url"]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chromePinnedTabs")
        })
    }

    func testInvalidURLInProjectDefaultTabsIsHardFailure() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        chromeDefaultTabs = ["just-text"]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chromeDefaultTabs")
        })
    }

    // MARK: - Multiple URLs

    func testMultipleValidURLs() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://a.com", "https://b.com"]
        defaultTabs = ["http://c.com", "https://d.com"]

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        chromePinnedTabs = ["https://e.com"]
        chromeDefaultTabs = ["https://f.com", "https://g.com"]
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.chrome.pinnedTabs, ["https://a.com", "https://b.com"])
        XCTAssertEqual(result.config?.chrome.defaultTabs, ["http://c.com", "https://d.com"])
        XCTAssertEqual(result.projects.first?.chromePinnedTabs, ["https://e.com"])
        XCTAssertEqual(result.projects.first?.chromeDefaultTabs, ["https://f.com", "https://g.com"])
    }

    // MARK: - Mixed valid and invalid URLs

    func testMixedValidAndInvalidURLsInGlobalPinned() {
        let toml = """
        [chrome]
        pinnedTabs = ["https://good.com", "bad-url"]

        [[project]]
        name = "Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config, "Config should be nil when any URL is invalid")
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("chrome.pinnedTabs[1]")
        })
    }
}
