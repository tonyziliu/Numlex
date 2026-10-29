import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import NumlexCore

/// What the system said about one global hotkey.
enum HotKeyStatus: Equatable {
    case unset
    case active
    /// RegisterEventHotKey refused it; usually another app owns the combination.
    case failed(OSStatus)
}

/// Owns the user's global hotkeys: `hotkeys.json`, the Carbon
/// registrations (RegisterEventHotKey needs no Accessibility permission)
/// and the per-action status the Settings page shows. Nothing is
/// registered until the user records a combination.
@MainActor
@Observable
final class GlobalHotKeyCenter {
    private(set) var bindings: HotKeyBindings
    private(set) var status: [HotKeyAction: HotKeyStatus] = [:]

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var refs: [HotKeyAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handlerRef: EventHandlerRef?
    @ObservationIgnored var onPress: (HotKeyAction) -> Void = { _ in }
    /// Opens a fresh main window; installed by the main window scene.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    private static let signature = OSType(0x4E4C_4850) // 'NLHP'

    init(directory: URL = Persistence.dataDirectory()) {
        self.directory = directory
        self.bindings = HotKeyPersistence.load(from: directory)
    }

    /// Idempotent: every main window calls it on appear, because
    /// NSApplication does not exist yet inside App.init.
    func start() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var id = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                         EventParamType(typeEventHotKeyID), nil,
                                         MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard read == noErr else { return read }
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue().fire(id)
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == noErr else {
            for action in HotKeyAction.allCases where bindings[action] != nil {
                status[action] = .failed(installed)
            }
            return
        }
        HotKeyAction.allCases.forEach(register)
    }

    /// Binds and registers `combo`, or returns why it was not accepted.
    func set(_ combo: KeyCombo, for action: HotKeyAction) -> HotKeyBindings.Rejection? {
        if let rejection = bindings.set(combo, for: action) { return rejection }
        HotKeyPersistence.save(bindings, to: directory)
        register(action)
        return nil
    }

    func clear(_ action: HotKeyAction) {
        bindings.clear(action)
        HotKeyPersistence.save(bindings, to: directory)
        register(action)
    }

    /// Converges the Carbon registration of `action` on its binding.
    private func register(_ action: HotKeyAction) {
        if let ref = refs.removeValue(forKey: action) { UnregisterEventHotKey(ref) }
        guard let combo = bindings[action] else { status[action] = .unset; return }
        guard handlerRef != nil else { return }
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(combo.keyCode, Self.carbonModifiers(combo.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: Self.id(action)),
                                         GetApplicationEventTarget(),
                                         OptionBits(kEventHotKeyExclusive), &ref)
        if result == noErr, let ref {
            refs[action] = ref
            status[action] = .active
        } else {
            status[action] = .failed(result)
        }
    }

    private func fire(_ id: EventHotKeyID) {
        guard id.signature == Self.signature,
              let action = HotKeyAction.allCases.first(where: { Self.id($0) == id.id }) else { return }
        onPress(action)
    }

    private static func id(_ action: HotKeyAction) -> UInt32 {
        UInt32(HotKeyAction.allCases.firstIndex(of: action)! + 1)
    }

    private static func carbonModifiers(_ m: HotKeyModifiers) -> UInt32 {
        var flags = 0
        if m.contains(.command) { flags |= cmdKey }
        if m.contains(.shift) { flags |= shiftKey }
        if m.contains(.option) { flags |= optionKey }
        if m.contains(.control) { flags |= controlKey }
        return UInt32(flags)
    }

    /// Show/hide Numlex: hides the app when it is frontmost with a window
    /// on screen; otherwise brings it forward, restoring minimized windows
    /// and opening a main window when none is left.
    func toggleApp() {
        let windows = NSApp.windows.filter { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }
        if NSApp.isActive, !NSApp.isHidden, windows.contains(where: \.isVisible) {
            NSApp.hide(nil)
            return
        }
        NSApp.unhide(nil)
        NSApp.activate()
        guard let window = windows.first(where: \.isVisible) ?? windows.first else {
            openMainWindow?()
            return
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

/// Hands the scene's openWindow action to the hotkey center, so show/hide
/// can reopen a main window after the last one was closed.
struct MainWindowOpenerInstaller: View {
    let center: GlobalHotKeyCenter
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                center.openMainWindow = { openWindow(id: NumlexApp.mainWindowID) }
            }
    }
}
