import XCTest
@testable import ProjectSwitcherCore

final class ErrorContextTests: XCTestCase {

    // MARK: - Creation

    func testErrorContextCreation() {
        let ctx = ErrorContext(category: .command, message: "Failed to activate", trigger: "activation")

        XCTAssertEqual(ctx.category, .command)
        XCTAssertEqual(ctx.message, "Failed to activate")
        XCTAssertEqual(ctx.trigger, "activation")
    }

    // MARK: - isCritical

    func testActivationCommandIsCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "activation")
        XCTAssertTrue(ctx.isCritical)
    }

    func testConfigLoadConfigurationIsCritical() {
        let ctx = ErrorContext(category: .configuration, message: "error", trigger: "configLoad")
        XCTAssertTrue(ctx.isCritical)
    }

    func testWorkspaceQueryIsNotCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "workspaceQuery")
        XCTAssertFalse(ctx.isCritical)
    }

    func testCloseProjectIsNotCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "closeProject")
        XCTAssertFalse(ctx.isCritical)
    }

    func testExitToPreviousIsNotCritical() {
        let ctx = ErrorContext(category: .command, message: "error", trigger: "exitToPrevious")
        XCTAssertFalse(ctx.isCritical)
    }

    func testCommandCategoryWithConfigLoadTriggerIsNotCritical() {
        // category .command + trigger "configLoad" is NOT critical (config errors use .configuration)
        let ctx = ErrorContext(category: .command, message: "error", trigger: "configLoad")
        XCTAssertFalse(ctx.isCritical)
    }

    func testConfigurationCategoryWithActivationTriggerIsNotCritical() {
        // category .configuration + trigger "activation" is NOT critical (activation errors use .command)
        let ctx = ErrorContext(category: .configuration, message: "error", trigger: "activation")
        XCTAssertFalse(ctx.isCritical)
    }

    func testWindowCategoryIsNotCritical() {
        let ctx = ErrorContext(category: .window, message: "error", trigger: "activation")
        XCTAssertFalse(ctx.isCritical)
    }

    func testFileSystemCategoryIsNotCritical() {
        let ctx = ErrorContext(category: .fileSystem, message: "error", trigger: "activation")
        XCTAssertFalse(ctx.isCritical)
    }

    // MARK: - isBreakerOpen

    func testIsBreakerOpenReturnsTrueForBreakerMessage() {
        let error = PsCoreError(message: "circuit breaker open")
        XCTAssertTrue(error.isBreakerOpen)
    }

    func testIsBreakerOpenReturnsTrueWhenMessageContainsBreakerPhrase() {
        let error = PsCoreError(
            category: .command,
            message: "aerospace list-workspaces failed: circuit breaker open (5 failures in 30s)"
        )
        XCTAssertTrue(error.isBreakerOpen)
    }

    func testIsBreakerOpenReturnsTrueForStructuredReasonWithoutMessagePhrase() {
        let error = PsCoreError(
            category: .command,
            message: "AeroSpace unavailable.",
            reason: .circuitBreakerOpen
        )
        XCTAssertTrue(error.isBreakerOpen)
    }

    func testIsBreakerOpenMatchesCaseInsensitiveMessagePhrase() {
        let error = PsCoreError(
            category: .command,
            message: "AEROSPACE is unresponsive (CIRCUIT BREAKER OPEN)."
        )
        XCTAssertTrue(error.isBreakerOpen)
    }

    func testIsBreakerOpenMatchesProductionBreakerOpenErrorMessage() {
        // This tests the actual message format produced by AeroSpaceCommandTransport.breakerOpenError().
        // If that message is ever reworded, this test will catch the mismatch.
        let error = PsCoreError(
            category: .command,
            message: "AeroSpace is unresponsive (circuit breaker open)."
        )
        XCTAssertTrue(error.isBreakerOpen)
    }

    func testIsBreakerOpenReturnsFalseForUnrelatedError() {
        let error = PsCoreError(message: "command timed out after 5s")
        XCTAssertFalse(error.isBreakerOpen)
    }

    func testIsBreakerOpenReturnsFalseForEmptyMessage() {
        let error = PsCoreError(message: "")
        XCTAssertFalse(error.isBreakerOpen)
    }

    // MARK: - isWindowTokenNotFound

    func testIsWindowTokenNotFoundReturnsTrueForStructuredReason() {
        let error = PsCoreError(
            category: .window,
            message: "Unrelated message text",
            reason: .windowTokenNotFound
        )
        XCTAssertTrue(error.isWindowTokenNotFound)
    }

    func testIsWindowTokenNotFoundReturnsTrueForLegacyMessagePrefix() {
        let error = PsCoreError(
            category: .window,
            message: "No window found with token 'PS:myProject' for com.microsoft.VSCode"
        )
        XCTAssertTrue(error.isWindowTokenNotFound)
    }

    func testIsWindowTokenNotFoundReturnsFalseForUnrelatedError() {
        let error = PsCoreError(
            category: .window,
            message: "Ambiguous: 3 windows found for com.microsoft.VSCode"
        )
        XCTAssertFalse(error.isWindowTokenNotFound)
    }

    func testIsWindowTokenNotFoundReturnsFalseForUnrelatedReason() {
        let error = PsCoreError(
            category: .command,
            message: "Something else entirely",
            reason: .circuitBreakerOpen
        )
        XCTAssertFalse(error.isWindowTokenNotFound)
    }

    // MARK: - isWindowInventoryEmpty

    func testIsWindowInventoryEmptyReturnsTrueForStructuredReason() {
        let error = PsCoreError(
            category: .window,
            message: "Unrelated message text",
            reason: .windowInventoryEmpty
        )
        XCTAssertTrue(error.isWindowInventoryEmpty)
    }

    func testIsWindowInventoryEmptyReturnsTrueForNoWindowsMessage() {
        let error = PsCoreError(
            category: .window,
            message: "No windows found for com.microsoft.VSCode (0 windows enumerated)"
        )
        XCTAssertTrue(error.isWindowInventoryEmpty)
    }

    func testIsWindowInventoryEmptyReturnsTrueForZeroWindowsMessage() {
        let error = PsCoreError(
            category: .window,
            message: "App has zero windows open"
        )
        XCTAssertTrue(error.isWindowInventoryEmpty)
    }

    func testIsWindowInventoryEmptyReturnsTrueForRegexCountMatch() {
        let error = PsCoreError(
            category: .window,
            message: "enumerated 0 windows for com.google.Chrome"
        )
        XCTAssertTrue(error.isWindowInventoryEmpty)
    }

    func testIsWindowInventoryEmptyReturnsFalseForUnrelatedError() {
        let error = PsCoreError(
            category: .window,
            message: "No window found with token 'PS:myProject'"
        )
        XCTAssertFalse(error.isWindowInventoryEmpty)
    }

    func testIsWindowInventoryEmptyReturnsFalseForUnrelatedReason() {
        let error = PsCoreError(
            category: .command,
            message: "Something else",
            reason: .commandTimeout
        )
        XCTAssertFalse(error.isWindowInventoryEmpty)
    }

    // MARK: - Equatable

    func testErrorContextEquatable() {
        let a = ErrorContext(category: .command, message: "error", trigger: "activation")
        let b = ErrorContext(category: .command, message: "error", trigger: "activation")
        let c = ErrorContext(category: .command, message: "different", trigger: "activation")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Doctor Context Integration

    func testDoctorRunAcceptsContext() {
        // Verify that Doctor.run(context:) accepts an ErrorContext and includes it in metadata
        let ctx = ErrorContext(category: .command, message: "activation failed", trigger: "activation")
        let doctor = makeDoctor()

        let report = doctor.run(context: ctx)

        // The report should render and include the context info
        let rendered = report.rendered()
        XCTAssertTrue(rendered.contains("Triggered by: activation"))
        XCTAssertTrue(rendered.contains("activation failed"))
    }

    func testDoctorRunWithoutContext() {
        let doctor = makeDoctor()

        let report = doctor.run()

        // Report should not contain "Triggered by:" when no context
        let rendered = report.rendered()
        XCTAssertFalse(rendered.contains("Triggered by:"))
    }

    // MARK: - Helper

    private func makeDoctor() -> Doctor {
        Doctor(
            runningApplicationChecker: StubRunningApplicationChecker(),
            hotkeyStatusProvider: StubHotkeyStatusProvider(),
            dateProvider: StubDateProvider(),
            aerospaceHealth: StubAeroSpaceHealth(),
            appDiscovery: StubAppDiscovery(),
            executableResolver: ExecutableResolver(
                fileSystem: StubFileSystem(),
                searchPaths: [],
                loginShellFallbackEnabled: false
            ),
            commandRunner: StubCommandRunner(),
            dataStore: DataPaths(homeDirectory: URL(fileURLWithPath: NSTemporaryDirectory()))
        )
    }
}

