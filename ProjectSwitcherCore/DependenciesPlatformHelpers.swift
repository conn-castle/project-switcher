import Carbon
import CoreServices
import Foundation

// MARK: - App Discovery

/// Application discovery interface for Launch Services lookups.
protocol AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL?
    func applicationURL(named appName: String) -> URL?
    func bundleIdentifier(forApplicationAt url: URL) -> String?
}

/// Launch Services-backed application discovery implementation.
struct LaunchServicesAppDiscovery: AppDiscovering {
    private let fileManager: FileManager
    private let searchRootsOverride: [URL]?

    init(fileManager: FileManager = .default, searchRootsOverride: [URL]? = nil) {
        self.fileManager = fileManager
        self.searchRootsOverride = searchRootsOverride
    }

    func applicationURL(bundleIdentifier: String) -> URL? {
        guard let unmanaged = LSCopyApplicationURLsForBundleIdentifier(bundleIdentifier as CFString, nil) else {
            return nil
        }
        let urls = unmanaged.takeRetainedValue() as NSArray
        return urls.firstObject as? URL
    }

    func applicationURL(named appName: String) -> URL? {
        let bundleName = appName.hasSuffix(".app") ? appName : "\(appName).app"
        let searchRoots = searchRootsOverride ?? applicationSearchRoots()

        for directory in searchRoots {
            if let directMatch = directMatch(bundleName: bundleName, in: directory, fileManager: fileManager) {
                return directMatch
            }
            if let found = shallowSearch(bundleName: bundleName, in: directory, fileManager: fileManager, maxDepth: 2) {
                return found
            }
        }

        return nil
    }

    func bundleIdentifier(forApplicationAt url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    private func applicationSearchRoots() -> [URL] {
        var roots = fileManager.urls(for: .applicationDirectory, in: .allDomainsMask)
        let fallbackRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Network/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in fallbackRoots {
            if !roots.contains(where: { $0.standardizedFileURL.path == root.standardizedFileURL.path }) {
                roots.append(root)
            }
        }
        return roots
    }

    private func directMatch(bundleName: String, in directory: URL, fileManager: FileManager) -> URL? {
        let candidates = [
            directory.appendingPathComponent(bundleName, isDirectory: true),
            directory.appendingPathComponent("Utilities", isDirectory: true).appendingPathComponent(bundleName, isDirectory: true)
        ]
        for candidate in candidates {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return candidate
            }
        }
        return nil
    }

    private func shallowSearch(
        bundleName: String,
        in root: URL,
        fileManager: FileManager,
        maxDepth: Int
    ) -> URL? {
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey]

        while let next = queue.first {
            queue.removeFirst()
            if next.depth > maxDepth {
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(
                at: next.url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for entry in entries {
                let values = try? entry.resourceValues(forKeys: resourceKeys)
                let isDirectory = values?.isDirectory ?? false
                let isPackage = values?.isPackage ?? false
                if isDirectory,
                   entry.lastPathComponent.compare(bundleName, options: [.caseInsensitive]) == .orderedSame {
                    return entry
                }
                if isDirectory, !isPackage, next.depth < maxDepth {
                    queue.append((entry, next.depth + 1))
                }
            }
        }

        return nil
    }
}

// MARK: - Hotkey Checking

/// Result of a hotkey registration check.
struct HotkeyCheckResult: Equatable, Sendable {
    let isAvailable: Bool
    let errorCode: Int32?

    init(isAvailable: Bool, errorCode: Int32?) {
        self.isAvailable = isAvailable
        self.errorCode = errorCode
    }
}

/// Hotkey availability checker used by Doctor.
protocol HotkeyChecking {
    func checkCommandShiftSpace() -> HotkeyCheckResult
}

/// Carbon-based hotkey checker for Cmd+Shift+Space.
struct CarbonHotkeyChecker: HotkeyChecking {
    init() {}

    func checkCommandShiftSpace() -> HotkeyCheckResult {
        let signature = OSType(0x41504354) // "APCT"
        let hotKeyId = EventHotKeyID(signature: signature, id: 1)
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_Space)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            if let hotKeyRef = hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
            return HotkeyCheckResult(isAvailable: true, errorCode: nil)
        }

        return HotkeyCheckResult(isAvailable: false, errorCode: status)
    }
}

// MARK: - Date Providing

/// Date provider used by Doctor for timestamps.
protocol DateProviding {
    func now() -> Date
}

/// Default date provider backed by Date().
struct SystemDateProvider: DateProviding {
    init() {}

    func now() -> Date {
        Date()
    }
}

// MARK: - Environment Providing

/// Environment accessor used by Doctor.
protocol EnvironmentProviding {
    func value(forKey key: String) -> String?
    func allValues() -> [String: String]
}

/// Default environment provider backed by the current process environment.
struct ProcessEnvironment: EnvironmentProviding {
    init() {}

    func value(forKey key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    func allValues() -> [String: String] {
        ProcessInfo.processInfo.environment
    }
}
