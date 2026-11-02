import Foundation

/// Button mappings: one global table plus per-app tables keyed by bundle ID.
/// An app table only needs the buttons it changes; the rest fall through to
/// the global table.
public struct Config: Equatable, Sendable {
    public var buttons: [DeviceButton: Action]
    public var apps: [String: [DeviceButton: Action]]

    public init(buttons: [DeviceButton: Action], apps: [String: [DeviceButton: Action]] = [:]) {
        self.buttons = buttons
        self.apps = apps
    }

    public func action(for button: DeviceButton, app bundleID: String?) -> Action? {
        if let bundleID, let action = apps[bundleID]?[button] {
            return action
        }
        return buttons[button]
    }

    /// Sets or, with nil, removes a mapping. For an app, nil means the button
    /// falls back to the global table again.
    public mutating func set(_ action: Action?, for button: DeviceButton, app bundleID: String?) {
        if let bundleID {
            apps[bundleID, default: [:]][button] = action
        } else {
            buttons[button] = action
        }
    }

    /// Adds an app with no overrides yet, so it can be configured.
    public mutating func addApp(_ bundleID: String) {
        if apps[bundleID] == nil { apps[bundleID] = [:] }
    }

    public mutating func removeApp(_ bundleID: String) {
        apps[bundleID] = nil
    }

    /// The mapping used when no config file exists yet.
    public static let defaults = Config(buttons: [
        .esc: .shortcut([], .code(0x35)),
        .ctrl: .modifier(.ctrl),
        .shift: .modifier(.shift),
        .alt: .modifier(.alt),
        .one: .shortcut(.cmd, .character("c")),
        .two: .shortcut(.cmd, .character("v")),
        .three: .shortcut(.cmd, .character("z")),
        .four: .shortcut([.cmd, .shift], .character("z")),
        .fit: .shortcut(.cmd, .character("0")),
    ])
}

public struct ConfigError: Error, CustomStringConvertible {
    public let description: String
}

extension Config {
    private struct File: Codable {
        var buttons: [String: String]
        var apps: [String: [String: String]]?
    }

    public init(json data: Data) throws {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw ConfigError(description: "config is not valid JSON of the expected shape: \(error)")
        }
        self.buttons = try Self.table(file.buttons, context: "buttons")
        self.apps = try (file.apps ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key] = try Self.table(entry.value, context: "apps.\(entry.key)")
        }
    }

    public init(contentsOf url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError(description: "cannot read \(url.path): \(error.localizedDescription)")
        }
        try self.init(json: data)
    }

    public func json() throws -> Data {
        let file = File(
            buttons: Self.strings(buttons),
            apps: apps.mapValues(Self.strings))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(file)
    }

    /// Writes atomically, creating the directory if needed.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json().write(to: url, options: .atomic)
    }

    private static func strings(_ table: [DeviceButton: Action]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: table.map { ($0.key.rawValue, $0.value.configString) })
    }

    private static func table(_ raw: [String: String], context: String) throws -> [DeviceButton: Action] {
        try raw.reduce(into: [:]) { result, entry in
            guard let button = DeviceButton(rawValue: entry.key.lowercased()) else {
                let known = DeviceButton.allCases.map(\.rawValue).joined(separator: ", ")
                throw ConfigError(description: "\(context): unknown button \"\(entry.key)\" (known: \(known))")
            }
            do {
                result[button] = try Action(parsing: entry.value)
            } catch {
                throw ConfigError(description: "\(context).\(entry.key): \(error)")
            }
        }
    }
}
