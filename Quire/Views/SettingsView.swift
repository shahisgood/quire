import SwiftUI
import UIKit
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
                link(.generation, "Models", "cpu", .qTileBlue, app.modelName(app.settings.defaultModelId))
                link(.prompts, "Personas", "person.crop.rectangle.stack", .qTileViolet,
                     app.presets.isEmpty ? "No personas" : "\(app.presets.count) persona\(app.presets.count == 1 ? "" : "s")")
                link(.memory, "Memory", "brain", .qTileTeal,
                     app.settings.memory.enabled ? "\(app.memory.count) facts · on" : "Off")
                link(.appearance, "Appearance", "textformat", .qTileAmber,
                     "\(app.settings.ui.colorTheme.name) · \(app.settings.ui.theme.label) · \(app.settings.ui.typeface.name)")
            }
            .listRowBackground(Color.qRaised)

            Section {
                link(.connection, "Connection", "key", .qTileSlate, app.apiKey == nil ? "No key" : (app.settings.keyMeta?.label ?? "Key saved"))
                link(.data, "Data & backup", "externaldrive", .qTileRose, backupDetail)
                link(.about, "About", "info.circle", .qTileSlate,
                     (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).map { "Version \($0)" })
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
                            .displayFont { .system(.headline, design: $0) }
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
                            .displayFont { .system(.headline, design: $0) }
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
            Group {
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
            .listRowBackground(Color.qRaised)
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

// MARK: - Models

/// The models page: the default model set out like a headline, the small housekeeping model and how
/// chats get their names, then the generation defaults every chat starts from.
private struct GenerationSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var pickDefault = false
    @State private var pickTitleModel = false

    var body: some View {
        @Bindable var app = app
        let defaultModel = app.model(app.settings.defaultModelId)
        SettingsPage(title: "Models") {
            hero(defaultModel)

            SettingsGroup(label: "Housekeeping", footer: housekeepingFooter) {
                Button { pickTitleModel = true } label: {
                    LinkRow(title: "Titles & memory", detail: "Names chats and notes what you tell it. Cheap and fast is best.",
                            value: shortName(app.settings.memory.extractionModelId))
                }
                .buttonStyle(.row)
                SettingRow("Name new chats", detail: titleDetail,
                           help: "Smart asks the titles model for a short name once the first reply is in, and tries again later if it couldn't. First message uses your opening line. A chat you rename keeps your name.") {
                    EmptyView()
                } below: {
                    ChoiceStrip(options: ChatTitleMode.allCases.map { (value: $0, label: $0.label) },
                                selection: Binding(get: { app.settings.chatTitles ?? .smart }, set: { app.settings.chatTitles = $0 }),
                                label: "Name new chats")
                }
            }

            ParamsEditor(model: defaultModel, target: $app.settings.globalSettings, base: nil)
        }
        .sheet(isPresented: $pickDefault) {
            ModelPickerView(title: "Default model", selected: app.settings.defaultModelId) { id in app.settings.defaultModelId = id }
        }
        .sheet(isPresented: $pickTitleModel) {
            ModelPickerView(title: "Titles & memory model", selected: app.settings.memory.extractionModelId) { id in app.settings.memory.extractionModelId = id }
        }
    }

    private func shortName(_ id: String) -> String { app.model(id)?.shortName ?? app.modelName(id) }

    /// The model new chats start with, set out like the Spending headline, with what it holds and
    /// what it costs underneath. Tap to change it.
    private func hero(_ model: ORModel?) -> some View {
        let id = app.settings.defaultModelId
        return Button { pickDefault = true } label: {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Default model")
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.qAccent)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortName(id))
                            .displayFont { .system(.title, design: $0).weight(.semibold) }
                            .foregroundStyle(Color.qInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.qInk2)
                    }
                    Text(id)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                }
                if let model {
                    HStack(alignment: .top, spacing: 0) {
                        figure(Fmt.context(model.contextLength), "Context")
                        Spacer(minLength: 8)
                        figure(Pricing.perMillion(model.pricing.prompt), "In, per million")
                        Spacer(minLength: 8)
                        figure(Pricing.perMillion(model.pricing.completion), "Out, per million")
                    }
                } else if !app.models.isEmpty {
                    Text("Not in OpenRouter's catalogue right now. It's still sent as-is; pick another if requests fail.")
                        .font(.footnote)
                        .foregroundStyle(Color.qDanger)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 22)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityHint("Chooses the model new chats start with")
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .displayFont { .system(.body, design: $0).weight(.semibold).monospacedDigit() }
                .foregroundStyle(Color.qInk)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.qInk2)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var titleDetail: String {
        switch app.settings.chatTitles ?? .smart {
        case .smart: "A short name, written once the first reply is in"
        case .firstMessage: "Your opening line, trimmed"
        case .off: "“New chat” until you rename it"
        }
    }

    private var housekeepingFooter: Text? {
        if !app.models.isEmpty && app.model(app.settings.memory.extractionModelId) == nil {
            return Text("This model isn't in the catalogue, so titles and memory will fail until you pick one that exists.")
                .foregroundStyle(Color.qDanger)
        }
        return nil
    }
}

