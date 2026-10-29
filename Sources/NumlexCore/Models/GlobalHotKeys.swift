import Foundation

/// Modifier keys of a global hotkey, independent of AppKit and Carbon.
public struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let shift = HotKeyModifiers(rawValue: 1 << 2)
    public static let command = HotKeyModifiers(rawValue: 1 << 3)

    /// The macOS menu glyphs in the system order.
    public var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

/// One recorded key combination. `keyCode` is the hardware virtual key code
/// Carbon registers; `key` is the layout character, used for display and for
/// comparing against the app's own menu shortcuts.
public struct KeyCombo: Codable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: HotKeyModifiers
    public let key: String

    /// Nil unless Command, Control or Option is held: a global hotkey made of
    /// plain or shifted keys would swallow ordinary typing everywhere. Also nil
    /// for keys without a printable character (Return, Tab, arrows, function
    /// keys), which could not be shown.
    public init?(keyCode: UInt32, modifiers: HotKeyModifiers, key: String) {
        let key = key.lowercased()
        guard !key.isEmpty,
              key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0)
                  && !(0xF700...0xF8FF).contains($0.value) }),
              !modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    public var display: String { modifiers.symbols + key.uppercased() }

    private enum CodingKeys: String, CodingKey { case keyCode, modifiers, key }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let combo = KeyCombo(keyCode: try c.decode(UInt32.self, forKey: .keyCode),
                                   modifiers: try c.decode(HotKeyModifiers.self, forKey: .modifiers),
                                   key: try c.decode(String.self, forKey: .key)) else {
            throw DecodingError.dataCorruptedError(forKey: .key, in: c,
                                                   debugDescription: "not a valid hotkey")
        }
        self = combo
    }
}

public enum HotKeyAction: String, CaseIterable, Codable, Sendable {
    case clipboardPopup
    case toggleApp
}

/// The user's global hotkeys. Nothing is bound by default.
public struct HotKeyBindings: Codable, Equatable, Sendable {
    public private(set) var clipboardPopup: KeyCombo?
    public private(set) var toggleApp: KeyCombo?

    public init() {}

    public enum Rejection: Equatable, Sendable {
        /// The other global hotkey already uses this combination.
        case usedBy(HotKeyAction)
        /// One of Numlex's own menu shortcuts uses this combination.
        case appShortcut
    }

    /// Numlex's own menu shortcuts. A global hotkey on one of them would fire
    /// instead of the menu command while Numlex is frontmost.
    public static let appShortcuts: Set<String> = {
        var keys: Set<String> = [
            "⌘n", "⌘t", "⇧⌘t", "⌘r", "⌘i", "⌘e", "⌘d", "⌘p", "⇧⌘m",
            "⌘,", "⌘q", "⌘w", "⌘h", "⌘m", "⌘c", "⌘v", "⌘x", "⌘z", "⇧⌘z", "⌘a", "⌃⌘s",
            "⌘k", "⌘[", "⌘]",
        ]
        keys.formUnion((1...9).map { "⌘\($0)" })
        keys.formUnion(FocusShortcut.allCases.map(\.chord))
        return keys
    }()

    public subscript(action: HotKeyAction) -> KeyCombo? {
        switch action {
        case .clipboardPopup: return clipboardPopup
        case .toggleApp: return toggleApp
        }
    }

    /// Binds `combo` to `action`, or returns why it cannot be used. A
    /// rejected combination leaves the bindings unchanged.
    @discardableResult
    public mutating func set(_ combo: KeyCombo, for action: HotKeyAction) -> Rejection? {
        if let other = HotKeyAction.allCases.first(where: { $0 != action && self[$0] == combo }) {
            return .usedBy(other)
        }
        if Self.appShortcuts.contains(combo.modifiers.symbols + combo.key) {
            return .appShortcut
        }
        assign(combo, to: action)
        return nil
    }

    public mutating func clear(_ action: HotKeyAction) {
        assign(nil, to: action)
    }

    private mutating func assign(_ combo: KeyCombo?, to action: HotKeyAction) {
        switch action {
        case .clipboardPopup: clipboardPopup = combo
        case .toggleApp: toggleApp = combo
        }
    }

    private enum CodingKeys: String, CodingKey { case clipboardPopup, toggleApp }

    /// A combination that no longer decodes is dropped on its own, so one bad
    /// entry never unbinds the other.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clipboardPopup = try? c.decodeIfPresent(KeyCombo.self, forKey: .clipboardPopup)
        toggleApp = try? c.decodeIfPresent(KeyCombo.self, forKey: .toggleApp)
    }
}

/// Reads and writes `hotkeys.json` beside `clipboard.json`, outside `StorePayload`.
public enum HotKeyPersistence {
    public static let fileName = "hotkeys.json"

    public static func url(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// A missing or unreadable file means no hotkeys.
    public static func load(from directory: URL) -> HotKeyBindings {
        guard let data = try? Data(contentsOf: url(in: directory)),
              let bindings = try? JSONDecoder().decode(HotKeyBindings.self, from: data)
        else { return HotKeyBindings() }
        return bindings
    }

    @discardableResult
    public static func save(_ bindings: HotKeyBindings, to directory: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(bindings) else { return false }
        return (try? data.write(to: url(in: directory), options: .atomic)) != nil
    }
}
