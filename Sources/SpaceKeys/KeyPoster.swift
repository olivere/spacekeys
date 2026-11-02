import CoreGraphics
import SpaceKeysCore

/// Turns button presses into keyboard events.
///
/// Every key or modifier sent on button down is remembered and released on
/// that button's up, even if the frontmost app or the config changed in
/// between, so nothing stays stuck.
@MainActor
final class KeyPoster {
    private struct Sent {
        let keyCode: UInt16
        let modifiers: Modifiers
        let heldModifier: Modifiers?
    }

    private let source: CGEventSource
    private var held: Modifiers = []
    private var sent: [DeviceButton: Sent] = [:]

    init() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            fatalError("cannot create a CGEventSource")
        }
        self.source = source
    }

    func press(_ button: DeviceButton, action: Action) throws {
        if sent[button] != nil { release(button) }
        switch action {
        case .modifier(let modifier):
            held.formUnion(modifier)
            for single in Modifiers.all where modifier.contains(single) {
                post(flagsChangedFor: single)
            }
            sent[button] = Sent(keyCode: 0, modifiers: [], heldModifier: modifier)
        case .shortcut(let modifiers, let key):
            let keyCode = try KeyboardLayout.keyCode(for: key)
            post(keyCode: keyCode, down: true, modifiers: modifiers.union(held))
            sent[button] = Sent(keyCode: keyCode, modifiers: modifiers, heldModifier: nil)
        }
    }

    func release(_ button: DeviceButton) {
        guard let entry = sent.removeValue(forKey: button) else { return }
        if let modifier = entry.heldModifier {
            // Another button may hold the same modifier; keep it down then.
            let stillHeld = sent.values.reduce(into: Modifiers()) { $0.formUnion($1.heldModifier ?? []) }
            held = stillHeld
            for single in Modifiers.all where modifier.contains(single) && !stillHeld.contains(single) {
                post(flagsChangedFor: single)
            }
        } else {
            post(keyCode: entry.keyCode, down: false, modifiers: entry.modifiers.union(held))
        }
    }

    func releaseAll() {
        // Release shortcuts before modifiers so no key-up arrives without them.
        let order = sent.sorted { ($0.value.heldModifier == nil) && ($1.value.heldModifier != nil) }
        for (button, _) in order { release(button) }
    }

    private func post(keyCode: UInt16, down: Bool, modifiers: Modifiers) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags(modifiers)
        event.post(tap: .cghidEventTap)
    }

    /// Posts the modifier key itself with the current `held` set, which tells
    /// the system whether it went down or up.
    private func post(flagsChangedFor modifier: Modifiers) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCode(modifier), keyDown: held.contains(modifier)) else { return }
        event.type = .flagsChanged
        event.flags = flags(held)
        event.post(tap: .cghidEventTap)
    }

    private func flags(_ modifiers: Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.cmd) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.alt) { flags.insert(.maskAlternate) }
        if modifiers.contains(.ctrl) { flags.insert(.maskControl) }
        return flags
    }

    // Left-hand modifier keys (Carbon kVK_Command, kVK_Shift, kVK_Option, kVK_Control).
    private static func keyCode(_ modifier: Modifiers) -> UInt16 {
        switch modifier {
        case .cmd: 0x37
        case .shift: 0x38
        case .alt: 0x3A
        default: 0x3B
        }
    }
}
