import AppKit

import ProjectSwitcherCore

/// Result of the onboarding check.
enum OnboardingResult {
    /// Setup is complete, app can continue.
    case ready
    /// User declined setup, app should quit.
    case declined
}

/// Handles first-launch setup for ProjectSwitcher.
/// Ensures AeroSpace is installed and configured before the app runs.
struct Onboarding {
    private let logger: ProjectSwitcherLogging
    private let aerospace: PsAeroSpace
    private let configManager: AeroSpaceConfigManager

    /// Creates an onboarding handler.
    /// - Parameter logger: Logger for diagnostic events.
    init(logger: ProjectSwitcherLogging) {
        self.logger = logger
        self.aerospace = PsAeroSpace()
        self.configManager = AeroSpaceConfigManager()
    }

    /// Performs onboarding if needed, calling completion when done.
    /// - Parameter completion: Called with result on main thread.
    func runIfNeeded(completion: @escaping (OnboardingResult) -> Void) {
        let needsAeroSpaceInstall = !aerospace.isAppInstalled()
        let needsConfigSetup = configManager.configStatus() != .managedByProjectSwitcher

        // If everything is set up, no onboarding needed
        guard needsAeroSpaceInstall || needsConfigSetup else {
            log(event: "onboarding.skipped", context: ["reason": "already_configured"])
            completion(.ready)
            return
        }

        log(
            event: "onboarding.required",
            context: [
                "needs_aerospace": needsAeroSpaceInstall ? "true" : "false",
                "needs_config": needsConfigSetup ? "true" : "false"
            ]
        )

        let userAccepted = showAlert(needsAeroSpaceInstall: needsAeroSpaceInstall)

        guard userAccepted else {
            log(event: "onboarding.declined")
            completion(.declined)
            return
        }

        log(event: "onboarding.accepted")

        // Show progress window
        let progressWindow = OnboardingProgressWindow(
            message: needsAeroSpaceInstall
                ? "Installing AeroSpace via Homebrew..."
                : "Configuring AeroSpace..."
        )
        progressWindow.show()

        // Run setup on background queue to avoid blocking main thread
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let success = self.performSetup(needsAeroSpaceInstall: needsAeroSpaceInstall)

            DispatchQueue.main.async {
                progressWindow.close()
                completion(success ? .ready : .declined)
            }
        }
    }

    /// Shows the onboarding alert asking user for permission.
    private func showAlert(needsAeroSpaceInstall: Bool) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "ProjectSwitcher requires AeroSpace"

        if needsAeroSpaceInstall {
            alert.informativeText = """
                AeroSpace is a window manager that ProjectSwitcher uses to organize your workspace. \
                ProjectSwitcher will install it via Homebrew and configure it automatically.

                ProjectSwitcher cannot run without AeroSpace installed. \
                If you choose Quit, the app will close.
                """
        } else {
            alert.informativeText = """
                ProjectSwitcher needs to configure AeroSpace to work correctly. \
                Your existing AeroSpace config will be backed up.

                ProjectSwitcher cannot run without a compatible AeroSpace configuration. \
                If you choose Quit, the app will close.
                """
        }

        alert.addButton(withTitle: needsAeroSpaceInstall ? "Install & Continue" : "Configure & Continue")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    /// Performs the actual setup: install AeroSpace and/or write config.
    private func performSetup(needsAeroSpaceInstall: Bool) -> Bool {
        // Install AeroSpace if needed
        if needsAeroSpaceInstall {
            log(event: "onboarding.installing_aerospace")
            switch aerospace.installViaHomebrew() {
            case .failure(let error):
                log(event: "onboarding.install_failed", context: ["error": error.message])
                DispatchQueue.main.sync {
                    showErrorAlert(message: "Failed to install AeroSpace: \(error.message)")
                }
                return false
            case .success:
                log(event: "onboarding.aerospace_installed")
            }
        }

        // Write safe config
        log(event: "onboarding.writing_config")
        switch configManager.writeSafeConfig() {
        case .failure(let error):
            log(event: "onboarding.config_failed", context: ["error": error.message])
            DispatchQueue.main.sync {
                showErrorAlert(message: "Failed to write AeroSpace config: \(error.message)")
            }
            return false
        case .success:
            log(event: "onboarding.config_written")
        }

        // Start AeroSpace
        log(event: "onboarding.starting_aerospace")
        switch aerospace.start() {
        case .failure(let error):
            log(event: "onboarding.start_failed", context: ["error": error.message])
            // Not fatal - AeroSpace might already be running or will start later
        case .success:
            log(event: "onboarding.aerospace_started")
        }

        log(event: "onboarding.completed")
        return true
    }

    /// Shows an error alert when setup fails.
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Setup Failed"
        alert.informativeText = "\(message)\n\nProjectSwitcher will now quit."
        alert.addButton(withTitle: "Quit")
        alert.runModal()
    }

    /// Logs an onboarding event.
    private func log(event: String, context: [String: String]? = nil) {
        _ = logger.log(event: event, level: .info, message: nil, context: context)
    }
}

// MARK: - Progress Window

/// Simple progress window for onboarding with spinner.
private final class OnboardingProgressWindow {
    private let window: NSWindow
    private let progressIndicator: NSProgressIndicator

    init(message: String) {
        let contentRect = NSRect(x: 0, y: 0, width: 400, height: 100)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "ProjectSwitcher Setup"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: contentRect)

        let label = NSTextField(labelWithString: message)
        label.frame = NSRect(x: 20, y: 50, width: 360, height: 30)
        label.alignment = .center
        contentView.addSubview(label)

        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.frame = NSRect(x: 180, y: 10, width: 40, height: 40)
        progressIndicator.startAnimation(nil)
        contentView.addSubview(progressIndicator)

        window.contentView = contentView
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        progressIndicator.stopAnimation(nil)
        window.close()
    }
}
