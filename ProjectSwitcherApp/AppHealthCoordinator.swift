import Foundation

import ProjectSwitcherCore

/// Coordinates background Doctor health checks and Doctor action orchestration.
///
/// Owns debouncing state, the in-flight flag, and pending critical context so that
/// AppDelegate only needs to call `refreshHealthInBackground(trigger:force:errorContext:)`
/// without duplicating health-refresh mutable state.
final class AppHealthCoordinator {
    /// Whether a background Doctor refresh is currently running.
    private(set) var isHealthRefreshInFlight: Bool = false

    /// Critical error context queued while a refresh was already in flight.
    private var pendingCriticalContext: ErrorContext?

    /// Timestamp of the most recent completed Doctor refresh.
    private(set) var lastHealthRefreshAt: Date?

    /// Minimum interval between background Doctor refreshes to avoid spamming CLI calls.
    private let refreshDebounceSeconds: TimeInterval

    private let logger: ProjectSwitcherLogging

    // MARK: - UI effect closures (provided by owner)

    /// Updates the menu bar icon based on Doctor severity.
    private let updateMenuBarHealthIndicator: (DoctorSeverity?) -> Void

    /// Shows a Doctor report in the Doctor window.
    /// Parameters: (report, skipActivation).
    private let showDoctorReport: (DoctorReport, Bool) -> Void

    /// Refreshes cached workspace/focus state for non-blocking menu updates.
    private let refreshMenuStateInBackground: () -> Void

    /// Creates a Doctor instance. Called on the background thread.
    private let makeDoctor: () -> Doctor

    /// The current `doctorIndicatorSeverity` from the owner, used for logging context.
    private let currentIndicatorSeverity: () -> DoctorSeverity?

    /// Returns whether Doctor auto-show should skip app activation for a given trigger.
    /// Used to suppress activation when an accessibility prompt is already displayed.
    private let shouldSkipAutoShowActivation: (String) -> Bool

    /// - Parameters:
    ///   - logger: Logger for structured event logging.
    ///   - refreshDebounceSeconds: Minimum interval between background refreshes.
    ///   - makeDoctor: Factory closure that creates a Doctor instance (called on background threads).
    ///   - currentIndicatorSeverity: Returns the current menu bar indicator severity for logging.
    ///   - updateMenuBarHealthIndicator: Closure invoked on the main thread to update the menu bar icon.
    ///   - showDoctorReport: Closure invoked on the main thread to present a Doctor report. Parameters: (report, skipActivation).
    ///   - refreshMenuStateInBackground: Closure invoked on the main thread to refresh workspace state.
    ///   - shouldSkipAutoShowActivation: Returns true when Doctor auto-show should skip app activation for the given trigger.
    init(
        logger: ProjectSwitcherLogging,
        refreshDebounceSeconds: TimeInterval,
        makeDoctor: @escaping () -> Doctor,
        currentIndicatorSeverity: @escaping () -> DoctorSeverity?,
        updateMenuBarHealthIndicator: @escaping (DoctorSeverity?) -> Void,
        showDoctorReport: @escaping (DoctorReport, Bool) -> Void,
        refreshMenuStateInBackground: @escaping () -> Void,
        shouldSkipAutoShowActivation: @escaping (String) -> Bool = { _ in false }
    ) {
        self.logger = logger
        self.refreshDebounceSeconds = refreshDebounceSeconds
        self.makeDoctor = makeDoctor
        self.currentIndicatorSeverity = currentIndicatorSeverity
        self.updateMenuBarHealthIndicator = updateMenuBarHealthIndicator
        self.showDoctorReport = showDoctorReport
        self.refreshMenuStateInBackground = refreshMenuStateInBackground
        self.shouldSkipAutoShowActivation = shouldSkipAutoShowActivation
    }

    // MARK: - Background health refresh

    /// Runs Doctor in the background and updates the menu bar health indicator.
    ///
    /// Debounced: skips the run if a refresh is already in flight or if the last
    /// refresh completed less than `refreshDebounceSeconds` ago.
    /// Pass `force: true` to bypass debouncing (used for startup).
    /// Critical errors (from `errorContext.isCritical`) skip debounce automatically.
    ///
    /// - Parameters:
    ///   - trigger: Log event name suffix describing what triggered the refresh.
    ///   - force: When true, bypasses the debounce window (e.g., for startup).
    ///   - errorContext: Optional error context that triggered this refresh.
    func refreshHealthInBackground(
        trigger: String,
        force: Bool = false,
        errorContext: ErrorContext? = nil
    ) {
        requireMainThread(function: #function)
        let skipDebounce = force || (errorContext?.isCritical == true)

        guard !isHealthRefreshInFlight else {
            // Store critical context so it's not dropped when in-flight
            if let errorContext, errorContext.isCritical {
                pendingCriticalContext = errorContext
            }
            logAppEvent(
                event: "doctor.refresh.skipped",
                context: ["trigger": trigger, "reason": "in_flight"]
            )
            return
        }

        if !skipDebounce, let lastRefresh = lastHealthRefreshAt,
           Date().timeIntervalSince(lastRefresh) < refreshDebounceSeconds {
            logAppEvent(
                event: "doctor.refresh.skipped",
                context: ["trigger": trigger, "reason": "debounced"]
            )
            return
        }

        isHealthRefreshInFlight = true
        logAppEvent(event: "doctor.refresh.requested", context: ["trigger": trigger])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = self.makeDoctor().run(context: errorContext)
            DispatchQueue.main.async {
                self.isHealthRefreshInFlight = false
                self.lastHealthRefreshAt = Date()
                self.updateMenuBarHealthIndicator(report.overallSeverity)
                self.logDoctorSummary(report, event: "doctor.refresh.completed")

                // Auto-show Doctor window for critical errors with FAIL findings
                if let ctx = errorContext, ctx.isCritical, report.hasFailures {
                    self.logAppEvent(
                        event: "doctor.auto_show",
                        context: ["trigger": ctx.trigger, "category": ctx.category.rawValue]
                    )
                    let skipActivation = self.shouldSkipAutoShowActivation(trigger)
                    self.showDoctorReport(report, skipActivation)
                }

                // Refresh cached workspace/focus state for non-blocking menu updates
                self.refreshMenuStateInBackground()

                // If a critical error was queued while in-flight, trigger a new refresh
                if let pending = self.pendingCriticalContext {
                    self.pendingCriticalContext = nil
                    self.refreshHealthInBackground(
                        trigger: pending.trigger,
                        errorContext: pending
                    )
                }
            }
        }
    }

