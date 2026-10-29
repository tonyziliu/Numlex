import AppKit
import SwiftUI
import NumlexCore

/// Published only by a main window whose editor is mounted, so the
/// navigation commands are disabled in Settings and during the welcome.
struct SheetNavigationContext {
    var model: AppModel
    var showsSwitcher: Binding<Bool>
}

private struct SheetNavigationContextKey: FocusedValueKey {
    typealias Value = SheetNavigationContext
}

extension FocusedValues {
    var sheetNavigationContext: SheetNavigationContext? {
        get { self[SheetNavigationContextKey.self] }
        set { self[SheetNavigationContextKey.self] = newValue }
    }
}

struct NavigationCommands: Commands {
    @FocusedValue(\.sheetNavigationContext) private var context
    var language: AppLanguage

    private func t(_ key: String) -> String { L10n.t(key, language: language) }

    var body: some Commands {
        CommandMenu(t("nav.menu")) {
            Button(t("nav.quickSwitcher")) { context?.showsSwitcher.wrappedValue = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(context == nil)
            Divider()
            Button(t("nav.previousSheet")) { context?.model.selectAdjacent(-1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(context == nil)
            Button(t("nav.nextSheet")) { context?.model.selectAdjacent(1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(context == nil)
            if let model = context?.model {
                let order = model.sidebarOrder.prefix(9)
                if !order.isEmpty { Divider() }
                ForEach(Array(order.enumerated()), id: \.offset) { offset, index in
                    Button(model.sheets[index].title) { model.selectNth(offset + 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(offset + 1)")), modifiers: .command)
                }
            }
            Divider()
            ForEach(FocusShortcut.allCases, id: \.self) { target in
                Button(t("nav.focus.\(target.rawValue)")) { focus(target) }
                    .keyboardShortcut(KeyEquivalent(target.key), modifiers: [.command, .option])
                    .disabled(context == nil)
            }
        }
    }

    private func focus(_ target: FocusShortcut) {
        guard let model = context?.model else { return }
        switch target {
        case .editor: NotebookFocus.focusEditor(in: NSApp.keyWindow)
        case .sheetList: model.requestSidebarFocus(.sheets)
        case .snippets: model.requestSidebarFocus(.snippets)
        case .clipboard: model.requestSidebarFocus(.clipboard)
        }
    }
}

extension AppModel {
    /// Shows `panel` in the sidebar and asks it to take keyboard focus.
    @MainActor
    func requestSidebarFocus(_ panel: SidebarPanel) {
        sidebarPanel = panel
        sidebarFocusRequest = panel
        // A panel with nothing focusable (empty Snippets, collapsed sidebar)
        // never consumes the request; expire it so it cannot fire later.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if self?.sidebarFocusRequest == panel { self?.sidebarFocusRequest = nil }
        }
    }
}

enum NotebookFocus {
    /// Makes the window's notebook editor first responder, keeping its caret.
    static func focusEditor(in window: NSWindow?) {
        guard let window, let editor = find(in: window.contentView) else { return }
        window.makeFirstResponder(editor)
    }

    private static func find(in view: NSView?) -> NotebookTextView? {
        guard let view else { return nil }
        if let editor = view as? NotebookTextView { return editor }
        for child in view.subviews {
            if let editor = find(in: child) { return editor }
        }
        return nil
    }
}

extension View {
    /// Takes keyboard focus when the model asks `panel` to be focused.
    func takesSidebarFocus(_ panel: SidebarPanel, model: AppModel,
                           focus: FocusState<Bool>.Binding) -> some View {
        onChange(of: model.sidebarFocusRequest, initial: true) { _, request in
            guard let request, request == panel else { return }
            model.sidebarFocusRequest = nil
            // The panel may have just been mounted; focus lands a turn later.
            DispatchQueue.main.async { focus.wrappedValue = true }
        }
    }
}

/// Per-window navigation host: publishes the command context and presents
/// the quick switcher.
struct SheetNavigationHost: ViewModifier {
    let model: AppModel
    let isEnabled: Bool
    @State private var showsSwitcher = false

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.sheetNavigationContext,
                               isEnabled ? SheetNavigationContext(model: model,
                                                                  showsSwitcher: $showsSwitcher) : nil)
            .sheet(isPresented: $showsSwitcher) {
                QuickSwitcherView(model: model) { showsSwitcher = false }
            }
    }
}

/// Cmd+K: type to filter sheets by title, folder and content; arrows move,
/// Return opens, Esc closes. The first row creates a new sheet.
struct QuickSwitcherView: View {
    let model: AppModel
    var onDone: () -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private enum Row: Hashable {
        case newSheet
        case sheet(index: Int)
    }

    private var language: AppLanguage { model.settings.language }
    private func t(_ key: String) -> String { L10n.t(key, language: language) }

    private var entries: [QuickSwitcher.Entry] {
        let folderNames = Dictionary(uniqueKeysWithValues: model.folders.map { ($0.id, $0.title) })
        let general = t("folderGeneral")
        let groups: [UUID?] = [nil] + model.folders.map(\.id)
        return groups.flatMap { group in
            model.sheets(in: group).map { index, sheet in
                QuickSwitcher.Entry(index: index, title: sheet.title,
                                    folder: group.flatMap { folderNames[$0] } ?? general,
                                    content: sheet.content)
            }
        }
    }

    private var ranked: [QuickSwitcher.Entry] { QuickSwitcher.rank(entries, query: query) }

    var body: some View {
        let ranked = self.ranked
        let rows: [Row] = [.newSheet] + ranked.map { .sheet(index: $0.index) }
        let current = min(highlighted, rows.count - 1)
        VStack(alignment: .leading, spacing: 8) {
            TextField(t("nav.searchSheets"), text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { open(rows[current]) }
                .onKeyPress(.upArrow) { highlighted = max(current - 1, 0); return .handled }
                .onKeyPress(.downArrow) { highlighted = min(current + 1, rows.count - 1); return .handled }
                .onKeyPress(.escape) { onDone(); return .handled }
                .onChange(of: query) { highlighted = ranked.isEmpty ? 0 : 1 }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        row(.newSheet, title: t("newSheet"), subtitle: nil,
                            symbol: "plus", isHighlighted: current == 0)
                        ForEach(Array(ranked.enumerated()), id: \.element.index) { offset, entry in
                            row(.sheet(index: entry.index), title: entry.title, subtitle: entry.folder,
                                symbol: "doc.text", isHighlighted: current == offset + 1)
                        }
                        if ranked.isEmpty && !query.isEmpty {
                            Text(t("clipboard.noMatches"))
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 12)
                        }
                    }
                }
                .onChange(of: current) { _, value in proxy.scrollTo(rows[value]) }
            }
        }
        .padding(12)
        .frame(width: 420, height: 360)
        .onAppear { highlighted = model.sheets.isEmpty ? 0 : 1; fieldFocused = true }
        .onExitCommand(perform: onDone)
    }

    private func row(_ row: Row, title: String, subtitle: String?, symbol: String,
                     isHighlighted: Bool) -> some View {
        Button { open(row) } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(row)
    }

    private func open(_ row: Row) {
        onDone()
        switch row {
        case .newSheet:
            model.newSheet()
        case .sheet(let index):
            model.select(index: index)
            model.focusSheetID = model.selectedSheet?.id
        }
    }
}
