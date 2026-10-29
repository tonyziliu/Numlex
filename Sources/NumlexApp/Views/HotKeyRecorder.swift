import AppKit
import Carbon.HIToolbox
import SwiftUI
import NumlexCore

/// Records one global hotkey. Click to record, press the combination,
/// Esc cancels. The clear button unbinds it. A rejection or a refused
/// registration shows under the control.
struct HotKeyRecorder: View {
    let action: HotKeyAction
    let language: AppLanguage
    @Environment(GlobalHotKeyCenter.self) private var center

    @State private var recording = false
    @State private var monitor: Any?
    @State private var rejection: HotKeyBindings.Rejection?

    private func t(_ key: String) -> String { L10n.t(key, language: language) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Button { recording ? stop() : start() } label: {
                    Text(label)
                        .font(.system(size: 12, design: .rounded))
                        .frame(minWidth: 110)
                }
                .help(t("hotkeys.recordHelp"))
                if center.bindings[action] != nil {
                    Button { rejection = nil; center.clear(action) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(t("hotkeys.clear"))
                    .accessibilityLabel(t("hotkeys.clear"))
                }
            }
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.trailing)
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return t("hotkeys.recording") }
        return center.bindings[action]?.display ?? t("hotkeys.none")
    }

    private var message: String? {
        switch rejection {
        case .usedBy: return t("hotkeys.usedByOther")
        case .appShortcut: return t("hotkeys.usedByApp")
        case nil: break
        }
        if case .failed(let code) = center.status[action] {
            return t("hotkeys.registrationFailed") + " (\(code))"
        }
        return nil
    }

    private func start() {
        rejection = nil
        recording = true
        center.setSuspended(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            guard let combo = KeyCombo(keyCode: UInt32(event.keyCode),
                                       modifiers: Self.modifiers(event.modifierFlags),
                                       key: event.charactersIgnoringModifiers ?? "") else {
                // Plain keys keep recording; a hotkey needs Command, Control or Option.
                return nil
            }
            rejection = center.set(combo, for: action)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        center.setSuspended(false)
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        var m: HotKeyModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }
}
