import Foundation

/// Help topics supported by the pswitcher CLI.
public enum PsHelpTopic: Equatable {
    case root
    case doctor
    case showConfig
    case listProjects
    case selectProject
    case closeProject
    case returnToWindow
}

/// Commands supported by the pswitcher CLI.
public enum PsCommand: Equatable {
    case help(PsHelpTopic)
    case version
    case doctor
    case showConfig
    case listProjects(String?)
    case selectProject(String)
    case closeProject(String)
    case returnToWindow
}

/// Parse errors for pswitcher CLI arguments.
public struct PsParseError: Error {
    /// Human-readable error message.
    public let message: String
    /// Usage topic to render after the error.
    public let usageTopic: PsHelpTopic

    public init(message: String, usageTopic: PsHelpTopic) {
        self.message = message
        self.usageTopic = usageTopic
    }
}

/// Parses pswitcher CLI arguments into commands.
public struct PsArgumentParser {
    public init() {}

    /// Parses CLI arguments into a pswitcher command.
    /// - Parameter arguments: Arguments excluding the process name.
    /// - Returns: Parsed command or a parse error.
    public func parse(arguments: [String]) -> Result<PsCommand, PsParseError> {
        guard let first = arguments.first else {
            return .failure(
                PsParseError(message: "missing command", usageTopic: .root)
            )
        }

        if first == "-h" || first == "--help" {
            return .success(.help(.root))
        }

        if first == "-v" || first == "--version" {
            return .success(.version)
        }

        switch first {
        case "doctor":
            return parseNoArgumentCommand(
                command: .doctor,
                helpTopic: .doctor,
                arguments: Array(arguments.dropFirst())
            )
        case "show-config":
            return parseNoArgumentCommand(
                command: .showConfig,
                helpTopic: .showConfig,
                arguments: Array(arguments.dropFirst())
            )
        case "list-projects":
            return parseOptionalArgumentCommand(
                commandBuilder: { .listProjects($0) },
                helpTopic: .listProjects,
                arguments: Array(arguments.dropFirst())
            )
        case "select-project":
            return parseSingleArgumentCommand(
                commandBuilder: { .selectProject($0) },
                helpTopic: .selectProject,
                arguments: Array(arguments.dropFirst())
            )
        case "close-project":
            return parseSingleArgumentCommand(
                commandBuilder: { .closeProject($0) },
                helpTopic: .closeProject,
                arguments: Array(arguments.dropFirst())
            )
        case "return":
            return parseNoArgumentCommand(
                command: .returnToWindow,
                helpTopic: .returnToWindow,
                arguments: Array(arguments.dropFirst())
            )
        default:
            return .failure(
                PsParseError(message: "unknown command: \(first)", usageTopic: .root)
            )
        }
    }

    /// Parses commands that accept no arguments (besides --help).
    private func parseNoArgumentCommand(
        command: PsCommand,
        helpTopic: PsHelpTopic,
        arguments: [String]
    ) -> Result<PsCommand, PsParseError> {
        if arguments.isEmpty {
            return .success(command)
        }

        if arguments.count == 1, let arg = arguments.first, arg == "-h" || arg == "--help" {
            return .success(.help(helpTopic))
        }

        return .failure(
            PsParseError(
                message: "unexpected arguments: \(arguments.joined(separator: " "))",
                usageTopic: helpTopic
            )
        )
    }

    /// Parses commands that require a single argument (besides --help).
    private func parseSingleArgumentCommand(
        commandBuilder: (String) -> PsCommand,
        helpTopic: PsHelpTopic,
        arguments: [String]
    ) -> Result<PsCommand, PsParseError> {
        if arguments.count == 1, let arg = arguments.first {
            if arg == "-h" || arg == "--help" {
                return .success(.help(helpTopic))
            }
            return .success(commandBuilder(arg))
        }

        if arguments.isEmpty {
            return .failure(
                PsParseError(message: "missing argument", usageTopic: helpTopic)
            )
        }

        return .failure(
            PsParseError(
                message: "unexpected arguments: \(arguments.joined(separator: " "))",
                usageTopic: helpTopic
            )
        )
    }

    /// Parses commands that accept an optional argument (besides --help).
    private func parseOptionalArgumentCommand(
        commandBuilder: (String?) -> PsCommand,
        helpTopic: PsHelpTopic,
        arguments: [String]
    ) -> Result<PsCommand, PsParseError> {
        if arguments.isEmpty {
            return .success(commandBuilder(nil))
        }

        if arguments.count == 1, let arg = arguments.first {
            if arg == "-h" || arg == "--help" {
                return .success(.help(helpTopic))
            }
            return .success(commandBuilder(arg))
        }

        return .failure(
            PsParseError(
                message: "unexpected arguments: \(arguments.joined(separator: " "))",
                usageTopic: helpTopic
            )
        )
    }
}
