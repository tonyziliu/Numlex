import AppKit
import Observation
import NumlexCore

/// The one clipboard history shared by the menu-bar popup, the hotkey
/// popup and the sidebar panel. It owns the pasteboard polling and the
/// `clipboard.json` persistence.
@MainActor
@Observable
final class ClipboardStore {
    private(set) var history: ClipboardHistory

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var timer: Timer?

    init(directory: URL = Persistence.dataDirectory()) {
        self.directory = directory
        self.history = ClipboardPersistence.load(from: directory)
        // Content already on the pasteboard at launch is not captured.
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Idempotent: every main window calls it on appear.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        // Advance even while paused so resuming never captures stale content.
        lastChangeCount = count
        let types = (pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
        guard ClipboardHistory.shouldCapture(typeIdentifiers: types),
              let text = pasteboard.string(forType: .string) else { return }
        if history.record(text) { save() }
    }

    /// Writes the item to the pasteboard and moves it to the top. The new
    /// change count is remembered so the poll does not record our own write.
    func copy(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        history.markUsed(item.id)
        save()
    }

    func togglePin(_ item: ClipboardItem) { history.togglePin(item.id); save() }
    func remove(_ item: ClipboardItem) { history.remove(item.id); save() }
    func clear(keepPinned: Bool) { history.clear(keepPinned: keepPinned); save() }
    func setPaused(_ paused: Bool) { history.setPaused(paused); save() }
    func setCap(_ cap: Int) { history.setCap(cap); save() }

    private func save() {
        ClipboardPersistence.save(history, to: directory)
    }
}
