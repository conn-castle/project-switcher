import XCTest

@testable import ProjectSwitcherCore

extension VSCodeSettingsManagerTests {

    // MARK: - injectBlock: workbench.colorCustomizations

    func testInjectBlockWithColorIncludesEmptyColorCustomizations() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj", color: "#8B5CF6"
        ).get()

        XCTAssertTrue(result.contains("\"workbench.colorCustomizations\": {}"))
    }

    func testInjectBlockWithoutColorExcludesColorCustomizations() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj"
        ).get()

        XCTAssertFalse(result.contains("workbench.colorCustomizations"))
    }

    func testInjectBlockPreservesExistingColorCustomizations() throws {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6",
            "titleBar.activeBackground": "#8b5cf6"
          }
          // <<< project-switcher
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj", color: "#8B5CF6"
        ).get()

        XCTAssertTrue(result.contains("\"statusBar.background\": \"#8b5cf6\""))
        XCTAssertTrue(result.contains("\"titleBar.activeBackground\": \"#8b5cf6\""))
    }

    func testInjectBlockPreservesColorCustomizationsAcrossIdentifierChange() throws {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:old-proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6"
          }
          // <<< project-switcher
          "editor.fontSize": 14
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(
            into: content, identifier: "new-proj", color: "#8B5CF6"
        ).get()

        XCTAssertTrue(result.contains("PS:new-proj"))
        XCTAssertFalse(result.contains("PS:old-proj"))
        XCTAssertTrue(result.contains("\"statusBar.background\": \"#8b5cf6\""))
        XCTAssertTrue(result.contains("\"editor.fontSize\": 14"))
    }

    // MARK: - injectBlock: trailing comma handling

    func testInjectBlockNoTrailingCommaWhenLastElement() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj", color: "#8B5CF6"
        ).get()

        // Last property should NOT have a trailing comma
        XCTAssertTrue(result.contains("\"workbench.colorCustomizations\": {}\n"))
        XCTAssertFalse(result.contains("\"workbench.colorCustomizations\": {},"))
    }

    func testInjectBlockTrailingCommaWhenNotLastElement() throws {
        let content = """
        {
          "editor.fontSize": 14
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj", color: "#8B5CF6"
        ).get()

        // Last property should have a trailing comma since content follows
        XCTAssertTrue(result.contains("\"workbench.colorCustomizations\": {},"))
    }

    func testInjectBlockNoTrailingCommaWithoutColorWhenLastElement() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(
            into: "{}\n", identifier: "proj"
        ).get()

        // window.title is the last property and should NOT have a trailing comma
        XCTAssertFalse(result.contains("${appName}\","))
        XCTAssertTrue(result.contains("${appName}\""))
    }

    func testInjectBlockTrailingCommaWithoutColorWhenNotLastElement() throws {
        let content = """
        {
          "editor.fontSize": 14
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj"
        ).get()

        // window.title should have a trailing comma since content follows
        XCTAssertTrue(result.contains("${appName}\","))
    }

    func testInjectBlockPreservesMultiLineColorCustomizationsWithTrailingComma() throws {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:proj - ${dirty}${activeEditorShort}${separator}${rootName}${separator}${appName}",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6",
            "titleBar.activeBackground": "#8b5cf6"
          }
          // <<< project-switcher
          "editor.fontSize": 14
        }
        """

        let result = try PsVSCodeSettingsManager.injectBlock(
            into: content, identifier: "proj", color: "#8B5CF6"
        ).get()

        // Multi-line value should have comma after closing } since content follows
        XCTAssertTrue(result.contains("\"titleBar.activeBackground\": \"#8b5cf6\""))
        XCTAssertTrue(result.contains("  },"))
    }

    // MARK: - extractColorCustomizations

    func testExtractColorCustomizationsReturnsEmptyObject() {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:proj",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {}
          // <<< project-switcher
        }
        """

        let result = PsVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertEqual(result, "{}")
    }

    func testExtractColorCustomizationsReturnsPopulatedObject() {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:proj",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6",
          "workbench.colorCustomizations": {
            "statusBar.background": "#8b5cf6",
            "titleBar.activeBackground": "#8b5cf6"
          }
          // <<< project-switcher
        }
        """

        let result = PsVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("\"statusBar.background\": \"#8b5cf6\""))
        XCTAssertTrue(result!.contains("\"titleBar.activeBackground\": \"#8b5cf6\""))
        XCTAssertTrue(result!.hasPrefix("{"))
        XCTAssertTrue(result!.hasSuffix("}"))
    }

    func testExtractColorCustomizationsReturnsNilWhenKeyMissing() {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:proj",
          "peacock.color": "#8B5CF6",
          "peacock.remoteColor": "#8B5CF6"
          // <<< project-switcher
        }
        """

        let result = PsVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNil(result)
    }

    func testExtractColorCustomizationsReturnsNilWhenNoBlock() {
        let content = """
        {
          "editor.fontSize": 14
        }
        """

        let result = PsVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNil(result)
    }

    func testExtractColorCustomizationsIgnoresKeyOutsideBlock() {
        let content = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:proj"
          // <<< project-switcher
          "workbench.colorCustomizations": {
            "statusBar.background": "#ff0000"
          }
        }
        """

        let result = PsVSCodeSettingsManager.extractColorCustomizations(from: content)
        XCTAssertNil(result)
    }
}