    // MARK: - Doctor action orchestration

    /// Runs a Doctor action on a background thread and presents the resulting report.
    /// - Parameters:
    ///   - action: The Doctor method to call (receives a Doctor instance).
    ///   - requestedEvent: Event name to log before the action.
    ///   - completedEvent: Event name to log after the action.
    ///   - showLoading: Closure called on main thread to show loading state before dispatching.
    func runDoctorAction(
        _ action: @escaping (Doctor) -> DoctorReport,
        requestedEvent: String,
        completedEvent: String,
        showLoading: (() -> Void)? = nil
    ) {
        requireMainThread(function: #function)
        logAppEvent(event: requestedEvent)
        // Show loading state immediately — the action + re-run can take 20-30s.
        showLoading?()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let report = action(self.makeDoctor())
            DispatchQueue.main.async {
                self.updateMenuBarHealthIndicator(report.overallSeverity)
                self.showDoctorReport(report, false)
                self.logDoctorSummary(report, event: completedEvent)
            }
        }
    }

    // MARK: - Doctor summary logging

    /// Logs a comprehensive summary for Doctor reports to aid remote diagnostics.
    /// Includes finding titles, timing breakdown, and the full rendered report text.
    /// - Parameters:
    ///   - report: Doctor report to summarize.
    ///   - event: Event name to log.
    func logDoctorSummary(_ report: DoctorReport, event: String) {
        requireMainThread(function: #function)
        let passCount = report.findings.filter { $0.severity == .pass }.count
        let warnCount = report.findings.filter { $0.severity == .warn }.count
        let failCount = report.findings.filter { $0.severity == .fail }.count

        let level: LogLevel = {
            switch report.overallSeverity {
            case .fail:
                return .error
            case .warn:
                return .warn
            case .pass:
                return .info
            }
        }()

        var context: [String: String] = [
            "pass_count": "\(passCount)",
            "warn_count": "\(warnCount)",
            "fail_count": "\(failCount)"
        ]
        context["overall_severity"] = report.overallSeverity.rawValue
        if let indicatorSeverity = currentIndicatorSeverity() {
            context["menu_bar_severity"] = indicatorSeverity.rawValue
        } else {
            context["menu_bar_severity"] = "PENDING"
        }

        // Include FAIL and WARN finding titles for remote diagnostics
        let failTitles = report.findings
            .filter { $0.severity == .fail && !$0.title.isEmpty }
            .map { $0.title }
        let warnTitles = report.findings
            .filter { $0.severity == .warn && !$0.title.isEmpty }
            .map { $0.title }
        if !failTitles.isEmpty {
            context["fail_findings"] = failTitles.joined(separator: "; ")
        }
        if !warnTitles.isEmpty {
            context["warn_findings"] = warnTitles.joined(separator: "; ")
        }

        // Include timing breakdown for performance diagnostics
        context["duration_ms"] = "\(report.metadata.durationMs)"
        let sortedSections = report.metadata.sectionTimings.sorted { $0.key < $1.key }
        for (section, ms) in sortedSections {
            context["timing_\(section)_ms"] = "\(ms)"
        }

        // Include the full rendered report text so remote debugging never lacks detail
        context["rendered_report"] = report.rendered()

        logAppEvent(
            event: event,
            level: level,
            context: context
        )
    }

    // MARK: - Private

    /// Writes a structured log entry for app-level events.
    private func logAppEvent(
        event: String,
        level: LogLevel = .info,
        message: String? = nil,
        context: [String: String]? = nil
    ) {
        _ = logger.log(event: event, level: level, message: message, context: context)
    }

    /// Enforces the coordinator's thread-confinement contract.
    ///
    /// Mutable coordinator state is main-thread confined. Callers must invoke
    /// public methods on the main thread.
    private func requireMainThread(function: StaticString) {
        precondition(Thread.isMainThread, "\(function) must be called on the main thread.")
    }
}
