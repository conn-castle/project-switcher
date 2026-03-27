import Foundation
import XCTest

@testable import ProjectSwitcherCore

final class SwitcherPerformanceTests: XCTestCase {
    // MARK: - Config Fingerprint

    func testFingerprintFromAttributesReturnsValueWhenSizeAndDatePresent() {
        let now = Date()
        let attributes: [FileAttributeKey: Any] = [
            .size: NSNumber(value: 128),
            .modificationDate: now
        ]

        let fingerprint = SwitcherConfigFingerprint.from(fileAttributes: attributes)

        XCTAssertNotNil(fingerprint)
        XCTAssertEqual(fingerprint?.sizeBytes, 128)
        XCTAssertEqual(fingerprint?.modificationDate, now)
    }

    func testFingerprintFromAttributesReturnsNilWhenSizeMissing() {
        let attributes: [FileAttributeKey: Any] = [
            .modificationDate: Date()
        ]

        XCTAssertNil(SwitcherConfigFingerprint.from(fileAttributes: attributes))
    }

    func testFingerprintFromAttributesReturnsNilWhenDateMissing() {
        let attributes: [FileAttributeKey: Any] = [
            .size: NSNumber(value: 42)
        ]

        XCTAssertNil(SwitcherConfigFingerprint.from(fileAttributes: attributes))
    }

    func testReloadPolicyRequiresReloadWhenCurrentFingerprintMissing() {
        let previous = SwitcherConfigFingerprint(sizeBytes: 10, modificationDate: Date())

        XCTAssertTrue(SwitcherConfigReloadPolicy.shouldReload(previous: previous, current: nil))
    }

    func testReloadPolicyRequiresReloadOnFirstFingerprint() {
        let current = SwitcherConfigFingerprint(sizeBytes: 10, modificationDate: Date())

        XCTAssertTrue(SwitcherConfigReloadPolicy.shouldReload(previous: nil, current: current))
    }

    func testReloadPolicySkipsReloadWhenFingerprintUnchanged() {
        let now = Date()
        let previous = SwitcherConfigFingerprint(sizeBytes: 10, modificationDate: now)
        let current = SwitcherConfigFingerprint(sizeBytes: 10, modificationDate: now)

        XCTAssertFalse(SwitcherConfigReloadPolicy.shouldReload(previous: previous, current: current))
    }

    func testReloadPolicyRequiresReloadWhenFingerprintChanges() {
        let now = Date()
        let previous = SwitcherConfigFingerprint(sizeBytes: 10, modificationDate: now)
        let current = SwitcherConfigFingerprint(sizeBytes: 11, modificationDate: now)

        XCTAssertTrue(SwitcherConfigReloadPolicy.shouldReload(previous: previous, current: current))
    }

    // MARK: - Debounce Tokens

    func testDebounceTokenSourceOnlyLatestTokenIsValid() {
        var source = DebounceTokenSource()
        let first = source.issueToken()
        let second = source.issueToken()

        XCTAssertFalse(source.isLatest(first))
        XCTAssertTrue(source.isLatest(second))
    }

    func testDebounceTokenSourceMarksLatestTokenValid() {
        var source = DebounceTokenSource()
        let token = source.issueToken()

        XCTAssertTrue(source.isLatest(token))
    }

    // MARK: - Reload Planner

    func testReloadPlannerReturnsNoReloadWhenStructureAndContentUnchanged() {
        let rows = [
            SwitcherRowSignature(kind: .sectionHeader, selectionKey: nil),
            SwitcherRowSignature(kind: .project, selectionKey: "project:a")
        ]

        let mode = SwitcherTableReloadPlanner.plan(
            previous: rows,
            next: rows,
            contentChanged: false
        )

        XCTAssertEqual(mode, .noReload)
    }

    func testReloadPlannerReturnsVisibleRowsReloadWhenStructureSameButContentChanged() {
        let previous = [
            SwitcherRowSignature(kind: .project, selectionKey: "project:a")
        ]
        let next = [
            SwitcherRowSignature(kind: .project, selectionKey: "project:a")
        ]

        let mode = SwitcherTableReloadPlanner.plan(
            previous: previous,
            next: next,
            contentChanged: true
        )

        XCTAssertEqual(mode, .visibleRowsReload)
    }

    func testReloadPlannerReturnsFullReloadWhenRowCountChanges() {
        let previous = [
            SwitcherRowSignature(kind: .project, selectionKey: "project:a")
        ]
        let next = [
            SwitcherRowSignature(kind: .sectionHeader, selectionKey: nil),
            SwitcherRowSignature(kind: .project, selectionKey: "project:a")
        ]

        let mode = SwitcherTableReloadPlanner.plan(
            previous: previous,
            next: next,
            contentChanged: true
        )

        XCTAssertEqual(mode, .fullReload)
    }

    func testReloadPlannerReturnsFullReloadWhenOrderChanges() {
        let previous = [
            SwitcherRowSignature(kind: .project, selectionKey: "project:a"),
            SwitcherRowSignature(kind: .project, selectionKey: "project:b")
        ]
        let next = [
            SwitcherRowSignature(kind: .project, selectionKey: "project:b"),
            SwitcherRowSignature(kind: .project, selectionKey: "project:a")
        ]

        let mode = SwitcherTableReloadPlanner.plan(
            previous: previous,
            next: next,
            contentChanged: true
        )

        XCTAssertEqual(mode, .fullReload)
    }

    func testReloadPlannerReturnsFullReloadWhenRowTypeChanges() {
        let previous = [
            SwitcherRowSignature(kind: .project, selectionKey: "project:a")
        ]
        let next = [
            SwitcherRowSignature(kind: .emptyState, selectionKey: nil)
        ]

        let mode = SwitcherTableReloadPlanner.plan(
            previous: previous,
            next: next,
            contentChanged: true
        )

        XCTAssertEqual(mode, .fullReload)
    }
}
