import SwiftUI

nonisolated enum ModelFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case vision = "Vision", files = "Files", tools = "Tools", reasoning = "Reasoning", structured = "Structured"
    case free = "Free", cheap = "Cheap", mid = "Mid", premium = "Premium"
    case ctx32 = "≥32k", ctx200 = "≥200k", ctx1m = "≥1M"
    var id: String { rawValue }

    var symbol: String? {
        switch self {
        case .vision: "eye"
        case .files: "doc"
        case .tools: "wrench.and.screwdriver"
        case .reasoning: "brain"
        case .structured: "curlybraces"
        default: nil
        }
    }

    func passes(_ m: ORModel) -> Bool {
        switch self {
        case .vision: m.acceptsImages
        case .files: m.acceptsFiles
        case .tools: m.supportsTools
        case .reasoning: m.supportsReasoning
        case .structured: m.supportsStructured
        case .free: m.priceBand == .free
        case .cheap: m.priceBand == .cheap
        case .mid: m.priceBand == .mid
        case .premium: m.priceBand == .premium
        case .ctx32: m.contextLength >= 32_000
        case .ctx200: m.contextLength >= 200_000
        case .ctx1m: m.contextLength >= 1_000_000
        }
    }
}

struct ModelPickerView: View {
    var title: String = "Model"
    let selected: String?
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filters: Set<ModelFilter> = []
    @State private var provider: String? = nil
    @State private var onlyNew = false
    @State private var card: ORModel? = nil

    private var providers: [String] { Array(Set(app.models.map(\.provider))).sorted() }

