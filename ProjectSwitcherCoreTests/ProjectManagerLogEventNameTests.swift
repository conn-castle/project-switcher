import XCTest
@testable import ProjectSwitcherCore

final class ProjectManagerLogEventNameTests: XCTestCase {

    func testActivationWindowEventNameForChromeHasStableShape() {
        let event = ProjectManager.activationWindowEventName(source: "chrome", action: "found")
        XCTAssertEqual(event, "select.chrome_found")
        XCTAssertFalse(event.contains(" "))
    }

    func testActivationWindowEventNameForVSCodeHasStableShape() {
        let event = ProjectManager.activationWindowEventName(source: "vscode", action: "launch_failed")
        XCTAssertEqual(event, "select.vscode_launch_failed")
        XCTAssertFalse(event.contains(" "))
    }
}
