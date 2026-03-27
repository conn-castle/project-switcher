import XCTest

@testable import ProjectSwitcherCLICore
@testable import ProjectSwitcherCore

extension PsCLIRunnerTests {

    func testSelectProjectFailsWhenCannotCaptureFocus() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = nil

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Could not capture current focus"])
        XCTAssertEqual(manager.selectProjectCalls.count, 0)
    }

    func testSelectProjectSuccessPrintsWarningIfPresent() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .success(ProjectActivationSuccess(ideWindowId: 42, tabRestoreWarning: "tabs failed"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Selected project: a"])
        XCTAssertEqual(output.stderr, ["warning: tabs failed"])
        XCTAssertEqual(manager.selectProjectCalls.count, 1)
        XCTAssertEqual(manager.selectProjectCalls[0].projectId, "a")
    }

    func testSelectProjectFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .failure(.projectNotFound(projectId: "a"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Project not found: a"])
    }

    func testSelectProjectConfigLoadFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.parseFailed(detail: "bad toml"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Failed to parse config: bad toml"])
    }

    func testSelectProjectConfigNotLoadedPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .failure(.configNotLoaded)

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Config not loaded"])
    }

    func testSelectProjectSuccessPrintsLayoutWarning() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .success(
            ProjectActivationSuccess(
                ideWindowId: 42,
                tabRestoreWarning: nil,
                layoutWarning: "layout not applied"
            )
        )

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Selected project: a"])
        XCTAssertEqual(output.stderr, ["warning: layout not applied"])
    }

    func testSelectProjectIdeLaunchFailedPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.captureCurrentFocusResult = CapturedFocus(windowId: 1, appBundleId: "app", workspace: "main")
        manager.selectProjectResult = .failure(.ideLaunchFailed(detail: "VS Code missing"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: IDE launch failed: VS Code missing"])
    }

    func testCloseProjectSuccessPrintsWarningIfPresent() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .success(ProjectCloseSuccess(tabCaptureWarning: "capture failed"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Closed project: a"])
        XCTAssertEqual(output.stderr, ["warning: capture failed"])
    }

    func testCloseProjectSuccessWaitsForSuspendingAsyncOperation() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .success(ProjectCloseSuccess(tabCaptureWarning: nil))
        manager.closeProjectDelayNanoseconds = 10_000_000

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Closed project: a"])
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(manager.closeProjectCalls, ["a"])
    }

    func testCloseProjectFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .failure(.aeroSpaceError(detail: "boom"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: AeroSpace error: boom"])
    }

    func testCloseProjectChromeLaunchFailedPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .failure(.chromeLaunchFailed(detail: "Chrome not installed"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Chrome launch failed: Chrome not installed"])
    }

    func testCloseProjectNoActiveProjectPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a"]))
        manager.closeProjectResult = .failure(.noActiveProject)

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: No active project"])
    }

    func testCloseProjectConfigLoadFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.fileNotFound(path: "/tmp/missing.toml"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["close-project", "a"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Config file not found: /tmp/missing.toml"])
    }

    func testReturnCommandSuccessPrintsMessage() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .success(())

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Returned to non-project space"])
        XCTAssertEqual(output.stderr, [])
    }

    func testReturnCommandWaitsForSuspendingAsyncOperation() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .success(())
        manager.exitDelayNanoseconds = 10_000_000

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["Returned to non-project space"])
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(manager.exitCalls, 1)
    }

    func testReturnCommandFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .failure(.noPreviousWindow)

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: No recent non-project window to return to"])
    }

    func testReturnCommandWindowNotFoundPrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .failure(.windowNotFound(detail: "missing"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Window not found: missing"])
    }

    func testReturnCommandFocusUnstablePrintsError() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: []))
        manager.exitToNonProjectResult = .failure(.focusUnstable(detail: "did not stabilize"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Focus unstable: did not stabilize"])
    }

    func testReturnCommandConfigLoadFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.readFailed(path: "/tmp/config.toml", detail: "permission denied"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["return"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Failed to read config at /tmp/config.toml: permission denied"])
    }
}
