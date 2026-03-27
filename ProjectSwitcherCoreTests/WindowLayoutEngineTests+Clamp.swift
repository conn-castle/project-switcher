import XCTest

@testable import ProjectSwitcherCore

extension WindowLayoutEngineTests {

    // MARK: - Clamp/Fit Logic

    func testClampOversizedWidth() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 0, y: 0, width: 2000, height: 800)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 1440)
        XCTAssertEqual(clamped.height, 800)
        // Centered horizontally
        XCTAssertEqual(clamped.midX, screen.midX, accuracy: 0.1)
    }

    func testClampOversizedHeight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 100, y: 100, width: 1000, height: 1200)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 1000)
        XCTAssertEqual(clamped.height, 900)
        // Centered because height was resized
        XCTAssertEqual(clamped.midY, screen.midY, accuracy: 0.1)
    }

    func testClampOversizedBothDimensions() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 0, y: 0, width: 2000, height: 1200)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 1440)
        XCTAssertEqual(clamped.height, 900)
        XCTAssertEqual(clamped.midX, screen.midX, accuracy: 0.1)
        XCTAssertEqual(clamped.midY, screen.midY, accuracy: 0.1)
    }

    func testClampOffScreenRight() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: 1200, y: 100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.width, 800)
        XCTAssertEqual(clamped.height, 600)
        XCTAssertLessThanOrEqual(clamped.maxX, screen.maxX + 0.1)
        XCTAssertGreaterThanOrEqual(clamped.origin.x, screen.minX)
    }

    func testClampOffScreenLeft() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(x: -200, y: 100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped.origin.x, 0)
        XCTAssertEqual(clamped.width, 800)
    }

    func testClampOffScreenBottom() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = CGRect(x: 100, y: -100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertGreaterThanOrEqual(clamped.origin.y, screen.minY)
    }

    func testClampOffScreenTop() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = CGRect(x: 100, y: 500, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertLessThanOrEqual(clamped.maxY, screen.maxY + 0.1)
    }

    func testClampFitsNoChange() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertEqual(clamped, frame)
    }

    func testClampOnSecondMonitor() {
        let screen = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 2500, y: -50, width: 800, height: 600)

        let clamped = WindowLayoutEngine.clampToScreen(frame: frame, screenVisibleFrame: screen)

        XCTAssertGreaterThanOrEqual(clamped.origin.x, screen.minX)
        XCTAssertGreaterThanOrEqual(clamped.origin.y, screen.minY)
        XCTAssertLessThanOrEqual(clamped.maxX, screen.maxX + 0.1)
        XCTAssertLessThanOrEqual(clamped.maxY, screen.maxY + 0.1)
    }
}
