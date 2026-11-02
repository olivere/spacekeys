import AppKit
import SwiftUI

@main
struct SpaceKeysApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("SpaceKeys", systemImage: "rotate.3d") {
            MenuContent()
                .environment(delegate.model)
        }

        Window("SpaceKeys Settings", id: SettingsView.windowID) {
            SettingsView()
                .environment(delegate.model)
        }
        .defaultSize(width: 760, height: 620)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()

        // Logout and `kill` send SIGTERM, which skips applicationWillTerminate;
        // let go of held keys first either way.
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [model] in
                MainActor.assumeIsolated { model.releaseAll() }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.releaseAll()
    }
}

struct MenuContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !model.trusted {
            Text("Needs Accessibility access to send keys")
            Button("Open Accessibility Settings…") { model.openAccessibilitySettings() }
        } else if let error = model.deviceError {
            Text(error)
        } else if let name = model.deviceName {
            Text("\(name) connected")
        } else {
            Text("No SpaceMouse connected")
        }
        if let error = model.configError ?? model.saveError {
            Text("Config problem, see Settings")
                .help(error)
        }

        Divider()

        Button("Settings…") {
            openWindow(id: SettingsView.windowID)
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Toggle("Open at Login", isOn: Binding(
            get: { model.opensAtLogin },
            set: { model.setOpensAtLogin($0) }))

        Divider()

        Button("Quit SpaceKeys") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
