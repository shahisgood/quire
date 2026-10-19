import Foundation

// The data model mirrors the PWA's TypeScript types key for key, so a backup exported from the
// web app imports here unchanged and vice versa. Timestamps are JavaScript-style milliseconds.
// Every type decodes leniently: a missing or mistyped field falls back to a default instead of
// failing the whole file, because the other side of an import may be an older or newer build.

nonisolated func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }
nonisolated func newID() -> String { UUID().uuidString.lowercased() }
nonisolated func dayKey(_ ms: Double = nowMs()) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: ms / 1000))
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

extension KeyedDecodingContainer {
    /// Decode a value, or return the default when the key is missing, null, or the wrong type.
    nonisolated func lenient<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback()
    }
}

// MARK: - Chats and messages

nonisolated enum Role: String, Codable, Hashable, Sendable { case system, user, assistant }
nonisolated enum MessageStatus: String, Codable, Hashable, Sendable { case complete, streaming, interrupted, error }

nonisolated struct Chat: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var createdAt: Double
    var updatedAt: Double
    var folderId: String?
    var pinned: Bool
    var archived: Bool
    var modelId: String
    var settingsOverride: GenerationSettings?
    var systemPromptId: String?
    var systemPromptInline: String?
    var memoryEnabled: Bool
    var tokenEstimate: Int
    var totalCostUsd: Double
    var activeLeafId: String?
    var draft: String?
    var scrollTop: Double?
    var lastPreview: String?
    var titleAuto: Bool?

    init(id: String = newID(), modelId: String, memoryEnabled: Bool) {
        let now = nowMs()
        self.id = id
        self.title = "New chat"
        self.createdAt = now
        self.updatedAt = now
        self.pinned = false
        self.archived = false
        self.modelId = modelId
        self.memoryEnabled = memoryEnabled
        self.tokenEstimate = 0
        self.totalCostUsd = 0
        self.draft = ""
        self.titleAuto = true
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = c.lenient(.title, "Untitled")
        createdAt = c.lenient(.createdAt, nowMs())
        updatedAt = c.lenient(.updatedAt, createdAt)
        folderId = c.lenient(.folderId, nil)
        pinned = c.lenient(.pinned, false)
        archived = c.lenient(.archived, false)
        modelId = c.lenient(.modelId, "")
        settingsOverride = c.lenient(.settingsOverride, nil)
        systemPromptId = c.lenient(.systemPromptId, nil)
        systemPromptInline = c.lenient(.systemPromptInline, nil)
        memoryEnabled = c.lenient(.memoryEnabled, true)
        tokenEstimate = c.lenient(.tokenEstimate, Int(c.lenient(.tokenEstimate, 0.0)))
        totalCostUsd = c.lenient(.totalCostUsd, 0)
        activeLeafId = c.lenient(.activeLeafId, nil)
        draft = c.lenient(.draft, nil)
        scrollTop = c.lenient(.scrollTop, nil)
        lastPreview = c.lenient(.lastPreview, nil)
        titleAuto = c.lenient(.titleAuto, nil)
    }
}

nonisolated struct Attachment: Codable, Identifiable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Hashable, Sendable { case image, file }
    var id: String
    var kind: Kind
    var mime: String
    var name: String
    var size: Int
    var dataUrl: String

    init(id: String = newID(), kind: Kind, mime: String, name: String, size: Int, dataUrl: String) {
        self.id = id; self.kind = kind; self.mime = mime; self.name = name; self.size = size; self.dataUrl = dataUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, newID())
        kind = c.lenient(.kind, .file)
        mime = c.lenient(.mime, "application/octet-stream")
        name = c.lenient(.name, "file")
        size = c.lenient(.size, 0)
        dataUrl = c.lenient(.dataUrl, "")
    }
}

nonisolated struct Usage: Codable, Hashable, Sendable {
    var promptTokens: Int
    var completionTokens: Int
    var reasoningTokens: Int?
    var costUsd: Double?
    var authoritative: Bool?
    var estimated: Bool?
    var webSearchCostUsd: Double?

    init(promptTokens: Int, completionTokens: Int, reasoningTokens: Int? = nil, costUsd: Double? = nil,
         authoritative: Bool? = nil, estimated: Bool? = nil, webSearchCostUsd: Double? = nil) {
        self.promptTokens = promptTokens; self.completionTokens = completionTokens; self.reasoningTokens = reasoningTokens
        self.costUsd = costUsd; self.authoritative = authoritative; self.estimated = estimated; self.webSearchCostUsd = webSearchCostUsd
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = c.lenient(.promptTokens, 0)
        completionTokens = c.lenient(.completionTokens, 0)
        reasoningTokens = c.lenient(.reasoningTokens, nil)
        costUsd = c.lenient(.costUsd, nil)
        authoritative = c.lenient(.authoritative, nil)
        estimated = c.lenient(.estimated, nil)
        webSearchCostUsd = c.lenient(.webSearchCostUsd, nil)
    }
}

