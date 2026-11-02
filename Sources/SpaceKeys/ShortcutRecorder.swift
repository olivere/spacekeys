import AppKit
import SpaceKeysCore
import SwiftUI

/// Click, then press a key combination. Pressing and releasing modifiers
/// alone records "hold these modifiers". Click again to cancel.
///
/// While recording, every key press in the window goes to the recorder, so
/// ⌘Q, ⌘W or Escape can be recorded like any other key.
struct ShortcutRecorder: View {
    /// The mapping set at this level; nil when unset.
    let action: Action?
    /// For an app: the All Apps mapping shown while `action` is nil.
    let inherited: Action?
    let isAppScope: Bool
    let onChange: (Action?) -> Void

    @Environment(AppModel.self) private var model
    @State private var id = UUID()
    @State private var monitor: Any?
    @State private var peak: Modifiers = []
    @State private var message: String?

    private var isRecording: Bool { monitor != nil }

    var body: some View {
        HStack(spacing: 6) {
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            SwiftUI.Button {
                isRecording ? stop() : start()
            } label: {
                Text(title)
                    .foregroundStyle(action == nil && !isRecording ? .secondary : .primary)
                    .frame(minWidth: 150)
            }
            .help(isRecording ? "Press a key combination, or click to cancel" : "Click to record a shortcut")

            SwiftUI.Button {
                stop()
                onChange(nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(action == nil ? 0 : 1)
            .disabled(action == nil)
            .help(isAppScope ? "Use the All Apps mapping" : "Unmap this button")
        }
        .onDisappear(perform: stop)
        .onChange(of: model.recorder) { _, current in
            if current != id { stop() }
        }
    }

    private var title: String {
        if isRecording {
            return peak.isEmpty ? "Type shortcut…" : peak.symbols
        }
        if let action { return action.displayString }
        if let inherited { return "\(inherited.displayString)  (All Apps)" }
        return isAppScope ? "None (All Apps)" : "None"
    }

    private func start() {
        peak = []
        message = nil
        model.recorder = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        peak = []
        if model.recorder == id { model.recorder = nil }
    }

    private func handle(_ event: NSEvent) {
        let modifiers = Self.modifiers(event.modifierFlags)
        switch event.type {
        case .keyDown:
            guard let key = KeyboardLayout.key(forKeyCode: event.keyCode) else {
                message = "Unsupported key"
                return
            }
            finish(.shortcut(modifiers, key))
        case .flagsChanged:
            if modifiers.isEmpty {
                if !peak.isEmpty { finish(.modifier(peak)) }
            } else {
                peak.formUnion(modifiers)
            }
        default:
            break
        }
    }

    private func finish(_ action: Action) {
        stop()
        message = nil
        onChange(action)
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> Modifiers {
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.cmd) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.alt) }
        if flags.contains(.control) { modifiers.insert(.ctrl) }
        return modifiers
    }
}
