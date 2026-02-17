import Foundation
import AppKit
import Carbon
import os

private let hotkeyLogger = Logger(subsystem: "com.snapclean.app", category: "hotkeys")

class HotkeyManager: HotkeyRegistering {
    static let shared = HotkeyManager()

    private struct HotkeySignature: Hashable {
        let keyCode: UInt16
        let modifiers: UInt32
    }

    private let eventSignature: OSType = 0x53434E50 // SCNP
    private var eventHandlerRef: EventHandlerRef?
    private var nextHotkeyID: UInt32 = 1
    private var hotkeyActions: [UInt32: () -> Void] = [:]
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var signatureToHotkeyID: [HotkeySignature: UInt32] = [:]
    // Lock for thread-safe dictionary access from Carbon event handler callback
    private let hotkeyAccessLock = NSLock()

    private init() {}

    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        let carbonModifiers = toCarbonModifiers(modifiers)
        let signature = HotkeySignature(keyCode: keyCode, modifiers: carbonModifiers)

        hotkeyAccessLock.lock()
        defer { hotkeyAccessLock.unlock() }

        if let existingID = signatureToHotkeyID[signature] {
            unregister(hotkeyID: existingID)
        }

        installEventHandlerIfNeeded()

        let hotkeyID = nextHotkeyID
        nextHotkeyID &+= 1

        let carbonHotkeyID = EventHotKeyID(signature: eventSignature, id: hotkeyID)
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            carbonHotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            hotkeyLogger.error("Failed to register hotkey keyCode=\(keyCode) modifiers=\(carbonModifiers) status=\(status)")
            return
        }

        hotkeyActions[hotkeyID] = action
        hotkeyRefs[hotkeyID] = hotkeyRef
        signatureToHotkeyID[signature] = hotkeyID
    }

    func unregister(keyCode: UInt16) {
        hotkeyAccessLock.lock()
        let matching = signatureToHotkeyID.filter { $0.key.keyCode == keyCode }.map(\.value)
        hotkeyAccessLock.unlock()

        for hotkeyID in matching {
            unregister(hotkeyID: hotkeyID)
        }
    }

    func unregisterAll() {
        hotkeyAccessLock.lock()
        let idsToUnregister = Array(hotkeyActions.keys)
        hotkeyAccessLock.unlock()

        for hotkeyID in idsToUnregister {
            unregister(hotkeyID: hotkeyID)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventTypeSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotkeyEvent(eventRef)
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventTypeSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func handleHotkeyEvent(_ eventRef: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        guard status == noErr else { return status }

        hotkeyAccessLock.lock()
        let action = hotkeyActions[hotkeyID.id]
        hotkeyAccessLock.unlock()

        if let action {
            // Execute action outside the lock to avoid potential deadlock
            action()
            return noErr
        }
        return OSStatus(eventNotHandledErr)
    }

    private func unregister(hotkeyID: UInt32) {
        hotkeyAccessLock.lock()
        defer { hotkeyAccessLock.unlock() }

        guard let hotkeyRef = hotkeyRefs[hotkeyID] else { return }
        UnregisterEventHotKey(hotkeyRef)
        hotkeyRefs.removeValue(forKey: hotkeyID)
        hotkeyActions.removeValue(forKey: hotkeyID)
        signatureToHotkeyID = signatureToHotkeyID.filter { $0.value != hotkeyID }

        if hotkeyActions.isEmpty, let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func toCarbonModifiers(_ modifiers: NSEvent.ModifierFlags) -> UInt32 {
        let masked = modifiers.intersection(.deviceIndependentFlagsMask).subtracting(.function)
        var carbonModifiers: UInt32 = 0

        if masked.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if masked.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if masked.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if masked.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        return carbonModifiers
    }

    deinit {
        for hotkeyRef in hotkeyRefs.values {
            UnregisterEventHotKey(hotkeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