nonisolated struct MessageError: Codable, Hashable, Sendable {
    var code: String
    var message: String
    var retryAfterMs: Double?

    init(code: String, message: String, retryAfterMs: Double? = nil) {
        self.code = code; self.message = message; self.retryAfterMs = retryAfterMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = c.lenient(.code, "unknown")
        message = c.lenient(.message, "")
        retryAfterMs = c.lenient(.retryAfterMs, nil)
    }
}

nonisolated struct Message: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var chatId: String
    var parentId: String?
    var role: Role
    var content: String
    var attachments: [Attachment]?
    var reasoning: String?
    var modelId: String?
    var generationId: String?
    var usage: Usage?
    var settingsSnapshot: GenerationSettings?
    var requestSnapshot: String?
    var createdAt: Double
    var status: MessageStatus
    var error: MessageError?
    var editedFrom: String?
    var lc: String?

    init(id: String = newID(), chatId: String, parentId: String?, role: Role, content: String,
         attachments: [Attachment]? = nil, modelId: String? = nil, createdAt: Double = nowMs(), status: MessageStatus) {
        self.id = id; self.chatId = chatId; self.parentId = parentId; self.role = role; self.content = content
        self.attachments = attachments; self.modelId = modelId; self.createdAt = createdAt; self.status = status
        self.lc = role == .user ? content.lowercased() : nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        chatId = c.lenient(.chatId, "")
        parentId = c.lenient(.parentId, nil)
        role = c.lenient(.role, .user)
        content = c.lenient(.content, "")
        attachments = c.lenient(.attachments, nil)
        reasoning = c.lenient(.reasoning, nil)
        modelId = c.lenient(.modelId, nil)
        generationId = c.lenient(.generationId, nil)
        usage = c.lenient(.usage, nil)
        settingsSnapshot = c.lenient(.settingsSnapshot, nil)
        requestSnapshot = c.lenient(.requestSnapshot, nil)
        createdAt = c.lenient(.createdAt, nowMs())
        status = c.lenient(.status, .complete)
        error = c.lenient(.error, nil)
        editedFrom = c.lenient(.editedFrom, nil)
        lc = c.lenient(.lc, nil)
    }
}

// MARK: - Generation settings

/// OpenRouter's unified effort scale. Providers accept a subset; OpenRouter maps the rest to the nearest they support.
nonisolated enum ReasoningEffort: String, Codable, CaseIterable, Hashable, Sendable {
    case none, minimal, low, medium, high, xhigh
    var label: String { self == .xhigh ? "Extra high" : rawValue.capitalized }
}

nonisolated struct ReasoningSettings: Codable, Hashable, Sendable {
    nonisolated enum Mode: String, Codable, CaseIterable, Hashable, Sendable { case off, effort, budget }
    var mode: Mode
    var effort: ReasoningEffort?
    var maxTokens: Int?
    var exclude: Bool

    init(mode: Mode = .off, effort: ReasoningEffort? = .medium, maxTokens: Int? = nil, exclude: Bool = false) {
        self.mode = mode; self.effort = effort; self.maxTokens = maxTokens; self.exclude = exclude
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.lenient(.mode, .off)
        effort = c.lenient(.effort, .medium)
        maxTokens = c.lenient(.maxTokens, nil)
        exclude = c.lenient(.exclude, false)
    }
}

nonisolated struct ProviderSettings: Codable, Hashable, Sendable {
    var sort: String?
    var order: [String]?
    var ignore: [String]?
    var allowFallbacks: Bool
    var requireParameters: Bool
    var denyDataCollection: Bool

    init(sort: String? = nil, allowFallbacks: Bool = true, requireParameters: Bool = true, denyDataCollection: Bool = false) {
        self.sort = sort; self.allowFallbacks = allowFallbacks; self.requireParameters = requireParameters; self.denyDataCollection = denyDataCollection
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sort = c.lenient(.sort, nil)
        order = c.lenient(.order, nil)
        ignore = c.lenient(.ignore, nil)
        allowFallbacks = c.lenient(.allowFallbacks, true)
        requireParameters = c.lenient(.requireParameters, true)
        denyDataCollection = c.lenient(.denyDataCollection, false)
    }
}