// MARK: - Personas

/// The global prompt, set like a quotation, and your personas, each a row you open to edit or hold
/// for more.
struct PromptsSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: Preset? = nil
    @State private var share: SharedFile? = nil
    @State private var importing = false

    var body: some View {
        @Bindable var app = app
        SettingsPage(title: "Personas") {
            SettingsGroup(label: "Global prompt",
                          footer: Text("Sent at the start of every chat that has no persona or prompt of its own. Personas and per-chat prompts replace it.")) {
                NavigationLink {
                    PromptEditorView(title: "Global system prompt", text: $app.settings.globalSystemPrompt,
                                     placeholder: "Sent at the start of every chat that has no persona or prompt of its own.",
                                     footer: "Personas and per-chat prompts replace this one.")
                } label: {
                    globalPrompt
                }
                .buttonStyle(.row)
            }

            SettingsGroup(label: "Personas",
                          footer: Text("A persona is a saved system prompt, optionally with its own model and settings. Hold the compose button to start a chat with one; hold a persona here for more.")) {
                ForEach(app.presets) { p in
                    Button { editing = p } label: { PersonaRow(preset: p) }
                        .buttonStyle(.row)
                        .contextMenu {
                            Button { app.startNewChat(persona: p) } label: { Label("New chat with \(p.name)", systemImage: "square.and.pencil") }
                            Button { app.duplicatePreset(p) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Divider()
                            Button(role: .destructive) { app.deletePreset(p.id) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
                Button { editing = Preset() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.qAccent)
                            .frame(width: 42, height: 42)
                            .background(Color.qAccentSoft, in: .rect(cornerRadius: 13, style: .continuous))
                        Text("New persona")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.qAccent)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.row)
            }
        }
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

    /// The prompt itself, a few lines of it, beside a rule in the accent like a pull quote.
    private var globalPrompt: some View {
        let prompt = app.settings.globalSystemPrompt
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.qAccent.opacity(prompt.isEmpty ? 0.25 : 0.6))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.isEmpty ? "No global prompt yet" : prompt)
                    .displayFont { .system(.subheadline, design: $0) }
                    .foregroundStyle(prompt.isEmpty ? Color.qInk2 : Color.qInk)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                Text(prompt.isEmpty ? "Tap to write one" : "\(prompt.count.formatted()) characters · about \(Tokens.estimate(prompt).formatted()) tokens")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.qInk2)
                .padding(.top, 2)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

private struct PersonaRow: View {
    let preset: Preset
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Text(preset.icon?.isEmpty == false ? preset.icon! : "◦")
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Color.qAccentSoft, in: .rect(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(preset.name.isEmpty ? "Untitled" : preset.name)
                        .displayFont { .system(.body, design: $0).weight(.semibold) }
                        .foregroundStyle(Color.qInk)
                        .lineLimit(1)
                    if let m = preset.modelId {
                        Text(app.model(m)?.shortName ?? app.modelName(m))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.qInk2.opacity(0.12), in: .capsule)
                    }
                }
                Text(preset.systemPrompt.isEmpty ? "No prompt" : preset.systemPrompt)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.qInk2)
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
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
            SettingsPage(title: isNew ? "New persona" : "Edit persona", inlineTitle: true) {
                HStack(spacing: 14) {
                    TextField("◦", text: Binding(get: { draft.icon ?? "" }, set: { draft.icon = String($0.prefix(2)) }))
                        .font(.title)
                        .multilineTextAlignment(.center)
                        .frame(width: 60, height: 60)
                        .background(Color.qAccentSoft, in: .rect(cornerRadius: 18, style: .continuous))
                        .accessibilityLabel("Icon, one emoji")
                    TextField("Name", text: $draft.name)
                        .displayFont { .system(.title2, design: $0).weight(.semibold) }
                        .foregroundStyle(Color.qInk)
                }
                .padding(16)
                .card(radius: 22)

                SettingsGroup(label: "System prompt",
                              footer: Text("\(draft.systemPrompt.count.formatted()) characters · about \(Tokens.estimate(draft.systemPrompt).formatted()) tokens")
                                .monospacedDigit()) {
                    ZStack(alignment: .topLeading) {
                        if draft.systemPrompt.isEmpty {
                            Text("You are…")
                                .foregroundStyle(Color.qInk2.opacity(0.7))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $draft.systemPrompt)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                    }
                    .padding(.vertical, 8)
                }

                SettingsGroup(label: "Model") {
                    Button { pickModel = true } label: {
                        LinkRow(title: "Pinned model",
                                detail: draft.modelId == nil ? "Uses whichever model the chat has" : nil,
                                value: draft.modelId.map { app.model($0)?.shortName ?? app.modelName($0) })
                    }
                    .buttonStyle(.row)
                    if draft.modelId != nil {
                        Button {
                            withAnimation(Motion.quick) { draft.modelId = nil }
                        } label: {
                            Text("Don't pin a model")
                                .foregroundStyle(Color.qAccent)
                                .padding(.vertical, 13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.row)
                    }
                }

                ParamsEditor(model: app.model(draft.modelId ?? app.settings.defaultModelId),
                             target: $draft.settings,
                             base: app.settings.globalSettings)

                if !isNew {
                    SettingsGroup {
                        actionRow("New chat with this persona", symbol: "square.and.pencil") {
                            app.startNewChat(persona: draft)
                            dismiss()
                        }
                        actionRow("Duplicate", symbol: "plus.square.on.square") {
                            app.duplicatePreset(draft)
                            dismiss()
                        }
                        actionRow("Delete persona", symbol: "trash", destructive: true) { confirmDelete = true }
                    }
                }
            }
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

    private func actionRow(_ title: String, symbol: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(destructive ? Color.qDanger : Color.qAccent)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.row)
    }
}

