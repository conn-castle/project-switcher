import AppKit

import ProjectSwitcherAppKit
import ProjectSwitcherCore

/// Controls the Doctor diagnostic window presentation.
final class DoctorWindowController: NSObject, NSWindowDelegate {
    // MARK: - Action Callbacks

    var onRunDoctor: (() -> Void)?
    var onCopyReport: (() -> Void)?
    var onInstallAeroSpace: (() -> Void)?
    var onStartAeroSpace: (() -> Void)?
    var onReloadConfig: (() -> Void)?
    var onRequestAccessibility: (() -> Void)?
    var onClose: (() -> Void)?

    // MARK: - Focus Restoration

    var capturedFocus: CapturedFocus?

    var previousApp: NSRunningApplication?

    // MARK: - UI State

    private var window: NSWindow?
    private var textView: NSTextView?
    private var scrollView: NSScrollView?
    private var loadingContainer: NSStackView?
    private var progressIndicator: NSProgressIndicator?
    private var loadingLabel: NSTextField?
    private var buttons: DoctorButtons?
    private var appearanceObservation: NSKeyValueObservation?
    private(set) var lastReport: DoctorReport?

    // MARK: - Public Interface

    func showLoading(skipActivation: Bool = false) {
        if window == nil {
            setupWindow()
        }

        setLoadingState()

        if !skipActivation {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func showReport(_ report: DoctorReport, skipActivation: Bool = false) {
        if window == nil {
            setupWindow()
        }

        updateUI(with: report)

        if !skipActivation {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func updateUI(with report: DoctorReport) {
        lastReport = report

        loadingContainer?.isHidden = true
        progressIndicator?.stopAnimation(nil)
        scrollView?.isHidden = false

        renderReportText(for: report)
        textView?.scrollToBeginningOfDocument(nil)

        applyReportState(report.actions)
    }

    func close() {
        window?.close()
    }

    // MARK: - Window Setup

    private func setupWindow() {
        let windowInstance = makeWindow()
        let textViewInstance = makeTextView()
        let scrollViewInstance = makeScrollView(documentView: textViewInstance)
        let loadingContainerInstance = makeLoadingContainer()
        let buttonsInstance = makeButtons()
        let contentView = makeContentView(
            scrollView: scrollViewInstance,
            loadingContainer: loadingContainerInstance,
            buttons: buttonsInstance
        )
        windowInstance.contentView = contentView
        windowInstance.isReleasedWhenClosed = false
        windowInstance.delegate = self

        window = windowInstance
        textView = textViewInstance
        scrollView = scrollViewInstance
        loadingContainer = loadingContainerInstance
        buttons = buttonsInstance
        observeAppearanceChanges(windowInstance)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func observeAppearanceChanges(_ window: NSWindow) {
        appearanceObservation = window.observe(\.effectiveAppearance) { [weak self] _, _ in
            guard let self, let report = self.lastReport else { return }
            self.renderReportText(for: report)
        }
    }

    private func renderReportText(for report: DoctorReport) {
        let appearance = window?.effectiveAppearance ?? textView?.effectiveAppearance
        let palette = DoctorReportRenderer.palette(for: appearance)
        scrollView?.drawsBackground = true
        scrollView?.backgroundColor = palette.reportBackgroundColor
        let attributed = DoctorReportRenderer.render(report, appearance: appearance)
        textView?.textStorage?.setAttributedString(attributed)
    }

    // MARK: - State Management

    private func setLoadingState() {
        scrollView?.isHidden = true
        loadingContainer?.isHidden = false
        progressIndicator?.startAnimation(nil)

        guard let buttons else { return }
        buttons.runDoctor.isEnabled = false
        buttons.copyReport.isEnabled = false
        buttons.installAeroSpace.isHidden = true
        buttons.startAeroSpace.isHidden = true
        buttons.reloadConfig.isHidden = true
        buttons.requestAccessibility.isHidden = true
    }

    /// Applies button visibility/enabled state based on report action availability.
    private func applyReportState(_ actions: DoctorActionAvailability) {
        guard let buttons else { return }
        buttons.runDoctor.isEnabled = true
        buttons.copyReport.isEnabled = true

        buttons.installAeroSpace.isHidden = !actions.canInstallAeroSpace
        buttons.startAeroSpace.isHidden = !actions.canStartAeroSpace
        buttons.reloadConfig.isHidden = !actions.canReloadAeroSpaceConfig
        buttons.requestAccessibility.isHidden = !actions.canRequestAccessibility
    }

    // MARK: - Window Construction

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ProjectSwitcher Doctor"
        window.minSize = NSSize(width: 520, height: 400)
        window.center()
        return window
    }

    private func makeContentView(
        scrollView: NSScrollView,
        loadingContainer: NSStackView,
        buttons: DoctorButtons
    ) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let reportArea = NSView()
        reportArea.translatesAutoresizingMaskIntoConstraints = false
        reportArea.addSubview(scrollView)
        reportArea.addSubview(loadingContainer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: reportArea.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: reportArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: reportArea.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: reportArea.bottomAnchor),

            loadingContainer.centerXAnchor.constraint(equalTo: reportArea.centerXAnchor),
            loadingContainer.centerYAnchor.constraint(equalTo: reportArea.centerYAnchor),
        ])

        reportArea.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        reportArea.setContentHuggingPriority(.defaultLow, for: .vertical)

        let buttonBar = makeButtonBar(buttons: buttons)

        container.addArrangedSubview(reportArea)
        container.addArrangedSubview(buttonBar)

        let contentView = NSView()
        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        return contentView
    }

    private func makeScrollView(documentView: NSTextView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = DoctorReportRenderer.palette(for: nil).reportBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        return scrollView
    }

    private func makeLoadingContainer() -> NSStackView {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.isIndeterminate = true
        spinner.controlSize = .regular
        spinner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 32),
            spinner.heightAnchor.constraint(equalToConstant: 32),
        ])
        progressIndicator = spinner

        let label = NSTextField(labelWithString: "Running diagnostics...")
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        loadingLabel = label

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true

        return stack
    }

    // MARK: - Button Bar

    private func makeButtonBar(buttons: DoctorButtons) -> NSStackView {
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 8
        bar.distribution = .gravityAreas

        bar.addView(buttons.runDoctor, in: .leading)
        bar.addView(buttons.copyReport, in: .leading)

        bar.addView(buttons.installAeroSpace, in: .center)
        bar.addView(buttons.startAeroSpace, in: .center)
        bar.addView(buttons.reloadConfig, in: .center)
        bar.addView(buttons.requestAccessibility, in: .center)

        bar.addView(buttons.close, in: .trailing)

        return bar
    }

    private func makeButtons() -> DoctorButtons {
        let runDoctorButton = makeButton(title: "Run Doctor", action: #selector(handleRunDoctor))
        runDoctorButton.keyEquivalent = "\r"

        let copyReportButton = makeButton(title: "Copy Report", action: #selector(handleCopyReport))
        let installAeroSpaceButton = makeButton(title: "Install AeroSpace", action: #selector(handleInstallAeroSpace))
        let startAeroSpaceButton = makeButton(title: "Start AeroSpace", action: #selector(handleStartAeroSpace))
        let reloadConfigButton = makeButton(title: "Reload Config", action: #selector(handleReloadConfig))
        let requestAccessibilityButton = makeButton(title: "Request Accessibility", action: #selector(handleRequestAccessibility))
        let closeButton = makeButton(title: "Close", action: #selector(handleClose))

        installAeroSpaceButton.isHidden = true
        startAeroSpaceButton.isHidden = true
        reloadConfigButton.isHidden = true
        requestAccessibilityButton.isHidden = true

        return DoctorButtons(
            runDoctor: runDoctorButton,
            copyReport: copyReportButton,
            installAeroSpace: installAeroSpaceButton,
            startAeroSpace: startAeroSpaceButton,
            reloadConfig: reloadConfigButton,
            requestAccessibility: requestAccessibilityButton,
            close: closeButton
        )
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    // MARK: - Text View

    private func makeTextView() -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = DoctorReportRenderer.palette(for: nil).primaryTextColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        return textView
    }

    // MARK: - Button Actions

    @objc private func handleRunDoctor() {
        onRunDoctor?()
    }

    @objc private func handleCopyReport() {
        onCopyReport?()
    }

    @objc private func handleInstallAeroSpace() {
        onInstallAeroSpace?()
    }

    @objc private func handleStartAeroSpace() {
        onStartAeroSpace?()
    }

    @objc private func handleReloadConfig() {
        onReloadConfig?()
    }

    @objc private func handleRequestAccessibility() {
        onRequestAccessibility?()
    }

    @objc private func handleClose() {
        window?.close()
    }
}

// MARK: - Supporting Types

/// Holds references to Doctor window buttons for state management.
struct DoctorButtons {
    let runDoctor: NSButton
    let copyReport: NSButton
    let installAeroSpace: NSButton
    let startAeroSpace: NSButton
    let reloadConfig: NSButton
    let requestAccessibility: NSButton
    let close: NSButton
}
