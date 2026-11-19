import SwiftUI

// Projects: homes for related chats. Each has a tile (symbol and colour) and can carry
// instructions every chat in it follows.

// MARK: - Look

/// The colours a project can take: the settings-tile family plus two earthier ones, all muted so a
/// list of projects never shouts louder than the accent.
nonisolated enum ProjectTint: String, CaseIterable, Identifiable, Sendable {
    case periwinkle, teal, violet, amber, rose, moss, clay, slate
    var id: String { rawValue }

    /// New projects take the next colour round the wheel, so neighbours differ.
    static func suggested(after count: Int) -> ProjectTint { allCases[count % allCases.count] }
}

extension ProjectTint {
    var color: Color {
        if ThemeStore.shared.mono { return grey }
        switch self {
        case .periwinkle: return .qTileBlue
        case .teal: return .qTileTeal
        case .violet: return .qTileViolet
        case .amber: return .qTileAmber
        case .rose: return .qTileRose
        case .moss: return Color(light: 0x4F7A34, dark: 0x5F8F45)
        case .clay: return Color(light: 0xA9573A, dark: 0xB86A4C)
        case .slate: return .qTileSlate
        }
    }

    /// Under Pitch: a grey of its own, so projects still tell apart, each dark enough for a white
    /// symbol.
    private var grey: Color {
        let dark: [UInt32] = [0x5A5A5A, 0x3C3C3C, 0x6E6E6E, 0x484848, 0x7C7C7C, 0x343434, 0x626262, 0x505050]
        let light: [UInt32] = [0x2A2A2A, 0x4A4A4A, 0x1E1E1E, 0x5E5E5E, 0x383838, 0x6A6A6A, 0x242424, 0x545454]
        let i = Self.allCases.firstIndex(of: self) ?? 0
        return Color(light: light[i], dark: dark[i])
    }

    var name: String { rawValue.capitalized }
}

nonisolated struct ProjectSymbol: Identifiable, Sendable {
    let symbol: String
    let name: String
    var id: String { symbol }
}

/// A short, curated set: enough to tell projects apart at a glance, not a symbol browser.
nonisolated enum ProjectSymbols {
    static let all: [ProjectSymbol] = [
        ProjectSymbol(symbol: "folder.fill", name: "Folder"),
        ProjectSymbol(symbol: "briefcase.fill", name: "Briefcase"),
        ProjectSymbol(symbol: "book.closed.fill", name: "Book"),
        ProjectSymbol(symbol: "graduationcap.fill", name: "Graduation cap"),
        ProjectSymbol(symbol: "pencil.and.outline", name: "Pencil"),
        ProjectSymbol(symbol: "chevron.left.forwardslash.chevron.right", name: "Code"),
        ProjectSymbol(symbol: "lightbulb.fill", name: "Light bulb"),
        ProjectSymbol(symbol: "sparkles", name: "Sparkles"),
        ProjectSymbol(symbol: "flask.fill", name: "Flask"),
        ProjectSymbol(symbol: "atom", name: "Atom"),
        ProjectSymbol(symbol: "chart.line.uptrend.xyaxis", name: "Chart"),
        ProjectSymbol(symbol: "banknote.fill", name: "Money"),
        ProjectSymbol(symbol: "paintbrush.pointed.fill", name: "Paintbrush"),
        ProjectSymbol(symbol: "camera.fill", name: "Camera"),
        ProjectSymbol(symbol: "music.note", name: "Music"),
        ProjectSymbol(symbol: "theatermasks.fill", name: "Theatre"),
        ProjectSymbol(symbol: "gamecontroller.fill", name: "Games"),
        ProjectSymbol(symbol: "quote.bubble.fill", name: "Quote"),
        ProjectSymbol(symbol: "heart.fill", name: "Heart"),
        ProjectSymbol(symbol: "dumbbell.fill", name: "Fitness"),
        ProjectSymbol(symbol: "leaf.fill", name: "Leaf"),
        ProjectSymbol(symbol: "fork.knife", name: "Food"),
        ProjectSymbol(symbol: "cup.and.saucer.fill", name: "Coffee"),
        ProjectSymbol(symbol: "stethoscope", name: "Health"),
        ProjectSymbol(symbol: "house.fill", name: "Home"),
        ProjectSymbol(symbol: "person.2.fill", name: "People"),
        ProjectSymbol(symbol: "pawprint.fill", name: "Pets"),
        ProjectSymbol(symbol: "airplane", name: "Travel"),
        ProjectSymbol(symbol: "mountain.2.fill", name: "Outdoors"),
        ProjectSymbol(symbol: "globe.americas.fill", name: "Globe"),
    ]
}

