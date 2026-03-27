import XCTest

@testable import ProjectSwitcher
@testable import ProjectSwitcherCore

final class LaunchAtLoginTogglerTests: XCTestCase {
    func testToggleOnSuccessLogsToggledOnAndConfigWritten() {
        let service = LaunchAtLoginServiceStub(initialEnabled: false)
        let writer = LaunchAtLoginConfigWriterStub()
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggled_on" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.config_written" }))
        XCTAssertFalse(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertEqual(service.isEnabled, true)
        XCTAssertEqual(writer.calls, 1)
        XCTAssertEqual(writer.lastWrittenValue, true)
    }

    func testToggleOffSuccessLogsToggledOffAndConfigWritten() {
        let service = LaunchAtLoginServiceStub(initialEnabled: true)
        let writer = LaunchAtLoginConfigWriterStub()
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggled_off" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.config_written" }))
        XCTAssertFalse(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertEqual(service.isEnabled, false)
        XCTAssertEqual(writer.calls, 1)
        XCTAssertEqual(writer.lastWrittenValue, false)
    }

    func testToggleConfigWriteFailureLogsRollbackSucceededAndRestoresStatus() {
        let service = LaunchAtLoginServiceStub(initialEnabled: false)
        let writer = LaunchAtLoginConfigWriterStub()
        writer.writeError = LaunchAtLoginTestError("write failed")
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggled_on" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.rollback_succeeded" }))
        XCTAssertEqual(service.isEnabled, false)
    }

    func testToggleConfigWriteFailureRollbackFailureLogsMismatch() {
        let service = LaunchAtLoginServiceStub(initialEnabled: false)
        service.unregisterResults = [.failure(LaunchAtLoginTestError("rollback unregister failed"))]
        let writer = LaunchAtLoginConfigWriterStub()
        writer.writeError = LaunchAtLoginTestError("write failed")
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggled_on" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.rollback_failed" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.rollback_state_mismatch" }))
        XCTAssertEqual(service.isEnabled, true)
    }

    func testToggleOffConfigWriteFailureLogsRollbackSucceededAndRestoresStatus() {
        let service = LaunchAtLoginServiceStub(initialEnabled: true)
        let writer = LaunchAtLoginConfigWriterStub()
        writer.writeError = LaunchAtLoginTestError("write failed")
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggled_off" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.rollback_succeeded" }))
        XCTAssertEqual(service.isEnabled, true)
    }

    func testToggleOffConfigWriteFailureRollbackFailureLogsMismatch() {
        let service = LaunchAtLoginServiceStub(initialEnabled: true)
        service.registerResults = [.failure(LaunchAtLoginTestError("rollback register failed"))]
        let writer = LaunchAtLoginConfigWriterStub()
        writer.writeError = LaunchAtLoginTestError("write failed")
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggled_off" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.rollback_failed" }))
        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.rollback_state_mismatch" }))
        XCTAssertEqual(service.isEnabled, false)
    }

    func testToggleOnRegisterFailureReturnsWithoutConfigWrite() {
        let service = LaunchAtLoginServiceStub(initialEnabled: false)
        service.registerResults = [.failure(LaunchAtLoginTestError("register failed"))]
        let writer = LaunchAtLoginConfigWriterStub()
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggle_register_failed" }))
        XCTAssertFalse(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertFalse(logs.contains(where: { $0.event == "launch_at_login.config_written" }))
        XCTAssertEqual(writer.calls, 0)
    }

    func testToggleOffUnregisterFailureReturnsWithoutConfigWrite() {
        let service = LaunchAtLoginServiceStub(initialEnabled: true)
        service.unregisterResults = [.failure(LaunchAtLoginTestError("unregister failed"))]
        let writer = LaunchAtLoginConfigWriterStub()
        let toggler = LaunchAtLoginToggler(service: service, configWriter: writer)

        let logs = toggler.toggle(configURL: URL(fileURLWithPath: "/tmp/config.toml", isDirectory: false))

        XCTAssertTrue(logs.contains(where: { $0.event == "launch_at_login.toggle_unregister_failed" }))
        XCTAssertFalse(logs.contains(where: { $0.event == "launch_at_login.config_write_failed" }))
        XCTAssertFalse(logs.contains(where: { $0.event == "launch_at_login.config_written" }))
        XCTAssertEqual(writer.calls, 0)
    }
}

private struct LaunchAtLoginTestError: Error, LocalizedError {
    private let detail: String

    init(_ detail: String) {
        self.detail = detail
    }

    var errorDescription: String? {
        detail
    }
}

private final class LaunchAtLoginServiceStub: LaunchAtLoginServiceManaging {
    private(set) var isEnabled: Bool
    var registerResults: [Result<Void, Error>] = []
    var unregisterResults: [Result<Void, Error>] = []

    init(initialEnabled: Bool) {
        self.isEnabled = initialEnabled
    }

    func register() throws {
        switch dequeue(resultFrom: &registerResults) {
        case .success:
            isEnabled = true
        case .failure(let error):
            throw error
        }
    }

    func unregister() throws {
        switch dequeue(resultFrom: &unregisterResults) {
        case .success:
            isEnabled = false
        case .failure(let error):
            throw error
        }
    }

    private func dequeue(resultFrom queue: inout [Result<Void, Error>]) -> Result<Void, Error> {
        if queue.isEmpty {
            return .success(())
        }
        return queue.removeFirst()
    }
}

private final class LaunchAtLoginConfigWriterStub: LaunchAtLoginConfigWriting {
    var writeError: Error?
    private(set) var calls: Int = 0
    private(set) var lastWrittenValue: Bool?

    func setAutoStartAtLogin(_ value: Bool, in _: URL) throws {
        calls += 1
        lastWrittenValue = value
        if let writeError {
            throw writeError
        }
    }
}
