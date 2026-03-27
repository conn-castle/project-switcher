import XCTest
@testable import ProjectSwitcherCore

final class IdNormalizationTests: XCTestCase {

    // MARK: - Direct IdNormalizer Tests

    func testNormalizeSimpleName() {
        XCTAssertEqual(IdNormalizer.normalize("MyProject"), "myproject")
    }

    func testNormalizeWithSpaces() {
        XCTAssertEqual(IdNormalizer.normalize("My Cool Project"), "my-cool-project")
    }

    func testNormalizeWithSpecialCharacters() {
        XCTAssertEqual(IdNormalizer.normalize("Project@2024!Test"), "project-2024-test")
    }

    func testNormalizePreservesNumbers() {
        XCTAssertEqual(IdNormalizer.normalize("Project123"), "project123")
    }

    func testNormalizeCollapsesMultipleHyphens() {
        let result = IdNormalizer.normalize("My   Spaced   Project")
        XCTAssertFalse(result.contains("--"))
        XCTAssertEqual(result, "my-spaced-project")
    }

    func testNormalizePreservesHyphens() {
        XCTAssertEqual(IdNormalizer.normalize("Already-Hyphenated"), "already-hyphenated")
    }

    func testNormalizeConvertsUnderscores() {
        XCTAssertEqual(IdNormalizer.normalize("Snake_Case_Name"), "snake-case-name")
    }

    func testNormalizeUppercaseToLowercase() {
        XCTAssertEqual(IdNormalizer.normalize("UPPERCASE"), "uppercase")
    }

    func testNormalizeMixedCase() {
        XCTAssertEqual(IdNormalizer.normalize("CamelCaseProject"), "camelcaseproject")
    }

    func testNormalizeTrimsWhitespace() {
        XCTAssertEqual(IdNormalizer.normalize("  trimmed  "), "trimmed")
    }

    func testNormalizeTrimsLeadingTrailingHyphens() {
        XCTAssertEqual(IdNormalizer.normalize("--test--"), "test")
    }

    func testNormalizeEmptyString() {
        XCTAssertEqual(IdNormalizer.normalize(""), "")
        XCTAssertFalse(IdNormalizer.isValid(""))
    }

    func testNormalizeOnlySpecialChars() {
        XCTAssertEqual(IdNormalizer.normalize("@#$%"), "")
        XCTAssertFalse(IdNormalizer.isValid("@#$%"))
    }

    func testIsValidWithValidInput() {
        XCTAssertTrue(IdNormalizer.isValid("My Project"))
        XCTAssertTrue(IdNormalizer.isValid("test123"))
    }

    func testIsReservedInbox() {
        XCTAssertTrue(IdNormalizer.isReserved("inbox"))
        XCTAssertFalse(IdNormalizer.isReserved("myinbox"))
    }

    // MARK: - Integration with ConfigParser

    func testSimpleName() {
        let toml = """
        [[project]]
        name = "MyProject"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertEqual(result.projects.first?.id, "myproject")
    }

    func testNameWithSpaces() {
        let toml = """
        [[project]]
        name = "My Cool Project"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertEqual(result.projects.first?.id, "my-cool-project")
    }

    func testNameWithSpecialCharacters() {
        let toml = """
        [[project]]
        name = "Project@2024!Test"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertEqual(result.projects.first?.id, "project-2024-test")
    }

    func testNamePreservesNumbers() {
        let toml = """
        [[project]]
        name = "Project123"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertEqual(result.projects.first?.id, "project123")
    }

    func testNameWithMultipleSpaces() {
        let toml = """
        [[project]]
        name = "My   Spaced   Project"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        // Multiple spaces become multiple hyphens, then collapsed
        XCTAssertFalse(result.projects.first?.id.contains("--") ?? true)
    }

    func testNameWithHyphens() {
        let toml = """
        [[project]]
        name = "Already-Hyphenated"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertEqual(result.projects.first?.id, "already-hyphenated")
    }

    func testNameWithUnderscores() {
        let toml = """
        [[project]]
        name = "Snake_Case_Name"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        // Underscores should be converted to hyphens
        XCTAssertEqual(result.projects.first?.id, "snake-case-name")
    }

    func testNameUppercaseToLowercase() {
        let toml = """
        [[project]]
        name = "UPPERCASE"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        XCTAssertEqual(result.projects.first?.id, "uppercase")
    }

    func testNameMixedCase() {
        let toml = """
        [[project]]
        name = "CamelCaseProject"
        path = "/test"
        color = "blue"
        useAgentLayer = false
        """
        let result = ConfigParser.parse(toml: toml)
        // Should be lowercased but not split on case boundaries
        XCTAssertEqual(result.projects.first?.id, "camelcaseproject")
    }
}
