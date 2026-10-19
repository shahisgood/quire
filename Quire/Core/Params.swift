import Foundation

/// Which reasoning controls to show for a model.
/// A curated table keyed on the model id, not data from OpenRouter: the catalogue's
/// `supported_parameters` only says whether `reasoning` is accepted, never which effort levels.
/// OpenRouter maps a level the provider lacks to the nearest one it has, so a wrong guess degrades
/// to "close enough" rather than an error. Edit freely as families change (ported from the PWA's
/// `detectReasoningStyle`, June 2026 knowledge).
nonisolated struct ReasoningStyle: Sendable {
    var defaultMode: ReasoningSettings.Mode
    var canDisable: Bool
    var efforts: [ReasoningEffort]
    var defaultBudget: Int
    var note: String

    static func detect(_ model: ORModel?) -> ReasoningStyle {
        let id = (model?.id ?? "").lowercased()
        func m(_ pattern: String) -> Bool { id.range(of: pattern, options: .regularExpression) != nil }
        let std: [ReasoningEffort] = [.low, .medium, .high]
        let src = "Levels come from a table in Quire keyed on the model family, not from OpenRouter; OpenRouter maps a level the provider lacks to the nearest one."

        if m("^openai/gpt-5\\.[1-9]|^openai/gpt-5-codex|^openai/codex") {
            return .init(defaultMode: .effort, canDisable: true, efforts: [.none, .minimal, .low, .medium, .high, .xhigh], defaultBudget: 8000, note: "GPT-5.1-class models take the full effort scale. " + src)
        }
        if m("^openai/gpt-5") {
            return .init(defaultMode: .effort, canDisable: false, efforts: [.minimal, .low, .medium, .high], defaultBudget: 8000, note: "GPT-5 takes minimal to high and always reasons. " + src)
        }
        if m("^openai/o[1-9]") {
            return .init(defaultMode: .effort, canDisable: false, efforts: std, defaultBudget: 8000, note: "o-series models always reason. " + src)
        }
        if m("^anthropic/claude-(3\\.7|4|opus-4|sonnet-4|haiku-4)") {
            return .init(defaultMode: .budget, canDisable: true, efforts: std, defaultBudget: 8000, note: "Claude takes a thinking-token budget; effort is converted by OpenRouter. " + src)
        }
        if m("^google/gemini-(2\\.5|3)") {
            return .init(defaultMode: .budget, canDisable: !m("pro"), efforts: std, defaultBudget: 8000, note: "Gemini takes a thinking budget; Pro models cannot turn thinking off. " + src)
        }
        if m("^deepseek/deepseek-v4|^deepseek/deepseek-v3\\.[1-9]") {
            return .init(defaultMode: .effort, canDisable: true, efforts: std, defaultBudget: 8000, note: "DeepSeek V3.1+ and V4 are hybrid: thinking can be turned off. " + src)
        }
        if m("^deepseek/deepseek-r1") {
            return .init(defaultMode: .effort, canDisable: false, efforts: [.high], defaultBudget: 0, note: "R1 always reasons at one level; you can only hide the trace. " + src)
        }
        if m("^x-ai/grok") {
            return .init(defaultMode: .effort, canDisable: false, efforts: [.low, .high], defaultBudget: 0, note: "Grok distinguishes low and high only. " + src)
        }
        if m("^qwen/qwen3|^moonshotai/kimi|^z-ai/glm|^minimax") {
            return .init(defaultMode: .budget, canDisable: true, efforts: std, defaultBudget: 4096, note: src)
        }
        return .init(defaultMode: .effort, canDisable: true, efforts: [.minimal, .low, .medium, .high, .xhigh], defaultBudget: 4096, note: "This family is not in Quire's table, so the whole unified scale is offered. " + src)
    }
}

