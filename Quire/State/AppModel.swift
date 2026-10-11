import Foundation
import Observation
import UIKit

/// App-wide state: settings, the API key, the model catalogue, the chat list and day costs.
/// One instance for the app's lifetime. The open thread and its stream engine live in `ChatSession`.
@Observable
final class AppModel {
    let store: Store

    var settings: AppSettings
    /// Mirrors the Keychain. Change it with `setAPIKey(_:)` so the Keychain stays in step.
    private(set) var apiKey: String? = nil

    private(set) var models: [ORModel] = []
    private(set) var modelsById: [String: ORModel] = [:]
    private(set) var catalogueFetchedAt: Double = 0
    private(set) var loadingModels = false
    private(set) var modelsError: String? = nil

    var chats: [Chat] = []
    var costs: [DayCost] = []
    var extras: BackupExtras

    /// Live sessions by chat id. A session keeps streaming while you browse elsewhere; idle ones
    /// are dropped when another chat opens so memory stays bounded.
    @ObservationIgnored var sessions: [String: ChatSession] = [:]

    /// Navigation, owned here so a cold launch can resume the last chat and search hits can deep-link.
    var path: [Route] = []

    private static let staleMs: Double = 6 * 60 * 60 * 1000

    init() {
        let store = Store()
        self.store = store
        settings = store.loadSettings()
        apiKey = Keychain.readKey()
        chats = store.loadChats().sorted { $0.updatedAt > $1.updatedAt }
        costs = store.loadCosts()
        extras = store.loadExtras()
        if let c = store.loadCatalogue() { applyCatalogue(c.models, fetchedAt: c.fetchedAt) }
        resumeLastChat()
    }

    func setAPIKey(_ key: String?) {
        let k = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (k?.isEmpty ?? true) ? nil : k
        Keychain.writeKey(apiKey)
        settings.keyMeta = nil
    }

    func persistSettings() { store.saveSettings(settings) }

    var client: OpenRouterClient { OpenRouterClient(apiKey: apiKey, baseURL: settings.proxyBaseUrl) }

    // MARK: Navigation

    private func resumeLastChat() {
        let visible = chats.filter { !$0.archived }
        if let last = settings.lastChatId, visible.contains(where: { $0.id == last }) { path = [.chat(last)] }
        else if let newest = visible.first { path = [.chat(newest.id)] }
        else { path = [.chat(newChat().chat.id)] }
    }

    func openChat(_ id: String, highlight: String? = nil) {
        path = [.chat(id)]
        if let highlight { session(for: id)?.highlightId = highlight }
    }

    func startNewChat() {
        let s = newChat()
        path = [.chat(s.chat.id)]
    }

    // MARK: Sessions

    func session(for id: String) -> ChatSession? {
        if let s = sessions[id] { return s }
        guard let chat = chats.first(where: { $0.id == id }) else { return nil }
        evictIdleSessions(keeping: id)
        let s = ChatSession(app: self, chat: chat, persisted: true)
        sessions[id] = s
        settings.lastChatId = id
        return s
    }

    @discardableResult
    func newChat(modelId: String? = nil) -> ChatSession {
        evictIdleSessions(keeping: nil)
        let chat = Chat(modelId: modelId ?? settings.defaultModelId, memoryEnabled: settings.memory.enabled)
        let s = ChatSession(app: self, chat: chat, persisted: false)
        sessions[chat.id] = s
        return s
    }

    private func evictIdleSessions(keeping id: String?) {
        for (k, s) in sessions where k != id && !s.generating {
            s.flushDraft()
            sessions[k] = nil
        }
    }

    var isAnyGenerating: Bool { sessions.values.contains { $0.generating } }

    // MARK: Chats

    /// Insert or replace a chat in the list and persist it.
    func upsertChat(_ chat: Chat) {
        if let i = chats.firstIndex(where: { $0.id == chat.id }) { chats[i] = chat } else { chats.append(chat) }
        chats.sort { $0.updatedAt > $1.updatedAt }
        store.saveChats(chats)
    }

    func chat(_ id: String) -> Chat? { chats.first { $0.id == id } }

    func patchChat(_ id: String, _ mutate: (inout Chat) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        mutate(&chats[i])
        let updated = chats[i]
        sessions[id]?.chatDidChangeExternally(updated)
        chats.sort { $0.updatedAt > $1.updatedAt }
        store.saveChats(chats)
    }

    func deleteChats(_ ids: Set<String>) {
        for id in ids {
            sessions[id]?.markDeleted()
            sessions[id] = nil
            store.deleteMessages(id)
        }
        chats.removeAll { ids.contains($0.id) }
        store.saveChats(chats)
        if case .chat(let open)? = path.last, ids.contains(open) { path = [] }
    }