// MARK: - Memory settings

/// How much is remembered, as a headline with its budget beneath, then how memory behaves.
private struct MemorySettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var pickModel = false

    var body: some View {
        @Bindable var app = app
        let total = MemoryLogic.totalChars(app.memory)
        let budget = app.settings.memory.maxInjectedChars
        SettingsPage(title: "Memory") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.settings.memory.enabled ? "Remembered" : "Memory is off")
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(app.settings.memory.enabled ? Color.qAccent : Color.qInk2)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(app.memory.count.formatted())
                            .displayFont { .system(size: 46, weight: .semibold, design: $0).monospacedDigit() }
                            .tracking(-0.8)
                            .foregroundStyle(Color.qInk)
                            .contentTransition(.numericText(value: Double(app.memory.count)))
                        Text(app.memory.count == 1 ? "fact" : "facts")
                            .displayFont { .system(.title3, design: $0) }
                            .foregroundStyle(Color.qInk2)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    MeterBar(fraction: Double(total) / Double(max(1, budget)), warn: total > budget, height: 6)
                    Text(total > budget
                         ? "\(total.formatted()) characters, more than the \(budget.formatted()) a chat takes: the most relevant go in"
                         : "\(total.formatted()) of \(budget.formatted()) characters go into each chat")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                }
                NavigationLink(value: Route.memory) {
                    Label("Open memory", systemImage: "brain")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qOnAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 38)
                        .background(Color.qAccent, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 22)

            SettingsGroup(label: "Behaviour", footer: footer) {
                SettingRow("Use memory", help: "Put remembered facts into chats, inside a <user_memory> block in the system message, with an instruction not to announce it.") {
                    Toggle("Use memory", isOn: $app.settings.memory.enabled).labelsHidden()
                }
                SettingRow("Extract automatically", help: "After replies, quietly ask the memory model to note durable facts you stated. Runs at most once per three exchanges or thirty seconds, after the reply, and never delays the chat.") {
                    Toggle("Extract automatically", isOn: $app.settings.memory.autoExtract).labelsHidden()
                }
                .disabled(!app.settings.memory.enabled)
                .opacity(app.settings.memory.enabled ? 1 : 0.5)
                Button { pickModel = true } label: {
                    LinkRow(title: "Memory model", value: app.model(app.settings.memory.extractionModelId)?.shortName ?? app.modelName(app.settings.memory.extractionModelId))
                }
                .buttonStyle(.row)
                SettingRow("Budget per chat", help: "How many characters of memory go into each request. Pinned facts always go in; the rest are chosen by relevance to your latest message, then recency.") {
                    Text(budget.formatted())
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.qInk)
                        .contentTransition(.numericText(value: Double(budget)))
                } below: {
                    ParamSlider(value: Binding(get: { Double(app.settings.memory.maxInjectedChars) },
                                               set: { app.settings.memory.maxInjectedChars = Int($0) }),
                                range: 200...20_000, step: 200, mark: 2000, ends: ("Lean", "Generous"),
                                label: "Budget per chat", format: { "\(Int($0).formatted()) characters" })
                }
            }
        }
        .sheet(isPresented: $pickModel) {
            ModelPickerView(title: "Memory model", selected: app.settings.memory.extractionModelId) { id in app.settings.memory.extractionModelId = id }
        }
    }

    private var footer: Text {
        if !app.models.isEmpty && app.model(app.settings.memory.extractionModelId) == nil {
            return Text("This model isn't in the catalogue, so extraction and titles will fail until you pick one that exists.")
                .foregroundStyle(Color.qDanger)
        }
        return Text("Each extraction is a small call to the memory model. Turn memory off for a single chat from its settings (incognito).")
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // What the controls and the preview show. They move the moment you choose; the app as a whole
    // follows a beat later, under a cross-fade (see `AppearanceChange`).
    @State private var theme: AppTheme = .quire
    @State private var mode: ThemeChoice = .dark
    @State private var face: Typeface = .newYork
    @State private var replyFace: ReadingFace = .serif
    @State private var size: ReadingSize = .standard
    @State private var density = "comfortable"
    @State private var strength = UISettings.defaultTextStrength
    @State private var loaded = false
    @State private var strengthCommit: Task<Void, Never>? = nil

    private var replyDesign: Font.Design {
        replyFace == .serif ? .serif : (face == .sfRounded ? .rounded : .default)
    }

    var body: some View {
        @Bindable var app = app
        SettingsPage(title: "Appearance") {
            labelled("Preview") {
                ReadingPreview(replyDesign: replyDesign, replyFace: replyFace == .serif ? "New York" : face.sansName,
                               typeface: face, size: size, compact: density == "compact", ink: strength)
                    .environment(\.displayDesign, face.design)
                    .padding(18)
                    .card(radius: 22)
                    .animation(reduceMotion ? nil : Motion.standard, value: size)
                    .animation(reduceMotion ? nil : Motion.standard, value: density)
            }

            labelled("Theme") {
                VStack(alignment: .leading, spacing: 12) {
                    ThemePicker(selection: theme) { picked in
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.select) { theme = picked }
                        AppearanceChange.apply {
                            ThemeStore.shared.use(picked)
                            app.settings.ui.colorTheme = picked
                        }
                    }
                    ChoiceStrip(options: ThemeChoice.allCases.map { (value: $0, label: $0.label) },
                                selection: deferred($mode) { app.settings.ui.theme = $0 }, label: "Light or dark")
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                SectionLabel(text: "Typeface").padding(.horizontal, 4)
                TypefacePicker(selection: face) { picked in
                    // Replies follow the typeface; they can be set apart again below.
                    face = picked
                    replyFace = picked == .newYork ? .serif : .sans
                    AppearanceChange.apply {
                        app.settings.ui.typeface = picked
                        app.settings.ui.readingFace = picked == .newYork ? .serif : .sans
                    }
                }
                Text(face.blurb)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .contentTransition(.opacity)
                    .animation(Motion.quick, value: face)
            }

            SettingsGroup(label: "Reading",
                          footer: Text("Replies follow the typeface unless you set them apart: SF Pro titles over New York replies reads like a magazine. Reply size is relative to the system text size, so it follows Dynamic Type.")) {
                SettingRow("Replies in") { EmptyView() } below: {
                    ChoiceStrip(options: [(value: ReadingFace.serif, label: "New York"), (value: ReadingFace.sans, label: face.sansName)],
                                selection: deferred($replyFace) { app.settings.ui.readingFace = $0 }, label: "Replies in")
                }
                SettingRow("Reply size", detail: size.label) { EmptyView() } below: {
                    SizeStrip(size: deferred($size) { app.settings.ui.fontScale = $0.scale })
                }
                SettingRow("Density") { EmptyView() } below: {
                    ChoiceStrip(options: [(value: "comfortable", label: "Comfortable"), (value: "compact", label: "Compact")],
                                selection: deferred($density) { app.settings.ui.density = $0 }, label: "Density")
                }
                SettingRow("Text strength", detail: "\(Int((strength * 100).rounded()))%",
                           help: "How strongly a reply's running text is inked. Bold always stays at full strength, so it stands out either way.") {
                    if abs(strength - UISettings.defaultTextStrength) >= 0.005 {
                        Button("Default") {
                            Haptics.selection()
                            withAnimation(Motion.standard) { strength = UISettings.defaultTextStrength }
                        }
                        .font(.footnote.weight(.semibold))
                        .tint(Color.qAccent)
                        .buttonStyle(.borderless)
                        .transition(.opacity)
                    }
                } below: {
                    ParamSlider(value: $strength, range: 0.6...1, step: 0.01,
                                mark: UISettings.defaultTextStrength, ends: ("Soft", "Strong"), label: "Text strength",
                                format: { "\(Int(($0 * 100).rounded())) percent" })
                }
            }

            SettingsGroup(label: "Behaviour",
                          footer: Text("Reasoning traces stay open while the model is still thinking either way. With a hardware keyboard, Shift-Return adds a line.")) {
                toggleRow("Context window", isOn: $app.settings.ui.showContext,
                          help: "A ring in the message box shows how much of the model's context this chat fills. Tap it for the exact count and what the chat has cost.")
                toggleRow("Show reasoning by default", isOn: $app.settings.ui.showReasoningByDefault)
                toggleRow("Show costs", isOn: $app.settings.ui.showCosts)
                toggleRow("Haptics", isOn: $app.settings.ui.hapticsEnabled)
                toggleRow("Return sends on a hardware keyboard", isOn: $app.settings.ui.sendOnEnter)
            }
        }
        .onAppear {
            guard !loaded else { return }
            let ui = app.settings.ui
            theme = ui.colorTheme
            mode = ui.theme
            face = ui.typeface
            replyFace = ui.readingFace
            size = ReadingSize(scale: ui.fontScale)
            density = ui.density
            strength = ui.textStrength
            loaded = true
        }
        // Dragging only moves the preview; the replies everywhere else catch up once you let go.
        .onChange(of: strength) { _, value in
            strengthCommit?.cancel()
            strengthCommit = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                app.settings.ui.textStrength = value
            }
        }
    }

    /// The control and the preview take the value straight away; the app takes it a beat later,
    /// under a cross-fade.
    private func deferred<Value>(_ local: Binding<Value>, apply: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { local.wrappedValue }, set: { value in
            local.wrappedValue = value
            AppearanceChange.apply { apply(value) }
        })
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: label).padding(.horizontal, 4)
            content()
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, help: String? = nil) -> some View {
        SettingRow(title, help: help) { Toggle(title, isOn: isOn).labelsHidden() }
    }
}

