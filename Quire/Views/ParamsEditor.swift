import SwiftUI

/// The generation settings editor, used at three levels: global defaults, a persona, one chat.
///
/// `target` is what gets written. `base` is what the level inherits (nil when editing the global
/// defaults). Each control shows `target`'s value if set, else the inherited one; a dot marks values
/// set at this level, and Inherit clears them. Only parameters the model reports as supported are
/// shown; the rest are listed, kept, and sent when you switch to a model that takes them.
///
/// It lays itself out as cards (sampling, repetition, output, reasoning, routing), for a
/// `SettingsPage`.
struct ParamsEditor: View {
    let model: ORModel?
    @Binding var target: GenerationSettings
    let base: GenerationSettings?
    @Environment(AppModel.self) private var app
    @State private var showRouting = false
    @State private var pickFallback = false
    @Namespace private var presetNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var display: GenerationSettings { (base ?? GenerationSettings.defaults).merged(with: target) }
    private var overrideMode: Bool { base != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            samplingGroup
            if Self.repetition.contains(where: { supports($0.api) }) { repetitionGroup }
            outputGroup
            if model?.supportsReasoning == true { reasoningGroup }
            routingGroup
            infoGroup
        }
        .sheet(isPresented: $pickFallback) {
            ModelPickerView(title: "Add a fallback model", selected: nil) { id in
                var list = display.fallbackModels ?? []
                if !list.contains(id) { list.append(id) }
                target.fallbackModels = list
            }
        }
    }

    // MARK: Sliders

    private struct SliderSpec {
        let api: String
        let label: String
        let help: String
        let keyPath: WritableKeyPath<GenerationSettings, Double?>
        let range: ClosedRange<Double>
        let step: Double
        let fallback: Double
        var neutral: Double? = nil
        let ends: (String, String)
    }

    private static let sampling: [SliderSpec] = [
        SliderSpec(api: "temperature", label: "Temperature", help: "How much randomness to allow. 0 is nearly deterministic; above 1.2 gets loose.", keyPath: \.temperature, range: 0...2, step: 0.05, fallback: 1, ends: ("Focused", "Free")),
        SliderSpec(api: "top_p", label: "Top P", help: "Only sample from the smallest set of tokens whose probabilities add up to this. 1 means no cutoff.", keyPath: \.topP, range: 0...1, step: 0.01, fallback: 1, ends: ("Narrow", "Open")),
        SliderSpec(api: "min_p", label: "Min P", help: "Drop tokens whose probability is below this fraction of the top token. 0 is off.", keyPath: \.minP, range: 0...1, step: 0.01, fallback: 0, ends: ("Off", "Strict")),
        SliderSpec(api: "top_a", label: "Top A", help: "Dynamic cutoff based on the top token's probability squared. 0 is off.", keyPath: \.topA, range: 0...1, step: 0.01, fallback: 0, ends: ("Off", "Strict")),
    ]

    private static let repetition: [SliderSpec] = [
        SliderSpec(api: "frequency_penalty", label: "Frequency penalty", help: "Push down tokens in proportion to how often they already appeared. Reduces repetition.", keyPath: \.frequencyPenalty, range: -2...2, step: 0.05, fallback: 0, neutral: 0, ends: ("Repeat more", "Repeat less")),
        SliderSpec(api: "presence_penalty", label: "Presence penalty", help: "Push down any token that has appeared at all. Encourages new topics.", keyPath: \.presencePenalty, range: -2...2, step: 0.05, fallback: 0, neutral: 0, ends: ("Stay on topic", "Wander")),
        SliderSpec(api: "repetition_penalty", label: "Repetition penalty", help: "Multiplicative penalty on repeated tokens. 1 is off; above 1 discourages repeats.", keyPath: \.repetitionPenalty, range: 0...2, step: 0.01, fallback: 1, neutral: 1, ends: ("Allow", "Discourage")),
    ]

    private func supports(_ api: String) -> Bool { RequestBuilder.supports(model, api) }

    private func sliderRow(_ spec: SliderSpec) -> some View {
        let kp = spec.keyPath
        let inherited = base?[keyPath: kp] ?? spec.fallback
        return SettingRow(spec.label, help: spec.help, overridden: isSet(kp),
                          onInherit: overrideMode ? { target[keyPath: kp] = nil } : nil) {
            OptionalNumberField(placeholder: format(inherited), value: binding(kp), range: spec.range)
        } below: {
            ParamSlider(value: Binding(get: { target[keyPath: kp] ?? inherited },
                                       set: { target[keyPath: kp] = $0 }),
                        range: spec.range, step: spec.step, neutral: spec.neutral, mark: inherited,
                        ends: spec.ends, label: spec.label, format: format)
        }
    }

    private func format(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: Sampling

    private var samplingGroup: some View {
        SettingsGroup(label: "Sampling",
                      footer: overrideMode ? Text("A dot marks a value set here. Everything else is inherited.") : nil) {
            SettingRow("Style", detail: presetDetail,
                       help: "A starting point for temperature, Top P and the two penalties. Move any of them and it becomes your own mix.") {
                EmptyView()
            } below: {
                presetStrip
            }
            ForEach(Self.sampling.filter { supports($0.api) }, id: \.api) { sliderRow($0) }
            if supports("top_k") {
                SettingRow("Top K", help: "Only consider the K most likely next tokens. 0 turns it off.", overridden: isSet(\.topK),
                           onInherit: overrideMode ? { target.topK = nil } : nil) {
                    OptionalNumberField(placeholder: "0", value: binding(\.topK), range: 0...1000)
                }
            }
        }
    }

    private var presetDetail: String {
        guard let p = SamplingPreset.all.first(where: { $0.matches(display) }) else { return "Your own mix" }
        switch p.name {
        case "Precise": return "Careful and consistent"
        case "Balanced": return "The everyday middle"
        default: return "Looser, more surprising"
        }
    }

    /// The three presets in a well, the matching one lifted out; none when the mix is your own.
    private var presetStrip: some View {
        HStack(spacing: 2) {
            ForEach(SamplingPreset.all) { p in
                let on = p.matches(display)
                Button {
                    Haptics.selection()
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.select) { p.apply(to: &target) }
                } label: {
                    Text(p.name)
                        .font(.subheadline.weight(on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.qOnAccent : Color.qInk2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Color.qAccent)
                                    .matchedGeometryEffect(id: "preset", in: presetNS)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.qSunken, in: .capsule)
    }

    // MARK: Repetition

    private var repetitionGroup: some View {
        SettingsGroup(label: "Repetition") {
            ForEach(Self.repetition.filter { supports($0.api) }, id: \.api) { sliderRow($0) }
        }
    }

    // MARK: Output

    private var outputGroup: some View {
        SettingsGroup(label: "Output") {
            if supports("max_tokens") {
                SettingRow("Max output tokens", help: "Hard cap on the reply's length. Empty lets the model decide, up to its limit.",
                           overridden: isSet(\.maxTokens), onInherit: overrideMode ? { target.maxTokens = nil } : nil) {
                    OptionalIntField(placeholder: "Model limit", value: binding(\.maxTokens), range: 1...max(1, model?.maxCompletionTokens ?? 2_000_000))
                } below: {
                    if let cap = model?.maxCompletionTokens, cap > 0, display.maxTokens != cap {
                        smallButton("Use the maximum, \(cap.formatted())", symbol: "arrow.up.to.line") { target.maxTokens = cap }
                    }
                }
            }
            if supports("stop") {
                SettingRow("Stop sequences", detail: (display.stop ?? []).isEmpty ? "None" : nil,
                           help: "Generation halts as soon as any of these appears. Up to four. Type \\n for a line break.",
                           overridden: isSet(\.stop), onInherit: overrideMode ? { target.stop = nil } : nil) {
                    EmptyView()
                } below: {
                    TagField(tags: Binding(get: { display.stop ?? [] }, set: { target.stop = $0 }), limit: 4, placeholder: "Add a stop sequence")
                }
            }
            if supports("seed") {
                SettingRow("Seed", help: "Fix the random seed so repeated requests give the same answer where the provider supports it. Empty is random.",
                           overridden: isSet(\.seed), onInherit: overrideMode ? { target.seed = nil } : nil) {
                    OptionalIntField(placeholder: "Random", value: binding(\.seed), range: 0...2_147_483_647)
                } below: {
                    HStack(spacing: 8) {
                        smallButton("Roll", symbol: "dice") {
                            target.seed = Int.random(in: 0...2_147_483_647)
                        }
                        if display.seed != nil {
                            smallButton("Clear", symbol: "xmark") { target.seed = nil }
                        }
                    }
                }
            }
            SettingRow("Stream", help: "Show tokens as they arrive. Off is useful for debugging and for the few models that stream badly.",
                       overridden: isSet(\.stream), onInherit: overrideMode ? { target.stream = nil } : nil) {
                Toggle("Stream", isOn: Binding(get: { display.stream ?? true }, set: { target.stream = $0 }))
                    .labelsHidden()
            }
        }
    }

    /// A small action under a row, quieter than a button.
    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.quick) { action() }
        } label: {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.qAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.qAccentSoft, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
    }

    // MARK: Reasoning

    private var reasoning: ReasoningSettings { display.reasoning ?? ReasoningSettings() }

    private func setReasoning(_ f: (inout ReasoningSettings) -> Void) {
        var r = reasoning
        f(&r)
        target.reasoning = r
    }

    private var reasoningGroup: some View {
        let style = ReasoningStyle.detect(model)
        var modes: [(value: ReasoningSettings.Mode, label: String)] = []
        if style.canDisable { modes.append((.off, "Off")) }
        modes += [(.effort, "Effort"), (.budget, "Budget")]
        return SettingsGroup(label: "Reasoning", footer: Text(style.note)) {
            SettingRow("Thinking", detail: reasoningDetail(style),
                       help: "Let the model think before answering. Thinking tokens are billed as output.",
                       overridden: isSet(\.reasoning), onInherit: overrideMode ? { target.reasoning = nil } : nil) {
                EmptyView()
            } below: {
                VStack(alignment: .leading, spacing: 10) {
                    ChoiceStrip(options: modes, selection: Binding(get: { reasoning.mode }, set: { m in
                        setReasoning { r in
                            r.mode = m
                            if r.effort == nil { r.effort = .medium }
                            if m == .budget && r.maxTokens == nil { r.maxTokens = style.defaultBudget }
                        }
                    }), label: "Reasoning mode")
                    if reasoning.mode == .effort {
                        ChoiceStrip(options: style.efforts.map { (value: $0, label: shortLabel($0)) },
                                    selection: Binding(get: { reasoning.effort ?? .medium }, set: { e in setReasoning { $0.effort = e } }),
                                    label: "Effort")
                            .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                    if reasoning.mode == .budget {
                        HStack {
                            Text("Thinking budget")
                                .font(.subheadline)
                                .foregroundStyle(Color.qInk2)
                            Spacer()
                            OptionalIntField(placeholder: "\(style.defaultBudget)", value: Binding(
                                get: { reasoning.maxTokens },
                                set: { v in setReasoning { $0.maxTokens = v } }), range: 1...200_000)
                            Text("tokens")
                                .font(.footnote)
                                .foregroundStyle(Color.qInk2)
                        }
                        .transition(.opacity.combined(with: .offset(y: -6)))
                    }
                }
            }
            SettingRow("Hide the trace", help: "Think, but don't return the reasoning. Reasoning tokens are still billed.") {
                Toggle("Hide the trace", isOn: Binding(get: { reasoning.exclude }, set: { v in setReasoning { $0.exclude = v } }))
                    .labelsHidden()
            }
        }
    }

    private func reasoningDetail(_ style: ReasoningStyle) -> String {
        switch reasoning.mode {
        case .off: style.canDisable ? "Answers straight away" : "This model always reasons"
        case .effort: "Thinks at \((reasoning.effort ?? .medium).rawValue) effort"
        case .budget: "Up to \((reasoning.maxTokens ?? style.defaultBudget).formatted()) thinking tokens"
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

    private var routingGroup: some View {
        SettingsGroup(label: "Routing") {
            Button {
                Haptics.selection()
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.reveal) { showRouting.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Providers, web search & fallbacks")
                            .foregroundStyle(Color.qInk)
                        Text(routingSummary)
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.qInk2)
                        .rotationEffect(.degrees(showRouting ? 180 : 0))
                }
                .padding(.vertical, 13)
                .contentShape(.rect)
            }
            .buttonStyle(.row)
            .accessibilityHint(showRouting ? "Hides the routing settings" : "Shows the routing settings")

            if showRouting {
                SettingRow("Prefer providers by", help: "Which provider OpenRouter tries first for this model. Default balances price and uptime.",
                           overridden: isSet(\.provider), onInherit: overrideMode ? { target.provider = nil } : nil) {
                    EmptyView()
                } below: {
                    ChoiceStrip(options: [("", "Default"), ("price", "Price"), ("throughput", "Speed"), ("latency", "Latency")],
                                selection: Binding(get: { provider.sort ?? "" }, set: { v in setProvider { $0.sort = v.isEmpty ? nil : v } }),
                                label: "Prefer providers by")
                }
                toggleRow("Deny data collection", help: "Only route to providers that promise not to train on or retain your prompts. Can exclude cheaper providers.",
                          isOn: Binding(get: { provider.denyDataCollection }, set: { v in setProvider { $0.denyDataCollection = v } }))
                toggleRow("Require parameters", help: "Only route to providers that honour every sampling parameter you send, instead of silently dropping some.",
                          isOn: Binding(get: { provider.requireParameters }, set: { v in setProvider { $0.requireParameters = v } }))
                toggleRow("Allow provider fallbacks", help: "If the preferred provider fails, try another one for the same model.",
                          isOn: Binding(get: { provider.allowFallbacks }, set: { v in setProvider { $0.allowFallbacks = v } }))
                SettingRow("Ignore providers", help: "Provider slugs OpenRouter must never route to, such as deepinfra.") {
                    EmptyView()
                } below: {
                    TagField(tags: Binding(get: { provider.ignore ?? [] }, set: { v in setProvider { $0.ignore = v.isEmpty ? nil : v } }), placeholder: "provider slug")
                }
                SettingRow("Fallback models", detail: (display.fallbackModels ?? []).isEmpty ? "None" : nil,
                           help: "If the model errors or is unavailable, OpenRouter tries these in order.",
                           overridden: isSet(\.fallbackModels), onInherit: overrideMode ? { target.fallbackModels = nil } : nil) {
                    EmptyView()
                } below: {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(display.fallbackModels ?? [], id: \.self) { id in
                            HStack {
                                Text(app.modelName(id))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.qInk)
                                Spacer()
                                Button {
                                    withAnimation(Motion.quick) {
                                        target.fallbackModels = (display.fallbackModels ?? []).filter { $0 != id }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Color.qDanger)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(app.modelName(id))")
                            }
                        }
                        smallButton("Add model", symbol: "plus") { pickFallback = true }
                    }
                }
                SettingRow("Web search", detail: display.webSearch?.enabled == true ? "\(display.webSearch?.maxResults ?? 5) results per request" : nil,
                           help: webHelp, overridden: isSet(\.webSearch), onInherit: overrideMode ? { target.webSearch = nil } : nil) {
                    HStack(spacing: 10) {
                        if display.webSearch?.enabled == true {
                            Stepper("Results per request", value: Binding(get: { display.webSearch?.maxResults ?? 5 }, set: { v in
                                target.webSearch = WebSearchSettings(enabled: true, maxResults: v)
                            }), in: 1...10)
                            .labelsHidden()
                            .transition(.opacity)
                        }
                        Toggle("Web search", isOn: Binding(get: { display.webSearch?.enabled ?? false }, set: { v in
                            withAnimation(Motion.quick) {
                                target.webSearch = WebSearchSettings(enabled: v, maxResults: display.webSearch?.maxResults ?? 5)
                            }
                        }))
                        .labelsHidden()
                    }
                }
                SettingRow("Trim long chats to fit", help: "When the conversation exceeds the model's context, OpenRouter silently removes content from the middle. Turn on only if you'd rather lose context than get an error.",
                           overridden: isSet(\.transforms), onInherit: overrideMode ? { target.transforms = nil } : nil) {
                    Toggle("Trim long chats to fit", isOn: Binding(get: { display.transforms?.contains("middle-out") ?? false }, set: { v in
                        target.transforms = v ? ["middle-out"] : []
                    }))
                    .labelsHidden()
                }
            }
        }
    }

    private func toggleRow(_ title: String, help: String, isOn: Binding<Bool>) -> some View {
        SettingRow(title, help: help) {
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }

    private var routingSummary: String {
        var parts: [String] = []
        switch provider.sort {
        case "price": parts.append("Cheapest first")
        case "throughput": parts.append("Fastest first")
        case "latency": parts.append("Quickest to start")
        default: parts.append("Default routing")
        }
        if display.webSearch?.enabled == true { parts.append("web search") }
        let fallbacks = display.fallbackModels?.count ?? 0
        if fallbacks > 0 { parts.append("\(fallbacks) fallback\(fallbacks == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
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
    private var infoGroup: some View {
        if let model {
            SettingsGroup(label: model.shortName) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Per million tokens")
                        .foregroundStyle(Color.qInk)
                    Spacer()
                    Text("\(Pricing.perMillion(model.pricing.prompt)) in · \(Pricing.perMillion(model.pricing.completion)) out")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                }
                .padding(.vertical, 13)
                if !unsupported.isEmpty {
                    SettingRow("\(unsupported.count) not supported",
                               help: "\(unsupported.joined(separator: ", ")). Stored values are kept but not sent.") {
                        EmptyView()
                    }
                }
                if !model.supportsReasoning {
                    Text("\(model.shortName) doesn't list reasoning support, so its controls are hidden.")
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                        .padding(.vertical, 13)
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
}
