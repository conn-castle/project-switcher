import XCTest
@testable import ProjectSwitcherCore

final class ColorValidationTests: XCTestCase {

    func testValidHexColor() {
        XCTAssertNotNil(ProjectColorPalette.resolve("#FF5500"))
        XCTAssertNotNil(ProjectColorPalette.resolve("#ffffff"))
        XCTAssertNotNil(ProjectColorPalette.resolve("#000000"))
        XCTAssertNotNil(ProjectColorPalette.resolve("#AABBCC"))
    }

    func testInvalidHexColorTooShort() {
        XCTAssertNil(ProjectColorPalette.resolve("#FFF"))
        XCTAssertNil(ProjectColorPalette.resolve("#FF"))
        XCTAssertNil(ProjectColorPalette.resolve("#F"))
    }

    func testInvalidHexColorMissingHash() {
        XCTAssertNil(ProjectColorPalette.resolve("FF5500"))
        XCTAssertNil(ProjectColorPalette.resolve("ffffff"))
    }

    func testInvalidHexColorBadCharacters() {
        XCTAssertNil(ProjectColorPalette.resolve("#GGGGGG"))
        XCTAssertNil(ProjectColorPalette.resolve("#ZZZZZZ"))
        XCTAssertNil(ProjectColorPalette.resolve("#12345G"))
    }

    func testNamedColorsResolve() {
        for name in ProjectColorPalette.sortedNames {
            XCTAssertNotNil(
                ProjectColorPalette.resolve(name),
                "Named color '\(name)' should resolve"
            )
        }
    }

    func testNamedColorsCaseInsensitive() {
        XCTAssertNotNil(ProjectColorPalette.resolve("BLUE"))
        XCTAssertNotNil(ProjectColorPalette.resolve("Blue"))
        XCTAssertNotNil(ProjectColorPalette.resolve("blue"))

        XCTAssertNotNil(ProjectColorPalette.resolve("RED"))
        XCTAssertNotNil(ProjectColorPalette.resolve("Red"))
        XCTAssertNotNil(ProjectColorPalette.resolve("red"))
    }

    func testUnknownColorReturnsNil() {
        XCTAssertNil(ProjectColorPalette.resolve("not-a-color"))
        XCTAssertNil(ProjectColorPalette.resolve("rainbowsparkle"))
        XCTAssertNil(ProjectColorPalette.resolve(""))
    }

    func testRGBValuesAreValid() {
        // Verify that resolved colors have valid RGB values (0.0-1.0 range for NSColor)
        for name in ProjectColorPalette.sortedNames {
            if let rgb = ProjectColorPalette.resolve(name) {
                XCTAssertGreaterThanOrEqual(rgb.red, 0.0)
                XCTAssertLessThanOrEqual(rgb.red, 1.0)
                XCTAssertGreaterThanOrEqual(rgb.green, 0.0)
                XCTAssertLessThanOrEqual(rgb.green, 1.0)
                XCTAssertGreaterThanOrEqual(rgb.blue, 0.0)
                XCTAssertLessThanOrEqual(rgb.blue, 1.0)
            }
        }
    }
}