extension Project {
    var tintChoice: ProjectTint { ProjectTint(rawValue: tint ?? "") ?? .periwinkle }
    var tintColor: Color { tintChoice.color }
}

/// Wording shared by the two places instructions are written.
enum ProjectInstructions {
    static let placeholder = "What should every chat in this project know? Background, tone, rules.\n\nFor example: “I'm planning two weeks in Japan in April with a toddler. Keep suggestions practical and budget-minded.”"

    static func footer(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = n.isEmpty ? "this project" : "“\(n)”"
        return "Every chat in \(subject) follows these, after the system prompt. Leave it empty for a project without instructions."
    }
}

/// A project's face: its symbol on a rounded square of its colour.
struct ProjectTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40

    init(symbol: String, color: Color, size: CGFloat = 40) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    init(project: Project, size: CGFloat = 40) {
        self.init(symbol: project.symbolName, color: project.tintColor, size: size)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .background(color.gradient, in: shape)
            .accessibilityHidden(true)
    }
}

/// A project in the chat list's strip: its tile, its name, and how many chats it holds and when one
/// was last touched, on a card washed with its colour. A dot by the name means a reply in it you
/// haven't read; the live dot, one being written.
struct ProjectCard: View {
    let project: Project
    @Environment(AppModel.self) private var app

    var body: some View {
        let chats = app.chats(inProject: project.id)
        let writing = chats.contains { app.sessions[$0.id]?.generating == true }
        let unread = chats.contains { $0.unread == true }
        HStack(spacing: Space.m) {
            ProjectTile(project: project, size: 36)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.xs) {
                    Text(project.name)
                        .displayFont { .system(.subheadline, design: $0).weight(.semibold) }
                        .foregroundStyle(Color.qInk)
                        .lineLimit(1)
                    if writing {
                        LiveDot(size: 6)
                            .transition(.pop)
                    } else if unread {
                        Circle()
                            .fill(Color.qAccent)
                            .frame(width: 7, height: 7)
                            .transition(.pop)
                    }
                }
                Text(writing ? "Writing…" : Self.summary(chats))
                    .font(.caption)
                    .foregroundStyle(writing ? Color.qAccent : Color.qInk2)
                    .lineLimit(1)
            }
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.l)
        .padding(.vertical, Space.m)
        .frame(minWidth: 150, maxWidth: 230, maxHeight: .infinity, alignment: .leading)
        .background(CardSurface(radius: Radius.l, tint: project.tintColor))
        .animation(Motion.bouncy, value: unread)
        .animation(Motion.quick, value: writing)
        .accessibilityElement(children: .combine)
        .accessibilityValue(unread ? "New replies" : (project.hasInstructions ? "Has instructions" : ""))
    }

    /// "5 chats · 2h ago", or that it's empty.
    static func summary(_ chats: [Chat]) -> String {
        guard let latest = chats.map(\.updatedAt).max() else { return "No chats yet" }
        let count = "\(chats.count) \(chats.count == 1 ? "chat" : "chats")"
        let r = Fmt.relative(latest)
        if r == "now" { return "\(count) · just now" }
        if r.first?.isNumber == true, r.count <= 4 { return "\(count) · \(r) ago" }
        return "\(count) · \(r)"
    }
}

/// The surface a card in the chat list sits on: one step lighter than the page, with a hairline
/// edge so it holds its shape in light mode, and an optional wash of colour.
struct CardSurface: View {
    var radius: CGFloat = Radius.l
    var tint: Color? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Color.qRaised)
            .overlay {
                if let tint { shape.fill(tint.opacity(0.08)) }
            }
            .overlay {
                shape.strokeBorder(tint.map { $0.opacity(0.18) } ?? Color.qRule.opacity(0.8), lineWidth: 0.5)
            }
    }
}

// MARK: - Editor

/// What the editor sheet should open with: an existing project, or a new one (optionally taking
/// some chats with it once it's made).
nonisolated struct ProjectEditorRequest: Identifiable {
    let id = UUID()
    var project: Project? = nil
    var moving: Set<String> = []
    /// Open the new project once it's made (when it was started from the list itself).
    var openAfterCreate = false
}