nonisolated struct WebSearchSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var maxResults: Int

    init(enabled: Bool = false, maxResults: Int = 5) { self.enabled = enabled; self.maxResults = maxResults }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.lenient(.enabled, false)
        maxResults = c.lenient(.maxResults, 5)
    }
}

/// Every field is optional so the same type serves as both the global settings and a partial per-chat override.
nonisolated struct GenerationSettings: Codable, Hashable, Sendable {
    var temperature: Double?
    var topP: Double?
    var topK: Double?
    var frequencyPenalty: Double?
    var presencePenalty: Double?
    var repetitionPenalty: Double?
    var minP: Double?
    var topA: Double?
    var seed: Int?
    var maxTokens: Int?
    var stop: [String]?
    var stream: Bool?
    var reasoning: ReasoningSettings?
    var provider: ProviderSettings?
    var webSearch: WebSearchSettings?
    var transforms: [String]?
    var fallbackModels: [String]?

    init() {}

    static let defaults: GenerationSettings = {
        var g = GenerationSettings()
        g.stream = true
        g.reasoning = ReasoningSettings()
        g.provider = ProviderSettings()
        g.webSearch = WebSearchSettings()
        g.transforms = []
        g.fallbackModels = []
        return g
    }()

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        temperature = c.lenient(.temperature, nil)
        topP = c.lenient(.topP, nil)
        topK = c.lenient(.topK, nil)
        frequencyPenalty = c.lenient(.frequencyPenalty, nil)
        presencePenalty = c.lenient(.presencePenalty, nil)
        repetitionPenalty = c.lenient(.repetitionPenalty, nil)
        minP = c.lenient(.minP, nil)
        topA = c.lenient(.topA, nil)
        seed = c.lenient(.seed, nil)
        maxTokens = c.lenient(.maxTokens, nil)
        stop = c.lenient(.stop, nil)
        stream = c.lenient(.stream, nil)
        reasoning = c.lenient(.reasoning, nil)
        provider = c.lenient(.provider, nil)
        webSearch = c.lenient(.webSearch, nil)
        transforms = c.lenient(.transforms, nil)
        fallbackModels = c.lenient(.fallbackModels, nil)
    }

    /// Overlay: fields set in `override` win; everything else comes from `self`.
    func merged(with override: GenerationSettings?) -> GenerationSettings {
        guard let o = override else { return self }
        var out = self
        if let v = o.temperature { out.temperature = v }
        if let v = o.topP { out.topP = v }
        if let v = o.topK { out.topK = v }
        if let v = o.frequencyPenalty { out.frequencyPenalty = v }
        if let v = o.presencePenalty { out.presencePenalty = v }
        if let v = o.repetitionPenalty { out.repetitionPenalty = v }
        if let v = o.minP { out.minP = v }
        if let v = o.topA { out.topA = v }
        if let v = o.seed { out.seed = v }
        if let v = o.maxTokens { out.maxTokens = v }
        if let v = o.stop { out.stop = v }
        if let v = o.stream { out.stream = v }
        if let v = o.reasoning { out.reasoning = v }
        if let v = o.provider { out.provider = v }
        if let v = o.webSearch { out.webSearch = v }
        if let v = o.transforms { out.transforms = v }
        if let v = o.fallbackModels { out.fallbackModels = v }
        return out
    }
}

// MARK: - App settings

nonisolated enum ThemeChoice: String, Codable, CaseIterable, Hashable, Sendable { case dark, light, system }
nonisolated enum ReadingFace: String, Codable, CaseIterable, Hashable, Sendable { case serif, sans }

nonisolated struct MemorySettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var autoExtract: Bool
    var extractionModelId: String
    var maxInjectedChars: Int

    init(enabled: Bool = true, autoExtract: Bool = true, extractionModelId: String = DefaultModels.extraction.id, maxInjectedChars: Int = 2000) {
        self.enabled = enabled; self.autoExtract = autoExtract; self.extractionModelId = extractionModelId; self.maxInjectedChars = maxInjectedChars
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.lenient(.enabled, true)
        autoExtract = c.lenient(.autoExtract, true)
        extractionModelId = c.lenient(.extractionModelId, DefaultModels.extraction.id)
        maxInjectedChars = c.lenient(.maxInjectedChars, 2000)
    }
}

