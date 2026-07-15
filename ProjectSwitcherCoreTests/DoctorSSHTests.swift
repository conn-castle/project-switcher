import XCTest
@testable import ProjectSwitcherCore

final class DoctorSSHTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DoctorSSHTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - SSH exit 0 → PASS

    func testSSHProjectExitZeroPassesFinding() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Remote project path exists: remote-ml")
        })
    }

    // MARK: - Default init coverage

    func testDoctorDefaultInitDoesNotCrash() {
        _ = Doctor(runningApplicationChecker: StubRunningAppChecker())
    }

    // MARK: - AeroSpace actions (install/start/reload)

    func testInstallAeroSpaceInvokesHealthInstallViaHomebrew() {
        let health = RecordingAeroSpaceHealth()
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            aerospaceHealth: health
        )

        _ = doctor.installAeroSpace()

        XCTAssertEqual(health.installCalls, 1)
        XCTAssertEqual(health.startCalls, 0)
        XCTAssertEqual(health.reloadCalls, 0)
    }

    func testStartAeroSpaceInvokesHealthStart() {
        let health = RecordingAeroSpaceHealth()
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            aerospaceHealth: health
        )

        _ = doctor.startAeroSpace()

        XCTAssertEqual(health.installCalls, 0)
        XCTAssertEqual(health.startCalls, 1)
        XCTAssertEqual(health.reloadCalls, 0)
    }

    func testReloadAeroSpaceConfigInvokesHealthReloadConfig() {
        let health = RecordingAeroSpaceHealth()
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            aerospaceHealth: health
        )

        _ = doctor.reloadAeroSpaceConfig()

        XCTAssertEqual(health.installCalls, 0)
        XCTAssertEqual(health.startCalls, 0)
        XCTAssertEqual(health.reloadCalls, 1)
    }

    // MARK: - Doctor.run branch coverage (non-SSH)

    func testRunReportsHomebrewMissing() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: [],
            runningAeroSpace: true,
            appDiscoveryInstalled: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Homebrew not found")
        })
    }

    func testRunReportsAeroSpaceNotInstalledAndCliUnavailable() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let health = RecordingAeroSpaceHealth()
        health.installStatusValue = AeroSpaceInstallStatus(isInstalled: false, appPath: nil)
        health.cliAvailableValue = false

        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: false,
            appDiscoveryInstalled: true,
            aerospaceHealth: health
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("AeroSpace.app not found")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("aerospace CLI not available")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Critical: AeroSpace setup incomplete")
        })
        XCTAssertTrue(report.actions.canInstallAeroSpace)
        XCTAssertFalse(report.actions.canStartAeroSpace)
        XCTAssertFalse(report.actions.canReloadAeroSpaceConfig)
    }

    func testRunUsesFoundLabelWhenAeroSpaceInstalledButAppPathNil() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """

        let health = RecordingAeroSpaceHealth()
        health.installStatusValue = AeroSpaceInstallStatus(isInstalled: true, appPath: nil)
        health.cliAvailableValue = true
        health.compatibilityValue = .compatible

        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            aerospaceHealth: health
        )

        let report = doctor.run()
        XCTAssertEqual(report.metadata.aerospaceApp, "FOUND")
    }

    func testRunReportsCompatibilityIncompatible() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let health = RecordingAeroSpaceHealth()
        health.installStatusValue = AeroSpaceInstallStatus(isInstalled: true, appPath: "/Applications/AeroSpace.app")
        health.cliAvailableValue = true
        health.compatibilityValue = .incompatible(detail: "missing flags")

        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            aerospaceHealth: health
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("aerospace CLI compatibility issues")
        })
    }

    func testRunReportsVSCodeFailureAndOptionalChromeWarningWhenProjectsConfigured() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: false
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("VS Code not found")
        }, "VS Code missing should be FAIL when projects are configured")
        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Google Chrome not found")
        }, "Optional Chrome must not make Doctor fail")
    }

    func testRunReportsVSCodeWarningAndChromeNotRequiredWhenNoProjectsConfigured() throws {
        // Config with no valid projects — all required fields missing
        let toml = """
        [[project]]
        name = ""
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: false
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("VS Code not found")
        }, "VS Code missing should be WARN when no valid projects are configured")
        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Google Chrome not required")
        }, "Chrome should not warn when no configured project enables it")
    }

    func testRunReportsAgentLayerCliMissingWhenRequiredByConfig() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        useAgentLayer = true
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Agent layer CLI (al) not found")
        })
    }

    func testRunReportsHotkeyStatusesWhenProviderPresent() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """

        do {
            let doctor = try makeDoctorForRun(
                toml: toml,
                allowedExecutables: ["/usr/bin/brew"],
                runningAeroSpace: true,
                appDiscoveryInstalled: true,
                hotkeyStatusProvider: StubHotkeyStatusProvider(status: .registered)
            )
            let report = doctor.run()
            XCTAssertTrue(report.findings.contains {
                $0.severity == .pass && $0.title.contains("Hotkey registered")
            })
        }

        do {
            let doctor = try makeDoctorForRun(
                toml: toml,
                allowedExecutables: ["/usr/bin/brew"],
                runningAeroSpace: true,
                appDiscoveryInstalled: true,
                hotkeyStatusProvider: StubHotkeyStatusProvider(status: .failed(osStatus: -50))
            )
            let report = doctor.run()
            XCTAssertTrue(report.findings.contains {
                $0.severity == .warn && $0.title.contains("Hotkey registration failed")
            })
        }
    }

    func testRunReportsConfigFileErrorWhenMissing() throws {
        // Do not create config file at all.
        let dataStore = DataPaths(homeDirectory: tempDir)

        let resolver = ExecutableResolver(
            fileSystem: SelectiveFileSystem(executablePaths: ["/usr/bin/brew"]),
            searchPaths: ["/usr/bin"],
            loginShellFallbackEnabled: false
        )

        let doctor = Doctor(
            runningApplicationChecker: StubRunningAppChecker(),
            hotkeyStatusProvider: nil,
            dateProvider: StubDateProvider(),
            aerospaceHealth: StubAeroSpaceHealth(),
            appDiscovery: StubAppDiscovery(),
            executableResolver: resolver,
            commandRunner: StubCommandRunner(result: .failure(PsCoreError(message: "not used"))),
            dataStore: dataStore
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Config file error")
        })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataStore.configFile.path))
    }

    // MARK: - Accessibility permission check

    func testRunReportsAccessibilityPassWhenTrusted() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            windowPositioner: StubWindowPositioner(trusted: true)
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title == "Accessibility permission granted"
        })
    }

    func testRunReportsAccessibilityWarnWhenNotTrusted() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            windowPositioner: StubWindowPositioner(trusted: false)
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title == "Accessibility permission not granted"
        })
    }

    func testCanRequestAccessibilityTrueWhenNotTrusted() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            windowPositioner: StubWindowPositioner(trusted: false)
        )

        let report = doctor.run()

        XCTAssertTrue(report.actions.canRequestAccessibility)
    }

    func testCanRequestAccessibilityFalseWhenTrusted() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            windowPositioner: StubWindowPositioner(trusted: true)
        )

        let report = doctor.run()

        XCTAssertFalse(report.actions.canRequestAccessibility)
    }

    func testCanRequestAccessibilityFalseWhenNoPositioner() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true
        )

        let report = doctor.run()

        XCTAssertFalse(report.actions.canRequestAccessibility)
    }

    func testRequestAccessibilityCallsPromptAndReturnsReport() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let positioner = StubWindowPositioner(trusted: false)
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true,
            windowPositioner: positioner
        )

        let report = doctor.requestAccessibility()

        XCTAssertEqual(positioner.promptCalls, 1)
        // The report should still exist (re-runs Doctor after prompting)
        XCTAssertFalse(report.findings.isEmpty)
    }

    func testRunOmitsAccessibilityCheckWhenNoPositioner() throws {
        let toml = """
        [[project]]
        name = "Local"
        path = "\(tempDir.path)"
        color = "blue"
        """
        let doctor = try makeDoctorForRun(
            toml: toml,
            allowedExecutables: ["/usr/bin/brew"],
            runningAeroSpace: true,
            appDiscoveryInstalled: true
        )

        let report = doctor.run()

        XCTAssertFalse(report.findings.contains {
            $0.title.contains("Accessibility")
        })
    }

    // MARK: - SSH exit 1 → FAIL (path missing)

    func testSSHProjectExitOneFailsFinding() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Remote project path missing: remote-ml")
        })
    }

    // MARK: - SSH exit 255 → WARN (SSH connection failed)

    func testSSHProjectExit255WarnsConnectionFailed() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 255, stdout: "", stderr: "Connection refused")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Cannot verify remote path: remote-ml")
        })
    }

    func testSSHProjectExit255WarnsConnectionFailedWhenStderrEmpty() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 255, stdout: "", stderr: "   ")),
            sshResolvable: true
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Cannot verify remote path: remote-ml")
        }
        XCTAssertNotNil(finding)
        XCTAssertTrue(finding?.bodyLines.contains("Detail: SSH connection failed") == true)
    }

    // MARK: - SSH other exit → WARN (unexpected)

    func testSSHProjectOtherExitWarnsUnexpected() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 42, stdout: "", stderr: "something weird")),
            sshResolvable: true
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Unexpected SSH result (exit 42): remote-ml")
        })
    }

    func testSSHProjectOtherExitWarnsUnexpectedWithNilDetailWhenStderrEmpty() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 42, stdout: "", stderr: "   ")),
            sshResolvable: true
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Unexpected SSH result (exit 42): remote-ml")
        }
        XCTAssertNotNil(finding)
        XCTAssertFalse(finding?.bodyLines.contains(where: { $0.hasPrefix("Detail:") }) == true)
    }

    // MARK: - ssh not found → WARN

    func testSSHProjectSSHNotFoundWarns() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: false
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("ssh not found")
        })
    }

    // MARK: - Command runner failure → WARN with verbatim message

    func testSSHProjectRunnerFailureWarnsWithMessage() {
        let doctor = makeDoctor(
            sshResult: .failure(PsCoreError(message: "Command timed out after 10.0s: ssh")),
            sshResolvable: true
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Cannot verify remote path for remote-ml")
        }
        XCTAssertNotNil(finding)
    }

    // MARK: - Local project unchanged

    func testLocalProjectPathCheckUnchanged() {
        let toml = """
        [[project]]
        name = "Local Project"
        path = "/nonexistent/path/for/testing"
        color = "blue"
        """
        let doctor = makeDoctor(
            toml: toml,
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        let hasLocalPathFinding = report.findings.contains {
            $0.title.contains("Project path") && $0.title.contains("local-project")
        }
        XCTAssertTrue(hasLocalPathFinding)
        let hasSSHFinding = report.findings.contains {
            $0.title.contains("Remote project path") || $0.title.contains("ssh not found")
        }
        XCTAssertFalse(hasSSHFinding)
    }

    // MARK: - SSH project skips .agent-layer check

    func testSSHProjectSkipsAgentLayerDirCheck() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        let hasAgentLayerFinding = report.findings.contains {
            $0.title.contains("Agent layer exists") || $0.title.contains("Agent layer missing")
        }
        XCTAssertFalse(hasAgentLayerFinding)
    }

    // MARK: - Option terminator

    func testSSHCommandIncludesOptionTerminator() {
        let runner = StubCommandRunner(
            result: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        )
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        _ = doctor.run()

        // Doctor makes 2 SSH calls per SSH project: path check + settings check
        // All SSH calls should include "--" option terminator
        XCTAssertGreaterThanOrEqual(runner.allArguments.count, 1, "At least one SSH call expected")
        for (index, args) in runner.allArguments.enumerated() {
            guard let terminatorIndex = args.firstIndex(of: "--") else {
                XCTFail("Expected '--' option terminator in SSH call \(index): \(args)")
                continue
            }
            let authorityIndex = terminatorIndex + 1
            XCTAssertTrue(authorityIndex < args.count, "Authority should follow '--' in call \(index)")
            XCTAssertEqual(args[authorityIndex], "nconn@happy-mac.local")
        }
    }

    func testSSHCommandEscapesSingleQuotesInRemotePath() {
        let runner = StubCommandRunner(
            result: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
        )
        let toml = """
        [[project]]
        name = "Remote ML"
        remote = "ssh-remote+nconn@happy-mac.local"
        path = "/Users/nconn/it's-project"
        color = "teal"
        useAgentLayer = false
        """
        let doctor = makeDoctor(
            toml: toml,
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        _ = doctor.run()

        // First SSH call is the path check (test -d)
        guard runner.allArguments.count >= 1 else {
            XCTFail("Expected ssh command to have been called")
            return
        }
        let pathCheckArgs = runner.allArguments[0]
        guard let last = pathCheckArgs.last else {
            XCTFail("Expected path check args to be non-empty")
            return
        }
        XCTAssertTrue(last.contains("test -d '/Users/nconn/it'\\''s-project'"), "Unexpected ssh test arg: \(last)")
    }

    // MARK: - SSH settings.json block check

    func testSSHSettingsBlockPresentPasses() {
        let settingsContent = """
        {
          // >>> project-switcher
          // Managed by ProjectSwitcher. Do not edit this block manually.
          "window.title": "PS:remote-ml - ${dirty}${activeEditorShort}",
          // <<< project-switcher
        }
        """
        let runner = SequentialCommandRunner(results: [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),       // path check
            .success(PsCommandResult(exitCode: 0, stdout: settingsContent, stderr: ""))  // settings check
        ])
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        let report = doctor.run()

        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Remote VS Code settings block present: remote-ml")
        })
    }

    func testSSHSettingsBlockMissingWarns() {
        let settingsContent = """
        {
          "editor.fontSize": 14
        }
        """
        let runner = SequentialCommandRunner(results: [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),        // path check
            .success(PsCommandResult(exitCode: 0, stdout: settingsContent, stderr: ""))  // settings check (no block)
        ])
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Remote .vscode/settings.json missing ProjectSwitcher block: remote-ml")
        }
        XCTAssertNotNil(finding)
        // When file exists but block missing, snippet should be just the block (no outer braces)
        XCTAssertNotNil(finding?.snippet)
        XCTAssertTrue(finding?.snippet?.contains("// >>> project-switcher") == true)
    }

    func testSSHSettingsBlockSSHFails255ReportsCheckUnavailable() {
        let runner = SequentialCommandRunner(results: [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),        // path check
            .success(PsCommandResult(exitCode: 255, stdout: "", stderr: "Connection refused"))  // settings check fails
        ])
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Cannot check remote VS Code settings for remote-ml")
        }
        XCTAssertNotNil(finding)
        XCTAssertNil(finding?.snippet)
    }

    func testSSHSettingsBlockSSHNotFoundWarns() {
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: false
        )

        let report = doctor.run()

        // When ssh is not found, both path check and settings check should warn
        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("ssh not found")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Cannot check remote VS Code settings")
        })
    }

    func testSSHSettingsBlockRunnerFailureHasNoMisleadingSnippet() {
        let runner = SequentialCommandRunner(results: [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .failure(PsCoreError(message: "SSH failed"))
        ])
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Cannot check remote VS Code settings")
        }
        XCTAssertNotNil(finding)
        XCTAssertNil(finding?.snippet)
    }

    func testSSHSettingsBlockMissingFileWarnsWithCreationSnippet() {
        let runner = SequentialCommandRunner(results: [
            .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            .success(PsCommandResult(exitCode: 44, stdout: "", stderr: ""))
        ])
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        let report = doctor.run()

        let finding = report.findings.first {
            $0.severity == .warn && $0.title.contains("Remote .vscode/settings.json missing ProjectSwitcher block")
        }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.snippetLanguage, "jsonc")
        XCTAssertTrue(finding?.bodyLines.contains(where: { $0.contains("Create or update") }) == true)
    }

    func testSSHSettingsCommandUsesDistinctMissingFileExitCode() {
        let runner = StubCommandRunner(
            result: .success(PsCommandResult(exitCode: 0, stdout: "{}", stderr: ""))
        )
        let doctor = makeDoctor(
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        _ = doctor.run()

        XCTAssertTrue(runner.allArguments.contains { arguments in
            arguments.last?.contains("else exit 44") == true
        })
    }

    // MARK: - Concurrent SSH checks

    func testMultipleSSHProjectsAllProduceFindings() {
        let toml = """
        [[project]]
        name = "Remote A"
        remote = "ssh-remote+user@hostA"
        path = "/home/user/a"
        color = "blue"
        useAgentLayer = false

        [[project]]
        name = "Remote B"
        remote = "ssh-remote+user@hostB"
        path = "/home/user/b"
        color = "red"
        useAgentLayer = false

        [[project]]
        name = "Remote C"
        remote = "ssh-remote+user@hostC"
        path = "/home/user/c"
        color = "green"
        useAgentLayer = false
        """
        let doctor = makeDoctor(
            toml: toml,
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true
        )

        let report = doctor.run()

        // All 3 SSH projects should have path check findings
        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Remote project path exists: remote-a")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Remote project path exists: remote-b")
        })
        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Remote project path exists: remote-c")
        })
    }

    func testConcurrentSSHChecksCollectAllFindingsFromMixedResults() {
        // Use a per-host runner that returns different exit codes per host
        let runner = PerHostCommandRunner(resultsByHost: [
            "user@hostA": .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            "user@hostB": .success(PsCommandResult(exitCode: 1, stdout: "", stderr: "")),
            "user@hostC": .success(PsCommandResult(exitCode: 255, stdout: "", stderr: "Connection refused"))
        ])

        let toml = """
        [[project]]
        name = "Remote A"
        remote = "ssh-remote+user@hostA"
        path = "/home/user/a"
        color = "blue"
        useAgentLayer = false

        [[project]]
        name = "Remote B"
        remote = "ssh-remote+user@hostB"
        path = "/home/user/b"
        color = "red"
        useAgentLayer = false

        [[project]]
        name = "Remote C"
        remote = "ssh-remote+user@hostC"
        path = "/home/user/c"
        color = "green"
        useAgentLayer = false
        """

        let doctor = makeDoctor(
            toml: toml,
            sshResult: .success(PsCommandResult(exitCode: 0, stdout: "", stderr: "")),
            sshResolvable: true,
            commandRunner: runner
        )

        let report = doctor.run()

        // Host A: exit 0 → PASS
        XCTAssertTrue(report.findings.contains {
            $0.severity == .pass && $0.title.contains("Remote project path exists: remote-a")
        })
        // Host B: exit 1 → FAIL
        XCTAssertTrue(report.findings.contains {
            $0.severity == .fail && $0.title.contains("Remote project path missing: remote-b")
        })
        // Host C: exit 255 → WARN
        XCTAssertTrue(report.findings.contains {
            $0.severity == .warn && $0.title.contains("Cannot verify remote path: remote-c")
        })
    }

    // MARK: - Helpers

    private static let sshConfigTOML = """
    [[project]]
    name = "Remote ML"
    remote = "ssh-remote+nconn@happy-mac.local"
    path = "/Users/nconn/project"
    color = "teal"
    useAgentLayer = false
    """

    private func makeDoctor(
        toml: String? = nil,
        sshResult: Result<PsCommandResult, PsCoreError>,
        sshResolvable: Bool,
        commandRunner: (any CommandRunning)? = nil,
        aerospaceHealth: AeroSpaceHealthChecking = StubAeroSpaceHealth()
    ) -> Doctor {
        let configDir = tempDir.appendingPathComponent(".config/project-switcher", isDirectory: true)
        try! FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configFile = configDir.appendingPathComponent("config.toml")
        try! (toml ?? Self.sshConfigTOML).write(to: configFile, atomically: true, encoding: .utf8)

        let dataStore = DataPaths(homeDirectory: tempDir)

        // Build a controlled ExecutableResolver:
        // - "brew" always found (avoids Doctor FAIL for Homebrew)
        // - "ssh" found only when sshResolvable is true
        // - Login shell fallback disabled so we fully control resolution
        let allowedExecutables: Set<String> = sshResolvable
            ? ["/usr/bin/brew", "/usr/bin/ssh"]
            : ["/usr/bin/brew"]
        let stubFS = SelectiveFileSystem(executablePaths: allowedExecutables)
        let resolver = ExecutableResolver(
            fileSystem: stubFS,
            searchPaths: ["/usr/bin"],
            loginShellFallbackEnabled: false
        )

        let runner = commandRunner ?? StubCommandRunner(result: sshResult)

        return Doctor(
            runningApplicationChecker: StubRunningAppChecker(),
            hotkeyStatusProvider: nil,
            dateProvider: StubDateProvider(),
            aerospaceHealth: aerospaceHealth,
            appDiscovery: StubAppDiscovery(),
            executableResolver: resolver,
            commandRunner: runner,
            dataStore: dataStore
        )
    }

    private func makeDoctorForRun(
        toml: String,
        allowedExecutables: Set<String>,
        runningAeroSpace: Bool,
        appDiscoveryInstalled: Bool,
        aerospaceHealth: AeroSpaceHealthChecking = StubAeroSpaceHealth(),
        hotkeyStatusProvider: HotkeyStatusProviding? = nil,
        windowPositioner: WindowPositioning? = nil
    ) throws -> Doctor {
        let configDir = tempDir.appendingPathComponent(".config/project-switcher", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let configFile = configDir.appendingPathComponent("config.toml")
        try toml.write(to: configFile, atomically: true, encoding: .utf8)

        let dataStore = DataPaths(homeDirectory: tempDir)

        let resolver = ExecutableResolver(
            fileSystem: SelectiveFileSystem(executablePaths: allowedExecutables),
            searchPaths: ["/usr/bin"],
            loginShellFallbackEnabled: false
        )

        let runningChecker = StubRunningAppCheckerOverride(runningAeroSpace: runningAeroSpace)
        let appDiscovery: any AppDiscovering = appDiscoveryInstalled ? StubAppDiscovery() : NilAppDiscovery()

        // Fail loudly if SSH path verification is attempted in these tests.
        let runner = StubCommandRunner(result: .failure(PsCoreError(message: "unexpected ssh invocation")))

        return Doctor(
            runningApplicationChecker: runningChecker,
            hotkeyStatusProvider: hotkeyStatusProvider,
            dateProvider: StubDateProvider(),
            aerospaceHealth: aerospaceHealth,
            appDiscovery: appDiscovery,
            executableResolver: resolver,
            commandRunner: runner,
            dataStore: dataStore,
            windowPositioner: windowPositioner
        )
    }
}

// MARK: - Test Doubles

private struct StubRunningAppChecker: RunningApplicationChecking {
    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        bundleIdentifier == "bobko.aerospace"
    }

    func terminateApplication(bundleIdentifier: String) -> Bool {
        XCTFail("Unexpected terminateApplication call in DoctorSSHTests (StubRunningAppChecker) for bundleIdentifier=\(bundleIdentifier)")
        return false
    }
}

private struct StubRunningAppCheckerOverride: RunningApplicationChecking {
    let runningAeroSpace: Bool

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        if bundleIdentifier == "bobko.aerospace" {
            return runningAeroSpace
        }
        return false
    }

    func terminateApplication(bundleIdentifier: String) -> Bool {
        XCTFail("Unexpected terminateApplication call in DoctorSSHTests (StubRunningAppCheckerOverride) for bundleIdentifier=\(bundleIdentifier)")
        return false
    }
}

private struct NilAppDiscovery: AppDiscovering {
    func applicationURL(bundleIdentifier: String) -> URL? { nil }
    func applicationURL(named appName: String) -> URL? { nil }
    func bundleIdentifier(forApplicationAt url: URL) -> String? { nil }
}

private struct StubHotkeyStatusProvider: HotkeyStatusProviding {
    let status: HotkeyRegistrationStatus?

    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus? { status }
}

private struct StubDateProvider: DateProviding {
    func now() -> Date { Date(timeIntervalSince1970: 1704067200) }
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

private final class RecordingAeroSpaceHealth: AeroSpaceHealthChecking {
    private(set) var installCalls: Int = 0
    private(set) var startCalls: Int = 0
    private(set) var reloadCalls: Int = 0
    var installStatusValue: AeroSpaceInstallStatus = AeroSpaceInstallStatus(isInstalled: true, appPath: "/Applications/AeroSpace.app")
    var cliAvailableValue: Bool = true
    var compatibilityValue: AeroSpaceCompatibility = .compatible

    func installStatus() -> AeroSpaceInstallStatus {
        installStatusValue
    }
    func isCliAvailable() -> Bool { cliAvailableValue }
    func healthCheckCompatibility() -> AeroSpaceCompatibility { compatibilityValue }

    func healthInstallViaHomebrew() -> Bool {
        installCalls += 1
        return true
    }

    func healthStart() -> Bool {
        startCalls += 1
        return true
    }

    func healthReloadConfig() -> Bool {
        reloadCalls += 1
        return true
    }
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

/// File system stub that reports specific paths as executable.
private struct SelectiveFileSystem: FileSystem {
    let executablePaths: Set<String>

    func fileExists(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func directoryExists(at url: URL) -> Bool { false }
    func isExecutableFile(at url: URL) -> Bool { executablePaths.contains(url.path) }
    func readFile(at url: URL) throws -> Data { throw NSError(domain: "stub", code: 1) }
    func createDirectory(at url: URL) throws {}
    func fileSize(at url: URL) throws -> UInt64 { 0 }
    func removeItem(at url: URL) throws {}
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {}
    func appendFile(at url: URL, data: Data) throws {}
    func writeFile(at url: URL, data: Data) throws {}
}

private class StubCommandRunner: CommandRunning {
    let result: Result<PsCommandResult, PsCoreError>
    private let lock = NSLock()
    private var _allArguments: [[String]] = []
    var allArguments: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _allArguments
    }
    var lastArguments: [String]? { allArguments.last }

    init(result: Result<PsCommandResult, PsCoreError>) {
        self.result = result
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        lock.lock()
        _allArguments.append(arguments)
        lock.unlock()
        return result
    }
}

private class StubWindowPositioner: WindowPositioning {
    let trusted: Bool
    private(set) var promptCalls = 0

    init(trusted: Bool) {
        self.trusted = trusted
    }

    func getPrimaryWindowFrame(bundleId: String, projectId: String) -> Result<CGRect, PsCoreError> {
        .failure(PsCoreError(category: .window, message: "stub"))
    }

    func setWindowFrames(bundleId: String, projectId: String, primaryFrame: CGRect, cascadeOffsetPoints: CGFloat) -> Result<WindowPositionResult, PsCoreError> {
        .failure(PsCoreError(category: .window, message: "stub"))
    }

    func recoverWindow(bundleId: String, windowTitle: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> { .success(.unchanged) }

    func recoverFocusedWindow(bundleId: String, screenVisibleFrame: CGRect) -> Result<RecoveryOutcome, PsCoreError> { .success(.unchanged) }

    func isAccessibilityTrusted() -> Bool {
        trusted
    }

    func promptForAccessibility() -> Bool {
        promptCalls += 1
        return trusted
    }
}

/// Command runner that routes results by SSH host (thread-safe, for concurrent SSH tests).
private class PerHostCommandRunner: CommandRunning {
    let resultsByHost: [String: Result<PsCommandResult, PsCoreError>]
    let fallback: Result<PsCommandResult, PsCoreError>

    init(
        resultsByHost: [String: Result<PsCommandResult, PsCoreError>],
        fallback: Result<PsCommandResult, PsCoreError> = .success(PsCommandResult(exitCode: 0, stdout: "", stderr: ""))
    ) {
        self.resultsByHost = resultsByHost
        self.fallback = fallback
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        // Extract the host from arguments: look for the argument after "--"
        if let terminatorIndex = arguments.firstIndex(of: "--"),
           terminatorIndex + 1 < arguments.count {
            let host = arguments[terminatorIndex + 1]
            if let result = resultsByHost[host] {
                return result
            }
        }
        return fallback
    }
}

/// Command runner that returns different results for sequential calls (thread-safe).
private class SequentialCommandRunner: CommandRunning {
    private let lock = NSLock()
    private var results: [Result<PsCommandResult, PsCoreError>]
    private var _lastArguments: [String]?
    var lastArguments: [String]? {
        lock.lock()
        defer { lock.unlock() }
        return _lastArguments
    }

    init(results: [Result<PsCommandResult, PsCoreError>]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        workingDirectory: String?
    ) -> Result<PsCommandResult, PsCoreError> {
        lock.lock()
        _lastArguments = arguments
        guard !results.isEmpty else {
            lock.unlock()
            return .failure(PsCoreError(message: "SequentialCommandRunner: no results left"))
        }
        let result = results.removeFirst()
        lock.unlock()
        return result
    }
}
