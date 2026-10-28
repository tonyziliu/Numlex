import Foundation

/// Pure planning for "insert this clipboard item into the sheet as a new line".
public enum ClipboardInsertion {
    public struct Plan: Equatable, Sendable {
        public var content: String
        public var edit: NotebookEdit
        /// UTF-16 offset at the end of the new content.
        public var caret: Int
    }

    /// Appends `text` at the end of `content`. U+FFFC is stripped because it
    /// is reserved for answer tokens. Nil when there is nothing to insert.
    public static func appendPlan(content: String, text: String) -> Plan? {
        var clean = text.replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        while clean.hasSuffix("\n") { clean.removeLast() }
        let lead = (content.isEmpty || content.hasSuffix("\n")) ? "" : "\n"
        let replacement = lead + clean
        guard !replacement.isEmpty else { return nil }
        let end = (content as NSString).length
        let newContent = content + replacement
        return Plan(content: newContent,
                    edit: NotebookEdit(range: NSRange(location: end, length: 0), replacement: replacement),
                    caret: (newContent as NSString).length)
    }
}
