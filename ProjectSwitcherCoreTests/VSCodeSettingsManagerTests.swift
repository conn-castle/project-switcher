import XCTest
@testable import ProjectSwitcherCore

/// Tests for `PsVSCodeSettingsManager`.
final class VSCodeSettingsManagerTests: XCTestCase {

    // MARK: - injectBlock: empty object

    func testInjectBlockIntoEmptyObject() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(into: "{}\n", identifier: "my-proj").get()

        XCTAssertTrue(result.contains("// >>> project-switcher"))
        XCTAssertTrue(result.contains("// <<< project-switcher"))
        XCTAssertTrue(result.contains("\"window.title\": \"PS:my-proj"))
        XCTAssertTrue(result.hasPrefix("{"))
        XCTAssertTrue(result.hasSuffix("}"))
    }

    func testInjectBlockIntoMinimalEmptyObject() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(into: "{}", identifier: "test").get()

        XCTAssertTrue(result.contains("// >>> project-switcher"))
        XCTAssertTrue(result.contains("PS:test"))
        XCTAssertTrue(result.hasPrefix("{"))
        XCTAssertTrue(result.hasSuffix("}"))
    }

    // MARK: - injectBlock: existing settings

    func testInjectBlockIntoObjectWithExistingSettings() throws {
        let content = """
        {
          "editor.fontSize": 14,
          "editor.tabSize": 2
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(into: content, identifier: "proj").get()

        XCTAssertTrue(result.contains("// >>> project-switcher"))
        XCTAssertTrue(result.contains("PS:proj"))
        XCTAssertTrue(result.contains("\"editor.fontSize\": 14"))
        XCTAssertTrue(result.contains("\"editor.tabSize\": 2"))
    }

    // MARK: - injectBlock: replaces existing block

    func testInjectBlockReplacesExistingBlock() throws {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:old-proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          // <<< project-switcher
          "editor.fontSize": 14
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(into: content, identifier: "new-proj").get()

        XCTAssertTrue(result.contains("PS:new-proj"))
        XCTAssertFalse(result.contains("PS:old-proj"))
        XCTAssertTrue(result.contains("\"editor.fontSize\": 14"))

        // Should have exactly one start marker and one end marker
        let startCount = result.components(separatedBy: "// >>> project-switcher").count - 1
        let endCount = result.components(separatedBy: "// <<< project-switcher").count - 1
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endCount, 1)
    }

    // MARK: - injectBlock: coexists with agent-layer block

    func testInjectBlockCoexistsWithAgentLayerBlock() throws {
        let content = """
        {
          // >>> agent-layer
          // Managed by Agent Layer.
          "some.setting": true,
          // <<< agent-layer
          "editor.fontSize": 14
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(into: content, identifier: "proj").get()

        XCTAssertTrue(result.contains("// >>> project-switcher"))
        XCTAssertTrue(result.contains("// <<< project-switcher"))
        XCTAssertTrue(result.contains("// >>> agent-layer"))
        XCTAssertTrue(result.contains("// <<< agent-layer"))
        XCTAssertTrue(result.contains("PS:proj"))
        XCTAssertTrue(result.contains("\"some.setting\": true"))
    }

    // MARK: - injectBlock: malformed input (no brace)

    func testInjectBlockReturnsErrorForNoBrace() {
        let content = "not valid json"

        let result = PsVSCodeSettingsManager.injectBlock(into: content, identifier: "proj")

        if case .failure(let error) = result {
            XCTAssertTrue(error.message.contains("no opening '{'"))
        } else {
            XCTFail("Expected failure for content with no opening brace")
        }
    }

    // MARK: - injectBlock: unbalanced markers (safety)

    func testInjectBlockReturnsErrorWhenOnlyStartMarkerExists() {
        let content = """
        {
          // >>> project-switcher
          "window.title": "old value",
          "editor.fontSize": 14
        }
        """

        let result = PsVSCodeSettingsManager.injectBlock(into: content, identifier: "new-proj")

        switch result {
        case .success:
            XCTFail("Expected failure for unbalanced markers")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("unbalanced"))
            XCTAssertTrue(error.message.contains("// >>> project-switcher"))
            XCTAssertTrue(error.message.contains("// <<< project-switcher"))
        }
    }

    func testInjectBlockReturnsErrorWhenOnlyEndMarkerExists() {
        let content = """
        {
          "editor.fontSize": 14,
          // <<< project-switcher
          "editor.tabSize": 2
        }
        """

        let result = PsVSCodeSettingsManager.injectBlock(into: content, identifier: "proj")

        switch result {
        case .success:
            XCTFail("Expected failure for unbalanced markers")
        case .failure(let error):
            XCTAssertTrue(error.message.contains("unbalanced"))
        }
    }

    // MARK: - injectBlock: window title format

    func testInjectBlockGeneratesCorrectWindowTitle() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(into: "{}", identifier: "test-123").get()

        let expected = "PS:test-123 - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}"
        XCTAssertTrue(result.contains(expected), "Window title should match expected format, got: \(result)")
    }

    // MARK: - PsSSHHelpers: remote authority parsing

    func testParseRemoteAuthorityHappyPath() throws {
        let target = try PsSSHHelpers.parseRemoteAuthority("ssh-remote+user@host.com").get()
        XCTAssertEqual(target, "user@host.com")
    }

    func testParseRemoteAuthorityRejectsWrongPrefix() {
        let result = PsSSHHelpers.parseRemoteAuthority("dev-container+user@host")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .missingPrefix)
        } else {
            XCTFail("Expected failure for wrong prefix")
        }
    }

    func testParseRemoteAuthorityRejectsWhitespace() {
        let result = PsSSHHelpers.parseRemoteAuthority("ssh-remote+user@host ")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .containsWhitespace)
        } else {
            XCTFail("Expected failure for whitespace in authority")
        }
    }

    func testParseRemoteAuthorityRejectsEmptyTarget() {
        let result = PsSSHHelpers.parseRemoteAuthority("ssh-remote+")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .missingTarget)
        } else {
            XCTFail("Expected failure for empty target")
        }
    }

    func testParseRemoteAuthorityRejectsDashPrefix() {
        let result = PsSSHHelpers.parseRemoteAuthority("ssh-remote+-flag")
        if case .failure(let error) = result {
            XCTAssertEqual(error, .targetStartsWithDash)
        } else {
            XCTFail("Expected failure for dash-prefixed target")
        }
    }

    // MARK: - PsSSHHelpers: shell escaping

    func testShellEscapeSimpleString() {
        XCTAssertEqual(PsSSHHelpers.shellEscape("hello"), "'hello'")
    }

    func testShellEscapeSingleQuote() {
        XCTAssertEqual(PsSSHHelpers.shellEscape("it's"), "'it'\\''s'")
    }

    func testShellEscapePathWithSpaces() {
        XCTAssertEqual(PsSSHHelpers.shellEscape("/path/to/my project"), "'/path/to/my project'")
    }

    func testShellEscapeMultipleSingleQuotes() {
        XCTAssertEqual(PsSSHHelpers.shellEscape("a'b'c"), "'a'\\''b'\\''c'")
    }

}
