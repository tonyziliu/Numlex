import Foundation
import NumlexCore

private func tempHotKeyDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("numlex-hotkeys-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private let optionSpace = KeyCombo(keyCode: 49, modifiers: [.option], key: " ")!
private let controlCommandJ = KeyCombo(keyCode: 38, modifiers: [.control, .command], key: "J")!

public let hotKeyCases: [EngineCase] = [

    EngineCase("hotkeys-have-no-defaults") {
        let b = HotKeyBindings()
        for action in HotKeyAction.allCases {
            try expect(b[action] == nil, "\(action) is unbound by default")
        }
        let dir = try tempHotKeyDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try expectEqual(HotKeyPersistence.load(from: dir), HotKeyBindings(), "missing file means none")
    },

    EngineCase("hotkeys-need-command-control-or-option") {
        try expect(KeyCombo(keyCode: 9, modifiers: [], key: "v") == nil, "plain key")
        try expect(KeyCombo(keyCode: 9, modifiers: [.shift], key: "v") == nil, "shift only")
        try expect(KeyCombo(keyCode: 9, modifiers: [.command], key: "") == nil, "no key")
        try expect(KeyCombo(keyCode: 36, modifiers: [.command], key: "\r") == nil, "Return")
        try expect(KeyCombo(keyCode: 126, modifiers: [.option], key: "\u{F700}") == nil, "arrow")
        try expect(KeyCombo(keyCode: 9, modifiers: [.option], key: "v") != nil, "option is enough")
        try expectEqual(controlCommandJ.display, "⌃⌘J", "glyphs in system order")
        try expectEqual(optionSpace.display, "⌥ ", "space keeps its character")
    },

    EngineCase("hotkeys-set-and-clear-one-action") {
        var b = HotKeyBindings()
        try expect(b.set(optionSpace, for: .toggleApp) == nil, "accepted")
        try expectEqual(b.toggleApp, optionSpace, "bound")
        try expect(b.clipboardPopup == nil, "the other action is untouched")
        b.clear(.toggleApp)
        try expect(b.toggleApp == nil, "cleared")
    },

    EngineCase("hotkeys-reject-a-combination-the-other-action-uses") {
        var b = HotKeyBindings()
        b.set(controlCommandJ, for: .clipboardPopup)
        try expectEqual(b.set(controlCommandJ, for: .toggleApp), .usedBy(.clipboardPopup), "conflict")
        try expect(b.toggleApp == nil, "rejected binding leaves the action unset")
        try expect(b.set(controlCommandJ, for: .clipboardPopup) == nil, "rebinding the same action is fine")
    },

    EngineCase("hotkeys-reject-numlex-menu-shortcuts") {
        var b = HotKeyBindings()
        let commandT = KeyCombo(keyCode: 17, modifiers: [.command], key: "t")!
        let shiftCommandM = KeyCombo(keyCode: 46, modifiers: [.command, .shift], key: "m")!
        try expectEqual(b.set(commandT, for: .clipboardPopup), .appShortcut, "⌘T is Add Subtotal")
        try expectEqual(b.set(shiftCommandM, for: .toggleApp), .appShortcut, "⇧⌘M is Minimal Mode")
        try expectEqual(b, HotKeyBindings(), "nothing bound")
        let shiftCommandV = KeyCombo(keyCode: 9, modifiers: [.command, .shift], key: "v")!
        try expect(b.set(shiftCommandV, for: .clipboardPopup) == nil, "⇧⌘V is free for the user to pick")
    },

    EngineCase("hotkeys-round-trip-through-hotkeys-json-only") {
        let dir = try tempHotKeyDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var b = HotKeyBindings()
        b.set(optionSpace, for: .clipboardPopup)
        b.set(controlCommandJ, for: .toggleApp)
        try expect(HotKeyPersistence.save(b, to: dir), "saved")
        try expectEqual(HotKeyPersistence.load(from: dir), b, "round trip")
        try expectEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path),
                        ["hotkeys.json"], "one file, no temp left, store.json untouched")
    },

    EngineCase("hotkeys-one-bad-entry-keeps-the-other") {
        let dir = try tempHotKeyDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = #"{"clipboardPopup":{"keyCode":9,"modifiers":0,"key":"v"},"#
            + #""toggleApp":{"keyCode":38,"modifiers":9,"key":"j"}}"#
        try Data(json.utf8).write(to: HotKeyPersistence.url(in: dir))
        let b = HotKeyPersistence.load(from: dir)
        try expect(b.clipboardPopup == nil, "modifier-less entry dropped")
        try expectEqual(b.toggleApp, controlCommandJ, "valid entry kept")
        try Data([0, 1]).write(to: HotKeyPersistence.url(in: dir))
        try expectEqual(HotKeyPersistence.load(from: dir), HotKeyBindings(), "garbage file means none")
    },

    EngineCase("hotkey-strings-exist-in-all-six-locales") {
        try expectKeysInAllLocales(prefix: "hotkeys.")
    },
]
