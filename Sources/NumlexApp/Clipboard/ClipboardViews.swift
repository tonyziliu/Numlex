import AppKit
import SwiftUI
import NumlexCore

/// Search field, pinned-first list and the options menu. Shared by the
/// sidebar panel and both popups so they cannot drift apart.
struct ClipboardListView: View {
    let model: AppModel
    let store: ClipboardStore
    /// Called after an item was copied (the popups close themselves).
    var onDone: (() -> Void)?

    @State private var query = ""

    private var language: AppLanguage { model.settings.language }
    private func t(_ key: String) -> String { L10n.t(key, language: language) }

    private var items: [ClipboardItem] { store.history.search(query) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(t("clipboard.search"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(Design.label)
                optionsMenu
            }
            if !store.history.settings.captureEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("clipboard.enableNotice"))
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(t("clipboard.enable")) { store.enableCapture() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if store.history.settings.isPaused {
                Text(t("clipboard.pausedNote"))
                    .font(Design.labelSmall)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if items.isEmpty {
                Text(t(query.isEmpty ? "clipboard.empty" : "clipboard.noMatches"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in row(item) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .onExitCommand { onDone?() }
    }

    private func row(_ item: ClipboardItem) -> some View {
        HStack(spacing: 4) {
            Button {
                copy(item)
            } label: {
                Text(item.text)
                    .font(Design.label)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t("clipboard.copy"))
            iconButton(item.isPinned ? "pin.fill" : "pin", help: pinLabel(item)) {
                store.togglePin(item)
            }
            iconButton("text.append", help: t("clipboard.insert")) {
                model.appendLine(item.text)
            }
            .disabled(model.selectedSheet == nil)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(item.isPinned ? Color.accentColor.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            Button(t("clipboard.copy")) { copy(item) }
            Button(t("clipboard.insert")) { model.appendLine(item.text) }
            Button(pinLabel(item)) { store.togglePin(item) }
            Divider()
            Button(t("clipboard.delete"), role: .destructive) { store.remove(item) }
        }
    }

    private func copy(_ item: ClipboardItem) {
        store.copy(item)
        onDone?()
    }

    private func pinLabel(_ item: ClipboardItem) -> String {
        t(item.isPinned ? "clipboard.unpin" : "clipboard.pin")
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var optionsMenu: some View {
        Menu {
            Button(t(store.history.settings.isPaused ? "clipboard.resume" : "clipboard.pause")) {
                store.setPaused(!store.history.settings.isPaused)
            }
            Picker(t("clipboard.limit"), selection: Binding(
                get: { store.history.settings.cap },
                set: { store.setCap($0) })) {
                ForEach(ClipboardSettings.capOptions, id: \.self) { Text("\($0)").tag($0) }
            }
            Divider()
            Button(t("clipboard.clearUnpinned")) { store.clear(keepPinned: true) }
            Button(t("clipboard.clearAll"), role: .destructive) { store.clear(keepPinned: false) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// The popup used by the menu-bar extra and the global hotkey panel.
struct ClipboardPopupView: View {
    let model: AppModel
    let store: ClipboardStore
    var onDone: () -> Void

    static let size = CGSize(width: 340, height: 420)

    var body: some View {
        ClipboardListView(model: model, store: store, onDone: onDone)
            .padding(10)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(.regularMaterial)
    }
}

/// The menu-bar extra's content. A pick closes only the window hosting
/// this view, never whichever window happens to be key.
struct ClipboardMenuBarView: View {
    let model: AppModel
    let store: ClipboardStore

    @State private var host = HostWindow()

    var body: some View {
        ClipboardPopupView(model: model, store: store, onDone: { host.window?.orderOut(nil) })
            .background(HostWindowReader(host: host))
    }
}

@MainActor
private final class HostWindow {
    weak var window: NSWindow?
}

private struct HostWindowReader: NSViewRepresentable {
    let host: HostWindow

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { host.window = view.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if host.window == nil { host.window = view.window }
    }
}
