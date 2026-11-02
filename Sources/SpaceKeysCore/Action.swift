public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let cmd = Modifiers(rawValue: 1 << 0)
    public static let shift = Modifiers(rawValue: 1 << 1)
    public static let alt = Modifiers(rawValue: 1 << 2)
    public static let ctrl = Modifiers(rawValue: 1 << 3)

    /// Single modifiers in a fixed order, for iterating a set.
    public static let all: [Modifiers] = [.cmd, .shift, .alt, .ctrl]

    static func named(_ name: String) -> Modifiers? {
        switch name {
        case "cmd", "command": .cmd
        case "shift": .shift
        case "alt", "opt", "option": .alt
        case "ctrl", "control": .ctrl
        default: nil
        }
    }
}

/// A key to press. Named keys have the same virtual key code on every layout;
/// characters are looked up in the active keyboard layout when the button is
/// pressed, so "cmd+z" means the key labelled Z on QWERTZ as well as QWERTY.
public enum Key: Equatable, Sendable {
    case code(UInt16)
    case character(Character)

    // Carbon kVK_* values, which are layout-independent for these keys.
    // The first name of each key is the one written back to the config.
    private static let canonical: [(String, UInt16)] = [
        ("return", 0x24), ("tab", 0x30), ("space", 0x31), ("delete", 0x33),
        ("escape", 0x35), ("forwarddelete", 0x75), ("home", 0x73), ("end", 0x77),
        ("pageup", 0x74), ("pagedown", 0x79),
        ("left", 0x7B), ("right", 0x7C), ("down", 0x7D), ("up", 0x7E),
        ("f1", 0x7A), ("f2", 0x78), ("f3", 0x63), ("f4", 0x76), ("f5", 0x60),
        ("f6", 0x61), ("f7", 0x62), ("f8", 0x64), ("f9", 0x65), ("f10", 0x6D),
        ("f11", 0x67), ("f12", 0x6F), ("f13", 0x69), ("f14", 0x6B), ("f15", 0x71),
        ("f16", 0x6A), ("f17", 0x40), ("f18", 0x4F), ("f19", 0x50), ("f20", 0x5A),
    ]
    private static let aliases: [(String, UInt16)] = [("enter", 0x24), ("backspace", 0x33), ("esc", 0x35)]

    static let named = Dictionary(uniqueKeysWithValues: canonical + aliases)
    private static let nameByCode = Dictionary(uniqueKeysWithValues: canonical.map { ($1, $0) })

    /// The config name of a layout-independent key, or nil for keys that are
    /// written as the character they type.
    public static func name(ofCode code: UInt16) -> String? { nameByCode[code] }

    /// Characters that cannot be written inside a shortcut string.
    static let characterNames: [String: Character] = ["plus": "+"]

    var configString: String {
        switch self {
        case .code(let code):
            guard let name = Key.nameByCode[code] else {
                preconditionFailure("key code \(code) has no config name; record it as a character")
            }
            return name
        case .character(let character):
            return Key.characterNames.first { $0.value == character }?.key ?? String(character)
        }
    }

    var symbol: String {
        switch self {
        case .character(let character):
            return character == " " ? "Space" : character.uppercased()
        case .code(let code):
            let name = Key.nameByCode[code] ?? "?"
            let symbols = [
                "return": "↩", "tab": "⇥", "space": "Space", "delete": "⌫", "escape": "⎋",
                "forwarddelete": "⌦", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
                "left": "←", "right": "→", "down": "↓", "up": "↑",
            ]
            return symbols[name] ?? name.uppercased()
        }
    }
}

public enum Action: Equatable, Sendable {
    /// Held like the modifier key on a keyboard while the button is down.
    case modifier(Modifiers)
    /// Pressed with the given modifiers while the button is down.
    case shortcut(Modifiers, Key)
}

public struct ActionParseError: Error, Equatable, CustomStringConvertible {
    public let input: String
    public let reason: String
    public var description: String { "invalid action \"\(input)\": \(reason)" }
}

extension Action {
    /// Parses "ctrl", "ctrl+shift" (held together), "escape", "cmd+shift+z",
    /// "cmd+plus".
    /// Names and letters are case-insensitive; "cmd+Z" is "cmd+z".
    public init(parsing input: String) throws {
        let parts = input.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(where: \.isEmpty) else {
            throw ActionParseError(input: input, reason: "empty part; write \"plus\" for the + key")
        }
        let lowered = parts.map { $0.lowercased() }

        let named = lowered.compactMap(Modifiers.named)
        if named.count == lowered.count {
            self = .modifier(named.reduce(into: []) { $0.formUnion($1) })
            return
        }

        var modifiers: Modifiers = []
        for name in lowered.dropLast() {
            guard let modifier = Modifiers.named(name) else {
                throw ActionParseError(input: input, reason: "\"\(name)\" is not a modifier")
            }
            modifiers.insert(modifier)
        }

        let keyName = lowered.last!
        let key: Key
        if let code = Key.named[keyName] {
            key = .code(code)
        } else if let character = Key.characterNames[keyName] {
            key = .character(character)
        } else if parts.last!.count == 1 {
            key = .character(Character(keyName))
        } else {
            throw ActionParseError(input: input, reason: "unknown key \"\(parts.last!)\"")
        }
        self = .shortcut(modifiers, key)
    }
}

extension Modifiers {
    var configNames: [String] {
        Modifiers.all.filter(contains).map {
            switch $0 {
            case .cmd: "cmd"
            case .shift: "shift"
            case .alt: "alt"
            default: "ctrl"
            }
        }
    }

    /// Apple's menu order: ⌃⌥⇧⌘.
    public var symbols: String {
        (contains(.ctrl) ? "⌃" : "") + (contains(.alt) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.cmd) ? "⌘" : "")
    }
}

extension Action {
    /// The text written to the config file; `Action(parsing:)` reads it back.
    public var configString: String {
        switch self {
        case .modifier(let modifiers):
            modifiers.configNames.joined(separator: "+")
        case .shortcut(let modifiers, let key):
            (modifiers.configNames + [key.configString]).joined(separator: "+")
        }
    }

    /// How the settings window shows the action, e.g. "⇧⌘Z" or "Hold ⌃".
    public var displayString: String {
        switch self {
        case .modifier(let modifiers):
            "Hold \(modifiers.symbols)"
        case .shortcut(let modifiers, let key):
            modifiers.symbols + key.symbol
        }
    }
}
