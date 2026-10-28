import Carbon.HIToolbox

/// Cmd+Shift+V through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission.
@MainActor
final class ClipboardHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    /// Returns false when the system refuses the registration.
    func register() -> Bool {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<ClipboardHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: OSType(0x4E4C_4350), id: 1) // 'NLCP'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            RemoveEventHandler(handlerRef)
            handlerRef = nil
            return false
        }
        return true
    }
}
