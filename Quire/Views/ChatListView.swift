import SwiftUI

struct ChatListView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var searchOpen = false
    @FocusState private var searchFocused: Bool
    @State private var emptyShown = false
    @State private var showArchived = false
    @State private var editMode: EditMode = .inactive
    @State private var selection: Set<String> = []
    @State private var sheets = ListSheets()
    @State private var projectsExpanded = false
    @State private var confirmBulkDelete = false

    private static let collapsedProjects = 4

    private var isSearching: Bool { query.trimmingCharacters(in: .whitespaces).count > 0 }
    private var isEditing: Bool { editMode.isEditing }
    private var visible: [Chat] { app.chats.filter { $0.archived == showArchived } }
    /// What the main list shows: chats outside any project (each project has its own screen).
    /// Archived shows everything archived, with the project named on each row.
    private var listed: [Chat] { showArchived ? visible : visible.filter { app.project(of: $0) == nil } }

    /// Not while archived or selecting, and not on a first run, where the empty state offers both.
    private var showsProjects: Bool {
        !showArchived && !isEditing && !(listed.isEmpty && app.folders.isEmpty)
    }

    private var bulkDeleteTitle: String {
        selection.count == 1 ? "Delete this chat?" : "Delete \(selection.count) chats?"
    }

    var body: some View {
        List(selection: $selection) {
            if isSearching {
                searchSections
            } else {
                if app.exportNudgeDue && !showArchived && !isEditing { backupNudge }
                if showsProjects { projectSections }
                listSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .environment(\.editMode, $editMode)
        .navigationTitle(showArchived ? "Archived" : "Quire")
        .navigationSubtitle(statusText)
        // Search is a button. It slides its own field in where the title bar was (which steps aside),
        // rather than using the system search controller, whose bar dropped in late and once left
        // the toolbar half-empty.
        .toolbar(searchOpen ? .hidden : .visible, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if searchOpen {
                searchBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: query) { await runSearch() }
        .toolbar { toolbarContent }
        .overlay {
            if listed.isEmpty && !isSearching && (showArchived || app.folders.isEmpty) { emptyState }
        }
        .animation(Motion.standard, value: showArchived)
        .animation(Motion.standard, value: isEditing)
        .listSheets(sheets)
        // Deleting a selection ends selecting in the same update, so the list changes once.
        .confirmationDialog(bulkDeleteTitle, isPresented: $confirmBulkDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let ids = selection
                withAnimation(Motion.standard) {
                    app.deleteChats(ids)
                    selection = []
                    editMode = .inactive
                }
                Haptics.warning()
            }
        } message: {
            Text("Every message and branch is removed from this iPhone. This can't be undone.")
        }
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
                    app.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        if !isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openSearch) { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
                    .accessibilityHint("Searches every message")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { withAnimation { editMode = .active } } label: { Label("Select chats", systemImage: "checkmark.circle") }
                    Button { sheets.editor = ProjectEditorRequest(openAfterCreate: true) } label: { Label("New project", systemImage: "folder.badge.plus") }
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
                ProjectMoveMenu(app, ids: selection, title: "Move", onMoved: finishBulk) {
                    let ids = selection
                    finishBulk()
                    sheets.editor = ProjectEditorRequest(moving: ids)
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button { ChatOps.archive(app, selection, to: !showArchived); finishBulk() } label: {
                    Label(showArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button {
                    if let url = try? app.exportChats(selection) { sheets.share = SharedFile(url: url) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Menu {
                    Button { withAnimation(Motion.standard) { app.patchChats(selection) { $0.pinned = true } }; finishBulk() } label: { Label("Pin", systemImage: "pin") }
                    Button { withAnimation(Motion.standard) { app.patchChats(selection) { $0.pinned = false } }; finishBulk() } label: { Label("Unpin", systemImage: "pin.slash") }
                    Divider()
                    Button(role: .destructive) { confirmBulkDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(selection.isEmpty)
            }
        }
    }

    // MARK: Search

    /// A glass field with the keyboard up and Cancel beside it. Results replace the list as you type
    /// (titles first, then matches inside messages); with nothing typed, your chats stay in view.
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.qInk2)
                TextField("Search every message", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Color.qInk)
                    .tint(Color.qAccent)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.qInk2)
                    }
                    .buttonStyle(.plain)
                    .transition(.pop)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .glassEffect(.regular, in: .capsule)

            Button("Cancel", action: closeSearch)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.qAccent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background {
            // The list fades out under the field instead of running into it.
            LinearGradient(stops: [.init(color: Color.qBase, location: 0), .init(color: Color.qBase, location: 0.7),
                                   .init(color: Color.qBase.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
        .animation(Motion.quick, value: query.isEmpty)
    }

    private func openSearch() {
        Haptics.selection()
        withAnimation(Motion.drawerIn) { searchOpen = true }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            searchFocused = true
        }
    }

    private func closeSearch() {
        searchFocused = false
        withAnimation(Motion.drawerOut) {
            searchOpen = false
            query = ""
        }
    }

    /// One quiet line under the title instead of a capsule in the bottom bar.
    private var statusText: String {
        let count = visible.count
        var parts = ["\(count) \(count == 1 ? "chat" : "chats")"]
        if !showArchived && !app.folders.isEmpty {
            parts.append("\(app.folders.count) \(app.folders.count == 1 ? "project" : "projects")")
        }
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

    // MARK: Projects

    /// Most recently used first. A long list folds to its first few; with none yet, the one row
    /// invites the first.
    private var projectSections: some View {
        let all = app.projects
        let folds = all.count > Self.collapsedProjects + 1
        let open = !folds || projectsExpanded
        return Section {
            ForEach(open ? all : Array(all.prefix(Self.collapsedProjects))) { projectRow($0) }
            if folds { foldRow(hidden: all.count - Self.collapsedProjects, open: open) }
            newProjectRow(invite: all.isEmpty)
        } header: {
            SectionLabel(text: "Projects")
        }
    }

    private func projectRow(_ p: Project) -> some View {
        NavigationLink(value: Route.project(p.id)) {
            ProjectRow(project: p)
        }
        .listRowBackground(Color.qRaised)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Not role: .destructive, which tells the list the row is already gone; deleting asks first.
            Button { sheets.deletingProject = p } label: { Label("Delete", systemImage: "trash") }
                .tint(.red)
            Button { sheets.editor = ProjectEditorRequest(project: p) } label: { Label("Edit", systemImage: "pencil") }
                .tint(Color.qTileSlate)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Haptics.tap()
                app.startNewChat(projectId: p.id)
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
            }
            .tint(p.tintColor)
        }
        .contextMenu {
            Button { app.startNewChat(projectId: p.id) } label: { Label("New chat", systemImage: "square.and.pencil") }
            Button { sheets.editor = ProjectEditorRequest(project: p) } label: { Label("Edit project", systemImage: "pencil") }
            Button { sheets.instructionsFor = p } label: {
                Label(p.hasInstructions ? "Edit instructions" : "Add instructions", systemImage: "text.quote")
            }
            Divider()
            Button(role: .destructive) { sheets.deletingProject = p } label: {
                Label("Delete project…", systemImage: "trash")
            }
        }
    }

    private func foldRow(hidden: Int, open: Bool) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.standard) { projectsExpanded.toggle() }
        } label: {
            HStack {
                Text(open ? "Show fewer" : "Show \(hidden) more")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.qInk2)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.qInk2)
                    .rotationEffect(.degrees(open ? 180 : 0))
            }
            .contentShape(.rect)
        }
        .listRowBackground(Color.qRaised)
    }

    private func newProjectRow(invite: Bool) -> some View {
        Button {
            Haptics.tap()
            sheets.editor = ProjectEditorRequest(openAfterCreate: true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.qAccent)
                    .frame(width: 38, height: 38)
                    .background(Color.qAccentSoft, in: .rect(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("New project")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.qAccent)
                    if invite {
                        Text("Group related chats, with instructions they all follow")
                            .font(.caption)
                            .foregroundStyle(Color.qInk2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .listRowBackground(Color.qRaised)
    }

    // MARK: Chats

    @ViewBuilder
    private var listSections: some View {
        let pinned = listed.filter(\.pinned)
        if !pinned.isEmpty {
            Section { ForEach(pinned) { row($0) } } header: { SectionLabel(text: "Pinned") }
        }
        let rest = listed.filter { !$0.pinned }
        ForEach(Fmt.DayGroup.allCases, id: \.self) { group in
            let items = rest.filter { Fmt.dayGroup($0.updatedAt) == group }
            if !items.isEmpty {
                Section { ForEach(items) { row($0) } } header: { SectionLabel(text: group.rawValue) }
            }
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let projectMatches = app.projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
        if !projectMatches.isEmpty {
            Section { ForEach(projectMatches) { projectRow($0) } } header: { SectionLabel(text: "Projects") }
        }
        let titleMatches = app.chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
        if !titleMatches.isEmpty {
            Section { ForEach(titleMatches) { row($0, showsProject: true) } } header: { SectionLabel(text: "Chats") }
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

    /// Sits at the optical centre of the space under the search field (a little above true middle,
    /// which reads as sagging there), and drifts in when the list empties.
    private var emptyState: some View {
        EmptyState(title: showArchived ? "Nothing archived" : "No chats yet",
                   message: showArchived ? "Swipe a chat to archive it. It stays searchable." : "Everything you write stays on this iPhone until you export it.") {
            if !showArchived {
                HStack(spacing: 10) {
                    Button { app.startNewChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                        .buttonStyle(.glassProminent)
                    Button { sheets.editor = ProjectEditorRequest(openAfterCreate: true) } label: {
                        Label("New project", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .entrance(emptyShown)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: .center, vertical: .opticalCenter))
        .onAppear { emptyShown = true }
        .onDisappear { emptyShown = false }
    }

    // MARK: Row

    private func row(_ chat: Chat, showsProject: Bool = false) -> some View {
        ChatListRow(chat: chat, sheets: sheets, showsProject: showsProject || showArchived)
    }

    // MARK: Actions

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

/// One chat in the list: serif title, two lines of preview, a quiet meta line (which names the
/// chat's project where the list mixes chats from several).
struct ChatRow: View {
    let chat: Chat
    var showsProject = false
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if chat.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.qAccent)
                        .transition(.pop)
                        .accessibilityLabel("Pinned")
                }
                Text(chat.title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                Text(Fmt.relative(chat.updatedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
            // A reply still coming in (you can leave a chat mid-reply) shows as a live line.
            if isWriting {
                HStack(spacing: 7) {
                    LiveDot()
                    Text("Writing…")
                        .foregroundStyle(Color.qAccent)
                }
                .font(.subheadline.weight(.medium))
                .transition(.opacity)
                .accessibilityLabel("Writing a reply")
            } else {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(2)
                    .transition(.opacity)
            }
            HStack(spacing: 6) {
                if showsProject, let p = app.project(of: chat) {
                    HStack(spacing: 3) {
                        Image(systemName: p.symbolName)
                            .foregroundStyle(p.tintColor)
                        Text(p.name)
                            .lineLimit(1)
                    }
                    Text("·")
                }
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
        .animation(Motion.standard, value: chat.title)
        .animation(Motion.quick, value: isWriting)
        .accessibilityElement(children: .combine)
    }

    private var isWriting: Bool { app.sessions[chat.id]?.generating == true }

    private var preview: String {
        if let d = chat.draft, !d.isEmpty { return "Draft: \(d)" }
        if let p = chat.lastPreview, !p.isEmpty { return p }
        return "No messages yet"
    }
}

/// Compose: tap for a new chat; hold for an incognito chat, one in a project, or one started from a
/// persona. Given a project (a chat in one, or the project's own screen), the new chat starts there
/// too, with a way out of it in the menu.
struct NewChatButton: View {
    var projectId: String? = nil
    @Environment(AppModel.self) private var app

    var body: some View {
        let project = app.project(projectId)
        Menu {
            if let project {
                Button { app.startNewChat(projectId: project.id) } label: {
                    Label("New chat in \(project.name)", systemImage: "square.and.pencil")
                }
                Button { app.startNewChat(incognito: true, projectId: project.id) } label: {
                    Label("Incognito chat", systemImage: "eye.slash")
                }
                Button { app.startNewChat() } label: {
                    Label("New chat outside project", systemImage: "tray")
                }
            } else {
                Button { app.startNewChat() } label: { Label("New chat", systemImage: "square.and.pencil") }
                Button { app.startNewChat(incognito: true) } label: { Label("Incognito chat", systemImage: "eye.slash") }
                if !app.folders.isEmpty {
                    Menu {
                        ForEach(app.projects) { p in
                            Button { app.startNewChat(projectId: p.id) } label: { Label(p.name, systemImage: p.symbolName) }
                        }
                    } label: {
                        Label("In a project", systemImage: "folder")
                    }
                }
            }
            if !app.presets.isEmpty {
                Section("Personas") {
                    ForEach(app.presets) { p in
                        Button { app.startNewChat(persona: p, projectId: project?.id) } label: { Text("\(p.icon ?? "◦")  \(p.name)") }
                    }
                }
            }
            Divider()
            Button { app.push(.section(.prompts)) } label: { Label("Manage personas", systemImage: "person.crop.rectangle.stack") }
        } label: {
            Image(systemName: "square.and.pencil")
        } primaryAction: {
            Haptics.tap()
            app.startNewChat(projectId: project?.id)
        }
        .accessibilityLabel(project.map { "New chat in \($0.name)" } ?? "New chat")
        .accessibilityHint("Hold for incognito, a persona or a project")
    }
}
