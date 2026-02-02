import Foundation
import Cocoa
import Carbon

class HotkeyManager {
    static let shared = HotkeyManager()

    private var hotkeys: [UInt16: (NSEvent.ModifierFlags, () -> Void)] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        hotkeys[keyCode] = (modifiers, action)
        setupEventMonitors()
    }

    func unregister(keyCode: UInt16) {
        hotkeys.removeValue(forKey: keyCode)
    }

    func unregisterAll() {
        hotkeys.removeAll()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Strip .function from flags — macOS always sets it for function keys,
        // so without this, comparing against empty modifiers [] always fails.
        let maskedFlags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.function)

        if let (modifiers, action) = hotkeys[event.keyCode],
           maskedFlags == modifiers {
            action()
        }
    }

    private func setupEventMonitors() {
        guard !hotkeys.isEmpty else { return }

        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }

        // Global monitor: fires when other apps are focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor: fires when this app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }
    }
}
