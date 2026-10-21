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

    private static let collapsedProjects = 3

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
            geo.contentOffset.y + geo.contentInsets.top > 62
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
                .displayFont { .system(.headline, design: $0).weight(.semibold) }
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

    /// Above the name, in small capitals: the day, then anything alive or wrong (a reply being
    /// written, being offline).
    private var eyebrow: Text {
        if showArchived {
            let n = visible.count
            return Text(n == 0 ? "Archive" : "Archive · \(n) \(n == 1 ? "chat" : "chats")")
        }
        var parts = [Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())]
        let writing = writingCount
        if writing > 0 { parts.append(Text(writing == 1 ? "Writing" : "Writing \(writing)")) }
        if !app.connectivity.online { parts.append(Text("Offline").foregroundStyle(Color.qWarn)) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) · \($1)") }
    }

    private var mastheadSection: some View {
        Section {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Masthead(title: showArchived ? "Archived" : "Quire", eyebrow: eyebrow, writing: writingCount > 0)
                if showArchived {
                    Button("Done") {
                        Haptics.selection()
                        showArchived = false
                    }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .tint(Color.qAccent)
                    .transition(.opacity)
                } else if app.settings.ui.showCosts && app.todayCost > 0 {
                    // Today's spend mirrors the left side: a small-capital label over a figure that
                    // sits on the name's baseline.
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Today")
                            .font(.caption.weight(.semibold))
                            .tracking(1.1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.qInk2)
                        Text(Fmt.usd(app.todayCost))
                            .displayFont { .system(.title2, design: $0).weight(.semibold).monospacedDigit() }
                            .foregroundStyle(Color.qInk)
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                    .transition(.opacity)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .padding(.top, 2)
            .listRowInsets(EdgeInsets(top: 4, leading: 17, bottom: 2, trailing: 17))
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.qAccentSoft, in: .rect(cornerRadius: 20, style: .continuous))
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.qBase)
            .listRowSeparator(.hidden)
            .selectionDisabled()
        }
        .listSectionSeparator(.hidden)
    }

    // MARK: Projects

    /// Projects as a shelf of cards, two across, most recently used first. A long shelf folds to
    /// its first few, with "Show all" on the heading; the last card is always the empty one that
    /// makes a new project.
    private var projectSections: some View {
        let all = app.projects
        let folds = all.count > Self.collapsedProjects
        let shown = folds && !projectsExpanded ? Array(all.prefix(Self.collapsedProjects)) : all
        return Section {
            ProjectShelf(projects: shown, sheets: sheets, showsNew: true)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.qBase)
                .listRowSeparator(.hidden)
                .selectionDisabled()
        } header: {
            ListHeading(text: "Projects",
                        actionLabel: folds ? (projectsExpanded ? "Show fewer" : "Show all \(all.count)") : nil) {
                Haptics.selection()
                withAnimation(Motion.standard) { projectsExpanded.toggle() }
            }
        }
        .listSectionSeparator(.hidden)
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
            Section {
                ProjectShelf(projects: projectMatches, sheets: sheets, showsNew: false)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.qBase)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
            } header: {
                ListHeading(text: "Projects")
            }
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
                .padding(.horizontal, 1)
                .plainListRow(vertical: 8)
                .selectionDisabled()
            }
            ForEach(hits) { hit in
                Button { app.openChat(hit.chatId, highlight: hit.messageId) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(app.chat(hit.chatId)?.title ?? "Chat")
                                .displayFont { .system(.body, design: $0).weight(.semibold) }
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CardSurface(radius: 20))
                    .contentShape(.rect(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
                .plainListRow(vertical: 5)
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

/// The top of the chat list, set like the masthead of a journal: the day in small capitals in the
/// accent, the name large in the serif beneath it. While a reply is being written, the live dot
/// leads the line. Scrolls away with the list, and the bar picks the name up.
private struct Masthead: View {
    let title: String
    let eyebrow: Text
    var writing = false
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                if writing {
                    LiveDot(size: 6)
                        .transition(.scale.combined(with: .opacity))
                }
                eyebrow
                    .font(.caption.weight(.semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.qAccent)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .animation(Motion.quick, value: writing)
            Text(title)
                .displayFont { .system(size: size, weight: .bold, design: $0) }
                .tracking(-0.6)
                .foregroundStyle(Color.qInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Projects

/// Project cards two across, with an empty dashed card at the end that makes a new one. Each
/// card opens its project; holding one gives everything a swipe used to.
private struct ProjectShelf: View {
    let projects: [Project]
    let sheets: ListSheets
    var showsNew = true
    @Environment(AppModel.self) private var app
    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 104

    private enum Slot: Identifiable {
        case project(Project)
        case new
        var id: String {
            switch self {
            case .project(let p): p.id
            case .new: "new"
            }
        }
    }

    var body: some View {
        let slots = projects.map(Slot.project) + (showsNew ? [Slot.new] : [])
        let rows = stride(from: 0, to: slots.count, by: 2).map { Array(slots[$0..<min($0 + 2, slots.count)]) }
        // Alone (no projects yet), the new card spans the shelf and says what projects are for.
        let invite = projects.isEmpty
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { slot in
                        cell(slot, invite: invite)
                            .frame(minHeight: invite ? nil : minHeight)
                            .gridCellColumns(invite ? 2 : 1)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ slot: Slot, invite: Bool) -> some View {
        switch slot {
        case .project(let p):
            Button {
                app.path.append(.project(p.id))
            } label: {
                ProjectCard(project: p)
                    .contentShape(.rect(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.pressable)
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 18, style: .continuous))
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
            .accessibilityHint("Hold for new chat, edit and delete")
        case .new:
            Button {
                Haptics.tap()
                sheets.editor = ProjectEditorRequest(openAfterCreate: true)
            } label: {
                newCard(invite: invite)
            }
            .buttonStyle(.pressable)
        }
    }

    private func newCard(invite: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let layout = invite ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        return layout {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.qAccent)
                .frame(width: 34, height: 34)
                .background(Color.qAccentSoft, in: .rect(cornerRadius: 34 * 0.3, style: .continuous))
            if !invite { Spacer(minLength: 14) }
            VStack(alignment: .leading, spacing: 2) {
                Text("New project")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.qAccent)
                Text(invite ? "Group related chats, with instructions they all follow" : "Group related chats")
                    .font(.caption)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if invite { Spacer(minLength: 0) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            shape.strokeBorder(Color.qInk2.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .contentShape(shape)
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(chat.title)
                    .displayFont { .system(.body, design: $0).weight(.semibold) }
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
            let tags = self.tags
            let cost = app.settings.ui.showCosts && chat.totalCostUsd > 0 ? Fmt.usd(chat.totalCostUsd) : nil
            if !tags.isEmpty || cost != nil {
                HStack(spacing: 6) {
                    ForEach(tags) { TagChip(tag: $0) }
                    Spacer(minLength: 0)
                    if let cost {
                        Text(cost)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.qInk2)
                    }
                }
                .padding(.top, 5)
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
    private var tags: [ChatTag] {
        let persona = app.preset(chat.systemPromptId)
        let project = app.project(of: chat)
        var tags: [ChatTag] = []
        if showsProject, let project {
            tags.append(ChatTag(id: "project", symbol: project.symbolName, label: project.name, tint: project.tintColor))
        }
        if let persona { tags.append(ChatTag(id: "persona", lead: persona.icon ?? "◦", label: persona.name)) }
        let usual = persona?.modelId ?? project?.modelId ?? app.settings.defaultModelId
        if !chat.modelId.isEmpty && chat.modelId != usual {
            tags.append(ChatTag(id: "model", label: app.modelName(chat.modelId)))
        }
        if !chat.memoryEnabled { tags.append(ChatTag(id: "incognito", symbol: "eye.slash", label: "Incognito")) }
        return tags
    }
}

/// A small fact about a chat, shown as a pill under its preview.
struct ChatTag: Identifiable {
    let id: String
    var symbol: String? = nil
    var lead: String? = nil
    let label: String
    var tint: Color? = nil
}

/// A pale pill in the tag's own colour (grey if it has none), with the text in that colour.
private struct TagChip: View {
    let tag: ChatTag

    var body: some View {
        let color = tag.tint ?? Color.qInk2
        HStack(spacing: 4) {
            if let symbol = tag.symbol { Image(systemName: symbol).imageScale(.small) }
            if let lead = tag.lead { Text(lead) }
            Text(tag.label).lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: .capsule)
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
