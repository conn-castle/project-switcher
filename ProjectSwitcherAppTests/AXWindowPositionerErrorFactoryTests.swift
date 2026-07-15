import XCTest

@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

final class AXWindowPositionerErrorFactoryTests: XCTestCase {
    func testTokenMatcherRejectsLongerProjectIdPrefix() {
        XCTAssertTrue(AXWindowPositioner.matchesLeadingToken(title: "PS:sample-project - Chrome", token: "PS:sample-project"))
        XCTAssertTrue(AXWindowPositioner.matchesLeadingToken(title: "  PS:sample-project", token: "PS:sample-project"))
        XCTAssertFalse(AXWindowPositioner.matchesLeadingToken(title: "PS:sample-project-original - Chrome", token: "PS:sample-project"))
        XCTAssertFalse(AXWindowPositioner.matchesLeadingToken(title: "Notes PS:sample-project - Chrome", token: "PS:sample-project"))
    }


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

    // MARK: - windowEnumerationError

    func testCannotCompleteEnumerationErrorIsTransient() {
        let error = AXWindowPositioner.windowEnumerationError(
            bundleId: "com.microsoft.VSCode",
            axError: .cannotComplete
        )

        XCTAssertEqual(error.reason, .windowEnumerationIncomplete)
        XCTAssertTrue(error.isTransientWindowLookupFailure)
    }

    func testPermissionDeniedEnumerationErrorIsPermanent() {
        let error = AXWindowPositioner.windowEnumerationError(
            bundleId: "com.microsoft.VSCode",
            axError: .apiDisabled
        )

        XCTAssertNil(error.reason)
        XCTAssertFalse(error.isTransientWindowLookupFailure)
    }
}
