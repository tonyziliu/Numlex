import AppKit
import SwiftUI
import NumlexCore

/// The sidebar Snippets tab: the pinned clipboard items. Click or Return
/// inserts the snippet into the current sheet as a new line.
struct SnippetsListView: View {
    let model: AppModel
    let store: ClipboardStore

    @State private var selection: ClipboardItem.ID?
    @FocusState private var listFocused: Bool

    private var language: AppLanguage { model.settings.language }
    private func t(_ key: String) -> String { L10n.t(key, language: language) }

    private var snippets: [ClipboardItem] { store.history.snippets }

    var body: some View {
        if snippets.isEmpty {
            VStack(spacing: 6) {
                Text(t("snippets.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text(t("snippets.emptyHint"))
                    .font(Design.labelSmall)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            Spacer(minLength: 0)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(snippets) { item in row(item) }
                }
            }
            .scrollIndicators(.hidden)
            .focusable()
            .focused($listFocused)
            .takesSidebarFocus(.snippets, model: model, focus: $listFocused)
            .onChange(of: listFocused) { _, focused in
                if focused && selection == nil { selection = snippets.first?.id }
            }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.return) {
                guard let item = snippets.first(where: { $0.id == selection }) else { return .ignored }
                insert(item)
                return .handled
            }
        }
    }

    private func row(_ item: ClipboardItem) -> some View {
        HStack(spacing: 4) {
            Button {
                selection = item.id
                insert(item)
            } label: {
                Text(item.text)
                    .font(Design.label)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.selectedSheet == nil)
            .help(t("clipboard.insert"))
            Button {
                store.togglePin(item)
            } label: {
                Image(systemName: "pin.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t("clipboard.unpin"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(selection == item.id ? Color.accentColor.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu {
            Button(t("clipboard.insert")) { insert(item) }
            Button(t("clipboard.copy")) { store.copy(item) }
            Button(t("clipboard.unpin")) { store.togglePin(item) }
            Divider()
            Button(t("clipboard.delete"), role: .destructive) { store.remove(item) }
        }
    }

    private func insert(_ item: ClipboardItem) {
        model.appendLine(item.text)
    }

    private func move(_ delta: Int) {
        let ids = snippets.map(\.id)
        guard !ids.isEmpty else { return }
        let current = selection.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + delta, 0), ids.count - 1) } ?? 0
        selection = ids[next]
    }
}
