import SwiftUI

/// Everything Quire will tell a model about you, grouped by kind. Pinned facts always go first;
/// disabled ones are kept but never sent.
struct MemoryView: View {
    /// Off when Memory settings is the screen underneath, where the gear would only lead back.
    var showsSettingsLink = true
    @Environment(AppModel.self) private var app
    @State private var adding = false
    @State private var newText = ""
    @State private var newCategory: MemoryCategory = .context
    @State private var editingId: String? = nil
    @State private var editText = ""
    @State private var query = ""
    @State private var confirmClear = false
    @FocusState private var focus: Field?

    nonisolated enum Field: Hashable { case add, edit }

    private var total: Int { MemoryLogic.totalChars(app.memory) }
    private var budget: Int { app.settings.memory.maxInjectedChars }

    private var shown: [MemoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? app.memory : app.memory.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            Section { budgetCard }
                .listRowBackground(Color.qRaised)

            if adding { addSection }

            if app.memory.isEmpty && !adding {
                Section {
                    EmptyState(title: "Nothing remembered yet",
                               message: "Facts you state in chats appear here after a reply. You can add one yourself, too.",
                               showMark: false) {
                        // An HStack rather than a Label: in a list row a Label's icon is tinted with the
                        // accent colour, which disappears against this accent-filled button and left
                        // the title sitting off-centre next to an invisible plus.
                        Button(action: startAdding) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Add a fact")
                            }
                        }
                        .buttonStyle(.glassProminent)
                    }
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)
            }

            ForEach(MemoryCategory.allCases) { cat in
                let items = shown.filter { $0.category == cat }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { e in entryRow(e) }
                    } header: {
                        Label(cat.title.uppercased(), systemImage: cat.symbol)
                            .font(.caption.weight(.semibold))
                            .tracking(1.1)
                            .foregroundStyle(Color.qInk2)
                    }
                }
            }

            if !app.memory.isEmpty {
                Section {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("Clear all memory", systemImage: "trash")
                    }
                } footer: {
                    Text("Chats aren't affected.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Memory")
        .searchable(text: $query, prompt: "Search memory")
        .animation(Motion.standard, value: app.memory)
        .animation(Motion.quick, value: adding)
        .toolbar {
            if showsSettingsLink {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.section(.memory)) { Image(systemName: "gearshape") }
                        .accessibilityLabel("Memory settings")
                }
            }
            // Only once there are facts: the empty state carries its own Add button, and with the
            // form already open there's nothing for this one to do.
            if !app.memory.isEmpty && !adding {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startAdding) { Image(systemName: "plus") }
                        .accessibilityLabel("Add a fact")
                }
            }
        }
        .sheet(isPresented: $confirmClear) {
            TypedConfirmSheet(title: "Clear all memory?",
                              message: "\(app.memory.count) entries are deleted. Chats are not affected.",
                              word: "clear", actionLabel: "Clear memory") {
                withAnimation(Motion.standard) { app.clearMemory() }
            }
        }
    }

    // MARK: Budget

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(app.memory.count) \(app.memory.count == 1 ? "fact" : "facts")")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.qInk)
                    .contentTransition(.numericText())
                Spacer()
                Text("\(total.formatted()) of \(budget.formatted()) characters")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
            MeterBar(fraction: budget > 0 ? Double(total) / Double(budget) : 0, warn: total > budget, height: 5)
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(total > budget ? Color.qAccent : Color.qInk2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if !app.settings.memory.enabled { return "Memory is off in settings. Entries are kept, but nothing is sent or extracted." }
        if total > budget { return "Over budget: the most relevant facts are sent each time, pinned first." }
        return "Everything here fits in every request. Pinned facts always go first."
    }

    // MARK: Add

    private var addSection: some View {
        Section {
            TextField("One fact, e.g. Works mostly in TypeScript.", text: $newText, axis: .vertical)
                .lineLimit(1...4)
                .focused($focus, equals: .add)
                .submitLabel(.done)
                .onSubmit(commitAdd)
            Picker("Kind", selection: $newCategory) {
                ForEach(MemoryCategory.allCases) { c in Label(c.singular, systemImage: c.symbol).tag(c) }
            }
            HStack {
                Button("Cancel") {
                    adding = false
                    newText = ""
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Remember", action: commitAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            SectionLabel(text: "New fact")
        }
    }

    private func startAdding() {
        withAnimation(Motion.quick) { adding = true }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            focus = .add
        }
    }

    private func commitAdd() {
        let t = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        app.addMemory(t, category: newCategory)
        newText = ""
        adding = false
        Haptics.success()
        app.toasts.show("Remembered", symbol: "brain")
    }

    // MARK: Entries

    @ViewBuilder
    private func entryRow(_ e: MemoryEntry) -> some View {
        if editingId == e.id {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Fact", text: $editText, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focus, equals: .edit)
                    .submitLabel(.done)
                    .onSubmit { commitEdit(e) }
                HStack {
                    Button("Cancel") { editingId = nil }.buttonStyle(.borderless)
                    Spacer()
                    Button("Save") { commitEdit(e) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .listRowBackground(Color.qRaised)
        } else {
            Button {
                editText = e.text
                editingId = e.id
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    focus = .edit
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if e.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Color.qAccent)
                            .accessibilityLabel("Pinned")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.text)
                            .foregroundStyle(e.disabled ? Color.qInk2 : Color.qInk)
                            .strikethrough(e.disabled, color: Color.qInk2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Fmt.relative(e.updatedAt) + (e.disabled ? " · disabled" : ""))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.qInk2)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.qRaised)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { app.deleteMemory(e.id) } label: { Label("Delete", systemImage: "trash") }
                Button { app.updateMemory(e.id) { $0.disabled.toggle() } } label: {
                    Label(e.disabled ? "Enable" : "Disable", systemImage: e.disabled ? "eye" : "eye.slash")
                }
                .tint(Color.qTileSlate)
            }
            .swipeActions(edge: .leading) {
                Button { app.updateMemory(e.id) { $0.pinned.toggle() }; Haptics.selection() } label: {
                    Label(e.pinned ? "Unpin" : "Pin", systemImage: e.pinned ? "pin.slash" : "pin")
                }
                .tint(Color.qAccent)
            }
            .contextMenu {
                Button { app.updateMemory(e.id) { $0.pinned.toggle() } } label: {
                    Label(e.pinned ? "Unpin" : "Pin", systemImage: e.pinned ? "pin.slash" : "pin")
                }
                Button { app.updateMemory(e.id) { $0.disabled.toggle() } } label: {
                    Label(e.disabled ? "Enable" : "Disable", systemImage: e.disabled ? "eye" : "eye.slash")
                }
                Menu {
                    ForEach(MemoryCategory.allCases) { c in
                        Button { app.updateMemory(e.id) { $0.category = c } } label: {
                            Label(c.singular, systemImage: e.category == c ? "checkmark" : c.symbol)
                        }
                    }
                } label: { Label("Kind", systemImage: "tag") }
                if let chatId = e.sourceChatId, app.chat(chatId) != nil {
                    Button { app.openChat(chatId, highlight: e.sourceMessageId) } label: {
                        Label("Go to source", systemImage: "arrow.turn.down.right")
                    }
                }
                Divider()
                Button(role: .destructive) { app.deleteMemory(e.id) } label: { Label("Delete", systemImage: "trash") }
            }
            .accessibilityHint("Edit. Swipe for pin, disable or delete.")
        }
    }

    private func commitEdit(_ e: MemoryEntry) {
        let t = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty && t != e.text { app.updateMemory(e.id) { $0.text = t } }
        editingId = nil
    }
}
