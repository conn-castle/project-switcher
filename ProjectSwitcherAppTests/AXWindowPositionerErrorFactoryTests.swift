import XCTest

@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

final class AXWindowPositionerErrorFactoryTests: XCTestCase {

    // MARK: - windowTokenNotFoundError

    func testWindowTokenNotFoundErrorHasCorrectReason() {
        let error = AXWindowPositioner.windowTokenNotFoundError(
            bundleId: "com.microsoft.VSCode", token: "PS:myProject"
        )
        XCTAssertEqual(error.reason, .windowTokenNotFound)
    }

    func testWindowTokenNotFoundErrorHasWindowCategory() {
        let error = AXWindowPositioner.windowTokenNotFoundError(
            bundleId: "com.microsoft.VSCode", token: "PS:myProject"
        )
        XCTAssertEqual(error.category, .window)
    }

    func testWindowTokenNotFoundErrorMessageIncludesTokenAndBundleId() {
        let error = AXWindowPositioner.windowTokenNotFoundError(
            bundleId: "com.google.Chrome", token: "PS:proj-1"
        )
        XCTAssertTrue(error.message.contains("PS:proj-1"))
        XCTAssertTrue(error.message.contains("com.google.Chrome"))
    }

    func testWindowTokenNotFoundErrorIsClassifiedCorrectly() {
        let error = AXWindowPositioner.windowTokenNotFoundError(
            bundleId: "com.microsoft.VSCode", token: "PS:x"
        )
        XCTAssertTrue(error.isWindowTokenNotFound)
        XCTAssertFalse(error.isWindowInventoryEmpty)
    }

    // MARK: - windowInventoryEmptyError

    func testWindowInventoryEmptyErrorHasCorrectReason() {
        let error = AXWindowPositioner.windowInventoryEmptyError(
            bundleId: "com.microsoft.VSCode"
        )
        XCTAssertEqual(error.reason, .windowInventoryEmpty)
    }

    func testWindowInventoryEmptyErrorHasWindowCategory() {
        let error = AXWindowPositioner.windowInventoryEmptyError(
            bundleId: "com.microsoft.VSCode"
        )
        XCTAssertEqual(error.category, .window)
    }

    func testWindowInventoryEmptyErrorMessageIncludesBundleId() {
        let error = AXWindowPositioner.windowInventoryEmptyError(
            bundleId: "com.google.Chrome"
        )
        XCTAssertTrue(error.message.contains("com.google.Chrome"))
    }

    func testWindowInventoryEmptyErrorIsClassifiedCorrectly() {
        let error = AXWindowPositioner.windowInventoryEmptyError(
            bundleId: "com.microsoft.VSCode"
        )
        XCTAssertTrue(error.isWindowInventoryEmpty)
        XCTAssertFalse(error.isWindowTokenNotFound)
    }
}
