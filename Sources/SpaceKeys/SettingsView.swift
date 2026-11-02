import AppKit
import SpaceKeysCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    static let windowID = "settings"

    @Environment(AppModel.self) private var model
    @State private var selection: String? = Self.allApps

    /// Sidebar tag for the global table; real entries are bundle IDs.
    static let allApps = "*"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("All Apps", systemImage: "square.grid.2x2")
                    .tag(Self.allApps)
                Section("Apps") {
                    ForEach(sortedApps, id: \.self) { bundleID in
                        AppLabel(bundleID: bundleID)
                            .tag(bundleID)
                            .contextMenu {
                                Button("Remove") { remove(bundleID) }
                            }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { sidebarButtons }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            MappingForm(app: selection == Self.allApps ? nil : selection)
                .id(selection)
        }
    }

    private var sortedApps: [String] {
        model.config.apps.keys.sorted {
            AppLabel.name(of: $0).localizedCaseInsensitiveCompare(AppLabel.name(of: $1)) == .orderedAscending
        }
    }

    private var sidebarButtons: some View {
        HStack(spacing: 0) {
            Menu {
                let running = runningApps
                ForEach(running, id: \.bundleIdentifier) { app in
                    Button {
                        add(app.bundleIdentifier!)
                    } label: {
                        if let icon = app.icon { Image(nsImage: icon) }
                        Text(app.localizedName ?? app.bundleIdentifier!)
                    }
                }
                if !running.isEmpty { Divider() }
                Button("Choose App…") { chooseApp() }
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add an app with its own mappings")

            Button {
                if let selection, selection != Self.allApps { remove(selection) }
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(selection == nil || selection == Self.allApps)
            .help("Remove the selected app and its mappings")

            Spacer()
        }
        .padding(8)
    }

    /// Regular apps that are running and not in the list yet.
    private var runningApps: [NSRunningApplication] {
        let added = Set(model.config.apps.keys)
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                      id != Bundle.main.bundleIdentifier, !added.contains(id)
                else { return false }
                return seen.insert(id).inserted
            }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func add(_ bundleID: String) {
        model.addApp(bundleID)
        selection = bundleID
    }

    private func remove(_ bundleID: String) {
        model.removeApp(bundleID)
        if selection == bundleID { selection = Self.allApps }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else {
            NSSound.beep()
            log("\(url.path) has no bundle identifier")
            return
        }
        add(bundleID)
    }
}

struct AppLabel: View {
    let bundleID: String

    var body: some View {
        Label {
            Text(Self.name(of: bundleID))
        } icon: {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
            }
        }
        .help(bundleID)
    }

    /// The app's display name, or its bundle ID when it is not installed.
    static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

struct MappingForm: View {
    /// nil edits the global table.
    let app: String?

    @Environment(AppModel.self) private var model

    private static let groups: [(String, [DeviceButton])] = [
        ("Keyboard keys", [.esc, .ctrl, .shift, .alt]),
        ("Shortcut keys", [.one, .two, .three, .four]),
        ("View keys", [.menu, .fit, .top, .right, .front, .roll, .lock]),
    ]

    var body: some View {
        Form {
            if let error = model.configError {
                Section {
                    Label {
                        Text("The config file could not be read, so no buttons are mapped. Changing a mapping here replaces the file.\n\n\(error)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    }
                }
            }
            if let error = model.saveError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                }
            }
            Section {
                Text(app == nil
                     ? "Used in every app without its own mapping. Press a SpaceMouse button to find its row."
                     : "Buttons left on \"All Apps\" use the global mapping.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Self.groups, id: \.0) { title, buttons in
                Section(title) {
                    ForEach(buttons, id: \.self) { button in
                        row(button)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(app.map(AppLabel.name(of:)) ?? "All Apps")
    }

    private func row(_ button: DeviceButton) -> some View {
        let own = app.map { model.config.apps[$0]?[button] } ?? model.config.buttons[button]
        return LabeledContent {
            ShortcutRecorder(
                action: own,
                inherited: app == nil ? nil : model.config.buttons[button],
                isAppScope: app != nil,
                onChange: { model.set($0, for: button, app: app) })
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.pressed.contains(button) ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
                Text(button.label)
                    .fontWeight(model.pressed.contains(button) ? .semibold : .regular)
            }
            .animation(.easeOut(duration: 0.12), value: model.pressed.contains(button))
        }
    }
}

extension DeviceButton {
    var label: String {
        switch self {
        case .menu: "Menu"
        case .fit: "Fit"
        case .top: "T (Top view)"
        case .right: "R (Right view)"
        case .front: "F (Front view)"
        case .roll: "Roll view"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .esc: "Esc"
        case .alt: "Alt"
        case .shift: "Shift"
        case .ctrl: "Ctrl"
        case .lock: "Rotation lock"
        }
    }
}
