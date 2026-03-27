import XCTest
@testable import ProjectSwitcherCore

final class FocusHistoryStoreCoverageTests: XCTestCase {
    private let focusHistoryFile = URL(fileURLWithPath: "/focus-history-coverage.json", isDirectory: false)

    func testLoadReturnsFailureWhenReadFails() {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readError = NSError(domain: "FocusHistoryStoreCoverageTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "read failed"
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        switch result {
        case .success:
            XCTFail("Expected read failure")
        case .failure(let error):
            XCTAssertEqual(error.message, "Failed to read focus history")
            XCTAssertEqual(error.detail, "read failed")
        }
    }

    func testLoadReturnsFailureWhenDecodeFails() {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readData = Data("not-json".utf8)
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to decode focus history")
            return
        }
        XCTFail("Expected decode failure")
    }

    func testLoadReturnsFailureWhenVersionIsUnsupported() throws {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readData = try JSONSerialization.data(withJSONObject: [
            "version": FocusHistoryStore.currentVersion + 1,
            "stack": [],
            "mostRecent": NSNull()
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Unsupported focus history version")
            return
        }
        XCTFail("Expected unsupported version failure")
    }

    func testLoadPrunesWhenStackExceedsMaxEntries() {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        let now = Date()
        let store = makeStore(fileSystem: fileSystem, maxAge: 60 * 60, maxEntries: 2)
        let state = FocusHistoryState(
            version: FocusHistoryStore.currentVersion,
            stack: [
                FocusHistoryEntry(windowId: 1, appBundleId: "com.apple.Terminal", workspace: "main", capturedAt: now),
                FocusHistoryEntry(windowId: 2, appBundleId: "com.apple.Safari", workspace: "main", capturedAt: now),
                FocusHistoryEntry(windowId: 3, appBundleId: "com.apple.TextEdit", workspace: "main", capturedAt: now)
            ],
            mostRecent: nil
        )
        _ = store.save(state: state)
        fileSystem.fileExistsValue = true
        fileSystem.readData = fileSystem.lastWrittenData

        let result = store.load(now: now)

        switch result {
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        case .success(let outcome):
            guard let outcome else {
                XCTFail("Expected pruned outcome")
                return
            }
            XCTAssertEqual(outcome.prunedCount, 1)
            XCTAssertEqual(outcome.state.stack.map(\.windowId), [2, 3])
        }
    }

    func testLoadReturnsFailureWhenTimestampIsInvalid() {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.fileExistsValue = true
        fileSystem.readData = Data(
            """
            {
              "version": 1,
              "stack": [
                {
                  "windowId": 1,
                  "appBundleId": "com.apple.Terminal",
                  "workspace": "main",
                  "capturedAt": "invalid-date"
                }
              ],
              "mostRecent": null
            }
            """.utf8
        )
        let store = makeStore(fileSystem: fileSystem)

        let result = store.load(now: Date())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to decode focus history")
            return
        }
        XCTFail("Expected timestamp parse failure")
    }

    func testSaveReturnsFailureWhenCreateDirectoryFails() {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.createDirectoryError = NSError(domain: "FocusHistoryStoreCoverageTests", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "mkdir failed"
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.save(state: sampleState())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to create focus history directory")
            XCTAssertEqual(error.detail, "mkdir failed")
            return
        }
        XCTFail("Expected create-directory failure")
    }

    func testSaveReturnsFailureWhenWriteFails() {
        let fileSystem = FocusHistoryTestFailingFileSystem()
        fileSystem.writeError = NSError(domain: "FocusHistoryStoreCoverageTests", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "write failed"
        ])
        let store = makeStore(fileSystem: fileSystem)

        let result = store.save(state: sampleState())

        if case .failure(let error) = result {
            XCTAssertEqual(error.message, "Failed to write focus history")
            XCTAssertEqual(error.detail, "write failed")
            return
        }
        XCTFail("Expected write failure")
    }

    private func makeStore(
        fileSystem: FocusHistoryTestFailingFileSystem,
        maxAge: TimeInterval = 60,
        maxEntries: Int = 20
    ) -> FocusHistoryStore {
        FocusHistoryStore(
            fileURL: focusHistoryFile,
            fileSystem: fileSystem,
            maxAge: maxAge,
            maxEntries: maxEntries
        )
    }

    private func sampleState() -> FocusHistoryState {
        FocusHistoryState(
            version: FocusHistoryStore.currentVersion,
            stack: [
                FocusHistoryEntry(
                    windowId: 42,
                    appBundleId: "com.apple.Terminal",
                    workspace: "main",
                    capturedAt: Date()
                )
            ],
            mostRecent: nil
        )
    }
}
