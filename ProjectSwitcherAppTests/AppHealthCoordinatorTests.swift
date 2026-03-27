import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherAppKit
@testable import ProjectSwitcherCore

/// Tests for `AppHealthCoordinator` covering debounce, in-flight queuing,
/// menu bar indicator updates, and Doctor action orchestration.
@MainActor
final class AppHealthCoordinatorTests: XCTestCase {

    // MARK: - Shared test state

    private var logger: CoordinatorTestRecordingLogger!
    private var tempDir: URL!

    /// Severities received by the `updateMenuBarHealthIndicator` closure.
    private var recordedIndicatorSeverities: [DoctorSeverity?] = []

    /// Reports received by the `showDoctorReport` closure, with skipActivation flag.
    private var recordedShownReports: [(report: DoctorReport, skipActivation: Bool)] = []

    /// Count of `refreshMenuStateInBackground` invocations.
    private var menuStateRefreshCount: Int = 0

    override func setUp() {
        super.setUp()
        logger = CoordinatorTestRecordingLogger()
        recordedIndicatorSeverities = []
        recordedShownReports = []
        menuStateRefreshCount = 0
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppHealthCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create AppHealthCoordinatorTests temp directory at \(tempDir.path): \(error)")
            fatalError("Cannot continue AppHealthCoordinatorTests without temp directory")
        }
    }

    override func tearDown() {
        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            XCTFail("Failed to remove AppHealthCoordinatorTests temp directory at \(tempDir?.path ?? "<nil>"): \(error)")
        }
        super.tearDown()
    }

    // MARK: - 1. Debounce skips second refresh

    func testDebounceSkipsSecondRefresh() {
        let firstCompleted = expectation(description: "first refresh completes")
        let secondLogged = expectation(description: "second refresh debounced")

        let coordinator = makeCoordinator(
            refreshDebounceSeconds: 60, // long window so second call is debounced
            makeDoctor: { self.makeTestDoctor() }
        )

        // Watch for the debounced log entry
        logger.onLog = { entry in
            if entry.event == "doctor.refresh.completed" {
                firstCompleted.fulfill()
            }
            if entry.event == "doctor.refresh.skipped" && entry.context?["reason"] == "debounced" {
                secondLogged.fulfill()
            }
        }

        // First call: should proceed
        coordinator.refreshHealthInBackground(trigger: "test_first")

        wait(for: [firstCompleted], timeout: 5.0)

        // Second call: should be debounced (within 60s window)
        coordinator.refreshHealthInBackground(trigger: "test_second")

        wait(for: [secondLogged], timeout: 2.0)

        let entries = logger.entriesSnapshot()
        let requestedCount = entries.filter { $0.event == "doctor.refresh.requested" }.count
        XCTAssertEqual(requestedCount, 1, "Only the first refresh should have been requested")

        let skippedEntries = entries.filter {
            $0.event == "doctor.refresh.skipped" && $0.context?["reason"] == "debounced"
        }
        XCTAssertEqual(skippedEntries.count, 1, "Second call should be debounced")
        XCTAssertEqual(skippedEntries.first?.context?["trigger"], "test_second")
    }

    // MARK: - 2. Force bypasses debounce

    func testForceBypassesDebounce() {
        let firstCompleted = expectation(description: "first refresh completes")
        let secondCompleted = expectation(description: "forced refresh completes")

        var completedCount = 0
        let coordinator = makeCoordinator(
            refreshDebounceSeconds: 60,
            makeDoctor: { self.makeTestDoctor() }
        )

        logger.onLog = { entry in
            if entry.event == "doctor.refresh.completed" {
                completedCount += 1
                if completedCount == 1 {
                    firstCompleted.fulfill()
                } else if completedCount == 2 {
                    secondCompleted.fulfill()
                }
            }
        }

        // First call: should proceed
        coordinator.refreshHealthInBackground(trigger: "test_first")

        wait(for: [firstCompleted], timeout: 5.0)

        // Second call with force: should bypass debounce
        coordinator.refreshHealthInBackground(trigger: "test_forced", force: true)

        wait(for: [secondCompleted], timeout: 5.0)

        let entries = logger.entriesSnapshot()
        let requestedCount = entries.filter { $0.event == "doctor.refresh.requested" }.count
        XCTAssertEqual(requestedCount, 2, "Both refreshes should have been requested")
    }

    // MARK: - 3. In-flight skip queues critical context and re-fires

    func testInFlightSkipQueuesCriticalContext() {
        let firstCompleted = expectation(description: "first refresh completes")
        let requeuedRefreshCompleted = expectation(description: "re-fired refresh completes")
        let firstDoctorFactoryStarted = expectation(description: "first doctor factory started")
        let inFlightSkipLogged = expectation(description: "second refresh skipped while in flight")

        var completedCount = 0
        let doctorFactoryStateQueue = DispatchQueue(label: "com.projectswitcher.tests.app_health.doctor_factory")
        let unblockFirstDoctorFactory = DispatchSemaphore(value: 0)
        var doctorFactoryCallCount = 0

        let coordinator = makeCoordinator(
            refreshDebounceSeconds: 0,
            makeDoctor: {
                let callNumber = doctorFactoryStateQueue.sync { () -> Int in
                    doctorFactoryCallCount += 1
                    return doctorFactoryCallCount
                }
                if callNumber == 1 {
                    firstDoctorFactoryStarted.fulfill()
                    unblockFirstDoctorFactory.wait()
                }
                return self.makeTestDoctor()
            }
        )

        logger.onLog = { entry in
            if entry.event == "doctor.refresh.completed" {
                completedCount += 1
                if completedCount == 1 {
                    firstCompleted.fulfill()
                } else if completedCount == 2 {
                    requeuedRefreshCompleted.fulfill()
                }
            }
            if entry.event == "doctor.refresh.skipped" && entry.context?["reason"] == "in_flight" {
                inFlightSkipLogged.fulfill()
            }
        }

        // First call: starts the background refresh
        coordinator.refreshHealthInBackground(trigger: "test_initial")
        wait(for: [firstDoctorFactoryStarted], timeout: 2.0)

        // Immediately queue a critical error while in-flight
        let criticalContext = ErrorContext(
            category: .command,
            message: "activation failed",
            trigger: "activation"
        )
        XCTAssertTrue(criticalContext.isCritical, "ErrorContext should be critical for command+activation")

        coordinator.refreshHealthInBackground(
            trigger: "test_critical",
            errorContext: criticalContext
        )

        wait(for: [inFlightSkipLogged], timeout: 2.0)
        unblockFirstDoctorFactory.signal()

        // Wait for first to complete — it should automatically re-fire for the pending critical context
        wait(for: [firstCompleted], timeout: 5.0)

        // Wait for the re-fired refresh to complete
        wait(for: [requeuedRefreshCompleted], timeout: 5.0)

        let allEntries = logger.entriesSnapshot()
        let requestedCount = allEntries.filter { $0.event == "doctor.refresh.requested" }.count
        XCTAssertEqual(requestedCount, 2, "Should have two requested refreshes: initial + re-fired")
        let skippedInFlight = allEntries.filter {
            $0.event == "doctor.refresh.skipped" && $0.context?["reason"] == "in_flight"
        }
        XCTAssertEqual(skippedInFlight.count, 1)
    }

    // MARK: - 4. Refresh updates menu bar indicator

    func testRefreshUpdatesMenuBarIndicator() {
        let refreshCompleted = expectation(description: "refresh completes")

        let coordinator = makeCoordinator(
            refreshDebounceSeconds: 0,
            makeDoctor: { self.makeTestDoctor() }
        )

        logger.onLog = { entry in
            if entry.event == "doctor.refresh.completed" {
                refreshCompleted.fulfill()
            }
        }

        XCTAssertTrue(recordedIndicatorSeverities.isEmpty, "No indicator updates before refresh")

        coordinator.refreshHealthInBackground(trigger: "test_indicator")

        wait(for: [refreshCompleted], timeout: 5.0)

        XCTAssertEqual(recordedIndicatorSeverities.count, 1, "Indicator should be updated once")
        // The exact severity depends on which Doctor checks pass with our stubs;
        // the important thing is the callback was invoked with a non-nil value.
        XCTAssertNotNil(recordedIndicatorSeverities[0],
                        "Indicator severity should have been provided")
    }

    // MARK: - 5. isHealthRefreshInFlight flag transitions

    func testIsHealthRefreshInFlightTransitions() {
        let doctorFactoryStarted = expectation(description: "doctor factory started")
        let refreshStarted = expectation(description: "refresh started")
        let refreshCompleted = expectation(description: "refresh completed")
        let unblockDoctorFactory = DispatchSemaphore(value: 0)

        let coordinator = makeCoordinator(
            refreshDebounceSeconds: 0,
            makeDoctor: {
                doctorFactoryStarted.fulfill()
                unblockDoctorFactory.wait()
                return self.makeTestDoctor()
            }
        )

        XCTAssertFalse(coordinator.isHealthRefreshInFlight, "Should be false before refresh")

        logger.onLog = { entry in
            if entry.event == "doctor.refresh.requested" {
                // Check flag immediately after request is dispatched
                DispatchQueue.main.async {
                    XCTAssertTrue(coordinator.isHealthRefreshInFlight, "Should be true while in-flight")
                    refreshStarted.fulfill()
                }
            }
            if entry.event == "doctor.refresh.completed" {
                refreshCompleted.fulfill()
            }
        }

        coordinator.refreshHealthInBackground(trigger: "test_flag")

        wait(for: [doctorFactoryStarted, refreshStarted], timeout: 2.0)
        unblockDoctorFactory.signal()
        wait(for: [refreshCompleted], timeout: 5.0)

        XCTAssertFalse(coordinator.isHealthRefreshInFlight, "Should be false after refresh completes")
    }

    // MARK: - 6. runDoctorAction presents result

    func testRunDoctorActionPresentsResult() {
        let actionCompleted = expectation(description: "action completes and result presented")

        let coordinator = makeCoordinator(
            refreshDebounceSeconds: 0,
            makeDoctor: { self.makeTestDoctor() }
        )

        var showLoadingCalled = false
        logger.onLog = { entry in
            if entry.event == "doctor.test_action.completed" {
                actionCompleted.fulfill()
            }
        }

        coordinator.runDoctorAction(
            { doctor in
                // Call the doctor's run method to produce a report
                doctor.run()
            },
            requestedEvent: "doctor.test_action.requested",
            completedEvent: "doctor.test_action.completed",
            showLoading: {
                showLoadingCalled = true
            }
        )

        wait(for: [actionCompleted], timeout: 5.0)

        XCTAssertTrue(showLoadingCalled, "showLoading should have been called")
        XCTAssertEqual(recordedShownReports.count, 1, "Report should have been presented")
        XCTAssertEqual(recordedShownReports.first?.skipActivation, false)
        XCTAssertEqual(recordedIndicatorSeverities.count, 1, "Indicator should be updated")

        let entries = logger.entriesSnapshot()
        XCTAssertTrue(entries.contains { $0.event == "doctor.test_action.requested" })
        XCTAssertTrue(entries.contains { $0.event == "doctor.test_action.completed" })
    }

    // MARK: - Helpers

    /// Builds the coordinator with test closures that record to shared state.
    private func makeCoordinator(
        refreshDebounceSeconds: TimeInterval,
        makeDoctor: @escaping () -> Doctor
    ) -> AppHealthCoordinator {
        AppHealthCoordinator(
            logger: logger,
            refreshDebounceSeconds: refreshDebounceSeconds,
            makeDoctor: makeDoctor,
            currentIndicatorSeverity: { nil },
            updateMenuBarHealthIndicator: { [weak self] severity in
                self?.recordedIndicatorSeverities.append(severity)
            },
            showDoctorReport: { [weak self] report, skipActivation in
                self?.recordedShownReports.append((report, skipActivation))
            },
            refreshMenuStateInBackground: { [weak self] in
                self?.menuStateRefreshCount += 1
            }
        )
    }

    /// Creates a Doctor with all-passing stubs (report has only PASS findings).
    private func makeTestDoctor() -> Doctor {
        let configDir = tempDir.appendingPathComponent(
            ".config/project-switcher-\(UUID().uuidString)", isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create test config directory at \(configDir.path): \(error)")
            fatalError("Cannot continue AppHealthCoordinatorTests without test config directory")
        }
        let configFile = configDir.appendingPathComponent("config.toml")
        let toml = """
        [[project]]
        name = "Test"
        path = "\(tempDir.path)"
        color = "blue"
        """
        do {
            try toml.write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to write test config file at \(configFile.path): \(error)")
            fatalError("Cannot continue AppHealthCoordinatorTests without config.toml")
        }

        let homeDir = configDir.deletingLastPathComponent().deletingLastPathComponent()
        let dataStore = DataPaths(homeDirectory: homeDir)
        do {
            try FileManager.default.createDirectory(
                at: dataStore.logsDirectory, withIntermediateDirectories: true
            )
        } catch {
            XCTFail("Failed to create logs directory at \(dataStore.logsDirectory.path): \(error)")
            fatalError("Cannot continue AppHealthCoordinatorTests without logs directory")
        }

        let resolver = ExecutableResolver(
            fileSystem: TestSelectiveFileSystem(executablePaths: ["/usr/bin/brew"]),
            searchPaths: ["/usr/bin"],
            loginShellFallbackEnabled: false
        )

        return Doctor(
            runningApplicationChecker: TestRunningAppChecker(runningAeroSpace: true),
            hotkeyStatusProvider: nil,
            dateProvider: TestDateProvider(),
            aerospaceHealth: TestAeroSpaceHealth(),
            appDiscovery: TestAppDiscovery(),
            executableResolver: resolver,
            commandRunner: TestCommandRunner(),
            dataStore: dataStore
        )
    }

}

