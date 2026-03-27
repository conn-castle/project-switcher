//
//  SwitcherViews.swift
//  ProjectSwitcher
//
//  Cell factory and display helper functions for the project switcher panel.
//

import AppKit

import ProjectSwitcherCore

// MARK: - Cell Factory Functions

/// Creates or reuses a project cell for display.
/// - Parameters:
///   - project: Project to display.
///   - isActive: Whether this project is the currently active one.
///   - isOpen: Whether this project has an open workspace.
///   - onClose: Callback when the close button is clicked.
///   - tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func projectCell(
    for project: ProjectConfig,
    isActive: Bool,
    isOpen: Bool,
    query: String,
    isSelected: Bool,
    onClose: (() -> Void)?,
    tableView: NSTableView
) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("ProjectRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ProjectRowView {
        configureProjectCell(
            cell,
            project: project,
            isActive: isActive,
            isOpen: isOpen,
            query: query,
            isSelected: isSelected,
            onClose: onClose
        )
        return cell
    }

    let cell = ProjectRowView()
    cell.identifier = identifier
    configureProjectCell(
        cell,
        project: project,
        isActive: isActive,
        isOpen: isOpen,
        query: query,
        isSelected: isSelected,
        onClose: onClose
    )
    return cell
}

/// Configures a project cell with project data.
/// - Parameters:
///   - cell: Cell to configure.
///   - project: Project providing display data.
///   - isActive: Whether this project is the currently active one.
///   - isOpen: Whether this project has an open workspace.
///   - onClose: Callback when the close button is clicked.
func configureProjectCell(
    _ cell: ProjectRowView,
    project: ProjectConfig,
    isActive: Bool,
    isOpen: Bool,
    query: String,
    isSelected: Bool,
    onClose: (() -> Void)?
) {
    cell.nameLabel.attributedStringValue = highlightedProjectName(project.name, query: query)
    cell.swatchView.layer?.backgroundColor = nsColor(from: project.color).cgColor
    cell.setRemote(project.isSSH)
    cell.setCurrent(isActive)
    cell.setCloseEnabled(isOpen)
    cell.setRowSelected(isSelected)
    cell.onClose = onClose
    cell.closeButton.setAccessibilityLabel("Close project \(project.name)")
}

/// Creates or reuses a section header cell.
/// - Parameters:
///   - title: Header text.
///   - tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func sectionHeaderCell(title: String, tableView: NSTableView) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("SectionHeaderRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? SectionHeaderRowView {
        cell.titleLabel.stringValue = title.uppercased()
        return cell
    }

    let cell = SectionHeaderRowView()
    cell.identifier = identifier
    cell.titleLabel.stringValue = title.uppercased()
    return cell
}

/// Creates or reuses the "Back to Non-Project Space" action row cell.
/// - Parameter tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func backActionCell(tableView: NSTableView) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("BackActionRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ActionRowView {
        return cell
    }

    let cell = ActionRowView()
    cell.identifier = identifier
    cell.setAccessibilityLabel("Back to Non-Project Space")
    return cell
}

/// Creates or reuses an empty state cell for display.
/// - Parameters:
///   - message: Message to display.
///   - tableView: Table view for cell reuse.
/// - Returns: Configured table cell view.
func emptyStateCell(message: String, tableView: NSTableView) -> NSTableCellView {
    let identifier = NSUserInterfaceItemIdentifier("EmptyStateRow")
    if let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
        cell.textField?.stringValue = message
        return cell
    }

    let cell = NSTableCellView()
    cell.identifier = identifier
    let label = NSTextField(labelWithString: message)
    label.textColor = .secondaryLabelColor
    label.font = NSFont.systemFont(ofSize: 12)
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    cell.addSubview(label)

    NSLayoutConstraint.activate([
        label.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
    ])

    cell.textField = label
    return cell
}

/// Highlights query matches in the project name.
/// - Parameters:
///   - name: Project display name.
///   - query: Search query.
/// - Returns: Attributed display name with matched ranges emphasized.
func highlightedProjectName(_ name: String, query: String) -> NSAttributedString {
    let attributed = NSMutableAttributedString(
        string: name,
        attributes: [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]
    )

    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
        return attributed
    }

    var searchStart = name.startIndex

    while searchStart < name.endIndex,
          let range = name.range(
              of: trimmedQuery,
              options: [.caseInsensitive, .diacriticInsensitive],
              range: searchStart..<name.endIndex
          ) {
        let nsRange = NSRange(range, in: name)
        attributed.addAttributes(
            [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)],
            range: nsRange
        )
        searchStart = range.upperBound
    }

    return attributed
}

/// Converts a color string to an NSColor using the project palette.
/// - Parameter colorString: Color name or hex value.
/// - Returns: Resolved NSColor, or accent color as fallback.
func nsColor(from colorString: String) -> NSColor {
    guard let rgb = ProjectColorPalette.resolve(colorString) else {
        return .controlAccentColor
    }
    return NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
}
