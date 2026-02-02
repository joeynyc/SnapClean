import Foundation
import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys: [UInt16: (NSEvent.ModifierFlags, () -> Void)] = [:]
    private var eventMonitor: Any?

    private init() {}

    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        hotkeys[keyCode] = (modifiers, action)
        setupEventMonitor()
    }

    func unregister(keyCode: UInt16) {
        hotkeys.removeValue(forKey: keyCode)
    }

    func unregisterAll() {
        hotkeys.removeAll()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func setupEventMonitor() {
        guard !hotkeys.isEmpty else { return }

        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }

            let maskedFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if let action = self.hotkeys[event.keyCode],
               maskedFlags == action.0 {
                action.1()
            }
        }
    }
}
