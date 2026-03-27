//
//  SwitcherSession.swift
//  ProjectSwitcher
//
//  Session management and logging for the project switcher.
//  Tracks switcher sessions with unique IDs for log correlation,
//  and provides structured logging for all switcher events.
//

import Foundation

import ProjectSwitcherCore

/// Manages switcher session lifecycle and structured logging.
///
/// Provides log correlation via session IDs and encapsulates all
/// logging operations for the switcher panel.
final class SwitcherSession {
    private let logger: ProjectSwitcherLogging
    private(set) var sessionId: String?
    private(set) var origin: SwitcherPresentationSource = .unknown

    /// Creates a session manager with the given logger.
    /// - Parameter logger: Logger for writing structured events.
    init(logger: ProjectSwitcherLogging) {
        self.logger = logger
    }

    /// Starts a new switcher session for log correlation.
    /// - Parameter origin: Source of the presentation request.
    func begin(origin: SwitcherPresentationSource) {
        sessionId = UUID().uuidString
        self.origin = origin
        logEvent(
            event: "switcher.session.start",
            context: ["source": origin.rawValue]
        )
    }

    /// Ends the current switcher session and records the reason.
    /// - Parameter reason: Reason for session dismissal.
    func end(reason: SwitcherDismissReason) {
        guard sessionId != nil else {
            return
        }

        logEvent(
            event: "switcher.session.end",
            context: ["reason": reason.rawValue]
        )
        sessionId = nil
        origin = .unknown
    }

    /// Writes a structured log entry with switcher session context.
    /// - Parameters:
    ///   - event: Event name to log.
    ///   - level: Severity level.
    ///   - message: Optional message for the log entry.
    ///   - context: Optional structured context.
    func logEvent(
        event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        var mergedContext = context ?? [:]
        if mergedContext["session_id"] == nil, let sessionId {
            mergedContext["session_id"] = sessionId
        }
        if mergedContext["source"] == nil, origin != .unknown {
            mergedContext["source"] = origin.rawValue
        }

        let contextValue = mergedContext.isEmpty ? nil : mergedContext
        _ = logger.log(event: event, level: level, message: message, context: contextValue)
    }

    /// Records a show request for diagnostic tracing.
    /// - Parameter origin: Source of the presentation request.
    func logShowRequested(origin: SwitcherPresentationSource) {
        logEvent(
            event: "switcher.show.requested",
            context: ["source": origin.rawValue]
        )
    }

    /// Logs successful config load summaries.
    /// - Parameter projectCount: Number of projects loaded.
    func logConfigLoaded(projectCount: Int) {
        let configPath = DataPaths.default().configFile.path
        logEvent(
            event: "switcher.config.loaded",
            context: [
                "project_count": "\(projectCount)",
                "config_path": configPath
            ]
        )
    }
}
