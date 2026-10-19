import SwiftUI
import Charts
import UniformTypeIdentifiers

/// Settings home: account and spending up top, then the sections, each with a one-line summary
/// so you can see the state of things without opening anything.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section { AccountCard() }
                .listRowBackground(Color.qRaised)

            if app.settings.ui.showCosts {
                Section {
                    SpendingCard()
                    NavigationLink(value: Route.spending) {
                        TileLabel(title: "Breakdown", symbol: "chart.bar.xaxis", color: .qTileBlue,
                                  detail: "By model, tokens and chat")
                    }
                } header: {
                    SectionLabel(text: "Spending")
                }
                .listRowBackground(Color.qRaised)
            }

            Section {
                link(.generation, "Models & generation", "cpu", .qTileBlue, app.modelName(app.settings.defaultModelId))
                link(.prompts, "Prompts & personas", "person.crop.rectangle.stack", .qTileViolet,
                     app.presets.isEmpty ? "No personas" : "\(app.presets.count) persona\(app.presets.count == 1 ? "" : "s")")
                link(.memory, "Memory", "brain", .qTileTeal,
                     app.settings.memory.enabled ? "\(app.memory.count) facts · on" : "Off")
                link(.appearance, "Appearance", "textformat", .qTileAmber,
                     "\(app.settings.ui.theme.label) · \(app.settings.ui.readingFace.label)")
            }
            .listRowBackground(Color.qRaised)

            Section {
                link(.connection, "Connection", "key", .qTileSlate, app.apiKey == nil ? "No key" : (app.settings.keyMeta?.label ?? "Key saved"))
                link(.data, "Data & backup", "externaldrive", .qTileRose, backupDetail)
                link(.about, "About", "info.circle", .qTileSlate, nil)
            }
            .listRowBackground(Color.qRaised)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Settings")
    }

    private var backupDetail: String {
        guard let last = app.settings.lastExportAt, last > 0 else { return "Never backed up" }
        return "Backed up \(Fmt.relative(last))"
    }

    private func link(_ s: SettingsSection, _ title: String, _ symbol: String, _ color: Color, _ detail: String?) -> some View {
        NavigationLink(value: Route.section(s)) {
            TileLabel(title: title, symbol: symbol, color: color, detail: detail)
        }
    }
}

struct SettingsSectionView: View {
    let section: SettingsSection

    var body: some View {
        switch section {
        case .connection: ConnectionSettings()
        case .generation: GenerationSettingsView()
        case .prompts: PromptsSettingsView()
        case .memory: MemorySettingsView()
        case .appearance: AppearanceSettings()
        case .data: DataSettings()
        case .about: AboutView()
        }
    }
}

// MARK: - Home cards

private struct AccountCard: View {
    @Environment(AppModel.self) private var app
    @State private var refreshing = false

    var body: some View {
        if app.apiKey == nil {
            NavigationLink(value: Route.section(.connection)) {
                HStack(spacing: 14) {
                    QuireMark(width: 34, breathing: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Connect OpenRouter")
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(Color.qInk)
                        Text("Paste a key or sign in. It stays in this iPhone's Keychain.")
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                    }
                }
                .padding(.vertical, 6)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.settings.keyMeta?.label ?? "OpenRouter key")
                            .font(.system(.headline, design: .serif))
                            .foregroundStyle(Color.qInk)
                        Text(app.settings.keyMeta?.isFreeTier == true ? "Free tier" : "Connected")
                            .font(.caption)
                            .foregroundStyle(Color.qInk2)
                    }
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(refreshing ? 360 : 0))
                            .animation(refreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: refreshing)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh key details")
                }
                if let meta = app.settings.keyMeta {
                    if let limit = meta.limit, limit > 0 {
                        let remaining = meta.limitRemaining ?? max(0, limit - meta.usage)
                        MeterBar(fraction: 1 - remaining / limit, warn: remaining / limit < 0.15, height: 5)
                        HStack {
                            Text("\(Fmt.usd(remaining)) left of \(Fmt.usd(limit))")
                            Spacer()
                            Text("\(Fmt.usd(meta.usage)) used")
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                    } else {
                        Text("\(Fmt.usd(meta.usage)) used · no credit limit on this key")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.qInk2)
                    }
                }
            }
            .padding(.vertical, 6)
            .task {
                if let meta = app.settings.keyMeta, nowMs() - meta.fetchedAt < 60_000 { return }
                await refresh()
            }
        }
    }

    private func refresh() async {
        refreshing = true
        try? await app.refreshKeyMeta()
        refreshing = false
    }
}

