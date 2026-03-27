import XCTest
@testable import ProjectSwitcherCore

final class AppConfigTests: XCTestCase {

    // MARK: - [app] Section Parsing

    func testParseAppSectionTrue() {
        let toml = """
        [app]
        autoStartAtLogin = true

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.app.autoStartAtLogin, true)
    }

    func testParseAppSectionFalse() {
        let toml = """
        [app]
        autoStartAtLogin = false

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.app.autoStartAtLogin, false)
    }

    func testParseAppSectionMissing() {
        let toml = """
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.app.autoStartAtLogin, false)
    }

    func testParseAppSectionAutoStartMissing() {
        let toml = """
        [app]

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNotNil(result.config)
        XCTAssertEqual(result.config?.app.autoStartAtLogin, false)
    }

    func testParseAppSectionInvalidType() {
        let toml = """
        [app]
        autoStartAtLogin = "yes"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains { $0.severity == .fail && $0.title.contains("app.autoStartAtLogin") })
    }

    func testParseAppSectionUnknownKey() {
        let toml = """
        [app]
        autoStartAtLogin = true
        unknownKey = "value"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains { $0.severity == .fail && $0.title.contains("unknownKey") })
    }

    func testParseAppSectionNotTable() {
        let toml = """
        app = "not a table"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let result = ConfigParser.parse(toml: toml)

        XCTAssertNil(result.config)
        XCTAssertTrue(result.findings.contains { $0.severity == .fail && $0.title.contains("[app] must be a table") })
    }

    // MARK: - Config Write-Back (Pure Function)

    func testWriteBackInsertsNewSection() {
        let original = """
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("[app]"))
        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
        // Original content preserved
        XCTAssertTrue(updated.contains("name = \"Test\""))
    }

    func testWriteBackUpdatesExistingKey() {
        let original = """
        [app]
        autoStartAtLogin = false

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
        XCTAssertFalse(updated.contains("autoStartAtLogin = false"))
        // Original content preserved
        XCTAssertTrue(updated.contains("name = \"Test\""))
    }

    func testWriteBackPreservesIndentationAndInlineCommentOnExistingKey() {
        let original = """
        [app]
        \tautoStartAtLogin = false   # keep comment

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("\tautoStartAtLogin = true   # keep comment"))
        XCTAssertFalse(updated.contains("\tautoStartAtLogin = false   # keep comment"))
    }

    func testWriteBackSetFalse() {
        let original = """
        [app]
        autoStartAtLogin = true

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: false)

        XCTAssertTrue(updated.contains("autoStartAtLogin = false"))
        XCTAssertFalse(updated.contains("autoStartAtLogin = true"))
    }

    func testWriteBackInsertsKeyIntoExistingEmptySection() {
        let original = """
        [app]

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("[app]"))
        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
        XCTAssertTrue(updated.contains("name = \"Test\""))
    }

    func testWriteBackPreservesComments() {
        let original = """
        # My config file
        # with comments

        [app]
        autoStartAtLogin = false

        # Chrome settings
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("# My config file"))
        XCTAssertTrue(updated.contains("# Chrome settings"))
        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
    }

    func testWriteBackRoundTrip() {
        let original = """
        [app]
        autoStartAtLogin = false

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        // Write true
        let step1 = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)
        let result1 = ConfigParser.parse(toml: step1)
        XCTAssertEqual(result1.config?.app.autoStartAtLogin, true)
        XCTAssertEqual(result1.config?.projects.count, 1)

        // Write false
        let step2 = ConfigWriteBack.updateAutoStartAtLogin(in: step1, value: false)
        let result2 = ConfigParser.parse(toml: step2)
        XCTAssertEqual(result2.config?.app.autoStartAtLogin, false)
        XCTAssertEqual(result2.config?.projects.count, 1)
    }

    func testWriteBackStopsAtDoubleSquareBracketSection() {
        // The [app] section scanner should stop at [[project]] headers
        let original = """
        [app]

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        // autoStartAtLogin should be inserted inside [app], not after [[project]]
        let lines = updated.components(separatedBy: "\n")
        let appIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[app]" }!
        let keyIndex = lines.firstIndex { $0.contains("autoStartAtLogin = true") }!
        let projectIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[[project]]" }!

        XCTAssertTrue(keyIndex > appIndex, "Key should be after [app]")
        XCTAssertTrue(keyIndex < projectIndex, "Key should be before [[project]]")
    }

    func testWriteBackDoesNotMatchPrefixKey() {
        // A key named "autoStartAtLoginExtra" should NOT be matched
        let original = """
        [app]
        autoStartAtLoginExtra = "some_value"

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        // The original key should be preserved
        XCTAssertTrue(updated.contains("autoStartAtLoginExtra = \"some_value\""))
        // A new autoStartAtLogin key should be inserted
        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
    }

    func testWriteBackExactKeyWithEquals() {
        // Key with no spaces: "autoStartAtLogin=false" should still be matched
        let original = """
        [app]
        autoStartAtLogin=false

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
        XCTAssertFalse(updated.contains("autoStartAtLogin=false"))
    }

    func testWriteBackMatchesSectionWithInlineComment() {
        // [app] with inline comment should still be found (not append a duplicate)
        let original = """
        [app] # app settings
        autoStartAtLogin = false

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
        XCTAssertFalse(updated.contains("autoStartAtLogin = false"))
        // Must NOT append a second [app] section
        let appCount = updated.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[app]") }
            .count
        XCTAssertEqual(appCount, 1, "Should not duplicate [app] section")
    }

    func testWriteBackInsertsKeyIntoCommentedSection() {
        // [app] with inline comment but no existing key
        let original = """
        [app] # app settings

        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        let updated = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)

        XCTAssertTrue(updated.contains("autoStartAtLogin = true"))
        // Key should be between [app] and [[project]]
        let lines = updated.components(separatedBy: "\n")
        let appIndex = lines.firstIndex { $0.contains("[app]") }!
        let keyIndex = lines.firstIndex { $0.contains("autoStartAtLogin = true") }!
        let projectIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "[[project]]" }!
        XCTAssertTrue(keyIndex > appIndex)
        XCTAssertTrue(keyIndex < projectIndex)
    }

    func testWriteBackRoundTripFromNoSection() {
        let original = """
        [[project]]
        name = "Test"
        path = "/Users/test/project"
        color = "blue"
        """

        // Insert [app] section with true
        let step1 = ConfigWriteBack.updateAutoStartAtLogin(in: original, value: true)
        let result1 = ConfigParser.parse(toml: step1)
        XCTAssertEqual(result1.config?.app.autoStartAtLogin, true)
        XCTAssertEqual(result1.config?.projects.count, 1)
        XCTAssertEqual(result1.config?.projects.first?.name, "Test")
    }
}
