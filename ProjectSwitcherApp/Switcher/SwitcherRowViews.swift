//
//  SwitcherRowViews.swift
//  ProjectSwitcher
//
//  Reusable AppKit row views for the project switcher table.
//

import AppKit

/// Custom panel that can control key window behavior.
final class SwitcherPanel: NSPanel {
    var allowsKeyWindow: Bool = true

    override var canBecomeKey: Bool {
        allowsKeyWindow
    }

    override var canBecomeMain: Bool {
        allowsKeyWindow
    }
}

/// Table cell view for section header rows in the results list.
final class SectionHeaderRowView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .tertiaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

/// Table cell view for an action row such as "Back to Non-Project Space".
final class ActionRowView: NSTableCellView {
    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let shortcutLabel = NSTextField(labelWithString: "")
    private let shortcutContainer = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        iconView.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = "Back to Non-Project Space"

        shortcutLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.stringValue = "\u{21E7}\u{21A9}"
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false

        shortcutContainer.translatesAutoresizingMaskIntoConstraints = false
        shortcutContainer.wantsLayer = true
        shortcutContainer.layer?.cornerRadius = 6
        shortcutContainer.layer?.masksToBounds = true
        shortcutContainer.layer?.backgroundColor = NSColor.controlColor.cgColor
        shortcutContainer.layer?.borderWidth = 1
        shortcutContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        shortcutContainer.addSubview(shortcutLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, titleLabel, spacer, shortcutContainer])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            shortcutLabel.leadingAnchor.constraint(equalTo: shortcutContainer.leadingAnchor, constant: 8),
            shortcutLabel.trailingAnchor.constraint(equalTo: shortcutContainer.trailingAnchor, constant: -8),
            shortcutLabel.topAnchor.constraint(equalTo: shortcutContainer.topAnchor, constant: 3),
            shortcutLabel.bottomAnchor.constraint(equalTo: shortcutContainer.bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        shortcutContainer.layer?.backgroundColor = NSColor.controlColor.cgColor
        shortcutContainer.layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

/// Table cell view for displaying a project row with color swatch, current badge, and close button.
final class ProjectRowView: NSTableCellView {
    let swatchView = NSView()
    let remoteIcon = NSImageView()
    let nameLabel = NSTextField(labelWithString: "")
    let currentPillContainer = NSView()
    let currentPillLabel = NSTextField(labelWithString: "Current")
    let closeButton = NSButton(frame: .zero)
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered: Bool = false {
        didSet {
            updateCloseButtonAppearance()
        }
    }
    private var isRowSelected: Bool = false {
        didSet {
            updateCloseButtonAppearance()
        }
    }
    private var canClose: Bool = false {
        didSet {
            updateCloseButtonAppearance()
        }
    }

    /// Called when the close button is clicked.
    var onClose: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 4
        swatchView.translatesAutoresizingMaskIntoConstraints = false

        remoteIcon.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Remote project")
        remoteIcon.contentTintColor = .secondaryLabelColor
        remoteIcon.translatesAutoresizingMaskIntoConstraints = false
        remoteIcon.setContentHuggingPriority(.required, for: .horizontal)
        remoteIcon.isHidden = true

        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.lineBreakMode = .byTruncatingTail

        currentPillContainer.wantsLayer = true
        currentPillContainer.layer?.cornerRadius = 9
        currentPillContainer.layer?.masksToBounds = true
        currentPillContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        currentPillContainer.translatesAutoresizingMaskIntoConstraints = false
        currentPillContainer.isHidden = true

        currentPillLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        currentPillLabel.textColor = .controlAccentColor
        currentPillLabel.translatesAutoresizingMaskIntoConstraints = false
        currentPillContainer.addSubview(currentPillLabel)

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close project")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 8
        closeButton.layer?.masksToBounds = true
        closeButton.setAccessibilityLabel("Close project")
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [swatchView, nameLabel, remoteIcon, spacer, currentPillContainer, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        NSLayoutConstraint.activate([
            swatchView.widthAnchor.constraint(equalToConstant: 10),
            swatchView.heightAnchor.constraint(equalToConstant: 10),
            remoteIcon.widthAnchor.constraint(equalToConstant: 14),
            remoteIcon.heightAnchor.constraint(equalToConstant: 14),
            currentPillLabel.leadingAnchor.constraint(equalTo: currentPillContainer.leadingAnchor, constant: 8),
            currentPillLabel.trailingAnchor.constraint(equalTo: currentPillContainer.trailingAnchor, constant: -8),
            currentPillLabel.topAnchor.constraint(equalTo: currentPillContainer.topAnchor, constant: 2),
            currentPillLabel.bottomAnchor.constraint(equalTo: currentPillContainer.bottomAnchor, constant: -2),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        updateCloseButtonAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        currentPillContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaRef = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    func setRowSelected(_ selected: Bool) {
        isRowSelected = selected
    }

    func setRemote(_ isRemote: Bool) {
        remoteIcon.isHidden = !isRemote
    }

    func setCurrent(_ isCurrent: Bool) {
        currentPillContainer.isHidden = !isCurrent
        updateAccessibilityLabel(isCurrent: isCurrent)
    }

    private func updateAccessibilityLabel(isCurrent: Bool) {
        var label = nameLabel.stringValue
        if !remoteIcon.isHidden { label += ", Remote" }
        if isCurrent { label += ", Current" }
        setAccessibilityLabel(label)
    }

    func setCloseEnabled(_ enabled: Bool) {
        canClose = enabled
        closeButton.isEnabled = enabled
    }

    private func updateCloseButtonAppearance() {
        let emphasized = isHovered || isRowSelected
        let alpha: CGFloat
        if canClose {
            alpha = emphasized ? 0.72 : 0.5
        } else {
            alpha = 0.0
        }

        closeButton.alphaValue = alpha
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.layer?.backgroundColor = NSColor.clear.cgColor
    }

    @objc private func closeButtonPressed() {
        onClose?()
    }
}