// MARK: - Test Stubs

private struct StubRunningApplicationChecker: RunningApplicationChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool { false }

    func terminateApplication(bundleIdentifier: String) -> Bool {
        XCTFail("Unexpected terminateApplication call in ErrorContextTests for bundleIdentifier=\(bundleIdentifier)")
        return false
    }
}

private struct StubHotkeyStatusProvider: HotkeyStatusProviding {
    var status: HotkeyRegistrationStatus? = .registered
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus? { status }
}

private struct StubDateProvider: DateProviding {
    func now() -> Date { Date() }
}

private struct StubAeroSpaceHealth: AeroSpaceHealthChecking {
    func installStatus() -> AeroSpaceInstallStatus {
        AeroSpaceInstallStatus(isInstalled: true, appPath: "/Applications/AeroSpace.app")
    }
    func isCliAvailable() -> Bool { true }
    func healthCheckCompatibility() -> AeroSpaceCompatibility { .compatible }
    func healthInstallViaHomebrew() -> Bool { true }
    func healthStart() -> Bool { true }
    func healthReloadConfig() -> Bool { true }
}

private struct StubAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func applicationURL(named appName: String) -> URL? {
        URL(fileURLWithPath: "/Applications/Test.app")
    }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

private struct StubFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool { false }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { false }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}

private class StubCommandRunner: CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
    }
}
