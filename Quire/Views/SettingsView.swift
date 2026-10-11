import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                NavigationLink { ConnectionSettings() } label: {
                    settingsRow("Connection", "key", app.apiKey == nil ? "No key yet" : (app.settings.keyMeta?.label ?? "Key saved"))
                }
                NavigationLink { GenerationSettingsView() } label: {
                    settingsRow("Generation", "slider.horizontal.3", app.model(app.settings.defaultModelId)?.shortName ?? shortId(app.settings.defaultModelId))
                }
                NavigationLink { AppearanceSettings() } label: {
                    settingsRow("Appearance", "textformat", app.settings.ui.theme.label)
                }
                NavigationLink { DataSettings() } label: {
                    settingsRow("Data", "externaldrive", "\(app.chats.count) chats")
                }
                NavigationLink { AboutView() } label: {
                    settingsRow("About", "info.circle", nil)
                }
            }
            if app.settings.ui.showCosts {
                Section("Spending") {
                    LabeledContent("Today") { Text(Fmt.usd(app.todayCost)).monospacedDigit() }
                    LabeledContent("Last 30 days") { Text(Fmt.usd(last30)).monospacedDigit() }
                    if let meta = app.settings.keyMeta, let remaining = meta.limitRemaining {
                        LabeledContent("Key limit left") { Text(Fmt.usd(remaining)).monospacedDigit() }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Settings")
    }

    private var last30: Double {
        let cutoff = dayKey(nowMs() - 29 * 86_400_000)
        return app.costs.filter { $0.day >= cutoff }.reduce(0) { $0 + $1.costUsd }
    }

    private func settingsRow(_ title: String, _ icon: String, _ detail: String?) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let detail {
                Text(detail).foregroundStyle(Color.qInk2).lineLimit(1)
            }
        }
    }
}

// MARK: - Connection

