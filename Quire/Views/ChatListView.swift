import SwiftUI

struct ChatListView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var showArchived = false
    @State private var renaming: Chat? = nil
    @State private var renameText = ""

    private var visible: [Chat] { app.chats.filter { $0.archived == showArchived } }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                listSections
            } else {
                searchSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle(showArchived ? "Archived" : "Quire")
        .searchable(text: $query, prompt: "Search chats and messages")
        .task(id: query) { await runSearch() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Route.settings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show archived", systemImage: "archivebox", isOn: $showArchived)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.startNewChat() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if app.settings.ui.showCosts && app.todayCost > 0 {
                Text("Today \(Fmt.usd(app.todayCost))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .overlay {
            if visible.isEmpty && query.isEmpty {
                ContentUnavailableView {
                    Label(showArchived ? "No archived chats" : "No chats yet", systemImage: "text.bubble")
                } description: {
                    Text(showArchived ? "Archived chats appear here." : "Start one with the compose button.")
                }
            }
        }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Save") {
                if let c = renaming {
                    let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { app.patchChat(c.id) { $0.title = t; $0.titleAuto = false } }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var listSections: some View {
        let pinned = visible.filter(\.pinned)
        if !pinned.isEmpty {
            Section("Pinned") { ForEach(pinned) { row($0) } }
        }
        let rest = visible.filter { !$0.pinned }
        ForEach(Fmt.DayGroup.allCases, id: \.self) { group in
            let items = rest.filter { Fmt.dayGroup($0.updatedAt) == group }
            if !items.isEmpty {
                Section(group.rawValue) { ForEach(items) { row($0) } }
            }
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let titleMatches = app.chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
        if !titleMatches.isEmpty {
            Section("Chats") { ForEach(titleMatches) { row($0) } }
        }
        Section {
            if hits.isEmpty {
                Text(searching ? "Searching…" : (q.count < 2 ? "Type at least two characters" : "No messages match"))
                    .foregroundStyle(Color.qInk2)
            }
            ForEach(hits) { hit in
                Button { app.openChat(hit.chatId, highlight: hit.messageId) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.chat(hit.chatId)?.title ?? "Chat")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.qInk)
                        Text(highlighted(hit.snippet, q))
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(3)
                    }
                }
                .listRowBackground(Color.qRaised)
            }
        } header: {
            Text("Messages")
        }
    }

    private func row(_ chat: Chat) -> some View {
        NavigationLink(value: Route.chat(chat.id)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.qInk)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.relative(chat.updatedAt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(chat.lastPreview ?? " ")
                        .font(.subheadline)
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if app.settings.ui.showCosts && chat.totalCostUsd > 0 {
                        Text(Fmt.usd(chat.totalCostUsd))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.qInk2)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.qRaised)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { app.deleteChats([chat.id]) } label: { Label("Delete", systemImage: "trash") }
            Button { app.patchChat(chat.id) { $0.archived.toggle() } } label: {
                Label(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            .tint(.gray)
        }
        .swipeActions(edge: .leading) {
            Button { app.patchChat(chat.id) { $0.pinned.toggle() } } label: {
                Label(chat.pinned ? "Unpin" : "Pin", systemImage: chat.pinned ? "pin.slash" : "pin")
            }
            .tint(Color.qAccent)
        }
        .contextMenu {
            Button { renameText = chat.title; renaming = chat } label: { Label("Rename", systemImage: "pencil") }
            Button { app.patchChat(chat.id) { $0.pinned.toggle() } } label: {
                Label(chat.pinned ? "Unpin" : "Pin", systemImage: chat.pinned ? "pin.slash" : "pin")
            }
            Button { app.patchChat(chat.id) { $0.archived.toggle() } } label: {
                Label(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) { app.deleteChats([chat.id]) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Search

    private func runSearch() async {
        let q = query
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { hits = []; searching = false; return }
        searching = true
        try? await Task.sleep(for: .milliseconds(150))   // debounce; cancelled when the query changes
        guard !Task.isCancelled else { return }
        await app.store.flush()
        let found = await Search.run(q, in: app.store.messagesDir)
        guard !Task.isCancelled else { return }
        hits = found
        searching = false
    }

    private func highlighted(_ snippet: String, _ q: String) -> AttributedString {
        var a = AttributedString(snippet)
        if let r = a.range(of: q, options: .caseInsensitive) {
            a[r][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.qInk
            a[r][AttributeScopes.SwiftUIAttributes.FontAttribute.self] = Font.footnote.bold()
        }
        return a
    }
}