/// The four themes as paint cards, two by two: each one's colours run dark to light across its
/// swatch, with its name and what it's made of beneath. The ring slides to the one you pick, and
/// the app re-colours around you as it does.
private struct ThemePicker: View {
    let selection: AppTheme
    let pick: (AppTheme) -> Void
    @Namespace private var ring
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                card(.quire)
                card(.velvet)
            }
            GridRow {
                card(.amethyst)
                card(.pitch)
            }
        }
    }

    private func card(_ theme: AppTheme) -> some View {
        let on = theme == selection
        let swatch = theme.palette.swatch
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            guard !on else { return }
            Haptics.selection()
            pick(theme)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                LinearGradient(stops: [.init(color: swatch[0], location: 0.05),
                                       .init(color: swatch[1], location: 0.55),
                                       .init(color: swatch[2], location: 1)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 72)
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: -6) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(swatch[i])
                                    .frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                            }
                        }
                        .padding(8)
                    }
                    .clipShape(.rect(cornerRadius: 13, style: .continuous))
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.qInk)
                        Text(theme.detail)
                            .font(.caption2)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 0)
                    if on {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.qAccent)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .background {
                if on {
                    shape.fill(Color.qAccentSoft)
                        .overlay { shape.strokeBorder(Color.qAccent, lineWidth: 1.5) }
                        .matchedGeometryEffect(id: "ring", in: ring)
                } else {
                    CardSurface(radius: 20)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .animation(reduceMotion ? nil : Motion.bouncy, value: on)
        .accessibilityLabel(theme.name)
        .accessibilityValue(theme.detail)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The typeface, chosen from three specimens side by side. Each card sets "Aa" in its own face
/// over its name and a word for its character; the accent ring slides to the one you pick, and
/// the whole app changes with it.
private struct TypefacePicker: View {
    let selection: Typeface
    let pick: (Typeface) -> Void
    @Namespace private var ring
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Typeface.allCases, id: \.self) { face in
                card(face, on: face == selection)
            }
        }
    }

    private func card(_ face: Typeface, on: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.bouncy) { pick(face) }
        } label: {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(.system(size: 34, weight: .semibold, design: face.design))
                    .foregroundStyle(on ? Color.qAccent : Color.qInk)
                    .frame(height: 46)
                Text(face.shortName)
                    .font(.system(.footnote, design: face.design).weight(.semibold))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(face.character)
                    .font(.system(.caption2, design: face.design))
                    .foregroundStyle(Color.qInk2)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background {
                if on {
                    shape.fill(Color.qAccentSoft)
                        .overlay { shape.strokeBorder(Color.qAccent, lineWidth: 1.5) }
                        .matchedGeometryEffect(id: "ring", in: ring)
                } else {
                    CardSurface(radius: 20)
                }
            }
            .overlay(alignment: .topTrailing) {
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.qAccent)
                        .padding(9)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(face.name)
        .accessibilityValue(face.character)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Reply size as five A's, each a size up from the last.
private struct SizeStrip: View {
    @Binding var size: ReadingSize
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ReadingSize.allCases) { s in
                let on = s == size
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy) { size = s }
                } label: {
                    Text("A")
                        .font(.system(size: 12 + CGFloat(s.rawValue + 1) * 2.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.qOnAccent : Color.qInk2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Color.qAccent)
                                    .matchedGeometryEffect(id: "size", in: ns)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.qSunken, in: .capsule)
    }
}

