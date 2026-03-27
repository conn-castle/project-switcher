import XCTest
@testable import ProjectSwitcherCLICore
@testable import ProjectSwitcherCore

final class PsCLIRunnerTests: XCTestCase {

    func testVersionCommandOutputsVersion() {
        let output = OutputRecorder()
        let deps = PsCLIDependencies(
            version: { "9.9.9" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["--version"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stdout, ["pswitcher 9.9.9"])
        XCTAssertTrue(output.stderr.isEmpty)
    }

    func testUnknownCommandPrintsUsageAndReturnsUsageExit() {
        let output = OutputRecorder()
        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["nope"])

        XCTAssertEqual(exitCode, PsExitCode.usage.rawValue)
        XCTAssertEqual(output.stderr.first, "error: unknown command: nope")
        XCTAssertTrue(output.stderr.last?.contains("Usage:") ?? false)
    }

    func testDoctorSuccessReturnsOkExit() {
        let output = OutputRecorder()
        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["doctor"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("ProjectSwitcher Doctor Report") ?? false)
    }

    func testDoctorFailureReturnsFailureExit() {
        let output = OutputRecorder()
        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: true) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["doctor"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("ProjectSwitcher Doctor Report") ?? false)
    }

    func testHelpCommandOutputsUsage() {
        let output = OutputRecorder()
        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["--help"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("pswitcher (ProjectSwitcher CLI)") ?? false)
    }

    func testSelectProjectHelpOutputsUsage() {
        let output = OutputRecorder()
        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { ProjectManager() },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["select-project", "--help"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertTrue(output.stdout.first?.contains("select-project") ?? false)
    }

    func testShowConfigSuccessPrintsFormattedConfig() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a", "b"]))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(output.stdout.count, 1)
        XCTAssertTrue(output.stdout[0].contains("# ProjectSwitcher Configuration"))
        XCTAssertTrue(output.stdout[0].contains("id = \"a\""))
        XCTAssertTrue(output.stdout[0].contains("id = \"b\""))
    }

    func testShowConfigWithWarningsPrintsWarningsToStderr() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(
            makeConfig(
                projectIds: ["a"],
                warnings: [ConfigFinding(severity: .warn, title: "Deprecated field: foo")]
            )
        )

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, ["warning: Deprecated field: foo"])
        XCTAssertEqual(output.stdout.count, 1)
        XCTAssertTrue(output.stdout[0].contains("# ProjectSwitcher Configuration"))
    }

    func testShowConfigFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.fileNotFound(path: "/tmp/missing"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr.first, "error: Config file not found: /tmp/missing")
    }

    func testShowConfigReadFailedPrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.readFailed(path: "/tmp/config.toml", detail: "permission denied"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr, ["error: Failed to read config at /tmp/config.toml: permission denied"])
    }

    func testShowConfigValidationFailedWithoutFailFindingsUsesGenericMessage() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.validationFailed(findings: [
            ConfigFinding(severity: .warn, title: "Warning only")
        ]))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["show-config"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr.first, "error: Config validation failed")
    }

    func testListProjectsSuccessPrintsProjectLines() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a", "b"]))
        manager.sortedProjectsResult = [
            makeProject(id: "a", name: "Alpha", path: "/p/a"),
            makeProject(id: "b", name: "Beta", path: "/p/b")
        ]

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-projects", "query"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(output.stdout, [
            "a\tAlpha\t/p/a",
            "b\tBeta\t/p/b"
        ])
        XCTAssertEqual(manager.sortedProjectsQueries, ["query"])
    }

    func testListProjectsFailurePrintsErrorAndReturnsFailureExit() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .failure(.parseFailed(detail: "bad toml"))

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-projects"])

        XCTAssertEqual(exitCode, PsExitCode.failure.rawValue)
        XCTAssertEqual(output.stdout, [])
        XCTAssertEqual(output.stderr.first, "error: Failed to parse config: bad toml")
    }

    func testListProjectsNoQueryUsesEmptyString() {
        let output = OutputRecorder()
        let manager = MockProjectManager()
        manager.loadConfigResult = .success(makeConfig(projectIds: ["a", "b"]))
        manager.sortedProjectsResult = [
            makeProject(id: "a", name: "Alpha", path: "/p/a"),
            makeProject(id: "b", name: "Beta", path: "/p/b")
        ]

        let deps = PsCLIDependencies(
            version: { "0.0.0" },
            projectManagerFactory: { manager },
            doctorRunner: { makeDoctorReport(hasFailures: false) }
        )
        let cli = PsCLI(parser: PsArgumentParser(), dependencies: deps, output: output.sink)

        let exitCode = cli.run(arguments: ["list-projects"])

        XCTAssertEqual(exitCode, PsExitCode.ok.rawValue)
        XCTAssertEqual(output.stderr, [])
        XCTAssertEqual(output.stdout, [
            "a\tAlpha\t/p/a",
            "b\tBeta\t/p/b"
        ])
        XCTAssertEqual(manager.sortedProjectsQueries, [""])
    }

    func testUsageTextHasUniqueContentPerHelpTopic() {
        XCTAssertTrue(usageText(for: .root).contains("Commands:"))
        XCTAssertTrue(usageText(for: .doctor).contains("pswitcher doctor"))
        XCTAssertTrue(usageText(for: .showConfig).contains("show-config"))
        XCTAssertTrue(usageText(for: .listProjects).contains("list-projects"))
        XCTAssertTrue(usageText(for: .selectProject).contains("select-project"))
        XCTAssertTrue(usageText(for: .closeProject).contains("close-project"))
        XCTAssertTrue(usageText(for: .returnToWindow).contains("pswitcher return"))
    }

    func testStandardOutputWritersExecute() {
        // Intentionally writes to stdout/stderr to cover the standard output sinks.
        PsCLIOutput.standard.stdout("stdout test")
        PsCLIOutput.standard.stderr("stderr test")
    }
}
