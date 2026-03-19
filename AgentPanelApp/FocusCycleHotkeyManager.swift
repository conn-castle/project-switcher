import AppKit
import Carbon
import CoreGraphics

import AgentPanelCore

/// Manages global hotkeys for Option-Tab / Option-Shift-Tab window cycling.
///
/// Separate from `HotkeyManager` to isolate risk from the switcher hotkey.
/// Registers two Carbon hotkeys and dispatches to callbacks.
/// Registration is atomic: both hotkeys must succeed or both are rolled back.
final class FocusCycleHotkeyManager: FocusCycleStatusProviding {
    private let logger: AgentPanelLogging
    private var nextHotKeyRef: EventHotKeyRef?
    private var prevHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerUPP: EventHandlerUPP?
    private(set) var registrationStatus: FocusCycleRegistrationStatus?
    private var overlayCycleActive = false
    private var optionModifierDown = false
    private var didLogOverlayMisconfiguration = false
    private var optionReleaseWatchdog: DispatchSourceTimer?

    /// Called when Option-Tab is pressed.
    var onCycleNext: (() -> Void)?
    /// Called when Option-Shift-Tab is pressed.
    var onCyclePrevious: (() -> Void)?
    /// Called on first Option-Tab/Option-Shift-Tab press while Option is held.
    var onCycleOverlayStart: ((CycleDirection) -> Void)?
    /// Called for repeated Option-Tab/Option-Shift-Tab presses while Option is held.
    var onCycleOverlayAdvance: ((CycleDirection) -> Void)?
    /// Called when Option is released during an active overlay cycle.
    var onCycleOverlayCommit: (() -> Void)?

    init(logger: AgentPanelLogging = AgentPanelLogger()) {
        self.logger = logger
    }

    deinit {
        unregisterAll()
    }

    /// Registers Option-Tab and Option-Shift-Tab global hotkeys.
    /// Registration is atomic: if either hotkey fails, both are unregistered.
    func registerHotkeys() {
        unregisterAll()

        let statusHandler = installEventHandler()
        guard statusHandler == noErr else {
            _ = logger.log(
                event: "focus_cycle.handler_failed",
                level: .error,
                message: "Failed to install focus cycle event handler",
                context: ["osStatus": "\(statusHandler)"]
            )
            registrationStatus = .failed(osStatus: statusHandler)
            return
        }

        // Option-Tab → cycle next (ID 10)
        let nextResult = registerSingleHotkey(
            keyCode: UInt32(kVK_Tab),
            modifiers: UInt32(optionKey),
            id: nextHotkeyId,
            label: "Option-Tab"
        )

        // Option-Shift-Tab → cycle previous (ID 11)
        let prevResult = registerSingleHotkey(
            keyCode: UInt32(kVK_Tab),
            modifiers: UInt32(optionKey | shiftKey),
            id: prevHotkeyId,
            label: "Option-Shift-Tab"
        )

        // Atomic: both must succeed
        switch (nextResult.ref, nextResult.status, prevResult.ref, prevResult.status) {
        case (let nextRef?, noErr, let prevRef?, noErr):
            nextHotKeyRef = nextRef
            prevHotKeyRef = prevRef
            registrationStatus = .registered
        default:
            // Roll back any successful registration
            if let ref = nextResult.ref { UnregisterEventHotKey(ref) }
            if let ref = prevResult.ref { UnregisterEventHotKey(ref) }
            if let handler = handlerRef {
                RemoveEventHandler(handler)
                handlerRef = nil
            }
            handlerUPP = nil
            let failedStatus = nextResult.status != noErr ? nextResult.status : prevResult.status
            registrationStatus = .failed(osStatus: failedStatus)
            _ = logger.log(
                event: "focus_cycle.registration_failed",
                level: .error,
                message: "Focus cycle hotkey registration failed (atomic rollback)",
                context: ["nextStatus": "\(nextResult.status)", "prevStatus": "\(prevResult.status)"]
            )
        }
    }

    /// Returns the current focus-cycle registration status for Doctor integration.
    func focusCycleRegistrationStatus() -> FocusCycleRegistrationStatus? {
        registrationStatus
    }

    private func registerSingleHotkey(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32,
        label: String
    ) -> (ref: EventHotKeyRef?, status: OSStatus) {
        let hotKeyId = EventHotKeyID(signature: hotkeySignature, id: id)
        var ref: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr {
            _ = logger.log(
                event: "focus_cycle.registered",
                level: .info,
                message: "\(label) hotkey registered",
                context: ["hotkey": label]
            )
        } else {
            _ = logger.log(
                event: "focus_cycle.registration_failed",
                level: .error,
                message: "\(label) hotkey registration failed",
                context: ["hotkey": label, "osStatus": "\(status)"]
            )
        }

        return (ref, status)
    }