private struct ConnectionSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var draftKey = ""
    @State private var reveal = false
    @State private var checking = false
    @State private var keyError: String? = nil
    @State private var pkce: PKCE? = nil
    @State private var code = ""
    @State private var exchanging = false

    var body: some View {
        Form {
            if let key = app.apiKey {
                Section {
                    LabeledContent("Key") { Text(masked(key)).font(.body.monospaced()) }
                    if let meta = app.settings.keyMeta {
                        LabeledContent("Label", value: meta.label + (meta.isFreeTier ? " · free tier" : ""))
                        LabeledContent("Used") { Text(Fmt.usd(meta.usage)).monospacedDigit() }
                        if let limit = meta.limit {
                            LabeledContent("Limit") { Text(Fmt.usd(limit)).monospacedDigit() }
                        }
                        if let rl = meta.rateLimit, rl.requests > 0 {
                            LabeledContent("Rate limit", value: "\(rl.requests) per \(rl.interval)")
                        }
                    }
                    if let keyError { Text(keyError).font(.footnote).foregroundStyle(Color.qDanger) }
                    Button { Task { await check() } } label: {
                        HStack { Text("Check key"); if checking { Spacer(); ProgressView() } }
                    }
                    Button("Remove key", role: .destructive) { app.setAPIKey(nil) }
                } header: {
                    Text("OpenRouter key")
                } footer: {
                    Text("Stored in the iPhone Keychain, on this device only.")
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
                    Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                        .buttonStyle(.borderless)
                }
                Button("Save key") {
                    let k = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty else { return }
                    app.setAPIKey(k)
                    draftKey = ""
                    Task { await check() }
                }
                .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Link("Get a key at openrouter.ai/keys", destination: URL(string: "https://openrouter.ai/keys")!)
            } header: {
                Text(app.apiKey == nil ? "Paste a key" : "Replace key")
            } footer: {
                Text("Use a key with a spending limit.")
            }

            Section {
                if pkce == nil {
                    Button("Sign in with OpenRouter") {
                        let p = PKCE()
                        pkce = p
                        if let url = OpenRouterClient.authURL(challenge: p.challenge) { openURL(url) }
                    }
                } else {
                    TextField("Paste the code from openrouter.ai", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button {
                        Task { await exchange() }
                    } label: {
                        HStack { Text("Finish sign-in"); if exchanging { Spacer(); ProgressView() } }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || exchanging)
                    Button("Start over") { pkce = nil; code = "" }
                }
            } header: {
                Text("Or sign in")
            } footer: {
                Text(pkce == nil
                     ? "Opens openrouter.ai in Safari. After you approve, OpenRouter shows a code; copy it and come back here."
                     : "Codes expire after 10 minutes.")
            }

            Section {
                TextField("https://openrouter.ai/api/v1", text: Binding(
                    get: { app.settings.proxyBaseUrl ?? "" },
                    set: { app.settings.proxyBaseUrl = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0.trimmingCharacters(in: .whitespaces) }))
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("API base URL")
            } footer: {
                Text("Leave empty for OpenRouter. Set it only if you route through your own proxy.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func masked(_ k: String) -> String {
        guard k.count > 12 else { return String(repeating: "•", count: k.count) }
        return String(k.prefix(9)) + "…" + String(k.suffix(4))
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
            await check()
        } catch {
            keyError = error.localizedDescription
        }
    }
}

// MARK: - Generation

private struct GenerationSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var pickDefault = false
    @State private var pickTitleModel = false

    var body: some View {
        @Bindable var app = app
        let g = $app.settings.globalSettings
        let defaultModel = app.model(app.settings.defaultModelId)
        let style = ReasoningStyle.detect(defaultModel)

        Form {
            Section {
                Button { pickDefault = true } label: {
                    LabeledContent("Default model") {
                        Text(defaultModel?.shortName ?? shortId(app.settings.defaultModelId)).foregroundStyle(Color.qInk2)
                    }
                }
                .foregroundStyle(Color.qInk)
                Button { pickTitleModel = true } label: {
                    LabeledContent("Title model") {
                        Text(app.model(app.settings.memory.extractionModelId)?.shortName ?? shortId(app.settings.memory.extractionModelId)).foregroundStyle(Color.qInk2)
                    }
                }
                .foregroundStyle(Color.qInk)
            } footer: {
                if !app.models.isEmpty && defaultModel == nil {
                    Text("The default model isn't in OpenRouter's catalogue. Pick another.").foregroundStyle(Color.qDanger)
                } else {
                    Text("New chats start with the default model. The title model names chats after the first reply; a cheap, fast one is best.")
                }
            }

            Section {
                TextEditor(text: $app.settings.globalSystemPrompt)
                    .frame(minHeight: 120)
            } header: {
                Text("System prompt")
            } footer: {
                Text("Sent at the start of every chat that doesn't set its own.")
            }

            Section("Sampling") {
                OptionalSlider(title: "Temperature", value: g.temperature, range: 0...2, step: 0.05, defaultValue: 1)
                OptionalSlider(title: "Top P", value: g.topP, range: 0...1, step: 0.01, defaultValue: 1)
                OptionalStepper(title: "Max output tokens", value: g.maxTokens, range: 64...200_000, step: 256, defaultValue: 4096)
            }

            Section {
                Picker("Reasoning", selection: reasoningMode) {
                    Text("Off").tag(ReasoningSettings.Mode.off)
                    Text("Effort").tag(ReasoningSettings.Mode.effort)
                    Text("Budget").tag(ReasoningSettings.Mode.budget)
                }
                if reasoning.mode == .effort {
                    Picker("Effort", selection: reasoningEffort) {
                        ForEach(ReasoningEffort.allCases, id: \.self) { e in Text(e.label).tag(e) }
                    }
                }
                if reasoning.mode == .budget {
                    Stepper(value: reasoningBudget, in: 512...64_000, step: 512) {
                        LabeledContent("Thinking budget") { Text("\(reasoning.maxTokens ?? style.defaultBudget) tokens").monospacedDigit() }
                    }
                }
                Toggle("Hide the reasoning trace", isOn: reasoningExclude)
            } header: {
                Text("Reasoning")
            } footer: {
                Text("Only sent to models that accept it. For \(defaultModel?.shortName ?? "the default model"): \(style.note)")
            }

            Section {
                Toggle("Web search", isOn: Binding(
                    get: { app.settings.globalSettings.webSearch?.enabled ?? false },
                    set: { v in mutateWeb { $0.enabled = v } }))
                if app.settings.globalSettings.webSearch?.enabled ?? false {
                    Stepper(value: Binding(
                        get: { app.settings.globalSettings.webSearch?.maxResults ?? 5 },
                        set: { v in mutateWeb { $0.maxResults = v } }), in: 1...10) {
                        LabeledContent("Results") { Text("\(app.settings.globalSettings.webSearch?.maxResults ?? 5)").monospacedDigit() }
                    }
                }
                Toggle("Stream replies", isOn: Binding(
                    get: { app.settings.globalSettings.stream ?? true },
                    set: { app.settings.globalSettings.stream = $0 }))
            } footer: {
                Text("Web search uses OpenRouter's web plugin and is billed per request.")
            }

            Section {
                Picker("Prefer", selection: Binding(
                    get: { app.settings.globalSettings.provider?.sort ?? "" },
                    set: { v in mutateProvider { $0.sort = v.isEmpty ? nil : v } })) {
                    Text("Default").tag("")
                    Text("Lowest price").tag("price")
                    Text("Throughput").tag("throughput")
                    Text("Latency").tag("latency")
                }
                Toggle("Allow fallbacks", isOn: Binding(
                    get: { app.settings.globalSettings.provider?.allowFallbacks ?? true },
                    set: { v in mutateProvider { $0.allowFallbacks = v } }))
                Toggle("Require all parameters", isOn: Binding(
                    get: { app.settings.globalSettings.provider?.requireParameters ?? true },
                    set: { v in mutateProvider { $0.requireParameters = v } }))
                Toggle("Deny data collection", isOn: Binding(
                    get: { app.settings.globalSettings.provider?.denyDataCollection ?? false },
                    set: { v in mutateProvider { $0.denyDataCollection = v } }))
            } header: {
                Text("Providers")
            } footer: {
                Text("Denying data collection removes some of the cheapest providers.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Generation")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickDefault) {
            ModelPickerView(selected: app.settings.defaultModelId) { id in app.settings.defaultModelId = id }
        }
        .sheet(isPresented: $pickTitleModel) {
            ModelPickerView(selected: app.settings.memory.extractionModelId) { id in app.settings.memory.extractionModelId = id }
        }
    }

    // MARK: Reasoning bindings

    private var reasoning: ReasoningSettings { app.settings.globalSettings.reasoning ?? ReasoningSettings() }

    private func mutateReasoning(_ f: (inout ReasoningSettings) -> Void) {
        var r = reasoning
        f(&r)
        app.settings.globalSettings.reasoning = r
    }

    private var reasoningMode: Binding<ReasoningSettings.Mode> {
        Binding(get: { reasoning.mode }, set: { v in mutateReasoning { $0.mode = v } })
    }
    private var reasoningEffort: Binding<ReasoningEffort> {
        Binding(get: { reasoning.effort ?? .medium }, set: { v in mutateReasoning { $0.effort = v } })
    }
    private var reasoningBudget: Binding<Int> {
        Binding(get: { reasoning.maxTokens ?? ReasoningStyle.detect(app.model(app.settings.defaultModelId)).defaultBudget },
                set: { v in mutateReasoning { $0.maxTokens = v } })
    }
    private var reasoningExclude: Binding<Bool> {
        Binding(get: { reasoning.exclude }, set: { v in mutateReasoning { $0.exclude = v } })
    }

    private func mutateWeb(_ f: (inout WebSearchSettings) -> Void) {
        var w = app.settings.globalSettings.webSearch ?? WebSearchSettings()
        f(&w)
        app.settings.globalSettings.webSearch = w
    }

    private func mutateProvider(_ f: (inout ProviderSettings) -> Void) {
        var p = app.settings.globalSettings.provider ?? ProviderSettings()
        f(&p)
        app.settings.globalSettings.provider = p
    }
}

/// A slider that can be switched off, so "unset" (let the provider decide) stays distinct from any value.
private struct OptionalSlider: View {
    let title: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { value != nil }, set: { value = $0 ? defaultValue : nil })) {
                LabeledContent(title) {
                    Text(value.map { String(format: "%.2f", $0) } ?? "Default").monospacedDigit()
                }
            }
            if let v = value {
                Slider(value: Binding(get: { v }, set: { value = ($0 / step).rounded() * step }), in: range)
            }
        }
    }
}

