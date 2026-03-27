import AppKit

/// Controls a simple progress panel shown during "Recover All Projects" operations.
///
/// Displays an indeterminate progress indicator and a status label.
/// On completion, replaces the indicator with a summary message and a Close button.
final class RecoveryProgressController: NSObject, NSWindowDelegate {

    /// Called when the user closes the progress window.
    var onClose: (() -> Void)?

    private var window: NSWindow?
    private var statusLabel: NSTextField?
    private var progressIndicator: NSProgressIndicator?
    private var closeButton: NSButton?

    override init() {
        super.init()
    }

    /// Shows the progress panel centered on screen.
    func show() {
        let win = makeWindow()
        let (label, indicator, button) = makeContentView(in: win)
        statusLabel = label
        progressIndicator = indicator
        closeButton = button
        window = win
        win.delegate = self
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Updates the progress label.
    /// - Parameters:
    ///   - current: Number of windows processed so far.
    ///   - total: Total number of windows to process.
    func updateProgress(current: Int, total: Int) {
        statusLabel?.stringValue = "Recovering projects and windows... (\(current) / \(total))"
    }

    /// Shows the completion state with a summary message and Close button.
    /// - Parameter message: Summary message to display.
    func showCompletion(message: String) {
        statusLabel?.stringValue = message
        progressIndicator?.stopAnimation(nil)
        progressIndicator?.isHidden = true
        closeButton?.isHidden = false
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    // MARK: - UI Construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recovering Projects"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        return window
    }

    private func makeContentView(
        in window: NSWindow
    ) -> (label: NSTextField, indicator: NSProgressIndicator, button: NSButton) {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.alignment = .centerX
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Recovering projects and windows...")
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center

        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.isIndeterminate = true
        indicator.startAnimation(nil)

        let button = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        button.bezelStyle = .rounded
        button.isHidden = true

        container.addArrangedSubview(label)
        container.addArrangedSubview(indicator)
        container.addArrangedSubview(button)

        let contentView = NSView()
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            indicator.widthAnchor.constraint(equalTo: container.widthAnchor)
        ])

        window.contentView = contentView
        return (label, indicator, button)
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
