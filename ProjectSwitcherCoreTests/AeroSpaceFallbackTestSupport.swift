import XCTest
@testable import ProjectSwitcherCore

/// Thread-safe mock command runner that records all calls and returns scripted results.
///
/// Supports two modes:
/// - **FIFO mode** (default): Call sites receive the next result from `results` in FIFO order.
/// - **Keyed mode**: When `keyedResults` is populated, results are returned by matching
///   the first argument (e.g., `"list-workspaces"`) against the key. Use for concurrent tests
///   where call order is non-deterministic.
///
/// Thread-safe for concurrent access via NSLock.
final class FallbackMockCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private(set) var calls: [Call] = []
    var results: [Result<PsCommandResult, PsCoreError>] = []
    var keyedResults: [String: Result<PsCommandResult, PsCoreError>] = [:]

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        lock.lock()
        calls.append(Call(executable: executable, arguments: arguments))

        // Keyed mode: match by first argument (command name)
        if !keyedResults.isEmpty, let firstArg = arguments.first,
           let result = keyedResults[firstArg] {
            lock.unlock()
            return result
        }

        // FIFO mode
        guard !results.isEmpty else {
            lock.unlock()
            return .failure(PsCoreError(message: "FallbackMockCommandRunner: no results left"))
        }
        let result = results.removeFirst()
        lock.unlock()
        return result
    }
}

/// Stub app discovery that always reports AeroSpace as not installed.
/// The fallback tests don't need app discovery.
struct FallbackStubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

struct FallbackStubBundleURLAppDiscovery: AppDiscovering {
    let bundleURL: URL?

    func applicationURL(bundleIdentifier: String) -> URL? { bundleURL }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

struct FallbackStubLegacyDirectoryFileSystem: FileSystem {
    let existingDirectories: Set<String>

    func fileExists(at url: URL) -> Bool { false }

    func directoryExists(at url: URL) -> Bool {
        existingDirectories.contains(url.path)
    }

    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { Data() }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}

// MARK: - Result helpers

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