    private func installEventHandler() -> OSStatus {
        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<FocusCycleHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleKeyboardEvent(eventRef)
        }

        handlerUPP = handler

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventRawKeyModifiersChanged)
            )
        ]

        return eventTypes.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(paramErr)
            }
            return InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                buffer.count,
                baseAddress,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &handlerRef
            )
        }
    }

    private func handleKeyboardEvent(_ event: EventRef) -> OSStatus {
        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            return handleHotkeyPressedEvent(event)
        case UInt32(kEventRawKeyModifiersChanged):
            return handleModifiersChangedEvent(event)
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func handleHotkeyPressedEvent(_ event: EventRef) -> OSStatus {
        var eventHotKeyId = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyId
        )

        guard status == noErr, eventHotKeyId.signature == hotkeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        switch eventHotKeyId.id {
        case nextHotkeyId:
            handleCycleKeyPress(direction: .next)
            return noErr
        case prevHotkeyId:
            handleCycleKeyPress(direction: .previous)
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func handleModifiersChangedEvent(_ event: EventRef) -> OSStatus {
        var modifiers: UInt32 = 0
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamKeyModifiers),
            EventParamType(typeUInt32),
            nil,
            MemoryLayout<UInt32>.size,
            nil,
            &modifiers
        )

        guard status == noErr else {
            return OSStatus(eventNotHandledErr)
        }

        let optionMask = UInt32(optionKey | rightOptionKey)
        let isOptionDown = (modifiers & optionMask) != 0
        if optionModifierDown, !isOptionDown {
            handleOptionReleased()
        }
        optionModifierDown = isOptionDown
        return noErr
    }

    private func handleCycleKeyPress(direction: CycleDirection) {
        if overlayCallbacksConfigured {
            optionModifierDown = true
            if overlayCycleActive {
                onCycleOverlayAdvance?(direction)
            } else {
                overlayCycleActive = true
                startOptionReleaseWatchdog()
                onCycleOverlayStart?(direction)
            }
            return
        }

        if hasAnyOverlayCallback, !didLogOverlayMisconfiguration {
            _ = logger.log(
                event: "focus_cycle.overlay_callbacks_misconfigured",
                level: .error,
                message: "Overlay callbacks must be either all set or all unset.",
                context: nil
            )
            didLogOverlayMisconfiguration = true
        }

        switch direction {
        case .next:
            onCycleNext?()
        case .previous:
            onCyclePrevious?()
        }
    }

    private func handleOptionReleased() {
        guard overlayCycleActive else {
            return
        }
        overlayCycleActive = false
        stopOptionReleaseWatchdog()
        onCycleOverlayCommit?()
    }

    private func unregisterAll() {
        if let nextHotKeyRef {
            UnregisterEventHotKey(nextHotKeyRef)
            self.nextHotKeyRef = nil
        }
        if let prevHotKeyRef {
            UnregisterEventHotKey(prevHotKeyRef)
            self.prevHotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        handlerUPP = nil
        overlayCycleActive = false
        optionModifierDown = false
        didLogOverlayMisconfiguration = false
        stopOptionReleaseWatchdog()
    }

    /// Starts a polling watchdog that commits overlay selection if Option-release events are missed.
    ///
    /// Carbon hotkey delivery is reliable for key presses, but modifier-changed events are not
    /// guaranteed across all focus states. The watchdog makes release-to-commit deterministic.
    private func startOptionReleaseWatchdog() {
        stopOptionReleaseWatchdog()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.03, repeating: 0.03)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.overlayCycleActive else {
                return
            }
            if !Self.isOptionModifierDownGlobally {
                self.handleOptionReleased()
            }
        }
        timer.resume()
        optionReleaseWatchdog = timer
    }

    private func stopOptionReleaseWatchdog() {
        optionReleaseWatchdog?.cancel()
        optionReleaseWatchdog = nil
    }

    private static var isOptionModifierDownGlobally: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    private var hotkeySignature: OSType {
        OSType(0x41504346) // "APCF"
    }

    private var overlayCallbacksConfigured: Bool {
        onCycleOverlayStart != nil &&
            onCycleOverlayAdvance != nil &&
            onCycleOverlayCommit != nil
    }

    private var hasAnyOverlayCallback: Bool {
        onCycleOverlayStart != nil ||
            onCycleOverlayAdvance != nil ||
            onCycleOverlayCommit != nil
    }

    private var nextHotkeyId: UInt32 { 10 }
    private var prevHotkeyId: UInt32 { 11 }
}
