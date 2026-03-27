import AppKit
import CoreGraphics

import ProjectSwitcherCore

/// Visual constants for the Option-Tab window cycle overlay.
private enum WindowCycleOverlayLayout {
    static let cornerRadius: CGFloat = 24
    static let minPanelWidth: CGFloat = 360
    static let maxPanelWidth: CGFloat = 1080
    static let horizontalPadding: CGFloat = 18
    static let topPadding: CGFloat = 14
    static let bottomPadding: CGFloat = 10
    static let titleTopSpacing: CGFloat = 8
    static let titleHeight: CGFloat = 20
    static let itemSize: CGFloat = 92
    static let panelHeight: CGFloat = topPadding + itemSize + titleTopSpacing + titleHeight + bottomPadding
    static let itemSpacing: CGFloat = 12
    static let preferredItemWidth: CGFloat = itemSize
    static let iconSize: CGFloat = 80
}

/// Presentation-only controller for the Option-Tab cycle overlay panel.
///
/// Renders cycle candidates and highlights the selected candidate.
/// Owns no business logic and performs no AeroSpace operations.
final class WindowCycleOverlayController {
    private var panel: NSPanel?
    private var stackView: NSStackView?
    private var selectedTitleLabel: NSTextField?
    private var itemViews: [WindowCycleOverlayItemView] = []
    private var candidateIds: [Int] = []
    private var candidateTitles: [String] = []

    /// Shows (or updates) the overlay for the provided cycle session.
    /// - Parameter session: Current cycle session snapshot.
    func show(session: WindowCycler.CycleSession) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !session.candidates.isEmpty else {
            hide()
            return
        }

