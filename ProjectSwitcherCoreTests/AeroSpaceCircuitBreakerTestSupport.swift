import Foundation
@testable import ProjectSwitcherCore

// MARK: - Integration: Circuit Breaker in PsAeroSpace

enum CircuitBreakerRecoveryTestValues {
    static let timeoutMessagePrefix = "Command timed out"
    static let terminateFailedDetail =
        "AeroSpace process is running but unresponsive, and termination failed. Restart AeroSpace manually."
    static let terminateUnsupportedDetail =
        "AeroSpace process is running but unresponsive, and the process checker cannot terminate it. Restart AeroSpace manually."
    static let nonTimeoutProbeFailureDetail =
        "AeroSpace responsiveness probe failed without timing out. Refusing automatic termination; restart AeroSpace manually."

    static func timeoutError(command: String, timeoutSeconds: TimeInterval = 2) -> PsCoreError {
        PsCoreError(
            category: .command,
            message: "\(timeoutMessagePrefix) after \(timeoutSeconds)s: \(command)",
            reason: .commandTimeout
        )
    }

    static func nonZeroProbeExitDetail(exitCode: Int32) -> String {
        "AeroSpace responsiveness probe exited with code \(exitCode). Refusing automatic termination; restart AeroSpace manually."
    }
}

/// Mock command runner for circuit breaker integration tests.
final class CircuitBreakerMockCommandRunner: CommandRunning {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let timeoutSeconds: TimeInterval?
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _results: [Result<PsCommandResult, PsCoreError>] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    var results: [Result<PsCommandResult, PsCoreError>] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _results
        }
        set {
            lock.lock()
            _results = newValue
            lock.unlock()
        }
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        lock.lock()
        _calls.append(
            Call(
                executable: executable,
                arguments: arguments,
                timeoutSeconds: timeoutSeconds
            )
        )
        guard !_results.isEmpty else {
            lock.unlock()
            return .failure(PsCoreError(message: "CircuitBreakerMockCommandRunner: no results left"))
        }
        let result = _results.removeFirst()
        lock.unlock()
        return result
    }
}

struct CircuitBreakerStubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

/// Mock process checker that returns a configurable result.
final class CircuitBreakerMockProcessChecker: RunningApplicationChecking, RunningApplicationTerminating {
    private let lock = NSLock()
    private let expectedBundleIdentifier: String
    private var _isRunning: Bool
    private var _terminateCalls: Int = 0
    private var _terminateResult: Bool
    private var _isApplicationRunningBundleIdentifiers: [String] = []
    private var _terminateBundleIdentifiers: [String] = []
    private var _invalidBundleIdentifiers: [String] = []

    init(
        isRunning: Bool,
        expectedBundleIdentifier: String = PsAeroSpace.bundleIdentifier,
        terminateResult: Bool = true
    ) {
        self.expectedBundleIdentifier = expectedBundleIdentifier
        self._isRunning = isRunning
        self._terminateResult = terminateResult
    }

    var isRunning: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isRunning }
        set { lock.lock(); _isRunning = newValue; lock.unlock() }
    }

    /// Number of times terminateApplication was called.
    var terminateCalls: Int {
        lock.lock(); defer { lock.unlock() }; return _terminateCalls
    }

    /// Bundle identifiers passed to isApplicationRunning(bundleIdentifier:).
    var isApplicationRunningBundleIdentifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _isApplicationRunningBundleIdentifiers
    }

    /// Bundle identifiers passed to terminateApplication(bundleIdentifier:).
    var terminateBundleIdentifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _terminateBundleIdentifiers
    }

    /// Bundle identifiers that did not match the expected value.
    var invalidBundleIdentifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _invalidBundleIdentifiers
    }

    /// Controls the return value from terminateApplication(bundleIdentifier:).
    var terminateResult: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _terminateResult }
        set { lock.lock(); _terminateResult = newValue; lock.unlock() }
    }

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        lock.lock()
        _isApplicationRunningBundleIdentifiers.append(bundleIdentifier)
        guard bundleIdentifier == expectedBundleIdentifier else {
            _invalidBundleIdentifiers.append(bundleIdentifier)
            lock.unlock()
            return false
        }
        let isRunning = _isRunning
        lock.unlock()
        return isRunning
    }

    func terminateApplication(bundleIdentifier: String) -> Bool {
        lock.lock()
        _terminateBundleIdentifiers.append(bundleIdentifier)
        guard bundleIdentifier == expectedBundleIdentifier else {
            _invalidBundleIdentifiers.append(bundleIdentifier)
            lock.unlock()
            return false
        }
        _terminateCalls += 1
        if _terminateResult {
            _isRunning = false
        }
        let didTerminate = _terminateResult
        lock.unlock()
        return didTerminate
    }
}

/// Query-only process checker used to verify recovery failure when termination is unavailable.
final class CircuitBreakerQueryOnlyProcessChecker: RunningApplicationChecking {
    private let lock = NSLock()
    private let isRunning: Bool
    private var _isApplicationRunningBundleIdentifiers: [String] = []

    init(isRunning: Bool) {
        self.isRunning = isRunning
    }

    var isApplicationRunningBundleIdentifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _isApplicationRunningBundleIdentifiers
    }

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        lock.lock()
        _isApplicationRunningBundleIdentifiers.append(bundleIdentifier)
        lock.unlock()
        return isRunning
    }
}
