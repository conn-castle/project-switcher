import XCTest
@testable import ProjectSwitcherCore

final class LayoutConfigParserTests: XCTestCase {

    /// Helper: minimal valid project TOML for tests that need a valid config.
    let minimalProject = """
    [[project]]
    name = "Test"
    path = "/test"
    color = "blue"
    """

    // MARK: - Defaults (no [layout] section)

    func testNoLayoutSectionUsesDefaults() {
        let toml = minimalProject
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        let layout = result.config!.layout
        XCTAssertEqual(layout.smallScreenThreshold, 24)
        XCTAssertEqual(layout.windowHeight, 90)
        XCTAssertEqual(layout.maxWindowWidth, 18)
        XCTAssertEqual(layout.idePosition, .left)
        XCTAssertEqual(layout.justification, .right)
        XCTAssertEqual(layout.maxGap, 10)
    }

    func testEmptyLayoutSectionUsesDefaults() {
        let toml = """
        [layout]

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        let layout = result.config!.layout
        XCTAssertEqual(layout.smallScreenThreshold, 24)
        XCTAssertEqual(layout.windowHeight, 90)
        XCTAssertEqual(layout.maxWindowWidth, 18)
        XCTAssertEqual(layout.idePosition, .left)
        XCTAssertEqual(layout.justification, .right)
        XCTAssertEqual(layout.maxGap, 10)
    }

    // MARK: - Valid Custom Values

    func testCustomLayoutValues() {
        let toml = """
        [layout]
        smallScreenThreshold = 20
        windowHeight = 85
        maxWindowWidth = 16
        idePosition = "right"
        justification = "left"
        maxGap = 5

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        let layout = result.config!.layout
        XCTAssertEqual(layout.smallScreenThreshold, 20)
        XCTAssertEqual(layout.windowHeight, 85)
        XCTAssertEqual(layout.maxWindowWidth, 16)
        XCTAssertEqual(layout.idePosition, .right)
        XCTAssertEqual(layout.justification, .left)
        XCTAssertEqual(layout.maxGap, 5)
    }

    func testSmallScreenThresholdAcceptsFloat() {
        let toml = """
        [layout]
        smallScreenThreshold = 23.5

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config!.layout.smallScreenThreshold, 23.5)
    }

    func testMaxWindowWidthAcceptsFloat() {
        let toml = """
        [layout]
        maxWindowWidth = 15.5

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config!.layout.maxWindowWidth, 15.5)
    }

    func testPartialLayoutUsesDefaultsForOmittedFields() {
        let toml = """
        [layout]
        windowHeight = 80
        idePosition = "right"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        let layout = result.config!.layout
        XCTAssertEqual(layout.smallScreenThreshold, 24) // default
        XCTAssertEqual(layout.windowHeight, 80)
        XCTAssertEqual(layout.maxWindowWidth, 18) // default
        XCTAssertEqual(layout.idePosition, .right)
        XCTAssertEqual(layout.justification, .right) // default
        XCTAssertEqual(layout.maxGap, 10) // default
    }

    // MARK: - Boundary Values

    func testWindowHeightBoundaryMin() {
        let toml = """
        [layout]
        windowHeight = 1

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config!.layout.windowHeight, 1)
    }

    func testWindowHeightBoundaryMax() {
        let toml = """
        [layout]
        windowHeight = 100

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config!.layout.windowHeight, 100)
    }

    func testMaxGapBoundaryMin() {
        let toml = """
        [layout]
        maxGap = 0

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config!.layout.maxGap, 0)
    }

    func testMaxGapBoundaryMax() {
        let toml = """
        [layout]
        maxGap = 100

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config!.layout.maxGap, 100)
    }

    // MARK: - Invalid Values (hard-fail, config nil)

    func testNegativeSmallScreenThresholdFails() {
        let toml = """
        [layout]
        smallScreenThreshold = -1

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("smallScreenThreshold")
        })
    }

    func testZeroSmallScreenThresholdFails() {
        let toml = """
        [layout]
        smallScreenThreshold = 0

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("smallScreenThreshold")
        })
    }

    func testWindowHeightZeroFails() {
        let toml = """
        [layout]
        windowHeight = 0

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("windowHeight")
        })
    }

    func testWindowHeight101Fails() {
        let toml = """
        [layout]
        windowHeight = 101

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("windowHeight")
        })
    }

    func testNegativeWindowHeightFails() {
        let toml = """
        [layout]
        windowHeight = -5

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("windowHeight")
        })
    }

    func testZeroMaxWindowWidthFails() {
        let toml = """
        [layout]
        maxWindowWidth = 0

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("maxWindowWidth")
        })
    }

    func testNegativeMaxWindowWidthFails() {
        let toml = """
        [layout]
        maxWindowWidth = -2

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("maxWindowWidth")
        })
    }

    func testIdePositionInvalidStringFails() {
        let toml = """
        [layout]
        idePosition = "center"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("idePosition")
        })
    }

    func testJustificationInvalidStringFails() {
        let toml = """
        [layout]
        justification = "middle"

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("justification")
        })
    }

    func testMaxGapNegativeFails() {
        let toml = """
        [layout]
        maxGap = -1

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("maxGap")
        })
    }

    func testMaxGap101Fails() {
        let toml = """
        [layout]
        maxGap = 101

        \(minimalProject)
        """
        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .fail && $0.title.contains("maxGap")
        })
    }

}