/// Create or edit a project, laid out like a settings page: a card washed in its colour with the
/// tile taking on each choice as you make it and the name typed straight into it, then the icon,
/// the colour, optional instructions, and the model new chats start with.
struct ProjectEditor: View {
    private let isNew: Bool
    private let original: Project
    private let onSave: (Project) -> Void
    private let onDelete: ((Project) -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: Project
    @State private var instructions: String
    @State private var showModels = false
    @FocusState private var nameFocused: Bool
    @Namespace private var picks

    init(project: Project?, newTint: ProjectTint = .periwinkle,
         onSave: @escaping (Project) -> Void = { _ in }, onDelete: ((Project) -> Void)? = nil) {
        var base = project ?? Project(name: "", order: 0)
        if project == nil {
            base.tint = newTint.rawValue
            base.symbol = "folder.fill"
        }
        isNew = project == nil
        original = base
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: base)
        _instructions = State(initialValue: base.instructions ?? "")
    }

    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedInstructions: String { instructions.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var choiceAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy }

    /// The draft as it would be saved.
    private var candidate: Project {
        var p = draft
        p.name = trimmedName
        p.instructions = trimmedInstructions.isEmpty ? nil : trimmedInstructions
        return p
    }

    private var hasChanges: Bool { candidate != original }