// MARK: - Test Doubles (private to this file)

private struct TestRunningAppChecker: RunningApplicationChecking {
    let runningAeroSpace: Bool

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        if bundleIdentifier == "bobko.aerospace" {
            return runningAeroSpace
        }
        return false
    }

    func terminateApplication(bundleIdentifier: String) -> Bool {
        XCTFail("Unexpected terminateApplication call in AppHealthCoordinatorTests for bundleIdentifier=\(bundleIdentifier)")
        return false
    }
}

private struct TestDateProvider: DateProviding {
    func now() -> Date { Date(timeIntervalSince1970: 1_704_067_200) }
}

private struct TestAeroSpaceHealth: AeroSpaceHealthChecking {
    func installStatus() -> AeroSpaceInstallStatus {
        AeroSpaceInstallStatus(isInstalled: true, appPath: "/Applications/AeroSpace.app")
    }
    func isCliAvailable() -> Bool { true }
    func healthCheckCompatibility() -> AeroSpaceCompatibility { .compatible }
    func healthInstallViaHomebrew() -> Bool { true }
    func healthStart() -> Bool { true }
    func healthReloadConfig() -> Bool { true }
}

private struct TestAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func applicationURL(named appName: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

private struct TestCommandRunner: CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        .failure(PsCoreError(message: "stub"))
    }
}

private struct TestSelectiveFileSystem: FileSystem {
    let executablePaths: Set<String>

    func fileExists(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func isExecutableFile(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
    func directoryExists(at url: URL) -> Bool { false }
}
