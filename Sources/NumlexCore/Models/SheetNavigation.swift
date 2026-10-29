import Foundation

/// Keyboard navigation over the sheets in sidebar order: Cmd+1..9 and
/// Cmd+[ / Cmd+]. `order` holds global sheet indices as the sidebar lists them.
public enum SheetNavigation {
    /// The global index of the nth sheet (1-based), or nil past the end.
    public static func nth(_ n: Int, in order: [Int]) -> Int? {
        order.indices.contains(n - 1) ? order[n - 1] : nil
    }

    /// The previous (`delta` -1) or next (+1) sheet, without wrapping. A
    /// selection outside `order` steps to its first or last sheet.
    public static func step(from selected: Int, by delta: Int, in order: [Int]) -> Int? {
        guard let position = order.firstIndex(of: selected) else {
            return delta < 0 ? order.last : order.first
        }
        let next = position + delta
        return order.indices.contains(next) ? order[next] : nil
    }
}

/// The focus shortcuts (Option-Command-1..4).
public enum FocusShortcut: String, CaseIterable, Sendable {
    case editor, sheetList, snippets, clipboard

    public var key: Character {
        switch self {
        case .editor: return "1"
        case .sheetList: return "2"
        case .snippets: return "3"
        case .clipboard: return "4"
        }
    }

    /// The same notation as `HotKeyBindings.appShortcuts`.
    public var chord: String { "⌥⌘\(key)" }
}

/// The Cmd+K quick switcher's ranking.
public enum QuickSwitcher {
    public struct Entry: Equatable, Sendable {
        public let index: Int
        public let title: String
        public let folder: String
        public let content: String

        public init(index: Int, title: String, folder: String, content: String) {
            self.index = index
            self.title = title
            self.folder = folder
            self.content = content
        }
    }

    /// Entries matching `query`, best first; ties keep the input order. Title
    /// matches beat folder matches, which beat content matches. Within the
    /// title a prefix beats a substring, which beats a subsequence with gaps.
    /// A blank query returns every entry in input order.
    public static func rank(_ entries: [Entry], query: String) -> [Entry] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return entries }
        return entries.enumerated()
            .compactMap { offset, entry in score(entry, q).map { (offset, entry, $0) } }
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .map(\.1)
    }

    private static func score(_ entry: Entry, _ q: String) -> Int? {
        let title = fold(entry.title)
        if title.hasPrefix(q) { return 4000 }
        if let r = title.range(of: q) { return 3000 - title.distance(from: title.startIndex, to: r.lowerBound) }
        if let gaps = subsequenceGaps(q, in: title) { return 2000 - gaps }
        if fold(entry.folder).contains(q) { return 1000 }
        if fold(entry.content).contains(q) { return 500 }
        return nil
    }

    /// The number of skipped characters when `needle` is a subsequence of
    /// `haystack`, or nil when it is not.
    private static func subsequenceGaps(_ needle: String, in haystack: String) -> Int? {
        var gaps = 0
        var rest = needle[...]
        var started = false
        for ch in haystack {
            guard let first = rest.first else { break }
            if ch == first {
                rest = rest.dropFirst()
                started = true
            } else if started {
                gaps += 1
            }
        }
        return rest.isEmpty ? min(gaps, 999) : nil
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