        let panel = ensurePanel()
        rebuildItemsIfNeeded(session: session)
        updateSelection(selectedIndex: session.selectedIndex)
        resizePanel(forCount: session.candidates.count)
        centerPanel(panel, forWindowId: session.initialWindowId)
        panel.orderFrontRegardless()
    }

    /// Dismisses the overlay if visible.
    func hide() {
        dispatchPrecondition(condition: .onQueue(.main))
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: WindowCycleOverlayLayout.minPanelWidth,
                height: WindowCycleOverlayLayout.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false

        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.translatesAutoresizingMaskIntoConstraints = false

        let roundedContainerView = NSView()
        roundedContainerView.wantsLayer = true
        roundedContainerView.layer?.cornerRadius = WindowCycleOverlayLayout.cornerRadius
        roundedContainerView.layer?.masksToBounds = true
        roundedContainerView.layer?.backgroundColor = NSColor.clear.cgColor
        roundedContainerView.translatesAutoresizingMaskIntoConstraints = false

        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        let tintView = NSView()
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        tintView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = WindowCycleOverlayLayout.itemSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let selectedTitleLabel = NSTextField(labelWithString: "")
        selectedTitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        selectedTitleLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        selectedTitleLabel.alignment = .center
        selectedTitleLabel.lineBreakMode = .byTruncatingTail
        selectedTitleLabel.maximumNumberOfLines = 1
        selectedTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        roundedContainerView.addSubview(visualEffectView)
        roundedContainerView.addSubview(tintView)
        roundedContainerView.addSubview(stackView)
        roundedContainerView.addSubview(selectedTitleLabel)
        rootView.addSubview(roundedContainerView)

        NSLayoutConstraint.activate([
            roundedContainerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            roundedContainerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            roundedContainerView.topAnchor.constraint(equalTo: rootView.topAnchor),
            roundedContainerView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            visualEffectView.leadingAnchor.constraint(equalTo: roundedContainerView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: roundedContainerView.trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: roundedContainerView.topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: roundedContainerView.bottomAnchor),

            tintView.leadingAnchor.constraint(equalTo: roundedContainerView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: roundedContainerView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: roundedContainerView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: roundedContainerView.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: roundedContainerView.leadingAnchor, constant: WindowCycleOverlayLayout.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: roundedContainerView.trailingAnchor, constant: -WindowCycleOverlayLayout.horizontalPadding),
            stackView.topAnchor.constraint(equalTo: roundedContainerView.topAnchor, constant: WindowCycleOverlayLayout.topPadding),
            stackView.heightAnchor.constraint(equalToConstant: WindowCycleOverlayLayout.itemSize),

            selectedTitleLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: WindowCycleOverlayLayout.titleTopSpacing),
            selectedTitleLabel.leadingAnchor.constraint(equalTo: roundedContainerView.leadingAnchor, constant: WindowCycleOverlayLayout.horizontalPadding),
            selectedTitleLabel.trailingAnchor.constraint(equalTo: roundedContainerView.trailingAnchor, constant: -WindowCycleOverlayLayout.horizontalPadding),
            selectedTitleLabel.bottomAnchor.constraint(equalTo: roundedContainerView.bottomAnchor, constant: -WindowCycleOverlayLayout.bottomPadding),
            selectedTitleLabel.heightAnchor.constraint(equalToConstant: WindowCycleOverlayLayout.titleHeight)
        ])

        panel.contentView = rootView
        self.panel = panel
        self.stackView = stackView
        self.selectedTitleLabel = selectedTitleLabel
        return panel
    }

    private func rebuildItemsIfNeeded(session: WindowCycler.CycleSession) {
        let ids = session.candidates.map(\.windowId)
        candidateTitles = session.candidates.map(titleText(for:))
        guard ids != candidateIds || itemViews.count != session.candidates.count else {
            return
        }
        candidateIds = ids

        guard let stackView else {
            return
        }
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        itemViews = session.candidates.map { candidate in
            let item = WindowCycleOverlayItemView(icon: icon(forBundleId: candidate.appBundleId))
            stackView.addArrangedSubview(item)
            return item
        }
    }

    private func updateSelection(selectedIndex: Int) {
        for (index, itemView) in itemViews.enumerated() {
            itemView.setSelected(index == selectedIndex)
        }
        if candidateTitles.indices.contains(selectedIndex) {
            selectedTitleLabel?.stringValue = candidateTitles[selectedIndex]
        } else {
            selectedTitleLabel?.stringValue = ""
        }
    }

    private func resizePanel(forCount count: Int) {
        guard let panel else {
            return
        }
        let preferredWidth = (CGFloat(count) * WindowCycleOverlayLayout.preferredItemWidth) +
            (CGFloat(max(0, count - 1)) * WindowCycleOverlayLayout.itemSpacing) +
            (WindowCycleOverlayLayout.horizontalPadding * 2)
        let targetWidth = min(max(preferredWidth, WindowCycleOverlayLayout.minPanelWidth), WindowCycleOverlayLayout.maxPanelWidth)
        panel.setContentSize(NSSize(width: targetWidth, height: WindowCycleOverlayLayout.panelHeight))
    }

    private func centerPanel(_ panel: NSPanel, forWindowId windowId: Int) {
        let targetScreen = screenForWindow(windowId: windowId) ?? fallbackScreen()
        let frame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: frame.midX - (panel.frame.width / 2),
            y: frame.midY - (panel.frame.height / 2)
        )
        panel.setFrameOrigin(origin)
    }

    private func screenForWindow(windowId: Int) -> NSScreen? {
        guard let bounds = windowBounds(windowId: windowId) else {
            return nil
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var displayId = CGDirectDisplayID()
        var matchCount: UInt32 = 0
        let status = CGGetDisplaysWithPoint(center, 1, &displayId, &matchCount)
        guard status == .success, matchCount > 0 else {
            return nil
        }
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayId
        }
    }

    private func windowBounds(windowId: Int) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowId)) as? [[String: Any]],
              let windowInfo = list.first,
              let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return nil
        }
        return bounds
    }

    private func fallbackScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main
    }

    private func titleText(for candidate: WindowCycleCandidate) -> String {
        if let appName = appName(forBundleId: candidate.appBundleId) {
            return appName
        }
        let trimmed = candidate.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if !candidate.appBundleId.isEmpty {
            return candidate.appBundleId
        }
        return "Unknown App"
    }

    private func icon(forBundleId bundleId: String) -> NSImage {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        if let runningIcon = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.icon {
            return runningIcon
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    private func appName(forBundleId bundleId: String) -> String? {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: appURL) {
            let rawName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
                (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            let appName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !appName.isEmpty {
                return appName
            }
        }

        let runningName = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first?
            .localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !runningName.isEmpty {
            return runningName
        }

        return nil
    }
}

/// Visual item for one cycle candidate.
private final class WindowCycleOverlayItemView: NSView {
    private let iconView = NSImageView()
    private var isSelectedState = false

    init(icon: NSImage) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.clear.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor

        let sizedIcon = icon.copy() as! NSImage
        sizedIcon.size = NSSize(width: WindowCycleOverlayLayout.iconSize, height: WindowCycleOverlayLayout.iconSize)
        iconView.image = sizedIcon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: WindowCycleOverlayLayout.itemSize),
            heightAnchor.constraint(equalToConstant: WindowCycleOverlayLayout.itemSize),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: WindowCycleOverlayLayout.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: WindowCycleOverlayLayout.iconSize)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySelectionStyle()
    }

    /// Updates selection styling.
    /// - Parameter isSelected: Whether this item is selected.
    func setSelected(_ isSelected: Bool) {
        isSelectedState = isSelected
        applySelectionStyle()
    }

    /// Applies current selection colors using the view's effective appearance.
    private func applySelectionStyle() {
        guard let layer else {
            return
        }
        if isSelectedState {
            layer.backgroundColor = selectedBackgroundColor().cgColor
            layer.borderColor = selectedBorderColor().cgColor
            return
        }
        layer.backgroundColor = NSColor.clear.cgColor
        layer.borderColor = NSColor.clear.cgColor
    }

    /// Returns a selected background color tuned for light vs dark appearance.
    private func selectedBackgroundColor() -> NSColor {
        if isDarkAppearance {
            return NSColor.white.withAlphaComponent(0.16)
        }
        return NSColor.black.withAlphaComponent(0.20)
    }

    /// Returns a selected border color tuned for light vs dark appearance.
    private func selectedBorderColor() -> NSColor {
        if isDarkAppearance {
            return NSColor.white.withAlphaComponent(0.24)
        }
        return NSColor.black.withAlphaComponent(0.14)
    }

    /// True when effective appearance resolves to dark Aqua.
    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