nonisolated struct UISettings: Codable, Hashable, Sendable {
    var theme: ThemeChoice
    var fontScale: Double
    var density: String
    var readingFace: ReadingFace
    var showReasoningByDefault: Bool
    var showCosts: Bool
    var sendOnEnter: Bool
    var hapticsEnabled: Bool
    /// How strongly a reply's running text is inked, from 0.6 (soft) to 1 (as strong as bold).
    var textStrength: Double

    static let defaultTextStrength = 0.86

    init() {
        theme = .dark; fontScale = 1; density = "comfortable"; readingFace = .serif
        showReasoningByDefault = false; showCosts = true; sendOnEnter = true; hapticsEnabled = true
        textStrength = Self.defaultTextStrength
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = c.lenient(.theme, .dark)
        fontScale = c.lenient(.fontScale, 1)
        density = c.lenient(.density, "comfortable")
        readingFace = c.lenient(.readingFace, .serif)
        showReasoningByDefault = c.lenient(.showReasoningByDefault, false)
        showCosts = c.lenient(.showCosts, true)
        sendOnEnter = c.lenient(.sendOnEnter, true)
        hapticsEnabled = c.lenient(.hapticsEnabled, true)
        textStrength = min(1, max(0.6, c.lenient(.textStrength, Self.defaultTextStrength)))
    }
}

nonisolated struct RateLimit: Codable, Hashable, Sendable {
    var requests: Int
    var interval: String
}

nonisolated struct KeyMeta: Codable, Hashable, Sendable {
    var label: String
    var usage: Double
    var limit: Double?
    var limitRemaining: Double?
    var isFreeTier: Bool
    var rateLimit: RateLimit?
    var fetchedAt: Double
}

nonisolated struct AppSettings: Codable, Hashable, Sendable {
    /// Only populated inside a backup bundle. At rest the key lives in the Keychain, never in this file.
    var apiKey: String?
    var proxyBaseUrl: String?
    var defaultModelId: String
    var globalSettings: GenerationSettings
    var globalSystemPrompt: String
    var memory: MemorySettings
    var ui: UISettings
    var lastSyncedModelsAt: Double
    var favouriteModelIds: [String]
    var recentModelIds: [String]
    var lastChatId: String?
    var lastExportAt: Double?
    var messagesSinceExport: Int?
    var keyMeta: KeyMeta?
    var seenModelIds: [String]?
    /// iOS only: when the backup reminder was last put off.
    var exportNudgeSnoozedUntil: Double?
    /// iOS only: how new chats get their names (nil is Smart).
    var chatTitles: ChatTitleMode?

    init() {
        defaultModelId = DefaultModels.chat.id
        globalSettings = .defaults
        globalSystemPrompt = ""
        memory = MemorySettings()
        ui = UISettings()
        lastSyncedModelsAt = 0
        favouriteModelIds = []
        recentModelIds = []
        lastExportAt = 0
        messagesSinceExport = 0
        seenModelIds = []
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = c.lenient(.apiKey, nil)
        proxyBaseUrl = c.lenient(.proxyBaseUrl, nil)
        defaultModelId = c.lenient(.defaultModelId, DefaultModels.chat.id)
        globalSettings = GenerationSettings.defaults.merged(with: c.lenient(.globalSettings, nil))
        globalSystemPrompt = c.lenient(.globalSystemPrompt, "")
        memory = c.lenient(.memory, MemorySettings())
        ui = c.lenient(.ui, UISettings())
        lastSyncedModelsAt = c.lenient(.lastSyncedModelsAt, 0)
        favouriteModelIds = c.lenient(.favouriteModelIds, [])
        recentModelIds = c.lenient(.recentModelIds, [])
        lastChatId = c.lenient(.lastChatId, nil)
        lastExportAt = c.lenient(.lastExportAt, 0)
        messagesSinceExport = c.lenient(.messagesSinceExport, 0)
        keyMeta = c.lenient(.keyMeta, nil)
        seenModelIds = c.lenient(.seenModelIds, [])
        exportNudgeSnoozedUntil = c.lenient(.exportNudgeSnoozedUntil, nil)
        chatTitles = c.lenient(.chatTitles, nil)
    }
}

