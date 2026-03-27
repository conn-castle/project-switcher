import AppKit

import ProjectSwitcherCore

extension SwitcherPanelController {
    // MARK: - Private Configuration

    /// Configures the switcher panel presentation behavior.
    func configurePanel() {
        panel.title = "Project Switcher"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
    }

    /// Configures the optional title label shown above the search field.
    func configureTitleLabel() {
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Configures the search field appearance and delegate wiring.
    func configureSearchField() {
        searchField.placeholderString = "Search projects…"
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
    }

    /// Configures the table view used for grouped rows.
    func configureTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ProjectColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(handleTableViewAction(_:))
        tableView.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Configures the status label used for warnings and errors.
    func configureStatusLabel() {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Configures the keybind hints footer label.
    func configureKeybindHints() {
        keybindHintLabel.textColor = .secondaryLabelColor
        keybindHintLabel.font = NSFont.systemFont(ofSize: 11)
        keybindHintLabel.alignment = .left
        keybindHintLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Lays out the panel content using Auto Layout.
    func layoutContent() {
        guard let contentView = panel.contentView else {
            return
        }

        let vfxView = NSVisualEffectView()
        vfxView.material = .contentBackground
        vfxView.blendingMode = .withinWindow
        vfxView.state = .active
        vfxView.wantsLayer = true
        vfxView.layer?.cornerRadius = 20
        vfxView.layer?.masksToBounds = true
        vfxView.layer?.backgroundColor =
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        vfxView.layer?.borderWidth = 1
        vfxView.layer?.borderColor =
            NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        vfxView.translatesAutoresizingMaskIntoConstraints = false
        self.visualEffectView = vfxView

        contentView.addSubview(vfxView)
        NSLayoutConstraint.activate([
            vfxView.topAnchor.constraint(equalTo: contentView.topAnchor),
            vfxView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            vfxView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            vfxView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let statusStack = NSStackView(views: [statusLabel])
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, searchField, scrollView, statusStack, keybindHintLabel])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        vfxView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: vfxView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: vfxView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: vfxView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: vfxView.bottomAnchor, constant: -16)
        ])
    }

}
