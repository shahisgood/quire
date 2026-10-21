import SwiftUI

struct ChatListView: View {
    @Environment(AppModel.self) private var app
    @Environment(SettingsDrawer.self) private var drawer
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
    /// The masthead has scrolled up under the bar, so the bar carries the name instead.
    @State private var mastheadAway = false

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

    private var showsMasthead: Bool { !isEditing && !searchOpen }

    private var bulkDeleteTitle: String {
        selection.count == 1 ? "Delete this chat?" : "Delete \(selection.count) chats?"
    }

    var body: some View {
        List(selection: $selection) {
            if isSearching {
                searchSections
            } else {
                if showsMasthead { mastheadSection }
                if app.exportNudgeDue && !showArchived && !isEditing { backupNudge }
                if showsProjects { projectSections }
                listSections
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .environment(\.editMode, $editMode)
        .navigationTitle(showArchived ? "Archived" : "Quire")
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 52
        } action: { _, away in
            withAnimation(Motion.quick) { mastheadAway = away }
        }
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
        .background {
            // Left to right anywhere on the list pulls settings in; the same swipe goes back from a
            // chat, a project or Memory.
            StackSwipes(pull: .init(direction: 1,
                                    allowed: { [app] in app.path.isEmpty && !app.settingsOpen && !searchOpen && !isEditing },
                                    changed: { [drawer, app] in drawer.pullChanged($0, app: app) },
                                    ended: { [drawer, app] in drawer.pullEnded($0, velocity: $1, app: app) }),
                        backAllowed: { [app] in !app.settingsOpen && app.path.last?.swipesBackAnywhere == true })
        }
        .animation(Motion.standard, value: showArchived)
        .animation(Motion.standard, value: isEditing)
        .animation(Motion.standard, value: searchOpen)
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

    /// The bar's own title: the name once the masthead has gone under it, or the count while
    /// selecting.
    private var barTitle: String {
        if isEditing { return selection.isEmpty ? "Select chats" : "\(selection.count) selected" }
        return showArchived ? "Archived" : "Quire"
    }

    private var barTitleShown: Bool { isEditing || mastheadAway }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text(barTitle)
                .font(.system(.headline, design: .serif).weight(.semibold))
                .foregroundStyle(Color.qInk)
                .contentTransition(.numericText())
                .opacity(barTitleShown ? 1 : 0)
                .offset(y: barTitleShown ? 0 : 6)
                .animation(Motion.quick, value: barTitle)
                .accessibilityHidden(!barTitleShown)
        }
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
                .accessibilityHint("Or swipe right anywhere on the list")
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

    // MARK: Masthead

    private var writingCount: Int { app.sessions.values.filter(\.generating).count }

    /// The day, then only what's worth a glance: replies on their way, today's spend, being offline.
    private var statusLine: Text {
        if showArchived {
            let n = visible.count
            return Text(n == 0 ? "Nothing archived" : "\(n) archived \(n == 1 ? "chat" : "chats") · swipe one to restore it")
        }
        var parts = [Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())]
        let writing = writingCount
        if writing > 0 {
            parts.append(Text(writing == 1 ? "Writing a reply" : "Writing \(writing) replies").foregroundStyle(Color.qAccent))
        }
        if app.settings.ui.showCosts && app.todayCost > 0 { parts.append(Text("\(Fmt.usd(app.todayCost)) today")) }
        if !app.connectivity.online { parts.append(Text("Offline").foregroundStyle(Color.qWarn)) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }

    private var mastheadSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Masthead(title: showArchived ? "Archived" : "Quire",
                         cursor: !showArchived,
                         writing: writingCount > 0,
                         status: statusLine)
                if showArchived {
                    Button("Done") {
                        Haptics.selection()
                        showArchived = false
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .tint(Color.qAccent)
                    .transition(.opacity)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 6, trailing: 20))
            .listRowBackground(Color.qBase)
            .listRowSeparator(.hidden)
            .selectionDisabled()
        }
        .listSectionSeparator(.hidden)
    }

    // MARK: Sections

    private var backupNudge: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.title3)
                        .foregroundStyle(Color.qAccent)
                    VStack(alignment: .leading, spacing: 3) {
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.qAccentSoft, in: .rect(cornerRadius: 18, style: .continuous))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.qBase)
            .listRowSeparator(.hidden)
            .selectionDisabled()
        }
        .listSectionSeparator(.hidden)
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
            ListHeading(text: "Projects")
        }
        .listSectionSeparator(.hidden)
    }

    private func projectRow(_ p: Project) -> some View {
        ZStack {
            NavigationLink(value: Route.project(p.id)) { EmptyView() }
                .opacity(0)
            ProjectRow(project: p)
        }
        .plainListRow(vertical: 7)
        // Everything on the trailing side: a swipe the other way pulls settings in.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                Haptics.tap()
                app.startNewChat(projectId: p.id)
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
            }
            .tint(p.tintColor)
            Button { sheets.editor = ProjectEditorRequest(project: p) } label: { Label("Edit", systemImage: "pencil") }
                .tint(Color.qTileSlate)
            // Not role: .destructive, which tells the list the row is already gone; deleting asks first.
            Button { sheets.deletingProject = p } label: { Label("Delete", systemImage: "trash") }
                .tint(.red)
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
            HStack(spacing: 6) {
                Text(open ? "Show fewer" : "Show \(hidden) more")
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(open ? 180 : 0))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.qInk2)
            .contentShape(.rect)
        }
        .plainListRow(vertical: 6)
        .selectionDisabled()
    }

    /// An empty tile waiting to be filled: quiet once you have projects, the accent's invitation
    /// before you've made one.
    private func newProjectRow(invite: Bool) -> some View {
        Button {
            Haptics.tap()
            sheets.editor = ProjectEditorRequest(openAfterCreate: true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(invite ? Color.qAccent : Color.qInk2)
                    .frame(width: 38, height: 38)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(invite ? Color.qAccent.opacity(0.5) : Color.qRule,
                                          style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("New project")
                        .font(.body.weight(.medium))
                        .foregroundStyle(invite ? Color.qAccent : Color.qInk2)
                    if invite {
                        Text("Group related chats, with instructions they all follow")
                            .font(.caption)
                            .foregroundStyle(Color.qInk2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .plainListRow(vertical: 7)
        .selectionDisabled()
    }

    // MARK: Chats

    @ViewBuilder
    private var listSections: some View {
        let pinned = listed.filter(\.pinned)
        if !pinned.isEmpty {
            Section { ForEach(pinned) { row($0, showsPin: false) } } header: { ListHeading(text: "Pinned") }
                .listSectionSeparator(.hidden)
        }
        let rest = listed.filter { !$0.pinned }
        ForEach(Fmt.DayGroup.allCases, id: \.self) { group in
            let items = rest.filter { Fmt.dayGroup($0.updatedAt) == group }
            if !items.isEmpty {
                Section { ForEach(items) { row($0) } } header: { ListHeading(text: group.rawValue) }
                    .listSectionSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private var searchSections: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let projectMatches = app.projects.filter { $0.name.localizedCaseInsensitiveContains(q) }
        if !projectMatches.isEmpty {
            Section { ForEach(projectMatches) { projectRow($0) } } header: { ListHeading(text: "Projects") }
                .listSectionSeparator(.hidden)
        }
        let titleMatches = app.chats.filter { $0.title.localizedCaseInsensitiveContains(q) }
        if !titleMatches.isEmpty {
            Section {
                ForEach(titleMatches) { ChatListRow(chat: $0, sheets: sheets, showsProject: true, plain: true) }
            } header: {
                ListHeading(text: "Chats")
            }
            .listSectionSeparator(.hidden)
        }
        Section {
            if hits.isEmpty {
                HStack(spacing: 8) {
                    if searching { ProgressView().controlSize(.small) }
                    Text(searching ? "Searching…" : (q.count < 2 ? "Type at least two characters" : "Nothing in any message matches “\(q)”"))
                        .font(.subheadline)
                        .foregroundStyle(Color.qInk2)
                }
                .plainListRow(vertical: 8)
                .selectionDisabled()
            }
            ForEach(hits) { hit in
                Button { app.openChat(hit.chatId, highlight: hit.messageId) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(app.chat(hit.chatId)?.title ?? "Chat")
                                .font(.system(.body, design: .serif).weight(.semibold))
                                .foregroundStyle(Color.qInk)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(Fmt.stamp(hit.createdAt))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color.qInk2)
                        }
                        Text(highlighted(hit.snippet, q))
                            .font(.subheadline)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(3)
                    }
                    .contentShape(.rect)
                }
                .plainListRow(vertical: 10)
                .selectionDisabled()
            }
        } header: {
            ListHeading(text: "In messages")
        }
        .listSectionSeparator(.hidden)
    }

    /// Sits at the optical centre of the space under the masthead (a little above true middle,
    /// which reads as sagging there), and drifts in when the list empties.
    private var emptyState: some View {
        EmptyState(title: showArchived ? "Nothing archived" : "No chats yet",
                   message: showArchived ? "Swipe a chat to archive it. It stays searchable." : "Everything you write stays on this iPhone until you export it.",
                   showMark: false) {
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

    /// The headings above already name the day, so a row gives the time on it.
    private func row(_ chat: Chat, showsPin: Bool = true) -> some View {
        ChatListRow(chat: chat, sheets: sheets, showsProject: showArchived, plain: true, dayShown: true, showsPin: showsPin)
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

// MARK: - Masthead

/// The top of the chat list: the name set in the serif with the app icon's cursor after it, which
/// breathes while a reply is being written; under it, the day and anything worth a glance. Scrolls
/// away with the list, and the bar picks the name up.
private struct Masthead: View {
    let title: String
    var cursor = true
    var writing = false
    let status: Text
    @ScaledMetric(relativeTo: .largeTitle) private var caret: CGFloat = 21
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: caret * 0.18) {
                Text(title)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.qInk)
                    .contentTransition(.opacity)
                if cursor {
                    caretBlock
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
                        .transition(.opacity)
                }
            }
            status
                .font(.subheadline)
                .foregroundStyle(Color.qInk2)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var caretBlock: some View {
        let block = RoundedRectangle(cornerRadius: caret * 0.14, style: .continuous)
            .fill(Color.qAccent)
            .frame(width: caret * 0.55, height: caret)
            .accessibilityHidden(true)
        if writing && !reduceMotion {
            block.phaseAnimator([1.0, 0.22]) { view, opacity in
                view.opacity(opacity)
            } animation: { _ in .easeInOut(duration: 0.8) }
        } else {
            block
        }
    }
}

// MARK: - Row

/// One chat in a list: its title in the serif, what was said last, and only the details that set
/// it apart (a project where chats from several are mixed, a persona, a model other than the one
/// a new chat would get, incognito, the cost). The time sits at the right; a dot before it means
/// a reply arrived that you haven't opened yet.
struct ChatRow: View {
    let chat: Chat
    var showsProject = false
    /// The list's headings already name the day, so the stamp can give the time.
    var dayShown = false
    /// Off in a Pinned section, which says it already.
    var showsPin = true
    @Environment(AppModel.self) private var app

    var body: some View {
        let unread = chat.unread == true
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chat.title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                stamp(unread: unread)
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
                preview
                    .font(.subheadline)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(2)
                    .transition(.opacity)
            }
            let details = detailText
            let cost = app.settings.ui.showCosts && chat.totalCostUsd > 0 ? Fmt.usd(chat.totalCostUsd) : nil
            if details != nil || cost != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    details?.lineLimit(1)
                    Spacer(minLength: 0)
                    if let cost { Text(cost).monospacedDigit() }
                }
                .font(.caption)
                .foregroundStyle(Color.qInk2.opacity(0.85))
                .padding(.top, 1)
            }
        }
        .animation(Motion.standard, value: chat.title)
        .animation(Motion.quick, value: isWriting)
        .animation(Motion.bouncy, value: unread)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? "New reply" : "")
    }

    private func stamp(unread: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if unread {
                Circle()
                    .fill(Color.qAccent)
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    .transition(.pop)
                    .accessibilityHidden(true)
            } else if chat.pinned && showsPin {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.qInk2)
                    .transition(.pop)
                    .accessibilityLabel("Pinned")
            }
            Text(Fmt.stamp(chat.updatedAt, dayShown: dayShown))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(unread ? Color.qAccent : Color.qInk2)
        }
    }

    private var isWriting: Bool { app.sessions[chat.id]?.generating == true }

    @ViewBuilder
    private var preview: some View {
        if let d = chat.draft?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
            Text("\(Text("Draft").foregroundStyle(Color.qAccent).fontWeight(.medium)) \(d)")
        } else if let p = chat.lastPreview, !p.isEmpty {
            Text(p)
        } else {
            Text("No messages yet").italic()
        }
    }

    /// What sets this chat apart from a new one, if anything.
    private var detailText: Text? {
        let persona = app.preset(chat.systemPromptId)
        let project = app.project(of: chat)
        var parts: [Text] = []
        if showsProject, let project {
            parts.append(Text("\(Text(Image(systemName: project.symbolName)).foregroundStyle(project.tintColor)) \(project.name)"))
        }
        if let persona { parts.append(Text("\(persona.icon ?? "◦") \(persona.name)")) }
        let usual = persona?.modelId ?? project?.modelId ?? app.settings.defaultModelId
        if !chat.modelId.isEmpty && chat.modelId != usual { parts.append(Text(app.modelName(chat.modelId))) }
        if !chat.memoryEnabled { parts.append(Text("\(Image(systemName: "eye.slash")) Incognito")) }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { Text("\($0) · \($1)") }
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
            // The pencil reaches past the square, so the symbol is placed by its ink, not its frame.
            OpticalSymbol("square.and.pencil")
        } primaryAction: {
            Haptics.tap()
            app.startNewChat(projectId: project?.id)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(project.map { "New chat in \($0.name)" } ?? "New chat")
        .accessibilityHint("Hold for incognito, a persona or a project")
    }
}
