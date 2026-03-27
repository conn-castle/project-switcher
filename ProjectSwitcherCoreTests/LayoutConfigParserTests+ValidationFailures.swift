import XCTest

@testable import ProjectSwitcherCore

extension LayoutConfigParserTests {

    // MARK: - Type Mismatch

    func testWindowHeightStringFails() {
        let toml = """
        [layout]
        windowHeight = "ninety"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("windowHeight") && $0.title.contains("integer")
        })
    }

    func testSmallScreenThresholdStringFails() {
        let toml = """
        [layout]
        smallScreenThreshold = "big"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("smallScreenThreshold") && $0.title.contains("number")
        })
    }

    func testMaxGapFloatFails() {
        let toml = """
        [layout]
        maxGap = 5.5

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("maxGap") && $0.title.contains("integer")
        })
    }

    func testLayoutNotATableFails() {
        let toml = """
        layout = "not a table"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("[layout] must be a table")
        })
    }

    // MARK: - Unknown Keys

    func testUnknownLayoutKeyFails() {
        let toml = """
        [layout]
        unknownKey = "test"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized") && $0.title.contains("unknownKey")
        })
    }

    // MARK: - Layout in knownTopLevelKeys

    func testLayoutIsRecognizedTopLevelKey() {
        let toml = """
        [layout]
        windowHeight = 80

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        // Should NOT have a finding about "layout" being unrecognized
        XCTAssertFalse(result.findings.contains {
            $0.severity == .fail && $0.title.contains("Unrecognized") && $0.title.contains("layout")
        })
    }

    // MARK: - Multiple Invalid Values

    func testMultipleInvalidLayoutValuesAllReported() {
        let toml = """
        [layout]
        smallScreenThreshold = -1
        windowHeight = 200
        idePosition = "center"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        let failTitles = result.findings.filter { $0.severity == .fail }.map { $0.title }
        XCTAssertTrue(failTitles.contains { $0.contains("smallScreenThreshold") })
        XCTAssertTrue(failTitles.contains { $0.contains("windowHeight") })
        XCTAssertTrue(failTitles.contains { $0.contains("idePosition") })
    }
}
