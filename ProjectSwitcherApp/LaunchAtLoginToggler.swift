import Foundation
import ServiceManagement

import ProjectSwitcherCore

/// Reuses the core structured log payload type for launch-at-login events.
typealias LaunchAtLoginLogEntry = LogEventPayload

/// Abstraction over login-item registration operations.
protocol LaunchAtLoginServiceManaging {
    /// True when the login item is currently enabled.
    var isEnabled: Bool { get }

    /// Enables the login item.
    func register() throws

    /// Disables the login item.
    func unregister() throws
}

/// Default login-item service adapter backed by `SMAppService.mainApp`.
struct MainAppLaunchAtLoginService: LaunchAtLoginServiceManaging {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Config write abstraction for launch-at-login settings.
protocol LaunchAtLoginConfigWriting {
    /// Writes the `app.autoStartAtLogin` value to config.
    /// - Parameters:
    ///   - value: Desired config value.
    ///   - configURL: Config file path.
    func setAutoStartAtLogin(_ value: Bool, in configURL: URL) throws
}

/// Default config writer backed by `ConfigWriteBack`.
struct LaunchAtLoginConfigWriter: LaunchAtLoginConfigWriting {
    func setAutoStartAtLogin(_ value: Bool, in configURL: URL) throws {
        try ConfigWriteBack.setAutoStartAtLogin(value, in: configURL)
    }
}

/// Handles launch-at-login toggle behavior for AppDelegate.
struct LaunchAtLoginToggler {
    private let service: LaunchAtLoginServiceManaging
    private let configWriter: LaunchAtLoginConfigWriting

    /// Creates a toggler with injectable dependencies for tests.
    /// - Parameters:
    ///   - service: Login-item service adapter.
    ///   - configWriter: Config write adapter.
    init(
        service: LaunchAtLoginServiceManaging = MainAppLaunchAtLoginService(),
        configWriter: LaunchAtLoginConfigWriting = LaunchAtLoginConfigWriter()
    ) {
        self.service = service
        self.configWriter = configWriter
    }

    /// Toggles launch-at-login and returns structured log events.
    /// - Parameter configURL: Config file path.
    /// - Returns: Ordered log events describing the toggle flow.
    func toggle(configURL: URL) -> [LaunchAtLoginLogEntry] {
        let isCurrentlyEnabled = service.isEnabled
        let newValue = !isCurrentlyEnabled
        var logs: [LaunchAtLoginLogEntry] = []

        if newValue {
            do {
                try service.register()
                logs.append(.init(event: "launch_at_login.toggled_on", level: .info, message: nil, context: nil))
            } catch {
                logs.append(.init(
                    event: "launch_at_login.toggle_register_failed",
                    level: .error,
                    message: "Failed to enable launch at login: \(error.localizedDescription)",
                    context: nil
                ))
                return logs
            }
        } else {
            do {
                try service.unregister()
                logs.append(.init(event: "launch_at_login.toggled_off", level: .info, message: nil, context: nil))
            } catch {
                logs.append(.init(
                    event: "launch_at_login.toggle_unregister_failed",
                    level: .error,
                    message: "Failed to disable launch at login: \(error.localizedDescription)",
                    context: nil
                ))
                return logs
            }
        }

        do {
            try configWriter.setAutoStartAtLogin(newValue, in: configURL)
            logs.append(.init(
                event: "launch_at_login.config_written",
                level: .info,
                message: nil,
                context: ["value": "\(newValue)"]
            ))
        } catch {
            logs.append(.init(
                event: "launch_at_login.config_write_failed",
                level: .error,
                message: "Config save failed: \(error.localizedDescription)",
                context: nil
            ))

            do {
                try setServiceEnabled(isCurrentlyEnabled)
                logs.append(.init(
                    event: "launch_at_login.rollback_succeeded",
                    level: .info,
                    message: nil,
                    context: ["value": "\(isCurrentlyEnabled)"]
                ))
            } catch {
                logs.append(.init(
                    event: "launch_at_login.rollback_failed",
                    level: .error,
                    message: "Rollback failed after config write failure: \(error.localizedDescription)",
                    context: ["expected": "\(isCurrentlyEnabled)"]
                ))
            }

            let actualValue = service.isEnabled
            if actualValue != isCurrentlyEnabled {
                logs.append(.init(
                    event: "launch_at_login.rollback_state_mismatch",
                    level: .error,
                    message: "Launch-at-login service state diverged from config after rollback attempt.",
                    context: [
                        "expected": "\(isCurrentlyEnabled)",
                        "actual": "\(actualValue)"
                    ]
                ))
            }
        }

        return logs
    }

    /// Sets the login-item service to an exact target enabled value.
    /// - Parameter enabled: Desired runtime login-item state.
    private func setServiceEnabled(_ enabled: Bool) throws {
        if enabled {
            try service.register()
        } else {
            try service.unregister()
        }
    }
}

/// Reconciles the configured launch-at-login value with the current service state.
struct LaunchAtLoginSynchronizer {
    private let service: LaunchAtLoginServiceManaging

    /// Creates a synchronizer with an injectable login-item service.
    /// - Parameter service: Login-item service adapter.
    init(service: LaunchAtLoginServiceManaging = MainAppLaunchAtLoginService()) {
        self.service = service
    }

    /// Applies the configured value only when registration state must change.
    /// - Parameter configValue: Desired launch-at-login setting.
    /// - Returns: Structured log entries describing an attempted state change.
    func sync(configValue: Bool) -> [LaunchAtLoginLogEntry] {
        guard service.isEnabled != configValue else { return [] }

        do {
            if configValue {
                try service.register()
                return [.init(event: "launch_at_login.registered", level: .info, message: nil, context: nil)]
            }

            try service.unregister()
            return [.init(event: "launch_at_login.unregistered", level: .info, message: nil, context: nil)]
        } catch {
            let action = configValue ? "registration" : "unregistration"
            let event = configValue ? "launch_at_login.register_failed" : "launch_at_login.unregister_failed"
            return [.init(
                event: event,
                level: .warn,
                message: "Launch at login configured but \(action) failed: \(error.localizedDescription)",
                context: nil
            )]
        }
    }
}