// MARK: - Connection

private struct ConnectionSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var draftKey = ""
    @State private var reveal = false
    @State private var showKey = false
    @State private var checking = false
    @State private var keyError: String? = nil
    @State private var pkce: PKCE? = nil
    @State private var code = ""
    @State private var exchanging = false
    @State private var baseURL = ""

    var body: some View {
        Form {
            if let key = app.apiKey {
                Section {
                    LabeledContent("Key") {
                        Text(showKey ? key : masked(key))
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    if let meta = app.settings.keyMeta {
                        LabeledContent("Label", value: meta.label + (meta.isFreeTier ? " · free tier" : ""))
                        LabeledContent("Used") { Text(Fmt.usd(meta.usage)).monospacedDigit() }
                        LabeledContent("Limit") {
                            Text(meta.limit.map { "\(Fmt.usd(meta.limitRemaining)) left of \(Fmt.usd($0))" } ?? "No limit").monospacedDigit()
                        }
                        if let rl = meta.rateLimit, rl.requests > 0 {
                            LabeledContent("Rate limit", value: "\(rl.requests) per \(rl.interval)")
                        }
                    }
                    if let keyError {
                        Label(keyError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Color.qDanger)
                    }
                    HStack {
                        Button(showKey ? "Hide key" : "Show key") { showKey.toggle() }
                        Spacer()
                        Button { Task { await check() } } label: {
                            if checking { ProgressView() } else { Text("Check") }
                        }
                    }
                    .buttonStyle(.borderless)
                    Button("Remove key", role: .destructive) {
                        app.setAPIKey(nil)
                        app.toasts.show("Key removed", symbol: "key")
                    }
                } header: {
                    SectionLabel(text: "Your key")
                } footer: {
                    Text("Stored in the iPhone Keychain, on this device only, and sent only to OpenRouter.")
                }
            }

            Section {
                HStack {
                    Group {
                        if reveal { TextField("sk-or-v1-…", text: $draftKey) } else { SecureField("sk-or-v1-…", text: $draftKey) }
                    }
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(saveKey)
                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(reveal ? "Hide" : "Show")
                }
                Button("Save key", action: saveKey)
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Link(destination: URL(string: "https://openrouter.ai/keys")!) {
                    Label("Get a key at openrouter.ai/keys", systemImage: "arrow.up.right.square")
                }
            } header: {
                SectionLabel(text: app.apiKey == nil ? "Paste a key" : "Replace key")
            } footer: {
                Text("Use a key with a spending limit.")
            }

            Section {
                if pkce == nil {
                    Button {
                        let p = PKCE()
                        pkce = p
                        if let url = OpenRouterClient.authURL(challenge: p.challenge) { openURL(url) }
                    } label: {
                        Label("Sign in with OpenRouter", systemImage: "person.badge.key")
                    }
                } else {
                    TextField("Paste the code from openrouter.ai", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button { Task { await exchange() } } label: {
                        HStack {
                            Text("Finish sign-in")
                            if exchanging { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || exchanging)
                    Button("Start over") {
                        pkce = nil
                        code = ""
                    }
                    .foregroundStyle(Color.qInk2)
                }
            } header: {
                SectionLabel(text: "Or sign in")
            } footer: {
                Text(pkce == nil
                     ? "Opens openrouter.ai in Safari. After you approve, OpenRouter shows a code: copy it and come back here."
                     : "Codes expire after 10 minutes.")
            }

            Section {
                TextField("https://openrouter.ai/api/v1", text: $baseURL)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .onSubmit(saveBaseURL)
            } header: {
                SectionLabel(text: "API base URL")
            } footer: {
                Text("Leave empty for OpenRouter. Change it only if you route through your own pass-through proxy.")
            }

            Section {
                Link(destination: URL(string: "https://openrouter.ai/settings/integrations")!) {
                    Label("Your own provider keys", systemImage: "arrow.up.right.square")
                }
                Link(destination: URL(string: "https://openrouter.ai/settings/credits")!) {
                    Label("Credits", systemImage: "creditcard")
                }
                Link(destination: URL(string: "https://openrouter.ai/activity")!) {
                    Label("Activity", systemImage: "chart.bar")
                }
            } footer: {
                Text("OpenRouter can route through keys you hold with OpenAI, Anthropic, Google and others. That's set up in your OpenRouter account; Quire works with whatever routing it uses.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { baseURL = app.settings.proxyBaseUrl ?? "" }
        .onDisappear(perform: saveBaseURL)
        .task {
            guard app.apiKey != nil else { return }
            if let meta = app.settings.keyMeta, nowMs() - meta.fetchedAt < 60_000 { return }
            await check()
        }
    }

    private func masked(_ k: String) -> String {
        guard k.count > 16 else { return String(repeating: "•", count: k.count) }
        return String(k.prefix(12)) + "…" + String(k.suffix(4))
    }

    private func saveKey() {
        let k = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        app.setAPIKey(k)
        draftKey = ""
        Haptics.success()
        app.toasts.show("Key saved on this iPhone", symbol: "key")
        Task {
            await check()
            await app.refreshModels(force: true)
        }
    }

    private func saveBaseURL() {
        let t = baseURL.trimmingCharacters(in: .whitespaces)
        let v: String? = t.isEmpty ? nil : t
        if app.settings.proxyBaseUrl != v { app.settings.proxyBaseUrl = v }
    }

    private func check() async {
        checking = true
        keyError = nil
        defer { checking = false }
        do { try await app.refreshKeyMeta() }
        catch { keyError = error.localizedDescription }
    }

    private func exchange() async {
        guard let p = pkce else { return }
        exchanging = true
        keyError = nil
        defer { exchanging = false }
        do {
            let key = try await app.client.exchange(code: code.trimmingCharacters(in: .whitespacesAndNewlines), verifier: p.verifier)
            app.setAPIKey(key)
            pkce = nil
            code = ""
            Haptics.success()
            app.toasts.show("Signed in", symbol: "checkmark")
            await check()
        } catch {
            keyError = error.localizedDescription
        }
    }
}

// MARK: - Models & generation

private struct GenerationSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var pickDefault = false
    @State private var pickTitleModel = false
    @State private var card: ORModel? = nil

    var body: some View {
        @Bindable var app = app
        let defaultModel = app.model(app.settings.defaultModelId)
        Form {
            Section {
                Button { pickDefault = true } label: {
                    modelRow("Default model", id: app.settings.defaultModelId, symbol: "cpu", color: .qTileBlue)
                }
                Button { pickTitleModel = true } label: {
                    modelRow("Titles & memory", id: app.settings.memory.extractionModelId, symbol: "text.badge.star", color: .qTileTeal)
                }
                Picker("Name new chats", selection: Binding(get: { app.settings.chatTitles ?? .smart },
                                                             set: { app.settings.chatTitles = $0 })) {
                    ForEach(ChatTitleMode.allCases, id: \.self) { m in Text(m.label).tag(m) }
                }
            } footer: {
                if !app.models.isEmpty && defaultModel == nil {
                    Text("The default model isn't in OpenRouter's catalogue right now. It's still sent as-is; pick another if requests fail.")
                        .foregroundStyle(Color.qDanger)
                } else {
                    Text("New chats start with the default model. The second one names chats and extracts memory: a cheap, fast model is best. Smart names a chat a moment after its first message; First message uses that message as the name.")
                }
            }

            ParamsEditor(model: defaultModel, target: $app.settings.globalSettings, base: nil)
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Models & generation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickDefault) {
            ModelPickerView(title: "Default model", selected: app.settings.defaultModelId) { id in app.settings.defaultModelId = id }
        }
        .sheet(isPresented: $pickTitleModel) {
            ModelPickerView(title: "Titles & memory model", selected: app.settings.memory.extractionModelId) { id in app.settings.memory.extractionModelId = id }
        }
    }

    private func modelRow(_ title: String, id: String, symbol: String, color: Color) -> some View {
        HStack {
            TileLabel(title: title, symbol: symbol, color: color, detail: app.modelName(id))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.qInk2)
        }
        .contentShape(.rect)
    }
}

// MARK: - Prompts & personas

struct PromptsSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: Preset? = nil
    @State private var share: SharedFile? = nil
    @State private var importing = false

    var body: some View {
        @Bindable var app = app
        List {
            Section {
                NavigationLink {
                    PromptEditorView(title: "Global system prompt", text: $app.settings.globalSystemPrompt,
                                     placeholder: "Sent at the start of every chat that has no persona or prompt of its own.",
                                     footer: "Personas and per-chat prompts replace this one.")
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Global system prompt").foregroundStyle(Color.qInk)
                        Text(app.settings.globalSystemPrompt.isEmpty ? "Empty" : app.settings.globalSystemPrompt)
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowBackground(Color.qRaised)

            Section {
                ForEach(app.presets) { p in
                    Button { editing = p } label: { PersonaRow(preset: p) }
                        .swipeActions {
                            Button(role: .destructive) { app.deletePreset(p.id) } label: { Label("Delete", systemImage: "trash") }
                            Button { app.duplicatePreset(p) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                .tint(Color.qTileSlate)
                        }
                        .contextMenu {
                            Button { app.startNewChat(persona: p) } label: { Label("New chat with \(p.name)", systemImage: "square.and.pencil") }
                            Button { app.duplicatePreset(p) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button(role: .destructive) { app.deletePreset(p.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                Button { editing = Preset() } label: { Label("New persona", systemImage: "plus") }
            } header: {
                SectionLabel(text: "Personas")
            } footer: {
                Text("A persona is a saved system prompt, optionally with its own model and settings. Hold the compose button to start a chat from one.")
            }
            .listRowBackground(Color.qRaised)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Prompts & personas")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Motion.standard, value: app.presets)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { importing = true } label: { Label("Import personas", systemImage: "square.and.arrow.down") }
                    Button {
                        if let url = try? app.exportPresets() { share = SharedFile(url: url) }
                    } label: { Label("Export personas", systemImage: "square.and.arrow.up") }
                    .disabled(app.presets.isEmpty)
                } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("Import or export")
            }
        }
        .sheet(item: $editing) { p in PersonaEditor(preset: p) }
        .sheet(item: $share) { f in ShareSheet(items: [f.url]).presentationDetents([.medium, .large]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let n = try app.importPresets(data)
                app.toasts.show("Imported \(n) persona\(n == 1 ? "" : "s")", symbol: "person.crop.rectangle.stack")
            } catch {
                app.toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle")
            }
        }
    }
}

private struct PersonaRow: View {
    let preset: Preset
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Text(preset.icon?.isEmpty == false ? preset.icon! : "◦")
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.qAccentSoft, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name.isEmpty ? "Untitled" : preset.name)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.qInk)
                Text(preset.systemPrompt.isEmpty ? "No prompt" : preset.systemPrompt)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(2)
                if let m = preset.modelId {
                    Label(app.modelName(m), systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(Color.qInk2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Create or edit a persona: icon, name, prompt, optional pinned model, and the settings it sets.
struct PersonaEditor: View {
    let preset: Preset
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Preset()
    @State private var loaded = false
    @State private var pickModel = false
    @State private var confirmDelete = false

    private var isNew: Bool { !app.presets.contains(where: { $0.id == preset.id }) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("◦", text: Binding(get: { draft.icon ?? "" }, set: { draft.icon = String($0.prefix(2)) }))
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .frame(width: 52, height: 52)
                            .background(Color.qAccentSoft, in: .circle)
                            .accessibilityLabel("Icon, one emoji")
                        TextField("Name", text: $draft.name)
                            .font(.system(.title3, design: .serif).weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if draft.systemPrompt.isEmpty {
                            Text("You are…")
                                .foregroundStyle(Color.qInk2.opacity(0.7))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft.systemPrompt)
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    SectionLabel(text: "System prompt")
                } footer: {
                    Text("\(draft.systemPrompt.count) characters · about \(Tokens.estimate(draft.systemPrompt)) tokens")
                        .monospacedDigit()
                }

                Section {
                    Button { pickModel = true } label: {
                        HStack {
                            TileLabel(title: "Pinned model", symbol: "cpu", color: .qTileBlue,
                                      detail: draft.modelId.map { app.modelName($0) } ?? "Uses the chat's model")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.qInk2)
                        }
                    }
                    if draft.modelId != nil {
                        Button("Don't pin a model") { draft.modelId = nil }
                    }
                }

                ParamsEditor(model: app.model(draft.modelId ?? app.settings.defaultModelId),
                             target: $draft.settings,
                             base: app.settings.globalSettings)

                if !isNew {
                    Section {
                        Button {
                            app.startNewChat(persona: draft)
                            dismiss()
                        } label: { Label("New chat with this persona", systemImage: "square.and.pencil") }
                        Button {
                            app.duplicatePreset(draft)
                            dismiss()
                        } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete persona", systemImage: "trash") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .navigationTitle(isNew ? "New persona" : "Edit persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var p = draft
                        p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        app.savePreset(p)
                        Haptics.success()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                draft = preset
                loaded = true
            }
            .sheet(isPresented: $pickModel) {
                ModelPickerView(title: "Persona model", selected: draft.modelId) { id in draft.modelId = id }
            }
            .confirmationDialog("Delete \(draft.name.isEmpty ? "this persona" : draft.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    app.deletePreset(preset.id)
                    dismiss()
                }
            } message: {
                Text("Chats that use it keep their messages and fall back to the global prompt.")
            }
        }
        .interactiveDismissDisabled(draft != preset && loaded)
    }
}

// MARK: - Memory settings

private struct MemorySettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var pickModel = false

    var body: some View {
        @Bindable var app = app
        let total = MemoryLogic.totalChars(app.memory)
        Form {
            Section {
                NavigationLink(value: Route.memory) {
                    VStack(alignment: .leading, spacing: 8) {
                        TileLabel(title: "Open memory", symbol: "brain", color: .qTileTeal,
                                  detail: "\(app.memory.count) facts · \(total.formatted()) characters")
                        MeterBar(fraction: Double(total) / Double(max(1, app.settings.memory.maxInjectedChars)),
                                 warn: total > app.settings.memory.maxInjectedChars)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Toggle(isOn: $app.settings.memory.enabled) {
                    HelpLabel(title: "Use memory", help: "Inject remembered facts into chats, inside a <user_memory> block in the system message, with an instruction not to announce it.")
                }
                Toggle(isOn: $app.settings.memory.autoExtract) {
                    HelpLabel(title: "Extract automatically", help: "After replies, quietly ask the memory model to note durable facts you stated. Runs at most once per three exchanges or thirty seconds, after the reply, and never delays the chat.")
                }
                .disabled(!app.settings.memory.enabled)
                Button { pickModel = true } label: {
                    HStack {
                        TileLabel(title: "Memory model", symbol: "text.badge.star", color: .qTileTeal,
                                  detail: app.modelName(app.settings.memory.extractionModelId))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.qInk2)
                    }
                }
                Stepper(value: $app.settings.memory.maxInjectedChars, in: 200...20_000, step: 200) {
                    HStack {
                        HelpLabel(title: "Injection budget", help: "How many characters of memory go into each request. Pinned facts always go in; the rest are chosen by relevance to your latest message, then recency.")
                        Spacer()
                        Text(app.settings.memory.maxInjectedChars.formatted())
                            .monospacedDigit()
                            .foregroundStyle(Color.qInk2)
                    }
                }
            } footer: {
                if !app.models.isEmpty && app.model(app.settings.memory.extractionModelId) == nil {
                    Text("This model isn't in the catalogue, so extraction and titles will fail until you pick one that exists.")
                        .foregroundStyle(Color.qDanger)
                } else {
                    Text("Each extraction is a small call to the memory model. Turn memory off for a single chat from its settings (incognito).")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickModel) {
            ModelPickerView(title: "Memory model", selected: app.settings.memory.extractionModelId) { id in app.settings.memory.extractionModelId = id }
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                ReadingPreview(face: app.settings.ui.readingFace, size: ReadingSize(scale: app.settings.ui.fontScale),
                               compact: app.settings.ui.density == "compact", ink: app.settings.ui.textStrength)
                    .listRowInsets(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
            } header: {
                SectionLabel(text: "Preview")
            }

            Section {
                Picker("Theme", selection: $app.settings.ui.theme) {
                    ForEach(ThemeChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Reply typeface", selection: $app.settings.ui.readingFace) {
                    ForEach(ReadingFace.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Reply size", selection: Binding(
                    get: { ReadingSize(scale: app.settings.ui.fontScale) },
                    set: { app.settings.ui.fontScale = $0.scale })) {
                    ForEach(ReadingSize.allCases) { Text($0.label).tag($0) }
                }
                Picker("Density", selection: $app.settings.ui.density) {
                    Text("Comfortable").tag("comfortable")
                    Text("Compact").tag("compact")
                }
                TextStrengthControl(value: $app.settings.ui.textStrength)
            } footer: {
                Text("Reply size is relative to the system text size, so it follows Dynamic Type. Text strength sets how strongly a reply's running text is inked; bold always stays at full strength, so it stands out either way.")
            }

            Section {
                Toggle("Show reasoning by default", isOn: $app.settings.ui.showReasoningByDefault)
                Toggle("Show costs", isOn: $app.settings.ui.showCosts)
                Toggle("Haptics", isOn: $app.settings.ui.hapticsEnabled)
                Toggle("Return sends on a hardware keyboard", isOn: $app.settings.ui.sendOnEnter)
            } footer: {
                Text("Reasoning traces stay open while the model is still thinking either way. With a hardware keyboard, Shift-Return adds a line.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .animation(Motion.standard, value: app.settings.ui)
    }
}

/// How strongly reply text is inked: a slider from soft to as strong as bold, with a way back to
/// the default once it's moved.
private struct TextStrengthControl: View {
    @Binding var value: Double

    private var isDefault: Bool { abs(value - UISettings.defaultTextStrength) < 0.005 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Text strength")
                    .foregroundStyle(Color.qInk)
                Spacer()
                if !isDefault {
                    Button("Default") {
                        Haptics.selection()
                        withAnimation(Motion.standard) { value = UISettings.defaultTextStrength }
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.borderless)
                    .transition(.opacity)
                }
                Text("\(Int((value * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: 0.6...1, step: 0.01) {
                Text("Text strength")
            } minimumValueLabel: {
                Text("Aa")
                    .font(.footnote)
                    .foregroundStyle(Color.qInkStrong.opacity(0.6))
                    .accessibilityHidden(true)
            } maximumValueLabel: {
                Text("Aa")
                    .font(.footnote)
                    .foregroundStyle(Color.qInkStrong)
                    .accessibilityHidden(true)
            }
            .accessibilityValue("\(Int((value * 100).rounded())) percent")
        }
        .padding(.vertical, 4)
        .animation(Motion.quick, value: isDefault)
    }
}

/// A live sample of a reply in the chosen face, size and text strength.
private struct ReadingPreview: View {
    let face: ReadingFace
    let size: ReadingSize
    let compact: Bool
    let ink: Double
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            HStack(spacing: 10) {
                Text("QUIRE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.qInk2)
                Rectangle().fill(Color.qRule).frame(height: 1)
            }
            Text(Inline.attributed("A quire is **a gathering of sheets** folded and bound together, the unit a book is sewn from. Replies here are set like pages: one column, *generous leading*, and a single accent for what's alive."))
                .font(.system(.body, design: face.design))
                .lineSpacing(5)
                .foregroundStyle(Color.qInkStrong.opacity(ink))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                Spacer(minLength: 40)
                Text("Which typeface reads best?")
                    .font(.body)
                    .foregroundStyle(Color.qInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .card(radius: 18)
            }
        }
        .environment(\.dynamicTypeSize, size.apply(to: typeSize))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of a reply in \(face.label), \(size.label)")
    }
}

// MARK: - Data

private struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @State private var includeKey = false
    @State private var share: SharedFile? = nil
    @State private var importing = false
    @State private var pendingImport: Data? = nil
    @State private var showImportChoice = false
    @State private var confirmReplace = false
    @State private var confirmWipe = false
    @State private var busy = false
    @State private var messageCount = 0
    @State private var bytes = 0

    var body: some View {
        Form {
            Section {
                LabeledContent("Chats") { Text("\(app.chats.count)").monospacedDigit() }
                LabeledContent("Messages") { Text(messageCount.formatted()).monospacedDigit() }
                LabeledContent("Memory facts") { Text("\(app.memory.count)").monospacedDigit() }
                LabeledContent("Personas") { Text("\(app.presets.count)").monospacedDigit() }
                LabeledContent("On this iPhone") { Text(Fmt.bytes(bytes)).monospacedDigit() }
            } header: {
                SectionLabel(text: "Storage")
            } footer: {
                Text("Kept in Quire's private storage, which iOS includes in your iPhone backups.")
            }

            Section {
                Toggle("Include API key", isOn: $includeKey)
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do {
                            share = SharedFile(url: try await app.exportBackup(includeKey: includeKey))
                            Haptics.success()
                        } catch {
                            app.toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle")
                        }
                    }
                } label: {
                    HStack {
                        Label("Export everything", systemImage: "square.and.arrow.up")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                Button { importing = true } label: { Label("Import a backup", systemImage: "square.and.arrow.down") }
            } header: {
                SectionLabel(text: "Backup")
            } footer: {
                Text(backupFooter)
            }

            Section {
                Button {
                    Task {
                        await app.clearModelCache()
                        app.toasts.show("Model list refreshed", symbol: "arrow.clockwise")
                    }
                } label: { Label("Refresh the model catalogue", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { confirmWipe = true } label: { Label("Erase everything", systemImage: "trash") }
            } header: {
                SectionLabel(text: "Maintenance")
            } footer: {
                Text("Erasing removes every chat, persona, memory fact, setting and the key from this iPhone.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Data & backup")
        .navigationBarTitleDisplayMode(.inline)
        .task { await measure() }
        .sheet(item: $share) { f in ShareSheet(items: [f.url]).presentationDetents([.medium, .large]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) {
                pendingImport = data
                showImportChoice = true
            } else {
                app.toasts.show("Couldn't read that file", symbol: "exclamationmark.triangle")
            }
        }
        .confirmationDialog("Import backup", isPresented: $showImportChoice, titleVisibility: .visible) {
            Button("Merge with what's here") { runImport(replace: false) }
            Button("Replace everything", role: .destructive) {
                // Let the dialog finish dismissing before the confirmation sheet comes up.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    confirmReplace = true
                }
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Merging adds chats from the file and updates ones with the same id. Replacing deletes what's here first.")
        }
        .sheet(isPresented: $confirmReplace, onDismiss: { if pendingImport != nil { pendingImport = nil } }) {
            TypedConfirmSheet(title: "Replace everything?",
                              message: "Chats, memory and personas on this iPhone are deleted first, then the backup is restored.",
                              word: "replace", actionLabel: "Replace") {
                runImport(replace: true)
            }
        }
        .sheet(isPresented: $confirmWipe) {
            TypedConfirmSheet(title: "Erase everything?",
                              message: "Chats, memory, personas, settings and the API key on this iPhone are erased. Export first if you want any of it.",
                              word: "erase", actionLabel: "Erase") {
                Task { await app.wipeEverything() }
            }
        }
    }

    private var backupFooter: String {
        var s = "A JSON file in the Quire web app's format, so backups move between the two in either direction."
        if let last = app.settings.lastExportAt, last > 0 {
            s += " Last export: \(Date(timeIntervalSince1970: last / 1000).formatted(date: .abbreviated, time: .omitted))."
        } else {
            s += " Never exported."
        }
        return s
    }

    private func measure() async {
        await app.store.flush()
        bytes = app.store.diskUsage()
        messageCount = app.chats.reduce(0) { $0 + app.allMessages($1.id).count }
    }

    private func runImport(replace: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        confirmReplace = false
        Task {
            do {
                let r = try await app.importBackup(data, replace: replace)
                Haptics.success()
                app.toasts.show("Imported \(r.chats) chats, \(r.messages) messages, \(r.memory) facts", symbol: "checkmark")
                await measure()
            } catch {
                Haptics.warning()
                app.toasts.show(error.localizedDescription, symbol: "exclamationmark.triangle")
            }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    @Environment(AppModel.self) private var app

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    QuireMark(width: 64, breathing: true)
                    Text("Quire")
                        .font(.system(.title, design: .serif).weight(.bold))
                        .foregroundStyle(Color.qInk)
                    Text("A gathering of sheets, bound together.")
                        .font(.system(.subheadline, design: .serif).italic())
                        .foregroundStyle(Color.qInk2)
                    Text("Version \(version)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }
            .listRowBackground(Color.clear)

            Section {
                Label("No accounts, no analytics, no server.", systemImage: "hand.raised")
                Label("Chats, memory and settings stay on this iPhone.", systemImage: "iphone")
                Label("The key lives in the Keychain.", systemImage: "key")
                Label("The only network traffic is to OpenRouter, or the base URL you set.", systemImage: "network")
            } header: {
                SectionLabel(text: "Privacy")
            }
            .font(.subheadline)
            .foregroundStyle(Color.qInk)
            .listRowBackground(Color.qRaised)

            Section {
                LabeledContent("Models in catalogue") { Text("\(app.models.count)").monospacedDigit() }
                LabeledContent("Catalogue updated") {
                    Text(app.catalogueFetchedAt > 0 ? Fmt.relative(app.catalogueFetchedAt) : "Never")
                }
                Link(destination: URL(string: "https://openrouter.ai/activity")!) {
                    Label("OpenRouter activity", systemImage: "arrow.up.right.square")
                }
            }
            .listRowBackground(Color.qRaised)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
