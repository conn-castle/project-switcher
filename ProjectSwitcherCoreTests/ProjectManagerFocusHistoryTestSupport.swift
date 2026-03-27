import XCTest
@testable import ProjectSwitcherCore

final class FocusHistoryTestAeroSpaceStub: AeroSpaceProviding {
    var focusedWindowResult: Result<PsWindow, PsCoreError> = .failure(PsCoreError(message: "stub"))
    var focusWindowSuccessIds: Set<Int> = []
    var workspacesWithFocusResult: Result<[PsWorkspaceSummary], PsCoreError> = .success([])
    var windowsByWorkspace: [String: [PsWindow]] = [:]
    var allWindows: [PsWindow] = []
    private(set) var focusedWindowIds: [Int] = []

    func getWorkspaces() -> Result<[String], PsCoreError> { .success([]) }
    func workspaceExists(_ name: String) -> Result<Bool, PsCoreError> { .success(false) }
    func listWorkspacesFocused() -> Result<[String], PsCoreError> { .success([]) }
    func listWorkspacesWithFocus() -> Result<[PsWorkspaceSummary], PsCoreError> { workspacesWithFocusResult }
    func createWorkspace(_ name: String) -> Result<Void, PsCoreError> { .success(()) }
    func closeWorkspace(name: String) -> Result<Void, PsCoreError> { .success(()) }

    func listWindowsForApp(bundleId: String) -> Result<[PsWindow], PsCoreError> { .success([]) }
    func listWindowsWorkspace(workspace: String) -> Result<[PsWindow], PsCoreError> {
        .success(windowsByWorkspace[workspace] ?? [])
    }
    func listAllWindows() -> Result<[PsWindow], PsCoreError> {
        .success(allWindows)
    }
    func focusedWindow() -> Result<PsWindow, PsCoreError> { focusedWindowResult }
    func focusWindow(windowId: Int) -> Result<Void, PsCoreError> {
        focusedWindowIds.append(windowId)
        guard focusWindowSuccessIds.contains(windowId) else {
            return .failure(PsCoreError(message: "window not found"))
        }
        if case .success(let focused) = focusedWindowResult, focused.windowId == windowId {
            return .success(())
        }
        if let match = allWindows.first(where: { $0.windowId == windowId }) {
            focusedWindowResult = .success(match)
        } else {
            focusedWindowResult = .success(PsWindow(
                windowId: windowId,
                appBundleId: "com.stub.app",
                workspace: "main",
                windowTitle: "Stub"
            ))
        }
        return .success(())
    }

    var focusWorkspaceResult: Result<Void, PsCoreError> = .success(())

    func moveWindowToWorkspace(workspace: String, windowId: Int, focusFollows: Bool) -> Result<Void, PsCoreError> { .success(()) }
    func focusWorkspace(name: String) -> Result<Void, PsCoreError> { focusWorkspaceResult }
}

struct FocusHistoryTestIdeLauncherStub: IdeLauncherProviding {
    func openNewWindow(identifier: String, projectPath: String?, remoteAuthority: String?, color: String?) -> Result<Void, PsCoreError> { .success(()) }
}

struct FocusHistoryTestChromeLauncherStub: ChromeLauncherProviding {
    func openNewWindow(identifier: String, initialURLs: [String]) -> Result<Void, PsCoreError> { .success(()) }
}

struct FocusHistoryTestTabCaptureStub: ChromeTabCapturing {
    func captureTabURLs(windowTitle: String) -> Result<[String], PsCoreError> { .success([]) }
}

struct FocusHistoryTestGitRemoteResolver: GitRemoteResolving {
    func resolve(projectPath: String) -> String? { nil }
}

struct FocusHistoryTestLogger: ProjectSwitcherLogging {
    func log(event: String, level: LogLevel, message: String?, context: [String: String]?) -> Result<Void, LogWriteError> { .success(()) }
}

final class FocusHistoryTestFailingFileSystem: FileSystem {
    var fileExistsValue = false
    var readData: Data?
    var readError: Error?
    var createDirectoryError: Error?
    var writeError: Error?
    var lastWrittenData: Data?
    var writeCallCount = 0

    func fileExists(at url: URL) -> Bool { fileExistsValue }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        if let readError {
            throw readError
        }
        if let readData {
            return readData
        }
        throw NSError(domain: "FocusHistoryTestFailingFileSystem", code: 99, userInfo: nil)
    }

    func createDirectory(at url: URL) throws {
        if let createDirectoryError {
            throw createDirectoryError
        }
    }

    func fileSize(at url: URL) throws -> UInt64 { UInt64(lastWrittenData?.count ?? 0) }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}

    func writeFile(at url: URL, data: Data) throws {
        writeCallCount += 1
        if let writeError {
            throw writeError
        }
        lastWrittenData = data
        readData = data
    }
}

final class FocusHistoryTestInMemoryFileSystem: FileSystem {
    private var storage: [URL: Data] = [:]
    private var directories: Set<URL> = []

    func fileExists(at url: URL) -> Bool { storage[url] != nil }
    func directoryExists(at url: URL) -> Bool { directories.contains(url) }
    func isExecutableFile(at url: URL) -> Bool { false }

    func readFile(at url: URL) throws -> Data {
        guard let data = storage[url] else {
            throw NSError(domain: "FocusHistoryTestInMemoryFileSystem", code: 1, userInfo: nil)
        }
        return data
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url)
    }

    func fileSize(at url: URL) throws -> UInt64 {
        guard let data = storage[url] else {
            throw NSError(domain: "FocusHistoryTestInMemoryFileSystem", code: 2, userInfo: nil)
        }
        return UInt64(data.count)
    }

    func removeItem(at url: URL) throws {
        storage.removeValue(forKey: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        storage[destinationURL] = storage[sourceURL]
        storage.removeValue(forKey: sourceURL)
    }

    func appendFile(at url: URL, data: Data) throws {
        let existing = storage[url] ?? Data()
        var updated = existing
        updated.append(data)
        storage[url] = updated
    }

    func writeFile(at url: URL, data: Data) throws {
        storage[url] = data
    }

    func contentsOfDirectory(at url: URL) throws -> [String] {
        storage.keys
            .filter { $0.deletingLastPathComponent() == url }
            .map { $0.lastPathComponent }
    }
}