/// How a new chat gets its name.
nonisolated enum ChatTitleMode: String, Codable, CaseIterable, Hashable, Sendable {
    /// A short title written by the titles model, right after the first message is sent.
    case smart
    /// The opening message itself, trimmed.
    case firstMessage
    /// Stays "New chat" until renamed.
    case off

    var label: String {
        switch self {
        case .smart: "Smart"
        case .firstMessage: "First message"
        case .off: "Off"
        }
    }
}

// MARK: - Model catalogue (normalised from OpenRouter's /models)

nonisolated struct ModelPricing: Codable, Hashable, Sendable {
    var prompt: String
    var completion: String
    var request: String
    var image: String
    var webSearch: String
    var internalReasoning: String
    var cacheRead: String?
    var cacheWrite: String?
}

nonisolated struct ORModel: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var canonicalSlug: String
    var name: String
    var created: Double
    var description: String
    var contextLength: Int
    var inputModalities: [String]
    var outputModalities: [String]
    var pricing: ModelPricing
    var maxCompletionTokens: Int?
    var isModerated: Bool
    var supportedParameters: [String]
    var tokenizer: String?
    var topContextLength: Int?

    var provider: String { id.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "" }
    var shortName: String {
        if let r = name.range(of: ": ") { return String(name[r.upperBound...]) }
        return name
    }
    var acceptsImages: Bool { inputModalities.contains("image") }
    var acceptsFiles: Bool { inputModalities.contains("file") }
    var supportsReasoning: Bool { supportedParameters.contains("reasoning") || supportedParameters.contains("include_reasoning") }
    var isFree: Bool { Pricing.parse(pricing.prompt) == 0 && Pricing.parse(pricing.completion) == 0 }
    var supportsTools: Bool { supportedParameters.contains("tools") }
    var supportsStructured: Bool { supportedParameters.contains("structured_outputs") || supportedParameters.contains("response_format") }

    nonisolated enum PriceBand: String, Sendable { case free, cheap, mid, premium }

    /// The PWA's bands, by price per million tokens.
    var priceBand: PriceBand {
        let c = Pricing.parse(pricing.completion) * 1_000_000
        let p = Pricing.parse(pricing.prompt) * 1_000_000
        if c == 0 && p == 0 { return .free }
        if c <= 1.5 && p <= 0.5 { return .cheap }
        if c <= 12 && p <= 4 { return .mid }
        return .premium
    }
}

nonisolated struct Catalogue: Codable, Sendable {
    var fetchedAt: Double
    var models: [ORModel]
}

nonisolated struct DayCost: Codable, Hashable, Sendable {
    var day: String
    var costUsd: Double
    var messages: Int

    init(day: String, costUsd: Double, messages: Int) { self.day = day; self.costUsd = costUsd; self.messages = messages }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = c.lenient(.day, "")
        costUsd = c.lenient(.costUsd, 0)
        messages = c.lenient(.messages, 0)
    }
}

// MARK: - Default models

/// The user's requested defaults, as hints: a best-guess id plus a name pattern. The catalogue
/// reconciles them after every load, so a wrong guess resolves to the newest matching model.
nonisolated struct ModelHint: Sendable {
    let id: String
    let pattern: String
    let previous: [String]
}

nonisolated enum DefaultModels {
    static let chat = ModelHint(id: "deepseek/deepseek-v4-flash-0731", pattern: "deepseek.*v4.*flash", previous: ["anthropic/claude-sonnet-4"])
    static let extraction = ModelHint(id: "z-ai/glm-5.3-flash", pattern: "glm.*5\\.3.*flash", previous: ["openai/gpt-4o-mini"])
}

// MARK: - Personas, memory, folders

/// A saved system prompt, optionally with its own model and partial generation settings.
/// The PWA calls these presets in code and personas in the interface.
nonisolated struct Preset: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var systemPrompt: String
    var modelId: String?
    var settings: GenerationSettings
    var icon: String?
    var createdAt: Double

    init(id: String = newID(), name: String = "", systemPrompt: String = "", modelId: String? = nil,
         settings: GenerationSettings = GenerationSettings(), icon: String? = nil, createdAt: Double = nowMs()) {
        self.id = id; self.name = name; self.systemPrompt = systemPrompt; self.modelId = modelId
        self.settings = settings; self.icon = icon; self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, newID())
        name = c.lenient(.name, "Persona")
        systemPrompt = c.lenient(.systemPrompt, "")
        modelId = c.lenient(.modelId, nil)
        settings = c.lenient(.settings, GenerationSettings())
        icon = c.lenient(.icon, nil)
        createdAt = c.lenient(.createdAt, nowMs())
    }
}

