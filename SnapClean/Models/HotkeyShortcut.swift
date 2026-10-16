import AppKit
import Carbon

/// A user-configurable global keyboard shortcut.
struct HotkeyShortcut: Codable, Equatable {
    let keyCode: UInt16
    private let modifierFlagsRawValue: UInt
    /// The key's label as shown to the user, e.g. "F1" or "4".
    let key: String

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifiers.intersection(Self.supportedModifiers).rawValue
        self.key = key
    }

    /// Builds a shortcut from a key press, or returns nil if it can't be used as a global hotkey.
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.supportedModifiers)
        let keyCode = event.keyCode
        let isFunctionKey = Self.functionKeyNames[Int(keyCode)] != nil
        // Without ⌘, ⌃ or ⌥ the shortcut would swallow ordinary typing; F-keys are the exception.
        guard isFunctionKey || !modifiers.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }
        guard let key = Self.keyName(for: event) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, key: key)
    }

    var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + key
    }

    static func defaultShortcut(for mode: CaptureMode) -> HotkeyShortcut {
        switch mode {
        case .region:
            HotkeyShortcut(keyCode: UInt16(kVK_F1), modifiers: [.command, .shift], key: "F1")
        case .window:
            HotkeyShortcut(keyCode: UInt16(kVK_F2), modifiers: [.command, .shift], key: "F2")
        case .screen:
            HotkeyShortcut(keyCode: UInt16(kVK_F3), modifiers: [.command, .shift], key: "F3")
        }
    }

    private static let supportedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    private static let functionKeyNames: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]

    private static func keyName(for event: NSEvent) -> String? {
        let keyCode = Int(event.keyCode)
        if let name = functionKeyNames[keyCode] ?? specialKeyNames[keyCode] {
            return name
        }
        // Use the unshifted character so ⇧1 shows as "1", not "!".
        guard let characters = event.characters(byApplyingModifiers: []),
              let character = characters.first,
              !character.isWhitespace,
              !(character.unicodeScalars.first.map { CharacterSet.controlCharacters.contains($0) } ?? true) else {
            return nil
        }
        return String(character).uppercased()
    }
}
