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

/// How the list is ordered.
nonisolated enum ModelOrder: String, CaseIterable, Hashable, Sendable {
    case catalogue, newest, cheapest, context

    var label: String {
        switch self {
        case .catalogue: "Popular"
        case .newest: "Newest"
        case .cheapest: "Cheapest"
        case .context: "Longest"
        }
    }

    func sorted(_ models: [ORModel]) -> [ORModel] {
        switch self {
        case .catalogue: models
        case .newest: models.sorted { $0.created > $1.created }
        case .cheapest: models.sorted { Self.price($0) < Self.price($1) }
        case .context: models.sorted { $0.contextLength > $1.contextLength }
        }
    }

    /// A blend weighted toward output, which is most of what a chat pays for.
    private static func price(_ m: ORModel) -> Double {
        Pricing.parse(m.pricing.prompt) + 3 * Pricing.parse(m.pricing.completion)
    }
}

/// Choosing a model, laid out like the rest of Quire: what's chosen now set out at the top, a
/// strip of what a model must be able to do, the finer filters a tap away, and the models in cards
/// of rows, each with its maker's mark, what it costs and holds, and what it can take.
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
    @State private var order: ModelOrder = .catalogue
    @State private var showFilters = false
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

    /// The filters folded behind Filters: provider, price, context.
    private var tuckedCount: Int { (price == .any ? 0 : 1) + (context == .any ? 0 : 1) + (provider == nil ? 0 : 1) }

    private var activeFilterCount: Int { abilities.count + tuckedCount + (onlyNew ? 1 : 0) }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isBrowsing: Bool { !searching && activeFilterCount == 0 }

    private var filtered: [ORModel] {
        let base = app.models.filter { m in
            (provider == nil || m.provider == provider)
                && (!onlyNew || app.newModelIds.contains(m.id))
                && price.passes(m)
                && context.passes(m)
                && abilities.allSatisfy { $0.passes(m) }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return order.sorted(base) }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xxl) {
                    if !searching, let id = selected { current(id) }
                    filterBar
                    if app.models.isEmpty {
                        loadingState
                    } else if isBrowsing {
                        let recents = app.settings.recentModelIds.compactMap { app.model($0) }.filter { $0.id != selected }.prefix(5)
                        if !recents.isEmpty { section("Recent", Array(recents)) }
                        let favs = app.settings.favouriteModelIds.compactMap { app.model($0) }
                            .filter { $0.id != selected && !recents.map(\.id).contains($0.id) }
                        if !favs.isEmpty { section("Favourites", favs) }
                        section("All \(app.models.count.formatted()) models", order.sorted(app.models))
                    } else if filtered.isEmpty {
                        noMatches
                    } else {
                        section("\(filtered.count.formatted()) of \(app.models.count.formatted()) models", filtered)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxxl)
            }
            .scrollDismissesKeyboard(.immediately)
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
            .animation(listAnimation, value: order)
            .sheet(item: $card) { m in
                ModelCardView(model: m, onUse: { pick(m.id) })
            }
            .task { await app.refreshModels() }
            .onDisappear { if onlyNew { app.acknowledgeNewModels() } }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Now

    /// The model chosen now, set out like the Models page's headline: its maker, its name in the
    /// display face, and what it holds and costs. Tap for everything OpenRouter says about it.
    private func current(_ id: String) -> some View {
        let m = app.model(id)
        return Button {
            if let m { card = m }
        } label: {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(alignment: .center, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Chosen")
                            .font(.caption.weight(.semibold))
                            .tracking(1.1)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.qAccent)
                        Text(m?.shortName ?? app.modelName(id))
                            .displayFont { .system(.title3, design: $0).weight(.semibold) }
                            .foregroundStyle(Color.qInk)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    if m != nil {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundStyle(Color.qInk2)
                    }
                }
                if let m {
                    HStack(alignment: .top, spacing: 0) {
                        figure(Fmt.context(m.contextLength), "Context")
                        Spacer(minLength: 8)
                        figure(m.isFree ? "Free" : Pricing.perMillion(m.pricing.prompt), "In, per million")
                        Spacer(minLength: 8)
                        figure(m.isFree ? "Free" : Pricing.perMillion(m.pricing.completion), "Out, per million")
                    }
                } else if !app.models.isEmpty {
                    Text("Not in OpenRouter's catalogue right now.")
                        .font(.footnote)
                        .foregroundStyle(Color.qDanger)
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: Radius.l)
            .contentShape(.rect(cornerRadius: Radius.l))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(m == nil)
        .accessibilityHint("Shows everything about it")
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
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

    // MARK: Filters

    /// One strip: the finer filters' switch, then what a model must be able to take or do. The
    /// finer ones (provider, price, context, and the order) open underneath it.
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    filtersChip
                    if activeFilterCount > 0 {
                        Button(action: clearFilters) {
                            Text("Clear")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.qAccent)
                                .padding(.horizontal, Space.m)
                                .frame(height: 34)
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
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.s)   // room for the chips' glow
            }
            .padding(.horizontal, -Space.xl)
            .padding(.vertical, -Space.s)

            if showFilters {
                finer
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.reveal, value: showFilters)
        .animation(reduceMotion ? nil : Motion.quick, value: activeFilterCount)
    }

    private var filtersChip: some View {
        Button {
            Haptics.selection()
            showFilters.toggle()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(tuckedCount > 0 ? "Filters · \(tuckedCount)" : "Filters")
                    .contentTransition(.numericText())
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(showFilters ? 180 : 0))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tuckedCount > 0 ? Color.qAccent : Color.qInk)
            .padding(.horizontal, Space.l)
            .frame(height: 34)
            .background(tuckedCount > 0 ? Color.qAccentSoft : Color.qRaised, in: .capsule)
            .overlay(Capsule().strokeBorder(tuckedCount > 0 ? Color.clear : Color.qRule, lineWidth: 1))
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Filters")
        .accessibilityValue(tuckedCount > 0 ? "\(tuckedCount) on" : "")
        .accessibilityHint(showFilters ? "Hides provider, price, context and order" : "Shows provider, price, context and order")
    }

    /// Provider, price, context and order, in a card of their own.
    private var finer: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            filterLine("Provider") { providerTrack }
            filterLine("Price") {
                SlidingSegments(options: PriceFilter.allCases.map { (value: $0, label: $0.label) }, selection: $price)
            }
            filterLine("Context") {
                SlidingSegments(options: ContextFilter.allCases.map { (value: $0, label: $0.label) }, selection: $context)
            }
            filterLine("Order") {
                SlidingSegments(options: ModelOrder.allCases.map { (value: $0, label: $0.label) }, selection: $order)
            }
        }
        .padding(Space.l)
        .card(radius: Radius.l)
    }

    private func filterLine<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(Color.qInk2)
                .padding(.horizontal, Space.xs)
            control()
        }
    }

    /// Providers by name, busiest first, scrolling sideways. The highlight slides to the one you
    /// tap; tap it again (or All) to clear it.
    private var providerTrack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xxs) {
                providerSegment(nil, count: app.models.count)
                ForEach(providers) { p in providerSegment(p.id, count: p.count) }
            }
            .padding(Space.xs)
            .background(Color.qSunken, in: .capsule)
        }
        .clipShape(.capsule)
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
            HStack(spacing: Space.xs) {
                Text(name)
                    .font(.footnote.weight(on ? .semibold : .medium))
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .opacity(0.7)
            }
            .foregroundStyle(on ? Color.qOnAccent : Color.qInk2)
            .lineLimit(1)
            .padding(.horizontal, Space.m)
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
        VStack(spacing: Space.m) {
            if app.loadingModels {
                ProgressView()
                Text("Loading OpenRouter's models…")
                    .font(.subheadline)
                    .foregroundStyle(Color.qInk2)
            } else {
                Text(app.modelsError ?? "No models loaded yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.qInk2)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await app.refreshModels(force: true) } }
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxxl)
    }

    private var noMatches: some View {
        VStack(spacing: Space.m) {
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
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxxl)
    }

    // MARK: Rows

    /// A label over a card of rows divided by hairlines. Lazy all the way down, since "All models"
    /// runs to hundreds.
    private func section(_ label: String, _ models: [ORModel]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(text: label)
                .padding(.horizontal, Space.xs)
            LazyVStack(spacing: 0) {
                ForEach(Array(models.enumerated()), id: \.element.id) { i, m in
                    if i > 0 {
                        Rectangle()
                            .fill(Color.qRule)
                            .frame(height: 0.5)
                            .padding(.leading, Space.l)
                    }
                    row(m)
                }
            }
            .card(radius: Radius.l)
            .clipShape(.rect(cornerRadius: Radius.l, style: .continuous))
        }
    }

    private func row(_ m: ORModel) -> some View {
        let isSelected = m.id == selected
        let isFav = app.settings.favouriteModelIds.contains(m.id)
        return HStack(spacing: 0) {
            Button { pick(m.id) } label: {
                HStack(alignment: .center, spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        HStack(spacing: Space.xs) {
                            Text(m.shortName)
                                .font(.body.weight(isSelected ? .semibold : .medium))
                                .foregroundStyle(Color.qInk)
                                .lineLimit(1)
                            if isFav {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Color.qWarn)
                                    .accessibilityLabel("Favourite")
                            }
                            if app.newModelIds.contains(m.id) {
                                Text("NEW")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.qAccent)
                                    .padding(.horizontal, Space.xs)
                                    .padding(.vertical, 1)
                                    .background(Color.qAccentSoft, in: .capsule)
                            }
                        }
                        HStack(spacing: Space.xs) {
                            Text("\(ProviderStyle.displayName(m.provider)) · \(Fmt.context(m.contextLength)) ·")
                            if m.isFree {
                                Text("Free").foregroundStyle(Color.qAccent)
                            } else {
                                Text("\(Pricing.perMillion(m.pricing.prompt)) / \(Pricing.perMillion(m.pricing.completion))")
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                        abilities(of: m)
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.qAccent)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.leading, Space.l)
                .padding(.vertical, Space.m)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.row)
            Button { card = m } label: {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(Color.qInk2)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.trailing, Space.xs)
            .accessibilityLabel("Details for \(m.shortName)")
        }
        .background(isSelected ? Color.qAccentSoft.opacity(0.6) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(m.shortName), \(ProviderStyle.displayName(m.provider)), \(Fmt.context(m.contextLength)) context, \(m.isFree ? "free" : "\(Pricing.perMillion(m.pricing.prompt)) in, \(Pricing.perMillion(m.pricing.completion)) out per million")")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { pick(m.id) }
        .accessibilityAction(named: "Details") { card = m }
        .accessibilityAction(named: isFav ? "Remove from favourites" : "Add to favourites") { app.toggleFavourite(m.id) }
        .contextMenu {
            Button { card = m } label: { Label("Details", systemImage: "info.circle") }
            Button { app.toggleFavourite(m.id) } label: { Label(isFav ? "Unfavourite" : "Favourite", systemImage: isFav ? "star.slash" : "star") }
            Button {
                app.settings.defaultModelId = m.id
                app.toasts.show("Default model set", symbol: "checkmark")
            } label: { Label("Set as default", systemImage: "pin") }
        }
    }

    /// What it can take or do beyond text, as small marks under its line.
    @ViewBuilder
    private func abilities(of m: ORModel) -> some View {
        let marks = ModelAbility.allCases.filter { $0 != .structured && $0.passes(m) }
        if !marks.isEmpty {
            HStack(spacing: Space.s) {
                ForEach(marks) { a in
                    HStack(spacing: 3) {
                        Image(systemName: a.symbol)
                        Text(a.rawValue)
                    }
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.qInk2.opacity(0.9))
            .padding(.top, 1)
            .accessibilityHidden(true)
        }
    }

    private func pick(_ id: String) {
        Haptics.selection()
        onPick(id)
        app.touchRecent(id)
        dismiss()
    }
}

