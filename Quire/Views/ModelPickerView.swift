import SwiftUI

/// What a model can take or do. Any number can be on at once.
nonisolated enum ModelAbility: String, CaseIterable, Identifiable, Hashable, Sendable {
    case vision = "Vision", files = "Files", tools = "Tools", reasoning = "Reasoning", structured = "JSON"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .vision: "eye"
        case .files: "doc"
        case .tools: "wrench.and.screwdriver"
        case .reasoning: "brain"
        case .structured: "curlybraces"
        }
    }

    func passes(_ m: ORModel) -> Bool {
        switch self {
        case .vision: m.acceptsImages
        case .files: m.acceptsFiles
        case .tools: m.supportsTools
        case .reasoning: m.supportsReasoning
        case .structured: m.supportsStructured
        }
    }
}

/// One price band at a time (a model can't be both free and premium).
nonisolated enum PriceFilter: String, CaseIterable, Hashable, Sendable {
    case any, free, cheap, mid, premium

    var label: String {
        switch self {
        case .any: "Any"
        case .free: "Free"
        case .cheap: "$"
        case .mid: "$$"
        case .premium: "$$$"
        }
    }

    func passes(_ m: ORModel) -> Bool {
        switch self {
        case .any: true
        case .free: m.priceBand == .free
        case .cheap: m.priceBand == .cheap
        case .mid: m.priceBand == .mid
        case .premium: m.priceBand == .premium
        }
    }
}

/// A minimum context window.
nonisolated enum ContextFilter: Int, CaseIterable, Hashable, Sendable {
    case any = 0, k32 = 32_000, k128 = 128_000, m1 = 1_000_000

    var label: String {
        switch self {
        case .any: "Any"
        case .k32: "32k+"
        case .k128: "128k+"
        case .m1: "1M+"
        }
    }

    func passes(_ m: ORModel) -> Bool { m.contextLength >= rawValue }
}

struct ModelPickerView: View {
    var title: String = "Model"
    let selected: String?
    let onPick: (String) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var abilities: Set<ModelAbility> = []
    @State private var price: PriceFilter = .any
    @State private var context: ContextFilter = .any
    @State private var provider: String? = nil
    @State private var onlyNew = false
    @State private var card: ORModel? = nil
    @Namespace private var providerSpace

    private struct ProviderCount: Identifiable {
        let id: String
        let count: Int
    }

