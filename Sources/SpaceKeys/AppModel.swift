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
            }
        }
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
        guard recorder == nil else { return }
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let action = config.action(for: button, app: bundleID) else { return }
        do {
            try poster.press(button, action: action)
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
