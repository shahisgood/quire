import SwiftUI

// Projects and areas: homes for related chats. Each has a tile (symbol and colour), and can carry
// instructions every chat in it follows. A project has a finish line; an area is ongoing. The two
// behave the same and are listed apart.

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

extension ProjectKind {
    var noun: String { label.lowercased() }
    var plural: String { self == .project ? "Projects" : "Areas" }

    var blurb: String {
        switch self {
        case .project: return "A project has a finish line: a launch, a trip, a thesis."
        case .area: return "An area is ongoing, with no end date: health, work, a craft."
        }
    }
}

extension Project {
    var tintChoice: ProjectTint { ProjectTint(rawValue: tint ?? "") ?? .periwinkle }
    var tintColor: Color { tintChoice.color }
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
            .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// A project in the chat list: tile, name, and a quiet line saying whether it has instructions and
/// when it was last used (or that a reply is being written in it right now).
struct ProjectRow: View {
    let project: Project
    @Environment(AppModel.self) private var app

    var body: some View {
        let chats = app.chats(inProject: project.id)
        let writing = chats.contains { app.sessions[$0.id]?.generating == true }
        HStack(spacing: 12) {
            ProjectTile(project: project, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if writing {
                        LiveDot(size: 6)
                        Text("Writing…")
                            .foregroundStyle(Color.qAccent)
                    } else {
                        if project.hasInstructions {
                            Image(systemName: "text.quote")
                                .foregroundStyle(project.tintColor)
                            Text("Instructions")
                            Text("·")
                        }
                        Text(Self.activity(chats))
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.qInk2)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !chats.isEmpty {
                Text("\(chats.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 3)
        .animation(Motion.quick, value: writing)
        .animation(Motion.standard, value: chats.count)
        .accessibilityElement(children: .combine)
    }

    static func activity(_ chats: [Chat]) -> String {
        guard let latest = chats.map(\.updatedAt).max() else { return "No chats yet" }
        let r = Fmt.relative(latest)
        if r == "now" { return "Active just now" }
        if r.first?.isNumber == true, r.count <= 4 { return "Active \(r) ago" }
        return "Active \(r)"
    }
}

// MARK: - Editor

/// What the editor sheet should open with: an existing project, or a new one (optionally taking
/// some chats with it once it's made).
nonisolated struct ProjectEditorRequest: Identifiable {
    let id = UUID()
    var project: Project? = nil
    var moving: Set<String> = []
    var focusInstructions = false
    /// Open the new project once it's made (when it was started from the list itself).
    var openAfterCreate = false
}

nonisolated private enum EditorField: Hashable { case name, instructions }

/// Create or edit a project: a live tile at the top that takes on each choice as you make it,
/// then kind, symbol, colour, instructions and the model new chats start with.
struct ProjectEditor: View {
    private let isNew: Bool
    private let original: Project
    private let focusInstructions: Bool
    private let onSave: (Project) -> Void
    private let onDelete: ((Project) -> Void)?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: Project
    @State private var instructions: String
    @State private var instructionsOn: Bool
    @State private var showModels = false
    @FocusState private var focus: EditorField?
    @Namespace private var picks

    init(project: Project?, focusInstructions: Bool = false, newTint: ProjectTint = .periwinkle,
         onSave: @escaping (Project) -> Void = { _ in }, onDelete: ((Project) -> Void)? = nil) {
        var base = project ?? Project(name: "", order: 0)
        if project == nil {
            base.tint = newTint.rawValue
            base.symbol = "folder.fill"
        }
        isNew = project == nil
        original = base
        self.focusInstructions = focusInstructions
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: base)
        _instructions = State(initialValue: base.instructions ?? "")
        _instructionsOn = State(initialValue: base.hasInstructions || focusInstructions)
    }

    private var noun: String { draft.projectKind.noun }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var choiceAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy }

    /// The draft as it would be saved.
    private var candidate: Project {
        var p = draft
        p.name = trimmedName
        let t = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        p.instructions = instructionsOn && !t.isEmpty ? t : nil
        return p
    }

    private var hasChanges: Bool { candidate != original }

    var body: some View {
        NavigationStack {
            Form {
                Section { identity }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                Section {
                    SlidingSegments(options: ProjectKind.allCases.map { (value: $0, label: $0.label) },
                                    selection: Binding(get: { draft.projectKind }, set: { draft.kind = $0 }))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text(draft.projectKind.blurb)
                        .contentTransition(.opacity)
                        .animation(Motion.quick, value: draft.projectKind)
                }

                Section { symbolGrid } header: { Text("Icon") }
                Section { swatches } header: { Text("Colour") }
                instructionsSection
                modelSection

                if !isNew, let onDelete {
                    Section {
                        Button(role: .destructive) { onDelete(original) } label: {
                            Label("Delete \(noun)…", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .navigationTitle(isNew ? "New \(noun)" : "Edit \(noun)")
            .navigationBarTitleDisplayMode(.inline)
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
            try? await Task.sleep(for: .milliseconds(450))
            if focusInstructions && instructionsOn { focus = .instructions } else if isNew { focus = .name }
        }
    }

    // MARK: Pieces

    private var identity: some View {
        VStack(spacing: 18) {
            ProjectTile(symbol: draft.symbolName, color: draft.tintColor, size: 84)
                .symbolEffect(.bounce, value: draft.symbolName)
                .shadow(color: draft.tintColor.opacity(0.4), radius: 18, y: 8)
                .animation(choiceAnimation, value: draft.tint)
            TextField(draft.projectKind == .project ? "Name, like “Trip to Lisbon”" : "Name, like “Health”", text: $draft.name)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(Color.qInk)
                .multilineTextAlignment(.center)
                .focused($focus, equals: .name)
                .submitLabel(.done)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Color.qRaised, in: .rect(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(focus == .name ? draft.tintColor.opacity(0.6) : Color.qRule, lineWidth: 1)
                )
                .animation(Motion.quick, value: focus)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 10) {
            ForEach(ProjectSymbols.all) { item in
                let on = item.symbol == draft.symbolName
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(choiceAnimation) { draft.symbol = item.symbol }
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(on ? Color.white : Color.qInk2)
                        .frame(width: 44, height: 44)
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
        .padding(.vertical, 8)
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
                                .strokeBorder(t.color, lineWidth: 2.5)
                                .frame(width: 40, height: 40)
                                .matchedGeometryEffect(id: "ring", in: picks)
                        }
                        Circle()
                            .fill(t.color.gradient)
                            .frame(width: 30, height: 30)
                        if on {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.white)
                                .transition(.pop)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(t.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var instructionsSection: some View {
        Section {
            Toggle(isOn: $instructionsOn.animation(reduceMotion ? nil : Motion.standard)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom instructions")
                        .foregroundStyle(Color.qInk)
                    Text(instructionsOn ? "Every chat here follows them" : "Chats here use your usual prompt")
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                        .contentTransition(.opacity)
                }
            }
            .onChange(of: instructionsOn) { _, on in
                if on {
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        focus = .instructions
                    }
                } else if focus == .instructions {
                    focus = nil
                }
            }
            if instructionsOn {
                ZStack(alignment: .topLeading) {
                    if instructions.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(Color.qInk2.opacity(0.7))
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $instructions)
                        .focused($focus, equals: .instructions)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                }
                .font(.body)
                if !instructions.isEmpty {
                    Text("About \(Tokens.estimate(instructions)) tokens, sent with every message")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                }
            }
        } footer: {
            Text(instructionsOn
                 ? "Added after the system prompt in every chat in this \(noun), including chats already in it."
                 : "Without instructions, chats in this \(noun) behave like any other chat.")
        }
    }

    private var placeholder: String {
        switch draft.projectKind {
        case .project:
            return "What should every chat here know? For example: “I'm planning two weeks in Japan in April with a toddler. Keep suggestions practical and budget-minded.”"
        case .area:
            return "What should every chat here know? For example: “I'm training for a half marathon. I'm vegetarian, and I like short, direct answers.”"
        }
    }

    private var modelSection: some View {
        Section {
            Button { showModels = true } label: {
                HStack(spacing: 14) {
                    IconTile(symbol: "cpu", color: draft.tintColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.modelId.map { app.modelName($0) } ?? "App default")
                            .foregroundStyle(Color.qInk)
                        Text(draft.modelId == nil ? app.modelName(app.settings.defaultModelId) : "Chosen for this \(noun)")
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.qInk2)
                }
            }
            if draft.modelId != nil {
                Button("Use the app default") {
                    Haptics.selection()
                    withAnimation(Motion.standard) { draft.modelId = nil }
                }
            }
        } header: {
            Text("New chats")
        } footer: {
            Text("Chats you start in this \(noun) begin with this model. You can still switch in any chat.")
        }
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

// MARK: - Project screen

/// One project: its tile and name, its instructions (or a way to add some), a button for a new chat
/// in it, and its chats. Zooms out of its row in the chat list.
struct ProjectView: View {
    let projectId: String
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sheets = ListSheets()
    /// The last copy seen, so the screen doesn't flash "not found" while it's popped after a delete.
    @State private var cached: Project? = nil
    @State private var showArchived = false
    @State private var instructionsOpen = false
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
            Section { header(p, count: chats.count) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowSeparator(.hidden)

            Section { instructionsCard(p) }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)

            Section {
                if chats.isEmpty { emptyRow(p) }
                ForEach(chats) { ChatListRow(chat: $0, sheets: sheets) }
            } header: {
                SectionLabel(text: "Chats")
            }

            if !archived.isEmpty {
                Section {
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.standard) { showArchived.toggle() }
                    } label: {
                        HStack(spacing: 10) {
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle(p.name)
        .navigationBarTitleDisplayMode(.inline)
        // The name moves up into the bar once the big one has scrolled away.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top > 150
        } action: { _, past in
            withAnimation(Motion.quick) { titleShown = past }
        }
        .toolbar { toolbar(p) }
        .listSheets(sheets)
        .animation(reduceMotion ? nil : Motion.standard, value: chats.map(\.id))
    }

    private func header(_ p: Project, count: Int) -> some View {
        VStack(spacing: 10) {
            ProjectTile(project: p, size: 76)
                .shadow(color: p.tintColor.opacity(0.35), radius: 16, y: 8)
                .padding(.bottom, 4)
            Text(p.name)
                .font(.system(.title, design: .serif).weight(.bold))
                .foregroundStyle(Color.qInk)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            Text(subtitle(p, count: count))
                .font(.subheadline)
                .foregroundStyle(Color.qInk2)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
            Button {
                Haptics.tap()
                app.startNewChat(projectId: p.id)
            } label: {
                Label("New chat", systemImage: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(p.tintColor)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .animation(Motion.standard, value: p)
    }

    private func subtitle(_ p: Project, count: Int) -> String {
        var parts = [p.projectKind.label, count == 0 ? "No chats yet" : "\(count) \(count == 1 ? "chat" : "chats")"]
        if let m = p.modelId { parts.append(app.modelName(m)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func instructionsCard(_ p: Project) -> some View {
        if p.hasInstructions {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "text.quote")
                        .foregroundStyle(p.tintColor)
                    Text("Instructions")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qInk)
                    Spacer()
                    Button("Edit") { sheets.editor = ProjectEditorRequest(project: p, focusInstructions: true) }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                        .tint(p.tintColor)
                }
                Text(p.trimmedInstructions)
                    .font(.subheadline)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(instructionsOpen ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(instructionsOpen ? "Every chat here follows these." : "Every chat here follows these. Tap to read all.")
                    .font(.caption)
                    .foregroundStyle(Color.qInk2.opacity(0.8))
                    .contentTransition(.opacity)
            }
            .padding(14)
            .background(Color.qRaised, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .leading) {
                // A thin stripe of the project's colour down the leading edge.
                Rectangle()
                    .fill(p.tintColor)
                    .frame(width: 4)
            }
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
            .contentShape(.rect)
            .onTapGesture {
                Haptics.selection()
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.standard) { instructionsOpen.toggle() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityHint(instructionsOpen ? "Shows less" : "Shows the full instructions")
        } else {
            Button {
                Haptics.tap()
                sheets.editor = ProjectEditorRequest(project: p, focusInstructions: true)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.badge.plus")
                        .font(.title3)
                        .foregroundStyle(p.tintColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add instructions")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.qInk)
                        Text("Give every chat here the same brief: context, tone, rules.")
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.qInk2.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)
        }
    }

    private func emptyRow(_ p: Project) -> some View {
        VStack(spacing: 4) {
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
        .padding(.vertical, 14)
        .listRowBackground(Color.qRaised)
        .selectionDisabled()
    }

    @ToolbarContentBuilder
    private func toolbar(_ p: Project) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                ProjectTile(project: p, size: 22)
                Text(p.name)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
            }
            .opacity(titleShown ? 1 : 0)
            .offset(y: titleShown || reduceMotion ? 0 : 6)
            .accessibilityHidden(!titleShown)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { sheets.editor = ProjectEditorRequest(project: p) } label: {
                    Label("Edit \(p.projectKind.noun)", systemImage: "pencil")
                }
                Button { app.startNewChat(projectId: p.id) } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
                Button { app.startNewChat(incognito: true, projectId: p.id) } label: {
                    Label("Incognito chat", systemImage: "eye.slash")
                }
                Divider()
                Button(role: .destructive) { sheets.deletingProject = p } label: {
                    Label("Delete \(p.projectKind.noun)…", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("\(p.projectKind.label) options")
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
            HStack(spacing: 12) {
                if let p {
                    ProjectTile(project: p, size: 34)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.qInk2)
                        .frame(width: 34, height: 34)
                        .background(Color.qSunken, in: .rect(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
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
        return p.hasInstructions ? "\(p.projectKind.label) · Has instructions" : p.projectKind.label
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
                Button("Delete \(p.projectKind.noun), keep chats") { delete(p, chats: false) }
                Button(n == 1 ? "Delete \(p.projectKind.noun) and its chat" : "Delete \(p.projectKind.noun) and \(n) chats",
                       role: .destructive) { delete(p, chats: true) }
            } else {
                Button("Delete \(p.projectKind.noun)", role: .destructive) { delete(p, chats: false) }
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

    private func delete(_ p: Project, chats deleting: Bool) {
        let ids = Set(app.chats.filter { $0.folderId == p.id }.map(\.id))
        withAnimation(Motion.standard) { app.deleteProject(p.id, deletingChats: deleting) }
        Haptics.warning()
        let name = p.name.count > 28 ? String(p.name.prefix(27)) + "…" : p.name
        if deleting || ids.isEmpty {
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
