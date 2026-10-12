import SwiftUI

/// The generation settings editor, used at three levels: global defaults, a persona, one chat.
///
/// `target` is what gets written. `base` is what the level inherits (nil when editing the global
/// defaults). Each control shows `target`'s value if set, else the inherited one; a dot marks values
/// set at this level, and Inherit clears them. Only parameters the model reports as supported are
/// shown; the rest are listed, kept, and sent when you switch to a model that takes them.
struct ParamsEditor: View {
    let model: ORModel?
    @Binding var target: GenerationSettings
    let base: GenerationSettings?
    @Environment(AppModel.self) private var app
    @State private var showAdvanced = false
    @State private var pickFallback = false

    private var display: GenerationSettings { (base ?? GenerationSettings.defaults).merged(with: target) }
    private var overrideMode: Bool { base != nil }

    var body: some View {
        // A Group would copy any modifier onto every section, so the one sheet lives on the routing section.
        Group {
            samplingSection
            if model?.supportsReasoning == true { reasoningSection }
            routingSection
                .sheet(isPresented: $pickFallback) {
                    ModelPickerView(title: "Add a fallback model", selected: nil) { id in
                        var list = display.fallbackModels ?? []
                        if !list.contains(id) { list.append(id) }
                        target.fallbackModels = list
                    }
                }
            infoSection
        }
    }

    // MARK: Sampling

    private struct SliderSpec {
        let api: String
        let label: String
        let help: String
        let keyPath: WritableKeyPath<GenerationSettings, Double?>
        let range: ClosedRange<Double>
        let step: Double
        let fallback: Double
    }

    private static let sliders: [SliderSpec] = [
        SliderSpec(api: "temperature", label: "Temperature", help: "How much randomness to allow. 0 is nearly deterministic; above 1.2 gets loose.", keyPath: \.temperature, range: 0...2, step: 0.05, fallback: 1),
        SliderSpec(api: "top_p", label: "Top P", help: "Only sample from the smallest set of tokens whose probabilities add up to this. 1 means no cutoff.", keyPath: \.topP, range: 0...1, step: 0.01, fallback: 1),
        SliderSpec(api: "frequency_penalty", label: "Frequency penalty", help: "Push down tokens in proportion to how often they already appeared. Reduces repetition.", keyPath: \.frequencyPenalty, range: -2...2, step: 0.05, fallback: 0),
        SliderSpec(api: "presence_penalty", label: "Presence penalty", help: "Push down any token that has appeared at all. Encourages new topics.", keyPath: \.presencePenalty, range: -2...2, step: 0.05, fallback: 0),
        SliderSpec(api: "repetition_penalty", label: "Repetition penalty", help: "Multiplicative penalty on repeated tokens. 1 is off; above 1 discourages repeats.", keyPath: \.repetitionPenalty, range: 0...2, step: 0.01, fallback: 1),
        SliderSpec(api: "min_p", label: "Min P", help: "Drop tokens whose probability is below this fraction of the top token. 0 is off.", keyPath: \.minP, range: 0...1, step: 0.01, fallback: 0),
        SliderSpec(api: "top_a", label: "Top A", help: "Dynamic cutoff based on the top token's probability squared. 0 is off.", keyPath: \.topA, range: 0...1, step: 0.01, fallback: 0),
    ]

    private func supports(_ api: String) -> Bool { RequestBuilder.supports(model, api) }

