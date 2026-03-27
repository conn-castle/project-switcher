import AppKit

import ProjectSwitcherCore

/// Lightweight abstraction over `NSRunningApplication` for testability.
protocol AppKitRunningApplication {
    /// Requests a graceful app termination.
    /// - Returns: True when the request was accepted by the system.
    @discardableResult
    func terminate() -> Bool

    /// Requests a force termination.
    /// - Returns: True when the request was accepted by the system.
    @discardableResult
    func forceTerminate() -> Bool
}

extension NSRunningApplication: AppKitRunningApplication {}

/// Injectable dependencies used by `AppKitRunningApplicationChecker`.
struct AppKitRunningApplicationCheckerDependencies {
    /// Returns running applications for a bundle identifier.
    let runningApplications: (String) -> [any AppKitRunningApplication]
    /// Current time provider.
    let now: () -> Date
    /// Sleep provider for polling loops.
    let sleep: (TimeInterval) -> Void

    /// Live AppKit-backed dependencies.
    static let live = AppKitRunningApplicationCheckerDependencies(
        runningApplications: { bundleIdentifier in
            NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .map { $0 as any AppKitRunningApplication }
        },
        now: { Date() },
        sleep: { Thread.sleep(forTimeInterval: $0) }
    )
}

/// Checks if an application is running using AppKit APIs.
public struct AppKitRunningApplicationChecker: RunningApplicationChecking, RunningApplicationTerminating {
    private static let gracefulTimeoutSeconds: TimeInterval = 3.0
    private static let forceTimeoutSeconds: TimeInterval = 2.0
    private static let rejectedForceSettleTimeoutSeconds: TimeInterval = 0.5
    private static let pollIntervalSeconds: TimeInterval = 0.25

    private let dependencies: AppKitRunningApplicationCheckerDependencies

    public init() {
        self.init(dependencies: .live)
    }

    init(dependencies: AppKitRunningApplicationCheckerDependencies) {
        self.dependencies = dependencies
    }

    public func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !dependencies.runningApplications(bundleIdentifier).isEmpty
    }

    /// Terminates all processes matching the given bundle identifier.
    ///
    /// Attempts graceful termination first (`terminate()`), polls up to 3 seconds,
    /// then falls back to force termination (`forceTerminate()`), polling up to
    /// 2 more seconds. If force requests are rejected, applies a short settle
    /// wait before failing. Returns true when the process is no longer running.
    ///
    /// - Parameter bundleIdentifier: Bundle identifier of the application to terminate.
    /// - Returns: True if the process is no longer running after this call.
    public func terminateApplication(bundleIdentifier: String) -> Bool {
        let apps = dependencies.runningApplications(bundleIdentifier)
        if apps.isEmpty { return true }

        // Graceful terminate
        var acceptedGracefulTerminate = false
        for app in apps {
            if app.terminate() {
                acceptedGracefulTerminate = true
            }
        }

        if acceptedGracefulTerminate {
            if waitForTermination(
                bundleIdentifier: bundleIdentifier,
                timeoutSeconds: Self.gracefulTimeoutSeconds
            ) {
                return true
            }
        }

        // Force terminate any survivors
        let remaining = dependencies.runningApplications(bundleIdentifier)
        var acceptedForceTerminate = false
        for app in remaining {
            if app.forceTerminate() {
                acceptedForceTerminate = true
            }
        }

        if acceptedForceTerminate {
            if waitForTermination(
                bundleIdentifier: bundleIdentifier,
                timeoutSeconds: Self.forceTimeoutSeconds
            ) {
                return true
            }
        } else if !remaining.isEmpty {
            // Some apps can be in-flight to exit even when force requests are rejected.
            // Keep a short settle wait to avoid false negatives without paying full timeout.
            if waitForTermination(
                bundleIdentifier: bundleIdentifier,
                timeoutSeconds: Self.rejectedForceSettleTimeoutSeconds
            ) {
                return true
            }
        }

        return dependencies.runningApplications(bundleIdentifier).isEmpty
    }

    /// Waits until no processes remain or the timeout elapses.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: Bundle identifier to poll.
    ///   - timeoutSeconds: Maximum wait duration.
    /// - Returns: True when the process exits before timeout, otherwise false.
    private func waitForTermination(
        bundleIdentifier: String,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        let deadline = dependencies.now().addingTimeInterval(timeoutSeconds)
        while dependencies.now() < deadline {
            if dependencies.runningApplications(bundleIdentifier).isEmpty {
                return true
            }
            dependencies.sleep(Self.pollIntervalSeconds)
        }
        return dependencies.runningApplications(bundleIdentifier).isEmpty
    }
}
