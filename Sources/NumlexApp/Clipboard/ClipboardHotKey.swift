import Carbon.HIToolbox

/// The callback of a C event handler cannot capture context, so the
/// action lives in a file-level slot. There is one hotkey per process.
nonisolated(unsafe) private var clipboardHotKeyAction: (@MainActor () -> Void)?

/// Cmd+Shift+V through Carbon's RegisterEventHotKey, which needs no
/// Accessibility permission.
final class ClipboardHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Returns false when the system refuses the registration.
    func register(action: @escaping @MainActor () -> Void) -> Bool {
        clipboardHotKeyAction = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in clipboardHotKeyAction?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: OSType(0x4E4C_4350), id: 1) // 'NLCP'
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }
}
