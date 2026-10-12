import SwiftUI

/// Settings for one chat: model, persona, its own system prompt, memory, and generation overrides.
/// Resolution order is global → persona → this chat, as in the PWA.
struct ChatSettingsSheet: View {
    let session: ChatSession
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var showModels = false

    private var overrideCount: Int {
        (session.chat.settingsOverride?.setCount ?? 0) + (session.chat.systemPromptInline == nil ? 0 : 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showModels = true } label: {
                        HStack(spacing: 14) {
                            IconTile(symbol: "cpu", color: .qTileBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.modelName(session.chat.modelId)).foregroundStyle(Color.qInk)
                                Text(session.chat.modelId)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(Color.qInk2)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.qInk2)
                        }
                    }
                    NavigationLink {
                        PersonaPickerList(selected: session.chat.systemPromptId) { id in session.setPersona(id) }
                    } label: {
                        TileLabel(title: "Persona", symbol: "person.crop.rectangle", color: .qTileViolet,
                                  detail: session.persona.map { "\($0.icon ?? "◦") \($0.name)" } ?? "None")
                    }
                    NavigationLink {
                        PromptEditorView(title: "Prompt for this chat",
                                         text: Binding(get: { session.chat.systemPromptInline ?? "" }, set: { session.setSystemPrompt($0) }),
                                         placeholder: session.inheritedSystemPrompt.isEmpty ? "You are…" : session.inheritedSystemPrompt,
                                         footer: "Leave empty to use the \(session.persona == nil ? "global" : "persona's") prompt.")
                    } label: {
                        TileLabel(title: session.chat.systemPromptInline == nil ? "System prompt" : "System prompt ●",
                                  symbol: "text.quote", color: .qTileAmber,
                                  detail: promptDetail)
                    }
                    Toggle(isOn: Binding(get: { session.chat.memoryEnabled }, set: { session.setMemoryEnabled($0) })) {
                        TileLabel(title: "Memory", symbol: "brain", color: .qTileTeal,
                                  detail: session.chat.memoryEnabled ? "Reads and writes remembered facts" : "Incognito: neither reads nor writes")
                    }
                    .disabled(!app.settings.memory.enabled)
                } footer: {
                    if !app.settings.memory.enabled { Text("Memory is off for the whole app in Settings → Memory.") }
                }

                ParamsEditor(model: session.model,
                             target: Binding(get: { session.chat.settingsOverride ?? GenerationSettings() },
                                             set: { session.setOverrides($0) }),
                             base: session.inheritedSettings)

                if overrideCount > 0 {
                    Section {
                        Button(role: .destructive) {
                            withAnimation(Motion.standard) { session.resetOverrides() }
                            Haptics.tap()
                        } label: {
                            Label("Reset \(overrideCount) chat setting\(overrideCount == 1 ? "" : "s")", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .navigationTitle("Chat settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .sheet(isPresented: $showModels) {
                ModelPickerView(title: "Model for this chat", selected: session.chat.modelId) { id in session.setModel(id) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var promptDetail: String {
        if let inline = session.chat.systemPromptInline { return inline }
        let inherited = session.inheritedSystemPrompt
        return inherited.isEmpty ? "None" : "Inherited: \(inherited)"
    }
}

/// A full-height prompt editor with an inherited placeholder.
struct PromptEditorView: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var footer: String? = nil
    @State private var draft = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(Color.qInk2.opacity(0.7))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .lineLimit(8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .focused($focused)
            }
            .card(radius: 14)
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
            }
            HStack {
                Text("\(draft.count) characters · about \(Tokens.estimate(draft)) tokens")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                Spacer()
                if !draft.isEmpty {
                    Button("Clear") { draft = "" }
                        .font(.footnote)
                }
            }
        }
        .padding(16)
        .background(Color.qBase)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            draft = text
            loaded = true
            focused = text.isEmpty
        }
        .onDisappear { if draft != text { text = draft } }
        .onChange(of: draft) { _, new in text = new }
    }
}

/// Pick a persona for a chat, or none.
struct PersonaPickerList: View {
    let selected: String?
    let onPick: (String?) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                row(title: "None", detail: "Global system prompt and defaults", icon: "◦", id: nil)
                ForEach(app.presets) { p in
                    row(title: p.name, detail: p.systemPrompt.isEmpty ? "No prompt" : p.systemPrompt, icon: p.icon ?? "◦", id: p.id)
                }
            } footer: {
                Text("A persona's pinned model replaces this chat's model when you pick it.")
            }
            Section {
                NavigationLink { PromptsSettingsView() } label: { Label("Manage personas", systemImage: "person.crop.rectangle.stack") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Persona")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, detail: String, icon: String, id: String?) -> some View {
        Button {
            onPick(id)
            Haptics.selection()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color.qAccentSoft, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.qInk)
                    Text(detail).font(.footnote).foregroundStyle(Color.qInk2).lineLimit(2)
                }
                Spacer()
                if selected == id {
                    Image(systemName: "checkmark").foregroundStyle(Color.qAccent).fontWeight(.semibold)
                }
            }
        }
        .accessibilityAddTraits(selected == id ? .isSelected : [])
    }
}
