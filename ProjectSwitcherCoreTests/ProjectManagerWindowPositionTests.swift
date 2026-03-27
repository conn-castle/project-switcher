import Foundation
import XCTest
@testable import ProjectSwitcherCore

/// Tests for window positioning integration in ProjectManager
/// (selectProject positioning, closeProject capture, exitToNonProjectWindow capture).
final class ProjectManagerWindowPositionTests: XCTestCase {
    let defaultIdeFrame = CGRect(x: 100, y: 200, width: 1200, height: 800)
    let defaultChromeFrame = CGRect(x: 1400, y: 200, width: 1100, height: 800)
}