    private var filtered: [ORModel] {
        let base = app.models.filter { m in
            (provider == nil || m.provider == provider)
                && (!onlyNew || app.newModelIds.contains(m.id))
                && filters.allSatisfy { $0.passes(m) }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base
            .map { (m: ORModel) -> (ORModel, Double) in
                (m, max(TextUtil.fuzzyScore(q, m.id) * 1.2, TextUtil.fuzzyScore(q, m.name) * 1.1, TextUtil.fuzzyScore(q, String(m.description.prefix(200))) * 0.5))
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private var isBrowsing: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && filters.isEmpty && provider == nil && !onlyNew }

    var body: some View {
        NavigationStack {
            List {
                Section { filterBar }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)

                if app.models.isEmpty {
                    Section { loadingState }
                } else if isBrowsing {
                    let recents = app.settings.recentModelIds.compactMap { app.model($0) }
                    if !recents.isEmpty {
                        Section { ForEach(recents) { row($0) } } header: { SectionLabel(text: "Recent") }
                    }
                    let favs = app.settings.favouriteModelIds.compactMap { app.model($0) }.filter { !app.settings.recentModelIds.contains($0.id) }
                    if !favs.isEmpty {
                        Section { ForEach(favs) { row($0) } } header: { SectionLabel(text: "Favourites") }
                    }
                    Section { ForEach(app.models) { row($0) } } header: { SectionLabel(text: "All \(app.models.count) models") }
                } else {
                    Section {
                        if filtered.isEmpty {
                            Text("No models match.").foregroundStyle(Color.qInk2)
                        }
                        ForEach(filtered) { row($0) }
                    } header: {
                        SectionLabel(text: "\(filtered.count) \(filtered.count == 1 ? "model" : "models")")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name, id or description")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await app.refreshModels(force: true) } } label: {
                        if app.loadingModels { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityLabel("Refresh models")
                }
            }
            .animation(Motion.quick, value: filters)
            .animation(Motion.quick, value: provider)
            .sheet(item: $card) { m in
                ModelCardView(model: m, onUse: { pick(m.id) })
            }
            .task { await app.refreshModels() }
            .onDisappear { if onlyNew { app.acknowledgeNewModels() } }
        }
        .presentationDragIndicator(.visible)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !app.newModelIds.isEmpty {
                    FilterChip(title: "New · \(app.newModelIds.count)", symbol: "sparkles", isOn: onlyNew) { onlyNew.toggle() }
                }
                Menu {
                    Button { provider = nil } label: { checkLabel("All providers", on: provider == nil) }
                    Divider()
                    ForEach(providers, id: \.self) { p in
                        Button { provider = p } label: { checkLabel(p, on: provider == p) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(provider ?? "Provider")
                        Image(systemName: "chevron.down").imageScale(.small)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(provider == nil ? Color.qInk : Color.qOnAccent)
                    .background(provider == nil ? Color.qRaised : Color.qAccent, in: .capsule)
                    .overlay(Capsule().strokeBorder(provider == nil ? Color.qRule : Color.clear, lineWidth: 1))
                }
                ForEach(ModelFilter.allCases) { f in
                    FilterChip(title: f.rawValue, symbol: f.symbol, isOn: filters.contains(f)) {
                        if filters.contains(f) { filters.remove(f) } else { filters.insert(f) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func checkLabel(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    @ViewBuilder
    private var loadingState: some View {
        if app.loadingModels {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading OpenRouter's models…").foregroundStyle(Color.qInk2)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(app.modelsError ?? "No models loaded yet.").foregroundStyle(Color.qInk2)
                Button("Try again") { Task { await app.refreshModels(force: true) } }
            }
        }
    }

    private func row(_ m: ORModel) -> some View {
        let isSelected = m.id == selected
        let isFav = app.settings.favouriteModelIds.contains(m.id)
        return Button { pick(m.id) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(m.shortName)
                            .font(.body.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                        if app.newModelIds.contains(m.id) {
                            Text("NEW")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.qOnAccent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.qAccent, in: .capsule)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(m.provider)
                        Text("·")
                        Text(Fmt.context(m.contextLength))
                        Text("·")
                        Text(m.isFree ? "free" : "\(Pricing.perMillion(m.pricing.prompt))/\(Pricing.perMillion(m.pricing.completion))")
                        if m.acceptsImages { Image(systemName: "eye").accessibilityLabel("Vision") }
                        if m.supportsReasoning { Image(systemName: "brain").accessibilityLabel("Reasoning") }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.qAccent)
                        .accessibilityHidden(true)
                }
                Button { app.toggleFavourite(m.id) } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundStyle(isFav ? Color.qAccent : Color.qInk2)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isFav ? "Remove from favourites" : "Add to favourites")
            }
        }
        .listRowBackground(Color.qRaised)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button { card = m } label: { Label("Details", systemImage: "info.circle") }
            Button { app.toggleFavourite(m.id) } label: { Label(isFav ? "Unfavourite" : "Favourite", systemImage: isFav ? "star.slash" : "star") }
            Button {
                app.settings.defaultModelId = m.id
                app.toasts.show("Default model set", symbol: "checkmark")
            } label: { Label("Set as default", systemImage: "pin") }
        }
        .swipeActions(edge: .trailing) {
            Button { card = m } label: { Label("Details", systemImage: "info.circle") }
                .tint(Color.qTileSlate)
        }
    }

    private func pick(_ id: String) {
        Haptics.selection()
        onPick(id)
        app.touchRecent(id)
        dismiss()
    }
}

/// Everything OpenRouter says about one model.
struct ModelCardView: View {
    let model: ORModel
    let onUse: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.id)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.qInk2)
                            .textSelection(.enabled)
                        Text(model.description.isEmpty ? "No description." : model.description)
                            .font(.system(.callout, design: .serif))
                            .foregroundStyle(Color.qInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    HStack {
                        Button {
                            dismiss()
                            onUse()
                        } label: { Label("Use this model", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent)
                        Button {
                            app.settings.defaultModelId = model.id
                            Haptics.success()
                        } label: { Label(app.settings.defaultModelId == model.id ? "Default" : "Set as default", systemImage: "pin") }
                            .buttonStyle(.bordered)
                            .disabled(app.settings.defaultModelId == model.id)
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Section {
                    priceRow("Prompt", Pricing.perMillion(model.pricing.prompt))
                    priceRow("Completion", Pricing.perMillion(model.pricing.completion))
                    if Pricing.parse(model.pricing.internalReasoning) > 0 { priceRow("Reasoning", Pricing.perMillion(model.pricing.internalReasoning)) }
                    if let r = model.pricing.cacheRead, Pricing.parse(r) > 0 { priceRow("Cache read", Pricing.perMillion(r)) }
                    if let w = model.pricing.cacheWrite, Pricing.parse(w) > 0 { priceRow("Cache write", Pricing.perMillion(w)) }
                    if Pricing.parse(model.pricing.image) > 0 { priceRow("Per image", String(format: "$%.4f", Pricing.parse(model.pricing.image))) }
                    if Pricing.parse(model.pricing.request) > 0 { priceRow("Per request", String(format: "$%.4f", Pricing.parse(model.pricing.request))) }
                    if Pricing.parse(model.pricing.webSearch) > 0 { priceRow("Web search", String(format: "$%.4f", Pricing.parse(model.pricing.webSearch))) }
                } header: { SectionLabel(text: "Price per million tokens") }

                Section {
                    priceRow("Context", "\(model.contextLength.formatted()) tokens")
                    if let t = model.topContextLength { priceRow("Top provider context", t.formatted()) }
                    if let c = model.maxCompletionTokens { priceRow("Max completion", c.formatted()) }
                    priceRow("Moderated", model.isModerated ? "Yes" : "No")
                    priceRow("Input", model.inputModalities.joined(separator: ", "))
                    priceRow("Output", model.outputModalities.joined(separator: ", "))
                    if let t = model.tokenizer, !t.isEmpty { priceRow("Tokenizer", t) }
                } header: { SectionLabel(text: "Limits") }

                Section {
                    if model.supportedParameters.isEmpty {
                        Text("None listed").foregroundStyle(Color.qInk2)
                    } else {
                        Text(model.supportedParameters.joined(separator: "  ·  "))
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.qInk2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: { SectionLabel(text: "Supported parameters") }
            }
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .navigationTitle(model.shortName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { app.toggleFavourite(model.id) } label: {
                        Image(systemName: app.settings.favouriteModelIds.contains(model.id) ? "star.fill" : "star")
                    }
                    .accessibilityLabel("Favourite")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func priceRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).monospacedDigit().foregroundStyle(Color.qInk)
        }
    }
}