    /// Providers by how many models they offer, most first.
    private var providers: [ProviderCount] {
        Dictionary(grouping: app.models, by: { $0.provider })
            .map { ProviderCount(id: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
    }

    private var activeFilterCount: Int {
        abilities.count + (price == .any ? 0 : 1) + (context == .any ? 0 : 1) + (provider == nil ? 0 : 1) + (onlyNew ? 1 : 0)
    }

    private var isBrowsing: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty && activeFilterCount == 0 }

    private var filtered: [ORModel] {
        let base = app.models.filter { m in
            (provider == nil || m.provider == provider)
                && (!onlyNew || app.newModelIds.contains(m.id))
                && price.passes(m)
                && context.passes(m)
                && abilities.allSatisfy { $0.passes(m) }
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

    private var listAnimation: Animation? { reduceMotion ? nil : Motion.quick }

    var body: some View {
        NavigationStack {
            List {
                Section { filterPanel }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if app.models.isEmpty {
                    Section { loadingState }
                        .listRowBackground(Color.qRaised)
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
                } else if filtered.isEmpty {
                    Section { noMatches }
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(filtered) { row($0) }
                    } header: {
                        SectionLabel(text: "\(filtered.count) of \(app.models.count) models")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .searchable(text: $query, prompt: "Search models")
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
                // Search lives at the bottom, within thumb's reach.
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
            .animation(listAnimation, value: abilities)
            .animation(listAnimation, value: price)
            .animation(listAnimation, value: context)
            .animation(listAnimation, value: provider)
            .animation(listAnimation, value: onlyNew)
            .sheet(item: $card) { m in
                ModelCardView(model: m, onUse: { pick(m.id) })
            }
            .task { await app.refreshModels() }
            .onDisappear { if onlyNew { app.acknowledgeNewModels() } }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Filters

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            abilityRow
            VStack(spacing: 8) {
                filterLine("Provider") { providerTrack }
                filterLine("Price") {
                    SlidingSegments(options: PriceFilter.allCases.map { (value: $0, label: $0.label) }, selection: $price)
                }
                filterLine("Context") {
                    SlidingSegments(options: ContextFilter.allCases.map { (value: $0, label: $0.label) }, selection: $context)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func filterLine<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(Color.qInk2)
                .frame(width: 62, alignment: .leading)
            control()
        }
    }

    /// Providers by name, busiest first, in the same track as price and context but scrolling
    /// sideways. The highlight slides to the one you tap; tap it again (or All) to clear it.
    private var providerTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                providerSegment(nil, count: app.models.count)
                ForEach(providers) { p in providerSegment(p.id, count: p.count) }
            }
            .padding(3)
            .background(Color.qRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.qRule, lineWidth: 1))
        }
        .contentMargins(.horizontal, 10, for: .scrollContent)
        // Soft edges say "there's more this way" without a scroll bar.
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                   .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .padding(.horizontal, -10)
    }

    private func providerSegment(_ p: String?, count: Int) -> some View {
        let on = provider == p
        let name = p.map { ProviderStyle.displayName($0) } ?? "All"
        return Button {
            Haptics.selection()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy) {
                provider = (p == nil || on) ? nil : p
            }
        } label: {
            HStack(spacing: 5) {
                Text(name)
                    .font(.footnote.weight(on ? .semibold : .medium))
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .opacity(0.7)
            }
            .foregroundStyle(on ? Color.qOnAccent : Color.qInk2)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                if on {
                    Capsule()
                        .fill(Color.qAccent.gradient)
                        .matchedGeometryEffect(id: "provider", in: providerSpace)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(p == nil ? "All providers" : name), \(count) models")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var abilityRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if activeFilterCount > 0 {
                    Button(action: clearFilters) {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark")
                            Text("Clear · \(activeFilterCount)")
                                .contentTransition(.numericText())
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Color.qAccentSoft, in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                    .transition(reduceMotion ? .opacity : .pop)
                    .accessibilityLabel("Clear \(activeFilterCount) filters")
                }
                if !app.newModelIds.isEmpty {
                    ToggleChip(title: "New · \(app.newModelIds.count)", symbol: "sparkles", isOn: onlyNew) { onlyNew.toggle() }
                }
                ForEach(ModelAbility.allCases) { a in
                    ToggleChip(title: a.rawValue, symbol: a.symbol, isOn: abilities.contains(a)) {
                        if abilities.contains(a) { abilities.remove(a) } else { abilities.insert(a) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)   // room for the chips' glow
        }
    }

    private func clearFilters() {
        Haptics.tap()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy) {
            abilities = []
            price = .any
            context = .any
            provider = nil
            onlyNew = false
        }
    }

    // MARK: States

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

    private var noMatches: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.qInk2)
            Text("No models match")
                .displayFont { .system(.headline, design: $0) }
                .foregroundStyle(Color.qInk)
            Text("Try fewer filters, or a different search.")
                .font(.subheadline)
                .foregroundStyle(Color.qInk2)
            if activeFilterCount > 0 {
                Button("Clear filters", action: clearFilters)
                    .buttonStyle(.glass)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    // MARK: Rows

    private func row(_ m: ORModel) -> some View {
        let isSelected = m.id == selected
        let isFav = app.settings.favouriteModelIds.contains(m.id)
        return Button { pick(m.id) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(m.shortName)
                            .font(.body.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                        if app.newModelIds.contains(m.id) {
                            Text("NEW")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.qOnAccent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.qAccent.gradient, in: .capsule)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(ProviderStyle.displayName(m.provider))
                        Text("·")
                        Text(Fmt.context(m.contextLength))
                        Text("·")
                        if m.isFree {
                            Text("Free").foregroundStyle(Color.qTileTeal)
                        } else {
                            Text("\(Pricing.perMillion(m.pricing.prompt)) / \(Pricing.perMillion(m.pricing.completion))")
                        }
                        HStack(spacing: 4) {
                            if m.acceptsImages { Image(systemName: "eye").accessibilityLabel("Vision") }
                            if m.supportsReasoning { Image(systemName: "brain").accessibilityLabel("Reasoning") }
                            if m.supportsTools { Image(systemName: "wrench.and.screwdriver").accessibilityLabel("Tools") }
                        }
                        .imageScale(.small)
                        .padding(.leading, 2)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.qAccent)
                        .accessibilityHidden(true)
                }
                Button {
                    app.toggleFavourite(m.id)
                    Haptics.selection()
                } label: {
                    Image(systemName: isFav ? "star.fill" : "star")
                        .foregroundStyle(isFav ? Color.qWarn : Color.qInk2.opacity(0.6))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isFav)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isFav ? "Remove from favourites" : "Add to favourites")
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(isSelected ? Color.qAccentSoft : Color.qRaised)
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
                            .displayFont { .system(.callout, design: $0) }
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