    // MARK: Costs

    var todayCost: Double { costs.first(where: { $0.day == dayKey() })?.costUsd ?? 0 }

    /// Apply a cost change to a chat and to today's total. Deltas, not absolutes, so an estimate
    /// later replaced by the authoritative figure never double-counts.
    func applyCostDelta(chatId: String, delta: Double, countMessage: Bool = false) {
        guard delta.isFinite, delta != 0 || countMessage else { return }
        if delta != 0 {
            patchChat(chatId) { $0.totalCostUsd = max(0, $0.totalCostUsd + delta) }
        }
        let day = dayKey()
        if let i = costs.firstIndex(where: { $0.day == day }) {
            costs[i].costUsd = max(0, costs[i].costUsd + delta)
            if countMessage { costs[i].messages += 1 }
        } else {
            costs.append(DayCost(day: day, costUsd: max(0, delta), messages: countMessage ? 1 : 0))
        }
        store.saveCosts(costs)
    }

    // MARK: Model catalogue

    func model(_ id: String?) -> ORModel? { id.flatMap { modelsById[$0] } }

    private func applyCatalogue(_ list: [ORModel], fetchedAt: Double) {
        models = list
        modelsById = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        catalogueFetchedAt = fetchedAt
        reconcileDefaults()
    }

    func refreshModels(force: Bool = false) async {
        if loadingModels { return }
        if !force, catalogueFetchedAt > 0, nowMs() - catalogueFetchedAt < Self.staleMs { return }
        loadingModels = true
        modelsError = nil
        defer { loadingModels = false }
        do {
            var list = try await client.models()
            guard !list.isEmpty else { throw ORError(status: 0, code: "empty", message: "OpenRouter returned an empty model list.") }
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let fetchedAt = nowMs()
            applyCatalogue(list, fetchedAt: fetchedAt)
            store.saveCatalogue(Catalogue(fetchedAt: fetchedAt, models: list))
            settings.lastSyncedModelsAt = fetchedAt
        } catch {
            modelsError = error.localizedDescription
        }
    }

    /// If a default model's guessed id isn't in the catalogue, adopt the newest model whose name
    /// matches the hint. Only touches settings the user hasn't changed from a default.
    private func reconcileDefaults() {
        guard !models.isEmpty else { return }
        func resolve(_ h: ModelHint) -> String? {
            if modelsById[h.id] != nil { return h.id }
            return models
                .filter { $0.name.range(of: h.pattern, options: [.regularExpression, .caseInsensitive]) != nil
                    || $0.id.range(of: h.pattern, options: [.regularExpression, .caseInsensitive]) != nil }
                .max { $0.created < $1.created }?.id
        }
        func isDefault(_ id: String, _ h: ModelHint) -> Bool { id == h.id || h.previous.contains(id) }
        if let chat = resolve(DefaultModels.chat), isDefault(settings.defaultModelId, DefaultModels.chat), settings.defaultModelId != chat {
            settings.defaultModelId = chat
        }
        if let ext = resolve(DefaultModels.extraction), isDefault(settings.memory.extractionModelId, DefaultModels.extraction), settings.memory.extractionModelId != ext {
            settings.memory.extractionModelId = ext
        }
    }

    func toggleFavourite(_ id: String) {
        if let i = settings.favouriteModelIds.firstIndex(of: id) { settings.favouriteModelIds.remove(at: i) }
        else { settings.favouriteModelIds.append(id) }
    }

    func touchRecent(_ id: String) {
        settings.recentModelIds = Array(([id] + settings.recentModelIds.filter { $0 != id }).prefix(8))
    }

    // MARK: Key

    func refreshKeyMeta() async throws {
        settings.keyMeta = try await client.keyMeta()
    }

    // MARK: Personas imported from the PWA

    /// Chats created from a PWA persona reference it by id. Personas aren't editable in this build,
    /// but their prompt and settings still apply to those chats.
    func preset(_ id: String?) -> (systemPrompt: String, settings: GenerationSettings?)? {
        guard let id, let p = extras.presets.first(where: { $0["id"]?.stringValue == id }) else { return nil }
        let s = p["settings"].flatMap { try? JSONDecoder().decode(GenerationSettings.self, from: $0.data()) }
        return (p["systemPrompt"]?.stringValue ?? "", s)
    }

    // MARK: Lifecycle

    func didEnterBackground() {
        for s in sessions.values { s.flushDraft() }
        persistSettings()
    }
}

enum Route: Hashable {
    case chat(String)
    case settings
}
