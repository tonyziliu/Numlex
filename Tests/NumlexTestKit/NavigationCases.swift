import Foundation
import NumlexCore

private func entry(_ index: Int, _ title: String, folder: String = "General",
                   content: String = "") -> QuickSwitcher.Entry {
    QuickSwitcher.Entry(index: index, title: title, folder: folder, content: content)
}

private func titles(_ entries: [QuickSwitcher.Entry]) -> [String] { entries.map(\.title) }

public let navigationCases: [EngineCase] = [

    EngineCase("nav-nth-follows-sidebar-order") {
        let order = [4, 0, 2]
        try expectEqual(SheetNavigation.nth(1, in: order), 4, "first sidebar row")
        try expectEqual(SheetNavigation.nth(3, in: order), 2, "third sidebar row")
        try expect(SheetNavigation.nth(4, in: order) == nil, "past the end")
        try expect(SheetNavigation.nth(0, in: order) == nil, "zero is not a row")
    },

    EngineCase("nav-step-moves-in-sidebar-order-without-wrapping") {
        let order = [4, 0, 2]
        try expectEqual(SheetNavigation.step(from: 0, by: 1, in: order), 2, "next")
        try expectEqual(SheetNavigation.step(from: 0, by: -1, in: order), 4, "previous")
        try expect(SheetNavigation.step(from: 2, by: 1, in: order) == nil, "no wrap at the end")
        try expect(SheetNavigation.step(from: 4, by: -1, in: order) == nil, "no wrap at the start")
        try expectEqual(SheetNavigation.step(from: 9, by: 1, in: order), 4,
                        "selection in another tab steps to the first row")
        try expectEqual(SheetNavigation.step(from: 9, by: -1, in: order), 2, "or the last row")
        try expect(SheetNavigation.step(from: 0, by: 1, in: []) == nil, "empty tab")
    },

    EngineCase("nav-blank-query-lists-everything-in-order") {
        let all = [entry(0, "B"), entry(1, "A")]
        try expectEqual(QuickSwitcher.rank(all, query: "  "), all, "unchanged")
    },

    EngineCase("nav-title-prefix-beats-substring-beats-subsequence") {
        let all = [entry(0, "Grocery budget"), entry(1, "Budget 2026"), entry(2, "Big update")]
        try expectEqual(titles(QuickSwitcher.rank(all, query: "budg")),
                        ["Budget 2026", "Grocery budget"], "prefix first, then substring")
        try expectEqual(titles(QuickSwitcher.rank(all, query: "bud")).first, "Budget 2026",
                        "a subsequence never outranks a prefix")
        let loose = [entry(0, "Bag of tea"), entry(1, "Bigot")]
        try expectEqual(titles(QuickSwitcher.rank(loose, query: "bgt")), ["Bigot", "Bag of tea"],
                        "subsequence: fewer gaps rank higher")
    },

    EngineCase("nav-title-beats-folder-beats-content") {
        let all = [entry(0, "Notes", content: "rent 1200"),
                   entry(1, "March", folder: "Rent"),
                   entry(2, "Rent split")]
        try expectEqual(titles(QuickSwitcher.rank(all, query: "rent")),
                        ["Rent split", "March", "Notes"], "title, folder, content")
    },

    EngineCase("nav-ranking-is-case-and-diacritic-insensitive-and-stable") {
        let all = [entry(0, "Café"), entry(1, "cafe 2"), entry(2, "Other")]
        try expectEqual(titles(QuickSwitcher.rank(all, query: "CAFE")), ["Café", "cafe 2"],
                        "equal scores keep sidebar order")
        try expect(QuickSwitcher.rank(all, query: "zzz").isEmpty, "no match")
    },

    EngineCase("nav-shortcuts-are-reserved-from-global-hotkeys") {
        for chord in ["⌘k", "⌘[", "⌘]", "⌘1", "⌘9"] + FocusShortcut.allCases.map(\.chord) {
            try expect(HotKeyBindings.appShortcuts.contains(chord), "\(chord) reserved")
        }
        try expectEqual(FocusShortcut.allCases.map(\.chord), ["⌥⌘1", "⌥⌘2", "⌥⌘3", "⌥⌘4"],
                        "focus chords")
    },

    EngineCase("nav-strings-exist-in-all-six-locales") {
        try expectKeysInAllLocales(prefix: "nav.")
    },
]