nonisolated enum RequestBuilder {
    static func supports(_ model: ORModel?, _ api: String) -> Bool {
        guard let model else { return true }   // unknown model: send everything
        return model.supportedParameters.contains(api)
    }

    static func reasoningPayload(_ r: ReasoningSettings?, model: ORModel?) -> JSONValue? {
        guard let r, let model, model.supportsReasoning else { return nil }
        let style = ReasoningStyle.detect(model)
        switch r.mode {
        case .off:
            if style.canDisable { return ["enabled": false] }
            return r.exclude ? ["exclude": true] : nil
        case .effort:
            var p: [String: JSONValue] = ["effort": .string((r.effort ?? .medium).rawValue)]
            if r.exclude { p["exclude"] = true }
            return .object(p)
        case .budget:
            var p: [String: JSONValue] = ["max_tokens": .int(max(1, r.maxTokens ?? style.defaultBudget))]
            if r.exclude { p["exclude"] = true }
            return .object(p)
        }
    }

    /// The OpenRouter request body. Only parameters the model reports as supported are sent.
    static func body(modelId: String, model: ORModel?, settings s: GenerationSettings, messages: [JSONValue]) -> [String: JSONValue] {
        var body: [String: JSONValue] = ["model": .string(modelId), "messages": .array(messages), "usage": ["include": true]]

        func put(_ api: String, _ v: Double?) {
            if let v, v.isFinite, supports(model, api) { body[api] = .double(v) }
        }
        put("temperature", s.temperature)
        put("top_p", s.topP)
        put("top_k", s.topK)
        put("frequency_penalty", s.frequencyPenalty)
        put("presence_penalty", s.presencePenalty)
        put("repetition_penalty", s.repetitionPenalty)
        put("min_p", s.minP)
        put("top_a", s.topA)
        if let seed = s.seed, supports(model, "seed") { body["seed"] = .int(seed) }
        if var mt = s.maxTokens, supports(model, "max_tokens") {
            if let cap = model?.maxCompletionTokens, cap > 0 { mt = min(mt, cap) }
            body["max_tokens"] = .int(mt)
        }
        if let stop = s.stop?.filter({ !$0.isEmpty }), !stop.isEmpty, supports(model, "stop") {
            body["stop"] = .array(stop.prefix(4).map { .string($0) })
        }
        if let r = reasoningPayload(s.reasoning, model: model) { body["reasoning"] = r }
        if let p = s.provider {
            var o: [String: JSONValue] = ["allow_fallbacks": .bool(p.allowFallbacks), "require_parameters": .bool(p.requireParameters)]
            if let sort = p.sort, !sort.isEmpty { o["sort"] = .string(sort) }
            if let order = p.order, !order.isEmpty { o["order"] = .array(order.map { .string($0) }) }
            if let ignore = p.ignore, !ignore.isEmpty { o["ignore"] = .array(ignore.map { .string($0) }) }
            if p.denyDataCollection { o["data_collection"] = "deny" }
            body["provider"] = .object(o)
        }
        if let w = s.webSearch, w.enabled {
            body["plugins"] = [["id": "web", "max_results": .int(min(10, max(1, w.maxResults)))]]
        }
        if let t = s.transforms, !t.isEmpty { body["transforms"] = .array(t.map { .string($0) }) }
        if let f = s.fallbackModels, !f.isEmpty {
            body["models"] = .array(([modelId] + f.filter { $0 != modelId }).map { .string($0) })
        }
        // A model that can draw only does when asked for images as well as text.
        if model?.outputModalities.contains("image") == true {
            body["modalities"] = .array([.string("image"), .string("text")])
        }
        return body
    }
}

/// Precise / Balanced / Creative, as in the PWA. A preset sets four sampling values; anything else
/// the user changes afterwards shows as "Custom".
nonisolated struct SamplingPreset: Identifiable, Sendable {
    let name: String
    let temperature: Double
    let topP: Double
    let frequencyPenalty: Double
    let presencePenalty: Double
    var id: String { name }

    static let all: [SamplingPreset] = [
        SamplingPreset(name: "Precise", temperature: 0.2, topP: 0.9, frequencyPenalty: 0, presencePenalty: 0),
        SamplingPreset(name: "Balanced", temperature: 0.7, topP: 1, frequencyPenalty: 0, presencePenalty: 0),
        SamplingPreset(name: "Creative", temperature: 1.1, topP: 1, frequencyPenalty: 0.2, presencePenalty: 0.3),
    ]

    /// Unset values count as the provider defaults (1, 1, 0, 0).
    func matches(_ s: GenerationSettings) -> Bool {
        func eq(_ a: Double?, _ fallback: Double, _ b: Double) -> Bool { abs((a ?? fallback) - b) < 1e-6 }
        return eq(s.temperature, 1, temperature) && eq(s.topP, 1, topP)
            && eq(s.frequencyPenalty, 0, frequencyPenalty) && eq(s.presencePenalty, 0, presencePenalty)
    }

    func apply(to s: inout GenerationSettings) {
        s.temperature = temperature
        s.topP = topP
        s.frequencyPenalty = frequencyPenalty
        s.presencePenalty = presencePenalty
    }
}