/// A live sample: a title in the typeface over a reply in its face, at the chosen size and
/// strength, and a message of yours beneath.
private struct ReadingPreview: View {
    let replyDesign: Font.Design
    let replyFace: String
    let typeface: Typeface
    let size: ReadingSize
    let compact: Bool
    let ink: Double
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quire")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.qAccent)
                Text("A gathering of sheets")
                    .displayFont { .system(.title3, design: $0).weight(.semibold) }
                    .foregroundStyle(Color.qInk)
            }
            Text(Inline.attributed("A quire is **a gathering of sheets** folded and bound together, the unit a book is sewn from. Replies here are set like pages: one column, *generous leading*, and a single accent for what's alive."))
                .font(.system(.body, design: replyDesign))
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
                    .card(radius: 18, fill: .qBase)
            }
        }
        .environment(\.dynamicTypeSize, size.apply(to: typeSize))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: titles in \(typeface.name), replies in \(replyFace), \(size.label)")
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
            Group {
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
            .listRowBackground(Color.qRaised)
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

/// About reads like the last pages of a book: what the word means, what you've gathered in it,
/// where everything is kept, and a colophon of how this copy is made. Each part settles in after
/// the one above it; the figures count up as they arrive.
private struct AboutView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var nameSize: CGFloat = 46
    @State private var shown = false
    @State private var messages = 0
    @State private var bytes: Int? = nil

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }

    var body: some View {
        SettingsPage(title: "About", inlineTitle: true) {
            titlePage.entrance(shown)
            gathered.entrance(shown, delay: 0.06)
            kept.entrance(shown, delay: 0.12)
            colophon.entrance(shown, delay: 0.18)
            elsewhere.entrance(shown, delay: 0.24)
            closing.entrance(shown, delay: 0.3)
        }
        .onAppear { shown = true }
        .task { await measure() }
    }

    // MARK: Title page

    private var titlePage: some View {
        VStack(spacing: 0) {
            // It still writes itself out on three taps, here as on a new chat.
            QuireMark(width: 56, breathing: true, playful: true)
                .padding(.bottom, 24)
            Text("Quire")
                .displayFont { .system(size: nameSize, weight: .bold, design: $0) }
                .tracking(-0.9)
                .foregroundStyle(Color.qInk)
                .accessibilityAddTraits(.isHeader)
            Text("/ˈkwaɪər/ · noun")
                .displayFont { .system(.subheadline, design: $0).italic() }
                .foregroundStyle(Color.qInk2)
                .padding(.top, 2)
                .accessibilityLabel("noun")
            Text("Sheets folded one inside another and sewn together: a book, gathered before it's bound.")
                .displayFont { .system(.body, design: $0) }
                .foregroundStyle(Color.qInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
                .padding(.top, 14)
            Text("Version \(version), build \(build)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.qInk2)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: What you've gathered

    private var gathered: some View {
        let live = shown || reduceMotion
        return VStack(alignment: .leading, spacing: 9) {
            SectionLabel(text: "Your quire").padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 0) {
                    figure(live ? app.chats.count : 0, app.chats.count == 1 ? "Chat" : "Chats")
                    Spacer(minLength: 8)
                    figure(live ? messages : 0, messages == 1 ? "Message" : "Messages")
                    Spacer(minLength: 8)
                    figure(live ? app.memory.count : 0, "Remembered")
                }
                if let line = gatheredLine {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .card(radius: 20)
        }
    }

    private func figure(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted())
                .displayFont { .system(.title, design: $0).weight(.semibold).monospacedDigit() }
                .foregroundStyle(Color.qInk)
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.qInk2)
        }
        .accessibilityElement(children: .combine)
    }

    /// When it began, what else is in it, and how much room it takes.
    private var gatheredLine: String? {
        var parts: [String] = []
        if let first = app.chats.map(\.createdAt).min() {
            parts.append("Begun \(Date(timeIntervalSince1970: first / 1000).formatted(date: .long, time: .omitted))")
        }
        let personas = app.presets.count, projects = app.projects.count
        if personas > 0 { parts.append("\(personas) persona\(personas == 1 ? "" : "s")") }
        if projects > 0 { parts.append("\(projects) project\(projects == 1 ? "" : "s")") }
        if let bytes { parts.append("\(Fmt.bytes(bytes)) on this iPhone") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Where things are kept

    private var host: String {
        guard let base = app.settings.proxyBaseUrl, let h = URL(string: base)?.host(), !h.isEmpty else { return "OpenRouter" }
        return h
    }

    private var kept: some View {
        SettingsGroup(label: "Where things are kept") {
            fact("iphone", "On this iPhone",
                 "Chats, memory, personas and settings live in Quire's own files here. Quire doesn't sync them anywhere.")
            fact("key", "In the Keychain",
                 "Your OpenRouter key is kept by iOS, apart from everything else. A backup carries it only if you ask.")
            fact("paperplane", "Straight to \(host)",
                 "Messages, titles and memory go from this iPhone to \(host) and nowhere else. There's no Quire server.")
            fact("eye.slash", "Nothing watching",
                 "No account, no analytics, no tracking, no ads.")
        }
    }

    private func fact(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.qAccent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.qInk)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    // MARK: Colophon

    private var setIn: String {
        let ui = app.settings.ui
        let titles = ui.typeface.name
        let replies = ui.readingFace == .serif ? "New York" : ui.typeface.sansName
        return titles == replies ? titles : "\(titles), replies in \(replies)"
    }

    private var colours: String {
        let ui = app.settings.ui
        switch ui.theme {
        case .dark: return "\(ui.colorTheme.name), dark"
        case .light: return "\(ui.colorTheme.name), light"
        case .system: return "\(ui.colorTheme.name), light or dark with iOS"
        }
    }

    private var colophon: some View {
        SettingsGroup(label: "Colophon",
                      footer: Text("A colophon is the note at the back of a book on how it was made.")) {
            line("Version", version)
            line("Build", build)
            line("Set in", setIn)
            line("Colours", colours)
            line("Models", app.models.isEmpty ? "None loaded yet" : "\(app.models.count.formatted()) from OpenRouter")
            if app.catalogueFetchedAt > 0 {
                line("List updated", Fmt.relative(app.catalogueFetchedAt))
            }
            line("Running on", "iOS \(UIDevice.current.systemVersion)")
            line("Made with", "SwiftUI, for iOS 26")
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Color.qInk2)
            Spacer(minLength: 8)
            Text(value)
                .displayFont { .system(.body, design: $0) }
                .foregroundStyle(Color.qInk)
                .multilineTextAlignment(.trailing)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Elsewhere

    private var elsewhere: some View {
        SettingsGroup(label: "On OpenRouter") {
            web("Activity", "Every request, its model and what it cost", "https://openrouter.ai/activity")
            web("Credits", "Your balance, and topping it up", "https://openrouter.ai/settings/credits")
            web("Models", "Everything you can talk to, with prices", "https://openrouter.ai/models")
            web("Privacy policy", "How OpenRouter handles what you send", "https://openrouter.ai/privacy")
        }
    }

    private func web(_ title: String, _ detail: String, _ address: String) -> some View {
        Button {
            guard let url = URL(string: address) else { return }
            Haptics.tap()
            openURL(url)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Color.qInk)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.qInk2)
            }
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.row)
        .accessibilityHint("Opens in Safari")
    }

    // MARK: Close

    private var closing: some View {
        VStack(spacing: 10) {
            QuireMark(width: 22)
                .opacity(0.55)
            Text("Every chat a leaf; together, a quire.")
                .displayFont { .system(.footnote, design: $0).italic() }
                .foregroundStyle(Color.qInk2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func measure() async {
        await app.store.flush()
        bytes = app.store.diskUsage()
        let count = app.chats.reduce(0) { $0 + app.allMessages($1.id).count }
        withAnimation(reduceMotion ? nil : Motion.standard) { messages = count }
    }
}
