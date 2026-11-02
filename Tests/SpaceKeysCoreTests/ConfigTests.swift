import Foundation
import Testing
@testable import SpaceKeysCore

@Suite struct ConfigLoading {
    private func load(_ json: String) throws -> Config {
        try Config(json: Data(json.utf8))
    }

    @Test func appTableOverridesGlobalTable() throws {
        let config = try load("""
            {
              "buttons": { "1": "cmd+c", "fit": "cmd+0" },
              "apps": { "com.apple.Preview": { "fit": "cmd+9" } }
            }
            """)
        #expect(config.action(for: .fit, app: "com.apple.Preview") == .shortcut(.cmd, .character("9")))
        #expect(config.action(for: .fit, app: "com.apple.Safari") == .shortcut(.cmd, .character("0")))
        #expect(config.action(for: .fit, app: nil) == .shortcut(.cmd, .character("0")))
    }

    @Test func appTableFallsThroughForMissingButtons() throws {
        let config = try load("""
            { "buttons": { "1": "cmd+c" }, "apps": { "com.apple.Preview": { "fit": "cmd+9" } } }
            """)
        #expect(config.action(for: .one, app: "com.apple.Preview") == .shortcut(.cmd, .character("c")))
    }

    @Test func unmappedButtonHasNoAction() throws {
        let config = try load(#"{ "buttons": {} }"#)
        #expect(config.action(for: .menu, app: nil) == nil)
    }

    @Test func buttonNamesAreCaseInsensitive() throws {
        let config = try load(#"{ "buttons": { "Fit": "cmd+0" } }"#)
        #expect(config.action(for: .fit, app: nil) != nil)
    }

    @Test func unknownButtonFails() {
        #expect(throws: ConfigError.self) { try load(#"{ "buttons": { "5": "cmd+c" } }"#) }
    }

    @Test func badActionNamesItsLocation() throws {
        let error = try #require(throws: ConfigError.self) {
            try load(#"{ "buttons": {}, "apps": { "com.x": { "1": "cmd+" } } }"#)
        }
        #expect(error.description.hasPrefix("apps.com.x.1:"))
    }

    @Test func missingButtonsKeyFails() {
        #expect(throws: ConfigError.self) { try load(#"{ "apps": {} }"#) }
    }

    @Test func jsonRoundTrips() throws {
        var config = Config.defaults
        config.set(.shortcut(.cmd, .character("9")), for: .fit, app: "com.apple.Preview")
        config.addApp("com.example.Empty")
        #expect(try Config(json: config.json()) == config)
    }

    @Test func writtenJSONIsReadable() throws {
        let config = try load(#"{ "buttons": { "1": "cmd+c" } }"#)
        let text = String(decoding: try config.json(), as: UTF8.self)
        #expect(text.contains(#""1" : "cmd+c""#))
    }

    @Test func settingNilOnAppFallsBackToGlobal() throws {
        var config = Config.defaults
        config.set(.shortcut(.cmd, .character("9")), for: .fit, app: "com.apple.Preview")
        config.set(nil, for: .fit, app: "com.apple.Preview")
        #expect(config.action(for: .fit, app: "com.apple.Preview") == .shortcut(.cmd, .character("0")))
        #expect(config.apps["com.apple.Preview"] == [:])
    }

    @Test func settingNilGloballyUnmaps() {
        var config = Config.defaults
        config.set(nil, for: .one, app: nil)
        #expect(config.action(for: .one, app: nil) == nil)
    }

    @Test func addAppKeepsExistingOverrides() {
        var config = Config.defaults
        config.set(.modifier(.cmd), for: .menu, app: "com.x")
        config.addApp("com.x")
        #expect(config.action(for: .menu, app: "com.x") == .modifier(.cmd))
    }

    @Test func removeAppDropsOverrides() {
        var config = Config.defaults
        config.set(.modifier(.cmd), for: .menu, app: "com.x")
        config.removeApp("com.x")
        #expect(config.apps["com.x"] == nil)
        #expect(config.action(for: .menu, app: "com.x") == nil)
    }

    @Test func writeCreatesDirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "nested/config.json")
        try Config.defaults.write(to: url)
        #expect(try Config(contentsOf: url) == Config.defaults)
    }
}