private struct OptionalStepper: View {
    let title: String
    @Binding var value: Int?
    let range: ClosedRange<Int>
    let step: Int
    let defaultValue: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { value != nil }, set: { value = $0 ? defaultValue : nil })) {
                LabeledContent(title) { Text(value.map { Fmt.tokens($0) } ?? "Model limit").monospacedDigit() }
            }
            if let v = value {
                Stepper("Adjust", value: Binding(get: { v }, set: { value = $0 }), in: range, step: step)
                    .labelsHidden()
            }
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
                Picker("Theme", selection: $app.settings.ui.theme) {
                    ForEach(ThemeChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Reply typeface", selection: $app.settings.ui.readingFace) {
                    ForEach(ReadingFace.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("Text size follows the system setting in Settings → Display & Brightness.")
            }
            Section {
                Toggle("Show reasoning by default", isOn: $app.settings.ui.showReasoningByDefault)
                Toggle("Show costs", isOn: $app.settings.ui.showCosts)
                Toggle("Haptics", isOn: $app.settings.ui.hapticsEnabled)
            } footer: {
                Text("Costs show under replies, in the chat list and in Settings. Reasoning traces stay open while the model is still thinking either way.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data

private struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @State private var includeKey = false
    @State private var share: SharedFile? = nil
    @State private var importing = false
    @State private var pendingImport: Data? = nil
    @State private var resultMessage: String? = nil
    @State private var confirmWipe = false
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Toggle("Include API key", isOn: $includeKey)
                Button {
                    Task {
                        busy = true
                        defer { busy = false }
                        do { share = SharedFile(url: try await app.exportBackup(includeKey: includeKey)) }
                        catch { resultMessage = error.localizedDescription }
                    }
                } label: {
                    HStack { Label("Export backup", systemImage: "square.and.arrow.up"); if busy { Spacer(); ProgressView() } }
                }
                Button { importing = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
            } header: {
                Text("Backup")
            } footer: {
                Text(exportFooter)
            }

            Section("Storage") {
                LabeledContent("Chats", value: "\(app.chats.count)")
                LabeledContent("On this device", value: Fmt.bytes(app.store.diskUsage()))
            }

            Section {
                Button("Erase everything", role: .destructive) { confirmWipe = true }
            } footer: {
                Text("Deletes every chat, the key and all settings from this device.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $share) { f in ShareSheet(items: [f.url]) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { pendingImport = try Data(contentsOf: url) }
                catch { resultMessage = error.localizedDescription }
            case .failure(let e):
                resultMessage = e.localizedDescription
            }
        }
        .confirmationDialog("Import backup", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button("Merge with what's here") { runImport(replace: false) }
            Button("Replace everything", role: .destructive) { runImport(replace: true) }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Merging keeps your chats and adds or updates the ones in the file. Replacing deletes what's here first.")
        }
        .confirmationDialog("Erase everything?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { Task { await app.wipeEverything() } }
        } message: {
            Text("This can't be undone. Export a backup first if you might want these chats.")
        }
        .alert("Backup", isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK", role: .cancel) { resultMessage = nil }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var exportFooter: String {
        var s = "A JSON file in the same format as the Quire web app, so backups move between the two in either direction."
        if let last = app.settings.lastExportAt, last > 0 {
            s += " Last export: \(Date(timeIntervalSince1970: last / 1000).formatted(date: .abbreviated, time: .omitted))."
        }
        return s
    }

    private func runImport(replace: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        Task {
            do {
                let r = try await app.importBackup(data, replace: replace)
                resultMessage = "Imported \(r.chats) chats and \(r.messages) messages."
            } catch {
                resultMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: version)
                Link("OpenRouter activity", destination: URL(string: "https://openrouter.ai/activity")!)
            }
            Section("Privacy") {
                Text("No accounts, no analytics. Chats and settings stay on this iPhone; the key is in the Keychain. The only network traffic is to OpenRouter (or the base URL you set).")
                    .font(.footnote)
            }
            Section("Not in this build yet") {
                Text("Memory, personas, folders, editing a sent message, and the full parameter editor. Personas and memory imported from the web app are kept and exported again unchanged.")
                    .font(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.qBase)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
