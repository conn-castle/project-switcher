import AppKit
import Carbon

import ProjectSwitcherCore

/// Manages global hotkey registration for the switcher.
final class HotkeyManager: HotkeyStatusProviding {
    private let logger: ProjectSwitcherLogging
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handlerUPP: EventHandlerUPP?
    private(set) var registrationStatus: HotkeyRegistrationStatus? {
        didSet {
            onStatusChange?(registrationStatus)
        }
    }

    /// Called when the hotkey is triggered.
    var onHotkey: (() -> Void)?

    /// Called whenever the registration status changes.
    var onStatusChange: ((HotkeyRegistrationStatus?) -> Void)?

    /// Creates a hotkey manager.
    /// - Parameter logger: Logger used to record registration failures.
    init(logger: ProjectSwitcherLogging = ProjectSwitcherLogger()) {
        self.logger = logger
    }

    deinit {
        unregisterHotkey()
    }

    /// Registers the Cmd+Shift+Space global hotkey.
    func registerHotkey() {
        unregisterHotkey()

        let statusHandler = installEventHandler()
        guard statusHandler == noErr else {
            recordFailure(osStatus: statusHandler)
            return
        }

        let signature = hotkeySignature
        let hotKeyId = EventHotKeyID(signature: signature, id: hotkeyId)
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_Space)
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
            hotKeyRef = ref
            registrationStatus = .registered
            _ = logger.log(
                event: "hotkey.registered",
                level: .info,
                message: "Cmd+Shift+Space hotkey registered",
                context: ["hotkey": "Cmd+Shift+Space"]
            )
        } else {
            recordFailure(osStatus: status)
            unregisterHotkey()
        }
    }

    /// Returns the last known registration status for Doctor integration.
    func hotkeyRegistrationStatus() -> HotkeyRegistrationStatus? {
        registrationStatus
    }

    private func installEventHandler() -> OSStatus {
        let handler: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else {
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkeyEvent(eventRef)
        }

        handlerUPP = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        return InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )
    }

    private func handleHotkeyEvent(_ event: EventRef) -> OSStatus {
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

        guard status == noErr else {
            return OSStatus(eventNotHandledErr)
        }

        guard eventHotKeyId.signature == hotkeySignature, eventHotKeyId.id == hotkeyId else {
            return OSStatus(eventNotHandledErr)
        }

        _ = logger.log(
            event: "hotkey.pressed",
            level: .info,
            message: nil,
            context: ["hotkey": "Cmd+Shift+Space"]
        )
        DispatchQueue.main.async { [weak self] in
            self?.onHotkey?()
        }
        return noErr
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }

        handlerUPP = nil
    }

    private func recordFailure(osStatus: OSStatus) {
        registrationStatus = .failed(osStatus: osStatus)
        _ = logger.log(
            event: "hotkey.registration_failed",
            level: .error,
            message: "Cmd+Shift+Space hotkey registration failed",
            context: ["osStatus": "\(osStatus)"]
        )
    }

    private var hotkeySignature: OSType {
        OSType(0x41504354) // "APCT"
    }

    private var hotkeyId: UInt32 {
        1
    }
}
