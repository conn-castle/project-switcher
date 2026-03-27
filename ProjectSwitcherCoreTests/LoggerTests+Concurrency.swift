import XCTest

@testable import ProjectSwitcherCore

extension LoggerTests {

    func testConcurrentWritesRemainValidJsonLinesWithInterleavingFileSystem() throws {
        let fileSystem = LoggerInterleavingAppendFileSystem(interleaveDelaySeconds: 0.05)
        let dataStore = DataPaths(homeDirectory: URL(fileURLWithPath: "/Users/testuser", isDirectory: true))
        let logger = ProjectSwitcherLogger(
            dataStore: dataStore,
            fileSystem: fileSystem,
            maxLogSizeBytes: 1024 * 1024,
            maxArchives: 2
        )

        let queue = DispatchQueue(label: "com.projectswitcher.tests.logger.concurrent", attributes: .concurrent)
        let startGate = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let resultLock = NSLock()
        var results: [Result<Void, LogWriteError>] = []

        for index in 0..<2 {
            group.enter()
            queue.async {
                startGate.wait()
                let result = logger.log(
                    event: "concurrent.event.\(index)",
                    level: .info,
                    message: String(repeating: "payload-", count: 40),
                    context: ["writer": "\(index)"]
                )
                resultLock.lock()
                results.append(result)
                resultLock.unlock()
                group.leave()
            }
        }

        startGate.signal()
        startGate.signal()
        let waitTimeoutSeconds: TimeInterval = 8
        let waitResult = group.wait(timeout: .now() + waitTimeoutSeconds)
        XCTAssertEqual(
            waitResult,
            .success,
            "Timed out after \(waitTimeoutSeconds)s waiting for concurrent writers. Partial results: \(results)"
        )

        XCTAssertEqual(results.count, 2)
        for result in results {
            if case .failure(let error) = result {
                XCTFail("Unexpected log failure: \(error)")
            }
        }

        let data = try fileSystem.readFile(at: dataStore.primaryLogFile)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, 2)

        for line in lines {
            do {
                _ = try JSONDecoder().decode(LogEntry.self, from: Data(line.utf8))
            } catch {
                XCTFail("Corrupted JSONL line: \(line)\nError: \(error)")
            }
        }
    }

    func testConcurrentWritesAcrossProcessesRemainValidJsonLines() throws {
        let tmpHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("project-switcher-logger-multiprocess-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpHome) }
        try FileManager.default.createDirectory(at: tmpHome, withIntermediateDirectories: true)

        let projectPath = tmpHome
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent("sample", isDirectory: true)
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        let configDir = tmpHome
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("project-switcher", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configPath = configDir.appendingPathComponent("config.toml", isDirectory: false)
        let config = """
        [[project]]
        name = "Sample"
        path = "\(projectPath.path)"
        color = "blue"
        """
        try config.write(to: configPath, atomically: true, encoding: .utf8)

        let cliURL = try resolveCLIBinaryURLOrSkip()

        // Warm up to ensure the shared log file exists before high-contention appends.
        let warmupStatus = try runCLIListProjects(cliURL: cliURL, homeDirectory: tmpHome)
        XCTAssertEqual(warmupStatus, 0)

        let workerCount = 6
        let runsPerWorker = 20
        let failureLock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
            for run in 0..<runsPerWorker {
                do {
                    let status = try runCLIListProjects(cliURL: cliURL, homeDirectory: tmpHome)
                    if status != 0 {
                        failureLock.lock()
                        failures.append("worker=\(worker) run=\(run) status=\(status)")
                        failureLock.unlock()
                    }
                } catch {
                    failureLock.lock()
                    failures.append("worker=\(worker) run=\(run) error=\(error)")
                    failureLock.unlock()
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "CLI subprocess failures: \(failures.joined(separator: "; "))")

        let dataStore = DataPaths(homeDirectory: tmpHome)
        let minimumExpectedLineCount = workerCount * runsPerWorker

        let fileData = try Data(contentsOf: dataStore.primaryLogFile)
        let text = try XCTUnwrap(String(data: fileData, encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertGreaterThanOrEqual(lines.count, minimumExpectedLineCount)

        for line in lines {
            do {
                _ = try JSONDecoder().decode(LogEntry.self, from: Data(line.utf8))
            } catch {
                XCTFail("Corrupted JSONL line: \(line)\nError: \(error)")
            }
        }
    }

    private func runCLIListProjects(cliURL: URL, homeDirectory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = cliURL
        process.arguments = ["list-projects"]
        process.currentDirectoryURL = homeDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = homeDirectory.path
        environment["CFFIXED_USER_HOME"] = homeDirectory.path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func resolveCLIBinaryURLOrSkip() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let builtProductsDirectory = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            candidates.append(
                URL(fileURLWithPath: builtProductsDirectory, isDirectory: true)
                    .appendingPathComponent("pswitcher", isDirectory: false)
            )
        }

        let bundleProductsDirectory = Bundle(for: LoggerTests.self).bundleURL.deletingLastPathComponent()
        candidates.append(bundleProductsDirectory.appendingPathComponent("pswitcher", isDirectory: false))

        // Fallback for repo-local `make test` / `make coverage` runs.
        let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent() // ProjectSwitcherCoreTests
            .deletingLastPathComponent() // repo root
        let repoDerivedDataCLI = repositoryRoot
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("DerivedData", isDirectory: true)
            .appendingPathComponent("Build", isDirectory: true)
            .appendingPathComponent("Products", isDirectory: true)
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("pswitcher", isDirectory: false)
        candidates.append(repoDerivedDataCLI)

        var checkedPaths: [String] = []
        for candidate in candidates {
            guard !checkedPaths.contains(candidate.path) else {
                continue
            }
            checkedPaths.append(candidate.path)

            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw XCTSkip(
            "Skipping multiprocess logger test: CLI binary 'pswitcher' not found in build products. Checked: \(checkedPaths.joined(separator: ", "))"
        )
    }
}
