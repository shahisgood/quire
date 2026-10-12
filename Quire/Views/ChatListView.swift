import SwiftUI

struct ChatListView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var searchActive = false
    @State private var showArchived = false
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<String> = []
    @State private var renaming: Chat? = nil
    @State private var renameText = ""
    @State private var newFolderFor: Set<String>? = nil
    @State private var newFolderName = ""
    @State private var renamingFolder: Folder? = nil
    @State private var folderName = ""
    @State private var confirmDelete: Set<String>? = nil
    @State private var share: SharedFile? = nil

    private var isSearching: Bool { query.trimmingCharacters(in: .whitespaces).count > 0 }
    private var isEditing: Bool { editMode.isEditing }
    private var visible: [Chat] { app.chats.filter { $0.archived == showArchived } }

    var body: some View {
        List(selection: $selection) {
            if isSearching {
                searchSections
            } else {
                if app.exportNudgeDue && !showArchived && !isEditing { backupNudge }
                listSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .environment(\.editMode, $editMode)
        .navigationTitle(showArchived ? "Archived" : "Quire")
        .navigationSubtitle(statusText)
        // Pinned under the title rather than hide-on-scroll: the automatic mode keeps the field out of
        // navigation transitions and then drops it in once they finish. The placement is explicit so
        // iOS never moves the field between the top and the bottom bar mid-search, and the toolbar
        // stays put while searching so settings and the menu are always reachable.
        .searchable(text: $query, isPresented: $searchActive, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search every message")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .task(id: query) { await runSearch() }
        .toolbar { toolbarContent }
        .overlay {
            if visible.isEmpty && !isSearching && (showArchived || app.folders.isEmpty) { emptyState }
        }
        .animation(Motion.standard, value: showArchived)
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $renameText)
            Button("Rename") {
                if let c = renaming {
                    let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { app.patchChat(c.id) { $0.title = t; $0.titleAuto = false } }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("New folder", isPresented: Binding(get: { newFolderFor != nil }, set: { if !$0 { newFolderFor = nil } })) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    let f = app.createFolder(name)
                    if let ids = newFolderFor, !ids.isEmpty { move(ids, to: f.id) }
                }
                newFolderFor = nil
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderFor = nil; newFolderName = "" }
        }
        .alert("Rename folder", isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            TextField("Name", text: $folderName)
            Button("Rename") {
                let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let f = renamingFolder, !name.isEmpty { app.renameFolder(f.id, to: name) }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let ids = confirmDelete {
                    withAnimation(Motion.standard) { app.deleteChats(ids) }
                    selection.subtract(ids)
                    Haptics.warning()
                    if isEditing && selection.isEmpty { editMode = .inactive }
                }
                confirmDelete = nil
            }
        } message: {
            Text("Every message and branch is removed from this iPhone. This can't be undone.")
        }
        .sheet(item: $share) { f in ShareSheet(items: [f.url]).presentationDetents([.medium, .large]) }
    }

    private var deleteTitle: String {
        let n = confirmDelete?.count ?? 0
        return n == 1 ? "Delete this chat?" : "Delete \(n) chats?"
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isEditing {
                Button("Done") { withAnimation { editMode = .inactive; selection = [] } }
                    .fontWeight(.semibold)
            } else {
                Button {
                    searchActive = false
                    app.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        if !isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { withAnimation { editMode = .active } } label: { Label("Select chats", systemImage: "checkmark.circle") }
                    Button { newFolderFor = []; newFolderName = "" } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    Divider()
                    Button { app.push(.memory) } label: { Label("Memory", systemImage: "brain") }
                    Toggle(isOn: $showArchived) {
                        Label("Show archived (\(app.chats.filter(\.archived).count))", systemImage: "archivebox")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NewChatButton()
            }
        }
        if isEditing {
            ToolbarItemGroup(placement: .bottomBar) {
                Menu {
                    Button { move(selection, to: nil) } label: { Label("No folder", systemImage: "tray") }
                    ForEach(app.folders) { f in
                        Button { move(selection, to: f.id) } label: { Label(f.name, systemImage: "folder") }
                    }
                    Divider()
                    Button { newFolderFor = selection; newFolderName = "" } label: { Label("New folder…", systemImage: "folder.badge.plus") }
                } label: {
                    Label("Move", systemImage: "folder")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button { archive(selection, to: !showArchived) } label: {
                    Label(showArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button {
                    if let url = try? app.exportChats(selection) { share = SharedFile(url: url) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Menu {
                    Button { app.patchChats(selection) { $0.pinned = true }; finishBulk() } label: { Label("Pin", systemImage: "pin") }
                    Button { app.patchChats(selection) { $0.pinned = false }; finishBulk() } label: { Label("Unpin", systemImage: "pin.slash") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = selection } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    /// One quiet line under the title instead of a capsule in the bottom bar.
    private var statusText: String {
        let count = visible.count
        var parts = ["\(count) \(count == 1 ? "chat" : "chats")"]
        if app.settings.ui.showCosts && app.todayCost > 0 { parts.append("\(Fmt.usd(app.todayCost)) today") }
        if !app.connectivity.online { parts.append("Offline") }
        return parts.joined(separator: " · ")
    }

    // MARK: Sections

    private var backupNudge: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.title3)
                        .foregroundStyle(Color.qAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Time for a backup").font(.subheadline.weight(.semibold)).foregroundStyle(Color.qInk)
                        Text("Your chats live only on this iPhone. Export a copy to Files or iCloud Drive.")
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Button("Back up now") { app.push(.section(.data)) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Later") { withAnimation(Motion.standard) { app.snoozeExportNudge() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.qAccentSoft)
    }

    @ViewBuilder
    private var listSections: some View {
        let inFolders = visible.filter { $0.folderId != nil && app.folder($0.folderId) != nil }
        let loose = visible.filter { $0.folderId == nil || app.folder($0.folderId) == nil }
        ForEach(app.folders) { f in
            let items = inFolders.filter { $0.folderId == f.id }
            if !showArchived || !items.isEmpty {
                Section {
                    if !(f.collapsed ?? false) {
                        ForEach(items) { row($0) }
                        if items.isEmpty {
                            Text("Empty. Move chats here from their menu.")
                                .font(.footnote)
                                .foregroundStyle(Color.qInk2)
                                .selectionDisabled()
                        }
                    }
                } header: {
                    folderHeader(f, count: items.count)
                }
            }
        }
        let pinned = loose.filter(\.pinned)
        if !pinned.isEmpty {
            Section { ForEach(pinned) { row($0) } } header: { SectionLabel(text: "Pinned") }
        }
        let rest = loose.filter { !$0.pinned }
        ForEach(Fmt.DayGroup.allCases, id: \.self) { group in
            let items = rest.filter { Fmt.dayGroup($0.updatedAt) == group }
            if !items.isEmpty {
                Section { ForEach(items) { row($0) } } header: { SectionLabel(text: group.rawValue) }
            }
        }
    }

    private func folderHeader(_ f: Folder, count: Int) -> some View {
        Button {
            withAnimation(Motion.standard) { app.toggleFolder(f.id) }
            Haptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: (f.collapsed ?? false) ? "folder" : "folder.fill")
                    .foregroundStyle(Color.qAccent)
                Text(f.name.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.qInk2)
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2.opacity(0.7))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.qInk2)
                    .rotationEffect(.degrees((f.collapsed ?? false) ? 0 : 90))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.name), \(count) chats")
        .accessibilityValue((f.collapsed ?? false) ? "Collapsed" : "Expanded")
        .contextMenu {
            Button { folderName = f.name; renamingFolder = f } label: { Label("Rename folder", systemImage: "pencil") }
            Button(role: .destructive) { withAnimation { app.deleteFolder(f.id) } } label: {
                Label("Delete folder (keeps chats)", systemImage: "folder.badge.minus")
            }
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let titleMatches = app.chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
        if !titleMatches.isEmpty {
            Section { ForEach(titleMatches) { row($0) } } header: { SectionLabel(text: "Chats") }
        }
        Section {
            if hits.isEmpty {
                HStack(spacing: 8) {
                    if searching { ProgressView().controlSize(.small) }
                    Text(searching ? "Searching…" : (q.count < 2 ? "Type at least two characters" : "Nothing in any message matches “\(q)”"))
                        .font(.subheadline)
                        .foregroundStyle(Color.qInk2)
                }
                .selectionDisabled()
            }
            ForEach(hits) { hit in
                Button { app.openChat(hit.chatId, highlight: hit.messageId) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(app.chat(hit.chatId)?.title ?? "Chat")
                                .font(.system(.subheadline, design: .serif).weight(.semibold))
                                .foregroundStyle(Color.qInk)
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.relative(hit.createdAt))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.qInk2)
                        }
                        Text(highlighted(hit.snippet, q))
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.qRaised)
                .selectionDisabled()
            }
        } header: {
            SectionLabel(text: "Messages")
        }
    }

    private var emptyState: some View {
        EmptyState(title: showArchived ? "Nothing archived" : "No chats yet",
                   message: showArchived ? "Swipe a chat to archive it. It stays searchable." : "Everything you write stays on this iPhone until you export it.") {
            if !showArchived {
                Button { app.startNewChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                    .buttonStyle(.glassProminent)
            }
        }
        .allowsHitTesting(true)
    }

    // MARK: Row

    private func row(_ chat: Chat) -> some View {
        NavigationLink(value: Route.chat(chat.id)) {
            ChatRow(chat: chat)
        }
        .listRowBackground(Color.qRaised)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { archive([chat.id], to: !chat.archived) } label: {
                Label(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            .tint(Color.qTileSlate)
            Button(role: .destructive) { confirmDelete = [chat.id] } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                app.patchChat(chat.id) { $0.pinned.toggle() }
                Haptics.selection()
            } label: {
                Label(chat.pinned ? "Unpin" : "Pin", systemImage: chat.pinned ? "pin.slash" : "pin")
            }
            .tint(Color.qAccent)
        }
        .contextMenu {
            Button { renameText = chat.title; renaming = chat } label: { Label("Rename", systemImage: "pencil") }
            Button { app.patchChat(chat.id) { $0.pinned.toggle() } } label: {
                Label(chat.pinned ? "Unpin" : "Pin", systemImage: chat.pinned ? "pin.slash" : "pin")
            }
            Menu {
                Button { move([chat.id], to: nil) } label: { Label("No folder", systemImage: "tray") }
                ForEach(app.folders) { f in
                    Button { move([chat.id], to: f.id) } label: {
                        Label(f.name, systemImage: chat.folderId == f.id ? "checkmark" : "folder")
                    }
                }
                Divider()
                Button { newFolderFor = [chat.id]; newFolderName = "" } label: { Label("New folder…", systemImage: "folder.badge.plus") }
            } label: {
                Label("Move to folder", systemImage: "folder")
            }
            Button {
                if let id = app.duplicateChat(chat.id) { app.toasts.show("Duplicated", symbol: "plus.square.on.square"); _ = id }
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button {
                if let url = try? app.exportChats([chat.id]) { share = SharedFile(url: url) }
            } label: { Label("Export as JSON", systemImage: "square.and.arrow.up") }
            Button { archive([chat.id], to: !chat.archived) } label: {
                Label(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) { confirmDelete = [chat.id] } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: Actions

    private func archive(_ ids: Set<String>, to archived: Bool) {
        guard !ids.isEmpty else { return }
        withAnimation(Motion.standard) { app.patchChats(ids) { $0.archived = archived } }
        Haptics.tap()
        let n = ids.count
        let noun = n == 1 ? "Chat" : "\(n) chats"
        app.toasts.show(archived ? "\(noun) archived" : "\(noun) unarchived", symbol: "archivebox",
                        action: (label: "Undo", run: { [app] in
                            withAnimation(Motion.standard) { app.patchChats(ids) { $0.archived = !archived } }
                        }))
        finishBulk()
    }

    private func move(_ ids: Set<String>, to folderId: String?) {
        guard !ids.isEmpty else { return }
        withAnimation(Motion.standard) { app.patchChats(ids) { $0.folderId = folderId } }
        Haptics.tap()
        let name = app.folder(folderId)?.name
        app.toasts.show(name.map { "Moved to \($0)" } ?? "Removed from folder", symbol: "folder")
        finishBulk()
    }

    private func finishBulk() {
        guard isEditing else { return }
        selection = []
        withAnimation { editMode = .inactive }
    }

    private func runSearch() async {
        let q = query
        guard q.trimmingCharacters(in: .whitespaces).count >= 2 else {
            hits = []
            searching = false
            return
        }
        searching = true
        try? await Task.sleep(for: .milliseconds(150))   // debounce; cancelled when the query changes
        guard !Task.isCancelled else { return }
        await app.store.flush()
        let found = await Search.run(q, in: app.store.messagesDir)
        guard !Task.isCancelled else { return }
        withAnimation(Motion.quick) { hits = found }
        searching = false
    }

    private func highlighted(_ snippet: String, _ q: String) -> AttributedString {
        var a = AttributedString(snippet)
        if let r = a.range(of: q, options: .caseInsensitive) {
            a[r][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.qInk
            a[r][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Color.qAccentSoft
        }
        return a
    }
}

/// One chat in the list: serif title, two lines of preview, a quiet meta line.
struct ChatRow: View {
    let chat: Chat
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if chat.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.qAccent)
                        .accessibilityLabel("Pinned")
                }
                Text(chat.title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Fmt.relative(chat.updatedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
            Text(preview)
                .font(.subheadline)
                .foregroundStyle(Color.qInk2)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let p = app.preset(chat.systemPromptId) {
                    Text("\(p.icon ?? "◦") \(p.name)")
                        .lineLimit(1)
                    Text("·")
                }
                Text(app.modelName(chat.modelId))
                    .lineLimit(1)
                if !chat.memoryEnabled {
                    Image(systemName: "eye.slash")
                        .accessibilityLabel("Incognito")
                }
                Spacer(minLength: 8)
                if app.settings.ui.showCosts && chat.totalCostUsd > 0 {
                    Text(Fmt.usd(chat.totalCostUsd))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(Color.qInk2.opacity(0.85))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var preview: String {
        if let d = chat.draft, !d.isEmpty { return "Draft: \(d)" }
        if let p = chat.lastPreview, !p.isEmpty { return p }
        return "No messages yet"
    }
}

/// Compose: tap for a new chat; hold for an incognito chat or one started from a persona.
struct NewChatButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Menu {
            Button { app.startNewChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
            Button { app.startNewChat(incognito: true) } label: { Label("Incognito chat", systemImage: "eye.slash") }
            if !app.presets.isEmpty {
                Section("Personas") {
                    ForEach(app.presets) { p in
                        Button { app.startNewChat(persona: p) } label: { Text("\(p.icon ?? "◦")  \(p.name)") }
                    }
                }
            }
            Divider()
            Button { app.push(.section(.prompts)) } label: { Label("Manage personas", systemImage: "person.crop.rectangle.stack") }
        } label: {
            Image(systemName: "square.and.pencil")
        } primaryAction: {
            Haptics.tap()
            app.startNewChat()
        }
        .accessibilityLabel("New chat")
        .accessibilityHint("Hold for incognito or a persona")
    }
}