    private var samplingSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SamplingPreset.all) { p in
                        FilterChip(title: p.name, isOn: p.matches(display)) {
                            withAnimation(Motion.quick) { p.apply(to: &target) }
                        }
                    }
                    if !SamplingPreset.all.contains(where: { $0.matches(display) }) {
                        Text("Custom")
                            .font(.subheadline)
                            .foregroundStyle(Color.qInk2)
                            .padding(.leading, 4)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            ForEach(Self.sliders.filter { supports($0.api) }, id: \.api) { spec in
                SliderRow(label: spec.label, help: spec.help,
                          value: binding(spec.keyPath),
                          range: spec.range, step: spec.step, fallback: spec.fallback,
                          overridden: isSet(spec.keyPath),
                          onInherit: overrideMode ? { target[keyPath: spec.keyPath] = nil } : nil)
            }

            if supports("top_k") {
                HStack {
                    HelpLabel(title: "Top K", help: "Only consider the K most likely next tokens. 0 turns it off.", overridden: isSet(\.topK))
                    Spacer()
                    inheritButton(isSet(\.topK)) { target.topK = nil }
                    OptionalNumberField(placeholder: "0", value: binding(\.topK), range: 0...1000)
                }
            }

            if supports("seed") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HelpLabel(title: "Seed", help: "Fix the random seed so repeated requests give the same answer where the provider supports it. Empty is random.", overridden: isSet(\.seed))
                        Spacer()
                        inheritButton(isSet(\.seed)) { target.seed = nil }
                        OptionalIntField(placeholder: "Random", value: binding(\.seed), range: 0...2_147_483_647)
                    }
                    HStack(spacing: 12) {
                        Button {
                            target.seed = Int.random(in: 0...2_147_483_647)
                            Haptics.selection()
                        } label: { Label("Roll", systemImage: "dice") }
                        if display.seed != nil {
                            Button("Clear") { target.seed = nil }
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.borderless)
                }
            }

            if supports("max_tokens") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HelpLabel(title: "Max output tokens", help: "Hard cap on the reply's length. Empty lets the model decide, up to its limit.", overridden: isSet(\.maxTokens))
                        Spacer()
                        inheritButton(isSet(\.maxTokens)) { target.maxTokens = nil }
                        OptionalIntField(placeholder: "Model limit", value: binding(\.maxTokens), range: 1...max(1, model?.maxCompletionTokens ?? 2_000_000))
                    }
                    if let cap = model?.maxCompletionTokens, cap > 0 {
                        Button("Use the maximum, \(cap.formatted())") { target.maxTokens = cap }
                            .font(.footnote.weight(.medium))
                            .buttonStyle(.borderless)
                    }
                }
            }

            if supports("stop") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HelpLabel(title: "Stop sequences", help: "Generation halts as soon as any of these appears. Up to four. Type \\n for a line break.", overridden: isSet(\.stop))
                        Spacer()
                        inheritButton(isSet(\.stop)) { target.stop = nil }
                    }
                    TagField(tags: Binding(get: { display.stop ?? [] }, set: { target.stop = $0 }), limit: 4, placeholder: "Add a stop sequence")
                }
            }

            Toggle(isOn: Binding(get: { display.stream ?? true }, set: { target.stream = $0 })) {
                HelpLabel(title: "Stream", help: "Show tokens as they arrive. Off is useful for debugging and for the few models that stream badly.", overridden: isSet(\.stream))
            }
        } header: {
            SectionLabel(text: "Sampling")
        } footer: {
            if overrideMode { Text("● marks a value set here. Everything else is inherited.") }
        }
    }

    // MARK: Reasoning

    private var reasoning: ReasoningSettings { display.reasoning ?? ReasoningSettings() }

    private func setReasoning(_ f: (inout ReasoningSettings) -> Void) {
        var r = reasoning
        f(&r)
        target.reasoning = r
    }

    private var reasoningSection: some View {
        let style = ReasoningStyle.detect(model)
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HelpLabel(title: "Reasoning", help: "Let the model think before answering. Thinking tokens are billed as output.", overridden: isSet(\.reasoning))
                    Spacer()
                    inheritButton(isSet(\.reasoning)) { target.reasoning = nil }
                }
                Picker("Reasoning mode", selection: Binding(get: { reasoning.mode }, set: { m in
                    setReasoning { r in
                        r.mode = m
                        if r.effort == nil { r.effort = .medium }
                        if m == .budget && r.maxTokens == nil { r.maxTokens = style.defaultBudget }
                    }
                })) {
                    if style.canDisable { Text("Off").tag(ReasoningSettings.Mode.off) }
                    Text("Effort").tag(ReasoningSettings.Mode.effort)
                    Text("Budget").tag(ReasoningSettings.Mode.budget)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if !style.canDisable && reasoning.mode == .off {
                    Text("This model always reasons. Pick effort or budget; Hide keeps the trace out of the reply.")
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                }
                if reasoning.mode == .effort {
                    Picker("Effort", selection: Binding(get: { reasoning.effort ?? .medium }, set: { e in setReasoning { $0.effort = e } })) {
                        ForEach(style.efforts, id: \.self) { e in Text(shortLabel(e)).tag(e) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if reasoning.mode == .budget {
                    HStack {
                        Text("Thinking budget").foregroundStyle(Color.qInk)
                        Spacer()
                        OptionalIntField(placeholder: "\(style.defaultBudget)", value: Binding(
                            get: { reasoning.maxTokens },
                            set: { v in setReasoning { $0.maxTokens = v } }), range: 1...200_000)
                        Text("tokens").font(.footnote).foregroundStyle(Color.qInk2)
                    }
                }
            }
            .animation(Motion.quick, value: reasoning.mode)

            Toggle(isOn: Binding(get: { reasoning.exclude }, set: { v in setReasoning { $0.exclude = v } })) {
                HelpLabel(title: "Hide the trace", help: "Think, but don't return the reasoning. Reasoning tokens are still billed.")
            }
        } header: {
            SectionLabel(text: "Reasoning")
        } footer: {
            Text(style.note)
        }
    }

    private func shortLabel(_ e: ReasoningEffort) -> String {
        switch e {
        case .none: "None"
        case .minimal: "Min"
        case .low: "Low"
        case .medium: "Med"
        case .high: "High"
        case .xhigh: "Max"
        }
    }

    // MARK: Routing

    private var provider: ProviderSettings { display.provider ?? ProviderSettings() }

    private func setProvider(_ f: (inout ProviderSettings) -> Void) {
        var p = provider
        f(&p)
        target.provider = p
    }

    private var routingSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HelpLabel(title: "Prefer providers by", help: "Which provider OpenRouter tries first for this model. Default balances price and uptime.", overridden: isSet(\.provider))
                        Spacer()
                        inheritButton(isSet(\.provider)) { target.provider = nil }
                    }
                    Picker("Sort", selection: Binding(get: { provider.sort ?? "" }, set: { v in setProvider { $0.sort = v.isEmpty ? nil : v } })) {
                        Text("Default").tag("")
                        Text("Price").tag("price")
                        Text("Speed").tag("throughput")
                        Text("Latency").tag("latency")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Toggle(isOn: Binding(get: { provider.denyDataCollection }, set: { v in setProvider { $0.denyDataCollection = v } })) {
                    HelpLabel(title: "Deny data collection", help: "Only route to providers that promise not to train on or retain your prompts. Can exclude cheaper providers.")
                }
                Toggle(isOn: Binding(get: { provider.requireParameters }, set: { v in setProvider { $0.requireParameters = v } })) {
                    HelpLabel(title: "Require parameters", help: "Only route to providers that honour every sampling parameter you send, instead of silently dropping some.")
                }
                Toggle(isOn: Binding(get: { provider.allowFallbacks }, set: { v in setProvider { $0.allowFallbacks = v } })) {
                    HelpLabel(title: "Allow provider fallbacks", help: "If the preferred provider fails, try another one for the same model.")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HelpLabel(title: "Ignore providers", help: "Provider slugs OpenRouter must never route to, such as deepinfra.")
                    TagField(tags: Binding(get: { provider.ignore ?? [] }, set: { v in setProvider { $0.ignore = v.isEmpty ? nil : v } }), placeholder: "provider slug")
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HelpLabel(title: "Fallback models", help: "If the model errors or is unavailable, OpenRouter tries these in order.", overridden: isSet(\.fallbackModels))
                        Spacer()
                        inheritButton(isSet(\.fallbackModels)) { target.fallbackModels = nil }
                    }
                    ForEach(display.fallbackModels ?? [], id: \.self) { id in
                        HStack {
                            Text(app.modelName(id)).foregroundStyle(Color.qInk)
                            Spacer()
                            Button {
                                target.fallbackModels = (display.fallbackModels ?? []).filter { $0 != id }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(Color.qDanger)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(app.modelName(id))")
                        }
                    }
                    Button { pickFallback = true } label: { Label("Add model", systemImage: "plus") }
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.borderless)
                }
                Toggle(isOn: Binding(get: { display.webSearch?.enabled ?? false }, set: { v in
                    target.webSearch = WebSearchSettings(enabled: v, maxResults: display.webSearch?.maxResults ?? 5)
                })) {
                    HelpLabel(title: "Web search", help: webHelp, overridden: isSet(\.webSearch))
                }
                if display.webSearch?.enabled == true {
                    Stepper(value: Binding(get: { display.webSearch?.maxResults ?? 5 }, set: { v in
                        target.webSearch = WebSearchSettings(enabled: true, maxResults: v)
                    }), in: 1...10) {
                        LabeledContent("Results per request") { Text("\(display.webSearch?.maxResults ?? 5)").monospacedDigit() }
                    }
                }
                Toggle(isOn: Binding(get: { display.transforms?.contains("middle-out") ?? false }, set: { v in
                    target.transforms = v ? ["middle-out"] : []
                })) {
                    HelpLabel(title: "Trim long chats to fit", help: "When the conversation exceeds the model's context, OpenRouter silently removes content from the middle. Turn on only if you'd rather lose context than get an error.", overridden: isSet(\.transforms))
                }
            } label: {
                Label("Routing, web search & fallbacks", systemImage: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(Color.qInk)
            }
        }
    }

    private var webHelp: String {
        var s = "Let the model search the web through OpenRouter's plugin. Billed separately"
        if let m = model, Pricing.parse(m.pricing.webSearch) > 0 {
            s += String(format: " (about $%.2f per thousand results on this model)", Pricing.parse(m.pricing.webSearch) * 1000)
        }
        return s + "."
    }

    // MARK: Info

    private var unsupported: [String] {
        guard let model else { return [] }
        let all: [(String, String)] = [("temperature", "Temperature"), ("top_p", "Top P"), ("top_k", "Top K"), ("frequency_penalty", "Frequency penalty"),
                                       ("presence_penalty", "Presence penalty"), ("repetition_penalty", "Repetition penalty"), ("min_p", "Min P"),
                                       ("top_a", "Top A"), ("seed", "Seed"), ("max_tokens", "Max tokens"), ("stop", "Stop sequences")]
        return all.filter { !model.supportedParameters.contains($0.0) }.map(\.1)
    }

    @ViewBuilder
    private var infoSection: some View {
        if let model {
            Section {
                LabeledContent("Pricing per million") {
                    Text("\(Pricing.perMillion(model.pricing.prompt)) in · \(Pricing.perMillion(model.pricing.completion)) out")
                        .monospacedDigit()
                }
                if !unsupported.isEmpty {
                    DisclosureGroup("\(unsupported.count) not supported by \(model.shortName)") {
                        Text("\(unsupported.joined(separator: ", ")). Stored values are kept but not sent.")
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                    }
                    .foregroundStyle(Color.qInk2)
                }
                if !model.supportsReasoning {
                    Text("\(model.shortName) doesn't list reasoning support, so its controls are hidden.")
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                }
            }
        }
    }

    // MARK: Helpers

    private func binding<T>(_ kp: WritableKeyPath<GenerationSettings, T?>) -> Binding<T?> {
        Binding(get: { target[keyPath: kp] ?? base?[keyPath: kp] },
                set: { target[keyPath: kp] = $0 })
    }

    private func isSet<T>(_ kp: KeyPath<GenerationSettings, T?>) -> Bool {
        overrideMode && target[keyPath: kp] != nil
    }

    @ViewBuilder
    private func inheritButton(_ shown: Bool, _ clear: @escaping () -> Void) -> some View {
        if shown && overrideMode {
            Button("Inherit") {
                withAnimation(Motion.quick) { clear() }
                Haptics.selection()
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
    }
}

/// A slider with its numeric value, which can also be cleared to "unset".
private struct SliderRow: View {
    let label: String
    let help: String
    @Binding var value: Double?
    let range: ClosedRange<Double>
    let step: Double
    let fallback: Double
    let overridden: Bool
    let onInherit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HelpLabel(title: label, help: help, overridden: overridden)
                Spacer()
                if overridden, let onInherit {
                    Button("Inherit") {
                        withAnimation(Motion.quick) { onInherit() }
                        Haptics.selection()
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                }
                OptionalNumberField(placeholder: format(fallback), value: $value, range: range)
            }
            Slider(value: Binding(get: { value ?? fallback }, set: { v in
                let snapped = ((v / step).rounded() * step * 10_000).rounded() / 10_000
                if snapped != value { value = snapped }
            }), in: range)
            .accessibilityLabel(label)
            .accessibilityValue(value.map(format) ?? "Default, \(format(fallback))")
        }
        .padding(.vertical, 2)
    }

    private func format(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)))
    }
}
