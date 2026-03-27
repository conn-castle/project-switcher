import XCTest

@testable import ProjectSwitcherCLICore
@testable import ProjectSwitcherCore

final class OutputRecorder {
    private(set) var stdout: [String] = []
    private(set) var stderr: [String] = []

    var sink: PsCLIOutput {
        PsCLIOutput(
            stdout: { [weak self] line in self?.stdout.append(line) },
            stderr: { [weak self] line in self?.stderr.append(line) }
        )
    }
}

func makeDoctorReport(hasFailures: Bool) -> DoctorReport {
    let metadata = DoctorMetadata(
        timestamp: "2024-01-01T00:00:00.000Z",
        projectSwitcherVersion: "test",
        macOSVersion: "macOS 15.7",
        aerospaceApp: "AVAILABLE",
        aerospaceCli: "AVAILABLE",
        errorContext: nil,
        durationMs: 0,
        sectionTimings: [:]
    )
    let findings = hasFailures
        ? [DoctorFinding(severity: .fail, title: "Failure")]
        : [DoctorFinding(severity: .pass, title: "Pass")]
    return DoctorReport(metadata: metadata, findings: findings)
}

func makeConfig(projectIds: [String], warnings: [ConfigFinding] = []) -> ConfigLoadSuccess {
    let projects = projectIds.map { id in
        makeProject(id: id, name: id.uppercased(), path: "/tmp/\(id)")
    }
    return ConfigLoadSuccess(config: Config(projects: projects), warnings: warnings)
}

func makeProject(id: String, name: String, path: String) -> ProjectConfig {
    ProjectConfig(
        id: id,
        name: name,
        remote: nil,
        path: path,
        color: "blue",
        useAgentLayer: false,
        chromePinnedTabs: [],
        chromeDefaultTabs: []
    )
}

final class MockProjectManager: ProjectManaging {
    var loadConfigResult: Result<ConfigLoadSuccess, ConfigLoadError> = .success(ConfigLoadSuccess(config: Config(projects: [])))
    var sortedProjectsResult: [ProjectConfig] = []
    var sortedProjectsQueries: [String] = []
    var captureCurrentFocusResult: CapturedFocus?
    var selectProjectResult: Result<ProjectActivationSuccess, ProjectError> = .success(ProjectActivationSuccess(ideWindowId: 1, tabRestoreWarning: nil))
    var selectProjectCalls: [(projectId: String, focus: CapturedFocus)] = []
    var closeProjectResult: Result<ProjectCloseSuccess, ProjectError> = .success(ProjectCloseSuccess(tabCaptureWarning: nil))
    var closeProjectCalls: [String] = []
    var closeProjectDelayNanoseconds: UInt64 = 0
    var exitToNonProjectResult: Result<Void, ProjectError> = .success(())
    var exitCalls: Int = 0
    var exitDelayNanoseconds: UInt64 = 0

    func loadConfig() -> Result<ConfigLoadSuccess, ConfigLoadError> {
        loadConfigResult
    }

    func sortedProjects(query: String) -> [ProjectConfig] {
        sortedProjectsQueries.append(query)
        return sortedProjectsResult
    }

    func captureCurrentFocus() -> CapturedFocus? {
        captureCurrentFocusResult
    }

    func selectProject(projectId: String, preCapturedFocus: CapturedFocus) async -> Result<ProjectActivationSuccess, ProjectError> {
        selectProjectCalls.append((projectId: projectId, focus: preCapturedFocus))
        return selectProjectResult
    }

    func closeProject(projectId: String) async -> Result<ProjectCloseSuccess, ProjectError> {
        if closeProjectDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: closeProjectDelayNanoseconds)
        }
        closeProjectCalls.append(projectId)
        return closeProjectResult
    }

    func exitToNonProjectWindow() async -> Result<Void, ProjectError> {
        if exitDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: exitDelayNanoseconds)
        }
        exitCalls += 1
        return exitToNonProjectResult
    }
}
