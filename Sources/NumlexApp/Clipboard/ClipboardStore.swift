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
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init(directory: URL = Persistence.dataDirectory()) {
        self.directory = directory
        self.history = ClipboardPersistence.load(from: directory)
        // Content already on the pasteboard at launch is not captured.
        self.lastChangeCount = NSPasteboard.general.changeCount
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// Idempotent: every main window calls it on appear.
    func start() {
        guard timer == nil, history.settings.captureEnabled else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // .common keeps capture running while a menu or the menu-bar window tracks events.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The user accepted the unencrypted-storage notice. Content copied
    /// before this point is not captured.
    func enableCapture() {
        history.setCaptureEnabled(true)
        lastChangeCount = NSPasteboard.general.changeCount
        save()
        start()
    }

    /// Generous UTF-8 bound (4 bytes per UTF-16 unit of the text limit), so
    /// oversize copies are skipped without being read as a String.
    private static let maxTextBytes = ClipboardHistory.maxTextLength * 4

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        // Advance even while paused so resuming never captures stale content.
        lastChangeCount = count
        let types = (pasteboard.pasteboardItems ?? []).flatMap { $0.types.map(\.rawValue) }
        guard ClipboardHistory.shouldCapture(typeIdentifiers: types),
              let data = pasteboard.data(forType: .string),
              data.count <= Self.maxTextBytes,
              let text = String(data: data, encoding: .utf8) ?? pasteboard.string(forType: .string)
        else { return }
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
    func clear(keepPinned: Bool) { history.clear(keepPinned: keepPinned); flush() }
    func setPaused(_ paused: Bool) { history.setPaused(paused); flush() }
    func setCap(_ cap: Int) { history.setCap(cap); save() }

    /// Trailing debounce. The encode and file write run on a serial queue
    /// from a value copy of the history, so the main thread never touches
    /// the file and there is no shared mutable state.
    private func save() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            let snapshot = self.history
            let directory = self.directory
            Self.writeQueue.async { ClipboardPersistence.save(snapshot, to: directory) }
        }
    }

    /// Writes now and waits, so a pause, clear or quit is on disk before
    /// the call returns. The serial queue keeps it ordered after any
    /// pending debounced write.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        let snapshot = history
        let directory = directory
        Self.writeQueue.sync { ClipboardPersistence.save(snapshot, to: directory) }
    }

    private static let writeQueue = DispatchQueue(label: "numlex.clipboard.write")
}