/// Everything OpenRouter says about one model, set out as a Quire page: the headline, what it
/// costs, what it holds, and what it takes.
struct ModelCardView: View {
    let model: ORModel
    let onUse: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsPage(title: model.shortName, inlineTitle: true) {
                headline
                SettingsGroup(label: "Price per million tokens") {
                    line("Prompt", Pricing.perMillion(model.pricing.prompt))
                    line("Completion", Pricing.perMillion(model.pricing.completion))
                    if Pricing.parse(model.pricing.internalReasoning) > 0 { line("Reasoning", Pricing.perMillion(model.pricing.internalReasoning)) }
                    if let r = model.pricing.cacheRead, Pricing.parse(r) > 0 { line("Cache read", Pricing.perMillion(r)) }
                    if let w = model.pricing.cacheWrite, Pricing.parse(w) > 0 { line("Cache write", Pricing.perMillion(w)) }
                    if Pricing.parse(model.pricing.image) > 0 { line("Per image", String(format: "$%.4f", Pricing.parse(model.pricing.image))) }
                    if Pricing.parse(model.pricing.request) > 0 { line("Per request", String(format: "$%.4f", Pricing.parse(model.pricing.request))) }
                    if Pricing.parse(model.pricing.webSearch) > 0 { line("Web search", String(format: "$%.4f", Pricing.parse(model.pricing.webSearch))) }
                }
                SettingsGroup(label: "Limits") {
                    line("Context", "\(model.contextLength.formatted()) tokens")
                    if let t = model.topContextLength { line("Top provider context", t.formatted()) }
                    if let c = model.maxCompletionTokens { line("Max completion", c.formatted()) }
                    line("Moderated", model.isModerated ? "Yes" : "No")
                    line("Input", model.inputModalities.joined(separator: ", "))
                    line("Output", model.outputModalities.joined(separator: ", "))
                    if let t = model.tokenizer, !t.isEmpty { line("Tokenizer", t) }
                }
                SettingsGroup(label: "Supported parameters") {
                    Text(model.supportedParameters.isEmpty ? "None listed" : model.supportedParameters.joined(separator: "  ·  "))
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.qInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Space.m)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    let fav = app.settings.favouriteModelIds.contains(model.id)
                    Button {
                        app.toggleFavourite(model.id)
                        Haptics.selection()
                    } label: {
                        Image(systemName: fav ? "star.fill" : "star")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(fav ? "Remove from favourites" : "Add to favourites")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .center, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(ProviderStyle.displayName(model.provider))
                        .font(.caption.weight(.semibold))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.qAccent)
                    Text(model.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Text(model.description.isEmpty ? "No description." : model.description)
                .displayFont { .system(.callout, design: $0) }
                .foregroundStyle(Color.qInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                Button {
                    dismiss()
                    onUse()
                } label: {
                    Label("Use this model", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qOnAccent)
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 38)
                        .background(Color.qAccent, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                let isDefault = app.settings.defaultModelId == model.id
                Button {
                    app.settings.defaultModelId = model.id
                    Haptics.success()
                } label: {
                    Label(isDefault ? "Default" : "Set as default", systemImage: "pin")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qInk)
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 38)
                        .background(Color.qInk.opacity(0.07), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .disabled(isDefault)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: Radius.l)
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(label)
                .foregroundStyle(Color.qInk2)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(Color.qInk)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, Space.m)
        .accessibilityElement(children: .combine)
    }
}
