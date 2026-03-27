import XCTest
@testable import ProjectSwitcherCore

final class VSCodeColorPaletteTests: XCTestCase {

    // MARK: - Hex conversion

    func testToHexBlack() {
        XCTAssertEqual(VSCodeColorPalette.toHex(ProjectColorRGB(red: 0.0, green: 0.0, blue: 0.0)), "#000000")
    }

    func testToHexWhite() {
        XCTAssertEqual(VSCodeColorPalette.toHex(ProjectColorRGB(red: 1.0, green: 1.0, blue: 1.0)), "#FFFFFF")
    }

    func testToHexRed() {
        XCTAssertEqual(VSCodeColorPalette.toHex(ProjectColorRGB(red: 1.0, green: 0.0, blue: 0.0)), "#FF0000")
    }

    func testToHexArbitraryColor() {
        // 128/255 ≈ 0.5020
        XCTAssertEqual(VSCodeColorPalette.toHex(ProjectColorRGB(red: 0.5020, green: 0.5020, blue: 0.5020)), "#808080")
    }

    // MARK: - peacockColorHex

    func testPeacockColorHexForNamedColor() {
        let hex = VSCodeColorPalette.peacockColorHex(for: "blue")
        XCTAssertEqual(hex, "#0000FF")
    }

    func testPeacockColorHexForHexColor() {
        let hex = VSCodeColorPalette.peacockColorHex(for: "#FF8800")
        XCTAssertEqual(hex, "#FF8800")
    }

    func testPeacockColorHexForInvalidColorReturnsNil() {
        XCTAssertNil(VSCodeColorPalette.peacockColorHex(for: "nonexistent"))
    }

    func testPeacockColorHexForAllNamedColors() {
        let namedColors = [
            "black", "blue", "brown", "cyan", "gray", "grey", "green",
            "indigo", "orange", "pink", "purple", "red", "teal", "white", "yellow"
        ]

        for name in namedColors {
            let hex = VSCodeColorPalette.peacockColorHex(for: name)
            XCTAssertNotNil(hex, "Expected hex for '\(name)'")
            guard let hex else { continue }
            XCTAssertTrue(hex.hasPrefix("#"), "Hex should start with # for '\(name)'")
            XCTAssertEqual(hex.count, 7, "Hex should be #RRGGBB format for '\(name)'")
        }
    }

    // MARK: - Settings block injection with Peacock color

    func testInjectBlockWithColorIncludesPeacockColor() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(
            into: "{}\n",
            identifier: "my-proj",
            color: "blue"
        ).get()

        XCTAssertTrue(result.contains("// >>> project-switcher"))
        XCTAssertTrue(result.contains("// <<< project-switcher"))
        XCTAssertTrue(result.contains("\"window.title\": \"PS:my-proj"))
        XCTAssertTrue(result.contains("\"peacock.color\": \"#0000FF\""))
        XCTAssertTrue(result.contains("\"peacock.remoteColor\": \"#0000FF\""))
        XCTAssertTrue(result.contains("\"workbench.colorCustomizations\": {}"))
    }

    func testInjectBlockWithNilColorOmitsPeacockColor() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(
            into: "{}\n",
            identifier: "my-proj",
            color: nil
        ).get()

        XCTAssertTrue(result.contains("\"window.title\":"))
        XCTAssertFalse(result.contains("peacock.color"))
        XCTAssertFalse(result.contains("peacock.remoteColor"))
    }

    func testInjectBlockWithInvalidColorOmitsPeacockColor() throws {
        let result = try PsVSCodeSettingsManager.injectBlock(
            into: "{}\n",
            identifier: "my-proj",
            color: "nonexistent"
        ).get()

        XCTAssertTrue(result.contains("\"window.title\":"))
        XCTAssertFalse(result.contains("peacock.color"))
        XCTAssertFalse(result.contains("peacock.remoteColor"))
    }

    func testInjectBlockReplacesExistingBlockIncludingColors() throws {
        // First inject with blue
        let first = try PsVSCodeSettingsManager.injectBlock(
            into: "{\n  \"editor.fontSize\": 14\n}",
            identifier: "proj",
            color: "blue"
        ).get()

        // Then replace with red
        let second = try PsVSCodeSettingsManager.injectBlock(
            into: first,
            identifier: "proj",
            color: "red"
        ).get()

        XCTAssertTrue(second.contains("\"peacock.color\": \"#FF0000\""))
        XCTAssertTrue(second.contains("\"peacock.remoteColor\": \"#FF0000\""))
        XCTAssertFalse(second.contains("#0000FF"))
        XCTAssertTrue(second.contains("\"editor.fontSize\": 14"))
    }
}