nonisolated enum MemoryCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case identity, preference, project, relationship, context
    var id: String { rawValue }
    var title: String {
        switch self {
        case .identity: "Identity"
        case .preference: "Preferences"
        case .project: "Projects"
        case .relationship: "Relationships"
        case .context: "Context"
        }
    }
    var singular: String {
        switch self {
        case .identity: "Identity"
        case .preference: "Preference"
        case .project: "Project"
        case .relationship: "Relationship"
        case .context: "Context"
        }
    }
    var symbol: String {
        switch self {
        case .identity: "person.text.rectangle"
        case .preference: "heart.text.square"
        case .project: "hammer"
        case .relationship: "person.2"
        case .context: "globe.desk"
        }
    }
}

nonisolated struct MemoryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    var category: MemoryCategory
    var createdAt: Double
    var updatedAt: Double
    var sourceChatId: String?
    var sourceMessageId: String?
    var pinned: Bool
    var disabled: Bool

    init(id: String = newID(), text: String, category: MemoryCategory, sourceChatId: String? = nil, sourceMessageId: String? = nil) {
        let now = nowMs()
        self.id = id; self.text = text; self.category = category; self.createdAt = now; self.updatedAt = now
        self.sourceChatId = sourceChatId; self.sourceMessageId = sourceMessageId; self.pinned = false; self.disabled = false
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, newID())
        text = c.lenient(.text, "")
        category = c.lenient(.category, .context)
        createdAt = c.lenient(.createdAt, nowMs())
        updatedAt = c.lenient(.updatedAt, createdAt)
        sourceChatId = c.lenient(.sourceChatId, nil)
        sourceMessageId = c.lenient(.sourceMessageId, nil)
        pinned = c.lenient(.pinned, false)
        disabled = c.lenient(.disabled, false)
    }
}

/// A project: a home for related chats, optionally with instructions every chat in it follows.
/// Stored as a folder, the web app's word, so backups round-trip both ways: the iOS fields are
/// optional, and a web-app folder arrives as a plain project without instructions.
nonisolated struct Folder: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var createdAt: Double
    var order: Int
    var collapsed: Bool?
    /// SF Symbol on the project's tile.
    var symbol: String?
    /// A `ProjectTint` name.
    var tint: String?
    /// Followed by every chat in the project, after the usual system prompt. Empty means none.
    var instructions: String?
    /// The model new chats in the project start with; nil means the app default.
    var modelId: String?

    init(id: String = newID(), name: String, order: Int) {
        self.id = id; self.name = name; self.createdAt = nowMs(); self.order = order
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(.id, newID())
        name = c.lenient(.name, "Project")
        createdAt = c.lenient(.createdAt, nowMs())
        order = c.lenient(.order, 0)
        collapsed = c.lenient(.collapsed, nil)
        symbol = c.lenient(.symbol, nil)
        tint = c.lenient(.tint, nil)
        instructions = c.lenient(.instructions, nil)
        modelId = c.lenient(.modelId, nil)
    }

    nonisolated var symbolName: String { symbol ?? "folder.fill" }
    nonisolated var trimmedInstructions: String { (instructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    nonisolated var hasInstructions: Bool { !trimmedInstructions.isEmpty }
}

/// What the interface calls them.
typealias Project = Folder

extension GenerationSettings {
    /// True when nothing is set, so an override struct can be dropped entirely.
    nonisolated var isEmpty: Bool { self == GenerationSettings() }

    /// How many fields are set, for "Reset 3" buttons.
    nonisolated var setCount: Int {
        var n = 0
        if temperature != nil { n += 1 }
        if topP != nil { n += 1 }
        if topK != nil { n += 1 }
        if frequencyPenalty != nil { n += 1 }
        if presencePenalty != nil { n += 1 }
        if repetitionPenalty != nil { n += 1 }
        if minP != nil { n += 1 }
        if topA != nil { n += 1 }
        if seed != nil { n += 1 }
        if maxTokens != nil { n += 1 }
        if stop != nil { n += 1 }
        if stream != nil { n += 1 }
        if reasoning != nil { n += 1 }
        if provider != nil { n += 1 }
        if webSearch != nil { n += 1 }
        if transforms != nil { n += 1 }
        if fallbackModels != nil { n += 1 }
        return n
    }
}