    var body: some View {
        NavigationStack {
            SettingsPage(title: isNew ? "New project" : "Edit project", inlineTitle: true) {
                preview

                SettingsGroup(label: "Icon") { symbolGrid }
                SettingsGroup(label: "Colour") { swatches }

                SettingsGroup(label: "Instructions",
                              footer: Text("Optional. With instructions, every chat in this project follows them, after the system prompt. Without, chats here behave like any other chat.")) {
                    NavigationLink {
                        PromptEditorView(title: "Instructions", text: $instructions,
                                         placeholder: ProjectInstructions.placeholder,
                                         footer: ProjectInstructions.footer(draft.name))
                    } label: {
                        LinkRow(title: trimmedInstructions.isEmpty ? "Add instructions" : "Instructions",
                                detail: trimmedInstructions.isEmpty ? "Background, tone, rules" : trimmedInstructions)
                    }
                    .buttonStyle(.row)
                }

                SettingsGroup(label: "New chats",
                              footer: Text("Chats you start in this project begin with this model. You can still switch in any chat.")) {
                    Button { showModels = true } label: {
                        LinkRow(title: "Model",
                                detail: draft.modelId == nil ? "The app default" : "Chosen for this project",
                                value: app.model(draft.modelId ?? app.settings.defaultModelId)?.shortName ?? app.modelName(draft.modelId ?? app.settings.defaultModelId))
                    }
                    .buttonStyle(.row)
                    if draft.modelId != nil {
                        Button {
                            Haptics.selection()
                            withAnimation(Motion.standard) { draft.modelId = nil }
                        } label: {
                            ActionRow(title: "Use the app default", symbol: "arrow.uturn.backward")
                        }
                        .buttonStyle(.row)
                    }
                }

                if !isNew, let onDelete {
                    SettingsGroup {
                        Button { onDelete(original) } label: {
                            ActionRow(title: "Delete project…", detail: "Asks first, and whether its chats go too", symbol: "trash", danger: true)
                        }
                        .buttonStyle(.row)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .sheet(isPresented: $showModels) {
                ModelPickerView(title: "Model for new chats", selected: draft.modelId ?? app.settings.defaultModelId) { id in
                    withAnimation(Motion.standard) { draft.modelId = id }
                }
            }
        }
        .tint(draft.tintColor)
        .interactiveDismissDisabled(hasChanges)
        .task {
            guard isNew else { return }
            try? await Task.sleep(for: .milliseconds(450))
            nameFocused = true
        }
    }

    // MARK: Pieces

    /// The project as it will look: its tile, taking each choice as you make it, over its name,
    /// which you type straight into, on a card washed with its colour.
    private var preview: some View {
        VStack(spacing: Space.l) {
            ProjectTile(symbol: draft.symbolName, color: draft.tintColor, size: 72)
                .symbolEffect(.bounce, value: draft.symbolName)
                .shadow(color: draft.tintColor.opacity(0.3), radius: 10, y: 5)
                .accessibilityHidden(true)
            TextField("Project name", text: $draft.name)
                .displayFont { .system(.title2, design: $0).weight(.semibold) }
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.qInk)
                .focused($nameFocused)
                .submitLabel(.done)
        }
        .padding(.vertical, Space.xl)
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity)
        .background(CardSurface(radius: Radius.l, tint: draft.tintColor))
        .animation(choiceAnimation, value: draft.tint)
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 6), spacing: Space.s) {
            ForEach(ProjectSymbols.all) { item in
                let on = item.symbol == draft.symbolName
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(choiceAnimation) { draft.symbol = item.symbol }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(on ? Color.white : Color.qInk2)
                        .frame(width: 40, height: 40)
                        .background {
                            ZStack {
                                Circle().fill(Color.qSunken)
                                if on {
                                    Circle()
                                        .fill(draft.tintColor.gradient)
                                        .matchedGeometryEffect(id: "symbol", in: picks)
                                }
                            }
                        }
                        .contentShape(.circle)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(item.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, Space.s)
    }

    private var swatches: some View {
        HStack(spacing: 0) {
            ForEach(ProjectTint.allCases) { t in
                let on = t == draft.tintChoice
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(choiceAnimation) { draft.tint = t.rawValue }
                } label: {
                    ZStack {
                        if on {
                            Circle()
                                .strokeBorder(t.color, lineWidth: 2)
                                .frame(width: 34, height: 34)
                                .matchedGeometryEffect(id: "ring", in: picks)
                        }
                        Circle()
                            .fill(t.color.gradient)
                            .frame(width: 26, height: 26)
                        if on {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.white)
                                .transition(.pop)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(t.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, Space.xs)
    }

    private func save() {
        let p = candidate
        guard !p.name.isEmpty else { return }
        var saved = p
        withAnimation(Motion.standard) {
            if isNew { saved = app.createProject(p) } else { app.updateProject(p) }
        }
        Haptics.success()
        onSave(saved)
        dismiss()
    }
}

/// Just the instructions, for "Add instructions" and "Edit" on the project's screen.
struct ProjectInstructionsSheet: View {
    let project: Project
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(project: Project) {
        self.project = project
        _text = State(initialValue: project.instructions ?? "")
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var changed: Bool { trimmed != project.trimmedInstructions }

    var body: some View {
        NavigationStack {
            PromptEditorView(title: "Instructions", text: $text,
                             placeholder: ProjectInstructions.placeholder,
                             footer: ProjectInstructions.footer(project.name))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                            .disabled(!changed)
                    }
                }
        }
        .tint(project.tintColor)
        .interactiveDismissDisabled(changed)
    }

    private func save() {
        guard var p = app.project(project.id) else {
            dismiss()
            return
        }
        p.instructions = trimmed.isEmpty ? nil : trimmed
        withAnimation(Motion.standard) { app.updateProject(p) }
        Haptics.success()
        app.toasts.show(trimmed.isEmpty ? "Instructions removed" : "Instructions saved", symbol: "text.quote")
        dismiss()
    }
}

// MARK: - Project screen

/// One project: a headline card washed in its colour (tile and name, its figures, its instructions
/// set like a pull quote or a way to add some, and a new chat in it), then its chats.
struct ProjectView: View {
    let projectId: String
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheets = ListSheets()
    /// The last copy seen, so the screen doesn't flash "not found" while it's leaving after a delete.
    @State private var cached: Project? = nil
    @State private var showArchived = false
    @State private var titleShown = false

    var body: some View {
        Group {
            if let p = app.project(projectId) ?? cached {
                content(p)
            } else {
                ContentUnavailableView("Not found", systemImage: "folder",
                                       description: Text("This project may have been deleted."))
            }
        }
        .onAppear { if let p = app.project(projectId) { cached = p } }
        .onChange(of: app.project(projectId)) { _, p in if let p { cached = p } }
    }

    private func content(_ p: Project) -> some View {
        let chats = app.chats(inProject: p.id)
        let archived = app.chats(inProject: p.id, archived: true)
        return List {
            // Outside the group below, so its clear cell isn't given the raised one.
            Section {
                headline(p, chats: chats)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Group {

            Section {
                if chats.isEmpty { emptyRow(p) }
                ForEach(chats) { ChatListRow(chat: $0, sheets: sheets) }
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    SectionLabel(text: "Chats")
                    if !chats.isEmpty {
                        Text(chats.count.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.qInk2.opacity(0.65))
                    }
                }
            }

            if !archived.isEmpty {
                Section {
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.standard) { showArchived.toggle() }
                    } label: {
                        HStack(spacing: Space.m) {
                            Image(systemName: "archivebox")
                                .foregroundStyle(Color.qInk2)
                            Text("Archived")
                                .foregroundStyle(Color.qInk)
                            Spacer()
                            Text("\(archived.count)")
                                .monospacedDigit()
                                .foregroundStyle(Color.qInk2)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.qInk2)
                                .rotationEffect(.degrees(showArchived ? 90 : 0))
                        }
                        .contentShape(.rect)
                    }
                    .listRowBackground(Color.qRaised)
                    if showArchived {
                        ForEach(archived) { ChatListRow(chat: $0, sheets: sheets) }
                    }
                }
            }
            }
            .listRowBackground(Color.qRaised)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        // The name goes up into the bar only once the big one has scrolled away.
        .navigationTitle(titleShown ? p.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 150
        } action: { _, past in
            titleShown = past
        }
        .toolbar { toolbar(p) }
        .listSheets(sheets)
    }

    /// The first row, on a clear cell, set out like the settings pages' headlines in the project's
    /// own colour.
    private func headline(_ p: Project, chats: [Chat]) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .center, spacing: Space.m) {
                ProjectTile(project: p, size: 52)
                    .shadow(color: p.tintColor.opacity(0.3), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Project")
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(p.tintColor)
                    Text(p.name)
                        .displayFont { .system(.title2, design: $0).weight(.bold) }
                        .foregroundStyle(Color.qInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            HStack(alignment: .top, spacing: 0) {
                figure(chats.count.formatted(), chats.count == 1 ? "Chat" : "Chats")
                Spacer(minLength: 8)
                figure(chats.map(\.updatedAt).max().map { Fmt.relative($0) } ?? "—", "Last active")
                Spacer(minLength: 8)
                figure(p.modelId.map { app.model($0)?.shortName ?? app.modelName($0) } ?? "Default", "Model")
            }
            instructions(p)
            HStack(spacing: Space.s) {
                Button {
                    Haptics.tap()
                    app.startNewChat(projectId: p.id)
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 40)
                        .background(p.tintColor.gradient, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                Button {
                    Haptics.tap()
                    app.startNewChat(incognito: true, projectId: p.id)
                } label: {
                    Label("Incognito", systemImage: "eye.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qInk)
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 40)
                        .background(Color.qInk.opacity(0.07), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardSurface(radius: Radius.l, tint: p.tintColor))
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(value)
                .displayFont { .system(.body, design: $0).weight(.semibold).monospacedDigit() }
                .foregroundStyle(Color.qInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.qInk2)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    /// The instructions set like a pull quote under a bar of the project's colour (tap to edit), or
    /// a quiet way to add some.
    private func instructions(_ p: Project) -> some View {
        Button {
            Haptics.tap()
            sheets.instructionsFor = p
        } label: {
            if p.hasInstructions {
                HStack(alignment: .top, spacing: Space.m) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(p.tintColor.opacity(0.6))
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(p.trimmedInstructions)
                            .displayFont { .system(.subheadline, design: $0).italic() }
                            .foregroundStyle(Color.qInk)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Every chat here follows these · Edit")
                            .font(.caption)
                            .foregroundStyle(Color.qInk2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(.rect)
            } else {
                HStack(spacing: Space.s) {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(p.tintColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Add instructions")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.qInk)
                        Text("Optional: background, tone, rules every chat here follows")
                            .font(.caption)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.qInk2)
                }
                .padding(Space.m)
                .background(Color.qInk.opacity(0.05), in: .rect(cornerRadius: Radius.m, style: .continuous))
                .contentShape(.rect)
            }
        }
        .buttonStyle(.row)
        .accessibilityHint(p.hasInstructions ? "Edit the instructions" : "Write instructions for this project")
    }

    private func emptyRow(_ p: Project) -> some View {
        VStack(spacing: Space.xs) {
            Text("No chats yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.qInk)
            Text(p.hasInstructions
                 ? "Start one above. It'll follow the instructions."
                 : "Start one above, or move a chat here from its menu.")
                .font(.footnote)
                .foregroundStyle(Color.qInk2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.m)
        .listRowBackground(Color.qRaised)
    }

    @ToolbarContentBuilder
    private func toolbar(_ p: Project) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheets.editor = ProjectEditorRequest(project: p) } label: {
                    Label("Edit project", systemImage: "pencil")
                }
                Button { sheets.instructionsFor = p } label: {
                    Label(p.hasInstructions ? "Edit instructions" : "Add instructions", systemImage: "text.quote")
                }
                Button { app.startNewChat(incognito: true, projectId: p.id) } label: {
                    Label("Incognito chat", systemImage: "eye.slash")
                }
                Divider()
                Button(role: .danger) { sheets.deletingProject = p } label: {
                    Label("Delete project…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Project options")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NewChatButton(projectId: p.id)
        }
    }
}

// MARK: - Picking a project for a chat

/// From chat settings: put this chat in a project, take it out, or make a new one for it.
struct ProjectPickerList: View {
    let selected: String?
    let onPick: (String?) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false

    var body: some View {
        List {
            Group {
            Section {
                row(nil)
                ForEach(app.projects) { row($0) }
            } footer: {
                Text("A project's instructions apply from the next reply after the chat moves in.")
            }
            Section {
                Button { creating = true } label: { Label("New project…", systemImage: "plus") }
            }
            }
            .listRowBackground(Color.qRaised)
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) {
            ProjectEditor(project: nil, newTint: .suggested(after: app.folders.count), onSave: { p in
                onPick(p.id)
            })
        }
    }

    private func row(_ p: Project?) -> some View {
        Button {
            onPick(p?.id)
            Haptics.selection()
            dismiss()
        } label: {
            HStack(spacing: Space.m) {
                if let p {
                    ProjectTile(project: p, size: 32)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.qInk2)
                        .frame(width: 32, height: 32)
                        .background(Color.qSunken, in: .rect(cornerRadius: Radius.s, style: .continuous))
                }
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(p?.name ?? "None")
                        .foregroundStyle(Color.qInk)
                    Text(detail(p))
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                }
                Spacer()
                if selected == p?.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.qAccent)
                        .fontWeight(.semibold)
                }
            }
        }
        .accessibilityAddTraits(selected == p?.id ? .isSelected : [])
    }

    private func detail(_ p: Project?) -> String {
        guard let p else { return "Your main chat list" }
        return p.hasInstructions ? "Has instructions" : "No instructions"
    }
}

// MARK: - Deleting

/// Asks before a project goes, and whether its chats go with it. Keeping them can be undone.
private struct ProjectDeletion: ViewModifier {
    @Binding var project: Project?
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: Binding(get: { project != nil }, set: { if !$0 { project = nil } }),
                                   titleVisibility: .visible, presenting: project) { p in
            let n = count(p)
            if n > 0 {
                Button("Delete project, keep chats") { confirm(p, deletingChats: false) }
                Button(n == 1 ? "Delete project and its chat" : "Delete project and \(n) chats", role: .danger) {
                    confirm(p, deletingChats: true)
                }
            } else {
                Button("Delete project", role: .danger) { confirm(p, deletingChats: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { p in
            Text(count(p) > 0
                 ? "Kept chats move back to your chat list. Deleted chats can't be recovered."
                 : "It has no chats.")
        }
    }

    private var title: String { project.map { "Delete “\($0.name)”?" } ?? "" }

    private func count(_ p: Project) -> Int { app.chats.filter { $0.folderId == p.id }.count }

    /// From the project's own screen, that screen leaves first and the project goes once it's off
    /// screen, so nothing on it changes mid-transition. Anywhere else it goes straight away.
    private func confirm(_ p: Project, deletingChats: Bool) {
        Haptics.warning()
        guard app.path.contains(.project(p.id)) else {
            Self.delete(p, deletingChats: deletingChats, app: app)
            return
        }
        let app = self.app
        Task {
            // Let the dialog finish closing, then go back, then delete.
            try? await Task.sleep(for: .milliseconds(250))
            if let i = app.path.firstIndex(of: .project(p.id)) { app.path = Array(app.path.prefix(upTo: i)) }
            try? await Task.sleep(for: .milliseconds(550))
            Self.delete(p, deletingChats: deletingChats, app: app)
        }
    }

    private static func delete(_ p: Project, deletingChats: Bool, app: AppModel) {
        guard app.project(p.id) != nil else { return }
        let ids = Set(app.chats.filter { $0.folderId == p.id }.map(\.id))
        withAnimation(Motion.standard) { app.deleteProject(p.id, deletingChats: deletingChats) }
        let name = p.name.count > 28 ? String(p.name.prefix(27)) + "…" : p.name
        if deletingChats || ids.isEmpty {
            app.toasts.show("Deleted “\(name)”", symbol: "trash")
        } else {
            app.toasts.show("Deleted “\(name)”", symbol: "trash", action: (label: "Undo", run: { [app] in
                withAnimation(Motion.standard) { app.restoreProject(p, chatIds: ids) }
            }))
        }
    }
}

extension View {
    func projectDeletion(_ project: Binding<Project?>) -> some View { modifier(ProjectDeletion(project: project)) }
}
