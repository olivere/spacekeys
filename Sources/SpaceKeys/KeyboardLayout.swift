import Carbon
import SpaceKeysCore

/// Translates between characters and key codes in the active keyboard layout.
/// Asked on every use, so a layout switch takes effect at once.
enum KeyboardLayout {
    struct MissingCharacter: Error, CustomStringConvertible {
        let character: Character
        var description: String {
            "\"\(character)\" has no key of its own in the active keyboard layout (it needs a modifier)"
        }
    }

    static func keyCode(for key: Key) throws -> UInt16 {
        switch key {
        case .code(let code):
            return code
        case .character(let character):
            let target = String(character)
            guard let code = (UInt16(0)..<128).first(where: { self.character(forKeyCode: $0) == target }) else {
                throw MissingCharacter(character: character)
            }
            return code
        }
    }

    /// The key a recorded key code stands for: a named key, or the character
    /// it types without modifiers. Nil for keys neither covers.
    static func key(forKeyCode code: UInt16) -> Key? {
        if Key.name(ofCode: code) != nil { return .code(code) }
        guard let string = character(forKeyCode: code), string.count == 1,
              let character = string.lowercased().first,
              !character.isWhitespace, !(character.asciiValue.map { $0 < 0x20 || $0 == 0x7F } ?? false)
        else { return nil }
        return .character(character)
    }

    private static func character(forKeyCode code: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

        return data.withUnsafeBytes { raw -> String? in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
