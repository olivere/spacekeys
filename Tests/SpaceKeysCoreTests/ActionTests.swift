import Testing
@testable import SpaceKeysCore

@Suite struct ActionParsing {
    @Test(arguments: [
        ("ctrl", Action.modifier(.ctrl)),
        ("Control", .modifier(.ctrl)),
        ("shift", .modifier(.shift)),
        ("alt", .modifier(.alt)),
        ("option", .modifier(.alt)),
        ("cmd", .modifier(.cmd)),
    ])
    func bareModifierIsHeld(input: String, expected: Action) throws {
        #expect(try Action(parsing: input) == expected)
    }

    @Test func namedKeyUsesFixedKeyCode() throws {
        #expect(try Action(parsing: "escape") == .shortcut([], .code(0x35)))
        #expect(try Action(parsing: "esc") == .shortcut([], .code(0x35)))
        #expect(try Action(parsing: "F12") == .shortcut([], .code(0x6F)))
    }

    @Test func characterKeyIsResolvedLater() throws {
        #expect(try Action(parsing: "cmd+c") == .shortcut(.cmd, .character("c")))
        #expect(try Action(parsing: "cmd+0") == .shortcut(.cmd, .character("0")))
        #expect(try Action(parsing: "cmd+-") == .shortcut(.cmd, .character("-")))
    }

    @Test func lettersAreCaseInsensitive() throws {
        #expect(try Action(parsing: "CMD+Shift+Z") == .shortcut([.cmd, .shift], .character("z")))
    }

    @Test func plusIsNamed() throws {
        #expect(try Action(parsing: "cmd+plus") == .shortcut(.cmd, .character("+")))
    }

    @Test func modifierOrderDoesNotMatter() throws {
        #expect(try Action(parsing: "shift+cmd+left") == Action(parsing: "cmd+shift+left"))
    }

    @Test func severalBareModifiersAreHeldTogether() throws {
        #expect(try Action(parsing: "ctrl+shift") == .modifier([.ctrl, .shift]))
    }

    @Test(arguments: ["", "cmd+", "+", "cmd++", "hyper+c", "cmd+nosuchkey"])
    func rejects(input: String) {
        #expect(throws: ActionParseError.self) { try Action(parsing: input) }
    }
}

@Suite struct ActionWriting {
    @Test(arguments: [
        "ctrl", "ctrl+shift", "escape", "cmd+c", "cmd+shift+z", "cmd+plus",
        "alt+f12", "cmd+left", "space", "cmd+0", "ctrl+alt+shift+cmd+-",
    ])
    func configStringRoundTrips(input: String) throws {
        let action = try Action(parsing: input)
        #expect(try Action(parsing: action.configString) == action)
    }

    @Test func configStringUsesCanonicalNames() throws {
        #expect(try Action(parsing: "esc").configString == "escape")
        #expect(try Action(parsing: "shift+CMD+Z").configString == "cmd+shift+z")
        #expect(try Action(parsing: "option").configString == "alt")
    }

    @Test(arguments: [
        ("cmd+shift+z", "⇧⌘Z"),
        ("ctrl+alt+left", "⌃⌥←"),
        ("escape", "⎋"),
        ("cmd+space", "⌘Space"),
        ("f5", "F5"),
        ("ctrl", "Hold ⌃"),
        ("cmd+plus", "⌘+"),
    ])
    func displayString(input: String, expected: String) throws {
        #expect(try Action(parsing: input).displayString == expected)
    }

    @Test func keyNameOfCode() {
        #expect(Key.name(ofCode: 0x35) == "escape")
        #expect(Key.name(ofCode: 0x06) == nil)
    }
}

@Suite struct Buttons {
    @Test func hidUsageRoundTrips() {
        for button in DeviceButton.allCases {
            #expect(DeviceButton(hidUsage: button.hidUsage) == button)
        }
    }

    @Test func usagesMatchDescriptor() {
        let usages = Set(DeviceButton.allCases.map(\.hidUsage))
        #expect(usages == [1, 2, 3, 5, 6, 9, 13, 14, 15, 16, 23, 24, 25, 26, 27])
    }

    @Test func unknownUsageIsNil() {
        #expect(DeviceButton(hidUsage: 4) == nil)
    }
}
