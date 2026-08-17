import CoreGraphics

/// A dedicated virtual key used only by the VoiceInk Touch Bar button.
/// VoiceInk accepts bare function keys, and F19 is absent from the built-in
/// keyboard on Touch Bar MacBooks, so it behaves as an independent key.
enum VoiceInkShortcutEmitter {
    static let keyCode: CGKeyCode = 80 // kVK_F19

    static func tap() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = []
        keyUp.flags = []
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
