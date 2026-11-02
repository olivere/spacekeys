import AppKit
import ApplicationServices
import Observation
import OSLog
import ServiceManagement
import SpaceKeysCore

private let logger = Logger(subsystem: "de.alt-f4.spacekeys", category: "app")

/// Readable with `make logs`.
func log(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}

@Observable
@MainActor
final class AppModel {
    static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/spacekeys/config.json")

    private(set) var config: Config
    /// Set when the config file exists but cannot be used. The app then runs
    /// with no mappings, and the next edit in Settings replaces the file.
    private(set) var configError: String?
    private(set) var saveError: String?
    private(set) var deviceName: String?
    /// The app holding the SpaceMouse exclusively. Its buttons do nothing
    /// here until that app lets go, typically when it leaves the front.
    private(set) var deviceOwner: String?
    private(set) var deviceError: String?
    private(set) var trusted = AXIsProcessTrusted()
    private(set) var pressed: Set<DeviceButton> = []
    private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginError: String?

    /// The shortcut field that is recording, if any. Only one records at a
    /// time. Meanwhile SpaceMouse buttons only light up their row and send
    /// nothing, so they cannot type into the recorder.
    var recorder: UUID?

    private let poster = KeyPoster()
    private let mouse = SpaceMouse()

    init() {
        if FileManager.default.fileExists(atPath: Self.configURL.path) {
            do {
                config = try Config(contentsOf: Self.configURL)
            } catch {
                config = Config(buttons: [:])
                configError = "\(error)"
                log("config: \(error)")
            }
        } else {
            config = .defaults
        }
    }

    func start() {
        mouse.onButton = { [weak self] button, down in self?.handle(button, down: down) }
        mouse.onConnected = { [weak self] name in self?.deviceName = name }
        mouse.onRemoved = { [weak self] in
            self?.deviceName = nil
            self?.pressed = []
            self?.poster.releaseAll()
        }

        // Prompts once; the system dialog links to the Accessibility settings.
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(prompt)
        Task {
            // Without the permission posted events are dropped silently, so
            // the device is opened only once it is granted.
            while !AXIsProcessTrusted() {
                // Throws only on cancellation, and nothing cancels this task.
                try? await Task.sleep(for: .seconds(2))
            }
            trusted = true
            do {
                try mouse.start()
                log("listening")
            } catch {
                deviceError = "\(error)"
                log("\(error)")
                return
            }
            // Nothing announces a seize, so look every two seconds.
            while true {
                updateDeviceOwner()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func updateDeviceOwner() {
        let owner = mouse.exclusiveOwner().map(Self.name(ofProcess:))
        guard owner != deviceOwner else { return }
        log(owner.map { "SpaceMouse in use by \($0)" } ?? "SpaceMouse available again")
        deviceOwner = owner
    }

    private static func name(ofProcess pid: Int32) -> String {
        let app = NSRunningApplication(processIdentifier: pid)
        return app?.executableURL.flatMap { displayName(forExecutablePath: $0.path) }
            ?? app?.localizedName
            ?? "process \(pid)"
    }

    func releaseAll() {
        poster.releaseAll()
    }

    private func handle(_ button: DeviceButton, down: Bool) {
        guard down else {
            pressed.remove(button)
            poster.release(button)
            return
        }
        pressed.insert(button)
        guard recorder == nil else {
            log("\(button.rawValue): ignored while a shortcut field records")
            return
        }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let action = config.action(for: button, app: bundleID) else {
            log("\(button.rawValue) in \(bundleID ?? "unknown app"): not mapped")
            return
        }
        do {
            let posted = try poster.press(button, action: action)
            log("\(button.rawValue) in \(bundleID ?? "unknown app"): \(action.configString), \(posted)")
        } catch {
            log("\(button.rawValue): \(error)")
        }
    }

    // MARK: Editing

    func set(_ action: Action?, for button: DeviceButton, app bundleID: String?) {
        config.set(action, for: button, app: bundleID)
        save()
    }

    func addApp(_ bundleID: String) {
        config.addApp(bundleID)
        save()
    }

    func removeApp(_ bundleID: String) {
        config.removeApp(bundleID)
        save()
    }

    private func save() {
        do {
            try config.write(to: Self.configURL)
            configError = nil
            saveError = nil
        } catch {
            saveError = "Cannot save \(Self.configURL.path): \(error.localizedDescription)"
            log(saveError!)
        }
    }

    // MARK: Login item

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            log("login item: \(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
