import Foundation
import Observation
import UIKit

nonisolated enum SettingsSection: String, Hashable, Sendable, CaseIterable {
    case connection, generation, prompts, memory, appearance, data, about
}

nonisolated enum Route: Hashable, Sendable {
    case chat(String)
    case project(String)
    case settings
    case section(SettingsSection)
    case memory
    case spending
}

/// App-wide state: settings, the API key, the model catalogue, chats, personas, memory, projects
/// and day costs. One instance for the app's lifetime. The open thread and its stream engine live
/// in `ChatSession`.
@Observable
final class AppModel {
    let store: Store
    let toasts = ToastCenter()
    let connectivity = Connectivity()
    let extractor = MemoryExtractor()

    var settings: AppSettings
    /// Mirrors the Keychain. Change it with `setAPIKey(_:)` so the Keychain stays in step.
    private(set) var apiKey: String? = nil

    private(set) var models: [ORModel] = []
    private(set) var modelsById: [String: ORModel] = [:]
    private(set) var catalogueFetchedAt: Double = 0
    private(set) var loadingModels = false
    private(set) var modelsError: String? = nil
    /// Models that appeared since the user last looked (the PWA's "new" badge).
    private(set) var newModelIds: Set<String> = []

    var chats: [Chat] = []
    var costs: [DayCost] = []
    var presets: [Preset] = []
    var memory: [MemoryEntry] = []
    var folders: [Folder] = []

    /// Live sessions by chat id. A session keeps streaming while you browse elsewhere; idle ones
    /// are dropped when another chat opens so memory stays bounded.
    @ObservationIgnored var sessions: [String: ChatSession] = [:]

    /// Navigation, owned here so a cold launch can resume the last chat and search hits can deep-link.
    var path: [Route] = []

    /// Settings opens as its own layer that slides in from the leading edge (the gear sits top-left),
    /// with its own stack for the sections inside it.
    var settingsOpen = false
    var settingsPath: [Route] = []

    private static let staleMs: Double = 6 * 60 * 60 * 1000

    init() {
        let store = Store()
        self.store = store
        settings = store.loadSettings()
        apiKey = Keychain.readKey()
        chats = store.loadChats().sorted { $0.updatedAt > $1.updatedAt }
        costs = store.loadCosts()
        presets = store.loadPresets().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        memory = store.loadMemory().sorted { $0.updatedAt > $1.updatedAt }
        folders = store.loadFolders().sorted { $0.order < $1.order }
        if let c = store.loadCatalogue() { applyCatalogue(c.models, fetchedAt: c.fetchedAt) }
        Haptics.enabled = settings.ui.hapticsEnabled
        resumeLastChat()
    }

    func persistSettings() {
        Haptics.enabled = settings.ui.hapticsEnabled
        store.saveSettings(settings)
    }

    var client: OpenRouterClient { OpenRouterClient(apiKey: apiKey, baseURL: settings.proxyBaseUrl) }

    func setAPIKey(_ key: String?) {
        let k = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (k?.isEmpty ?? true) ? nil : k
        Keychain.writeKey(apiKey)
        settings.keyMeta = nil
    }

    func refreshKeyMeta() async throws {
        settings.keyMeta = try await client.keyMeta()
    }

    // MARK: Navigation

    private func resumeLastChat() {
        let visible = chats.filter { !$0.archived }
        if let last = settings.lastChatId, visible.contains(where: { $0.id == last }) { path = stack(for: last) }
        else if let newest = visible.first { path = stack(for: newest.id) }
        else { path = [.chat(newChat().chat.id)] }
    }

    func openChat(_ id: String, highlight: String? = nil) {
        if let highlight { session(for: id)?.highlightId = highlight }
        path = stack(for: id)
        closeSettings()
    }

    /// A chat in a project opens over its project, so going back lands there rather than on a list
    /// the chat isn't in.
    private func stack(for chatId: String, projectId: String? = nil) -> [Route] {
        let pid = projectId ?? chat(chatId)?.folderId
        if let p = project(pid) { return [.project(p.id), .chat(chatId)] }
        return [.chat(chatId)]
    }

    /// Opens a fresh chat; one started in a project opens over the project.
    func startNewChat(persona: Preset? = nil, incognito: Bool = false, projectId: String? = nil) {
        let s = newChat(persona: persona, incognito: incognito, projectId: projectId)
        path = stack(for: s.chat.id, projectId: s.chat.folderId)
        closeSettings()
    }

    /// Pushes onto whichever stack is on screen: the settings layer when it's open, else the main one.
    func push(_ route: Route) {
        if settingsOpen { settingsPath.append(route) } else { path.append(route) }
    }

    /// Always opens at the top of settings, wherever it was left last time.
    func openSettings() {
        guard !settingsOpen else { return }
        settingsPath = []
        settingsOpen = true
    }

    func closeSettings() { if settingsOpen { settingsOpen = false } }

    /// A reply finished in a chat that isn't the one on screen (replies keep streaming while you
    /// browse): say so, with a way straight back to it.
    func replyFinished(chatId: String, title: String) {
        // Unless you're looking at the chat (or will be, the moment settings closes), its row in the
        // list shows a dot until you open it.
        let onTop: Bool
        if case .chat(let open)? = path.last { onTop = open == chatId } else { onTop = false }
        if !onTop { patchChat(chatId) { $0.unread = true } }
        if onTop && !settingsOpen { return }
        guard UIApplication.shared.applicationState == .active else { return }
        let name = title.count > 32 ? String(title.prefix(31)) + "…" : title
        Haptics.success()
        toasts.show("Reply ready in “\(name)”", symbol: "text.bubble",
                    action: (label: "Open", run: { [weak self] in self?.openChat(chatId) }))
    }

    func markRead(_ id: String) {
        guard chat(id)?.unread == true else { return }
        patchChat(id) { $0.unread = nil }
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
    func newChat(persona: Preset? = nil, incognito: Bool = false, modelId: String? = nil, projectId: String? = nil) -> ChatSession {
        evictIdleSessions(keeping: nil)
        let project = self.project(projectId)
        var chat = Chat(modelId: modelId ?? persona?.modelId ?? project?.modelId ?? settings.defaultModelId,
                        memoryEnabled: !incognito && settings.memory.enabled)
        chat.systemPromptId = persona?.id
        chat.folderId = project?.id
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

    func chat(_ id: String) -> Chat? { chats.first(where: { $0.id == id }) }

    func patchChat(_ id: String, _ mutate: (inout Chat) -> Void) {
        guard let i = chats.firstIndex(where: { $0.id == id }) else { return }
        mutate(&chats[i])
        let updated = chats[i]
        sessions[id]?.chatDidChangeExternally(updated)
        chats.sort { $0.updatedAt > $1.updatedAt }
        store.saveChats(chats)
    }

    func patchChats(_ ids: Set<String>, _ mutate: (inout Chat) -> Void) {
        for i in chats.indices where ids.contains(chats[i].id) {
            mutate(&chats[i])
            sessions[chats[i].id]?.chatDidChangeExternally(chats[i])
        }
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
        if case .chat(let open)? = path.last, ids.contains(open) { path.removeLast() }
    }

    /// Add a complete chat (from duplicate or branch) and its messages.
    func insertChat(_ chat: Chat, messages: [Message]) {
        store.saveMessages(chat.id, messages)
        upsertChat(chat)
    }

    func duplicateChat(_ id: String) -> String? {
        guard let src = chat(id) else { return nil }
        sessions[id]?.flushDraft()
        let msgs = sessions[id].map { Array($0.messages.values) } ?? store.loadMessages(id)
        var idMap: [String: String] = [:]
        for m in msgs { idMap[m.id] = newID() }
        let now = nowMs()
        var copy = src
        copy.id = newID()
        copy.title = "\(src.title) (copy)"
        copy.createdAt = now
        copy.updatedAt = now
        copy.pinned = false
        copy.draft = ""
        copy.totalCostUsd = 0
        copy.activeLeafId = src.activeLeafId.flatMap { idMap[$0] }
        let newMsgs: [Message] = msgs.map { (m: Message) -> Message in
            var n = m
            n.id = idMap[m.id] ?? newID()
            n.chatId = copy.id
            n.parentId = m.parentId.flatMap { idMap[$0] }
            n.editedFrom = m.editedFrom.flatMap { idMap[$0] }
            return n
        }
        insertChat(copy, messages: newMsgs)
        return copy.id
    }

    // MARK: Projects

    /// Most recently active first: a project rises when any chat in it moves.
    var projects: [Project] {
        let latest = latestActivity
        return folders.sorted { (latest[$0.id] ?? $0.createdAt) > (latest[$1.id] ?? $1.createdAt) }
    }

    /// The newest `updatedAt` among each project's chats, in one pass.
    private var latestActivity: [String: Double] {
        var out: [String: Double] = [:]
        for c in chats {
            guard let id = c.folderId else { continue }
            out[id] = max(out[id] ?? 0, c.updatedAt)
        }
        return out
    }

    func project(_ id: String?) -> Project? {
        guard let id else { return nil }
        return folders.first(where: { $0.id == id })
    }

    /// The project a chat is in, if it still exists (a deleted one leaves no dangling links, but
    /// a backup from elsewhere might).
    func project(of chat: Chat) -> Project? { project(chat.folderId) }

    func chats(inProject id: String, archived: Bool = false) -> [Chat] {
        chats.filter { $0.folderId == id && $0.archived == archived }
    }

    @discardableResult
    func createProject(_ draft: Project) -> Project {
        var p = draft
        p.order = (folders.map(\.order).max() ?? -1) + 1
        p.createdAt = nowMs()
        folders.append(p)
        store.saveFolders(folders)
        return p
    }

    func updateProject(_ p: Project) {
        guard let i = folders.firstIndex(where: { $0.id == p.id }) else { return }
        folders[i] = p
        store.saveFolders(folders)
    }

    /// Removes a project. Its chats either go with it or move back to the main list.
    func deleteProject(_ id: String, deletingChats: Bool) {
        let inside = Set(chats.filter { $0.folderId == id }.map(\.id))
        if !inside.isEmpty {
            if deletingChats { deleteChats(inside) } else { patchChats(inside) { $0.folderId = nil } }
        }
        folders.removeAll { $0.id == id }
        store.saveFolders(folders)
        if let i = path.firstIndex(of: .project(id)) { path = Array(path.prefix(upTo: i)) }
    }

    /// Puts a deleted project back, with the chats it had (the undo after a delete that kept them).
    func restoreProject(_ p: Project, chatIds: Set<String>) {
        guard project(p.id) == nil else { return }
        folders.append(p)
        store.saveFolders(folders)
        let still = chatIds.filter { id in chats.contains { $0.id == id && $0.folderId == nil } }
        if !still.isEmpty { patchChats(Set(still)) { $0.folderId = p.id } }
    }

    /// Moves chats into a project (or out of any, with nil).
    func moveChats(_ ids: Set<String>, toProject id: String?) {
        guard !ids.isEmpty else { return }
        patchChats(ids) { $0.folderId = id }
    }

    // MARK: Personas

    func preset(_ id: String?) -> Preset? {
        guard let id else { return nil }
        return presets.first(where: { $0.id == id })
    }

    func savePreset(_ p: Preset) {
        if let i = presets.firstIndex(where: { $0.id == p.id }) { presets[i] = p } else { presets.append(p) }
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        store.savePresets(presets)
    }

    func deletePreset(_ id: String) {
        presets.removeAll { $0.id == id }
        store.savePresets(presets)
    }

    @discardableResult
    func duplicatePreset(_ p: Preset) -> Preset {
        var copy = p
        copy.id = newID()
        copy.name = "\(p.name) (copy)"
        copy.createdAt = nowMs()
        savePreset(copy)
        return copy
    }

    // MARK: Memory

    func addMemory(_ text: String, category: MemoryCategory) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        memory.insert(MemoryEntry(text: t, category: category), at: 0)
        store.saveMemory(memory)
    }

    func updateMemory(_ id: String, _ mutate: (inout MemoryEntry) -> Void) {
        guard let i = memory.firstIndex(where: { $0.id == id }) else { return }
        mutate(&memory[i])
        memory[i].updatedAt = nowMs()
        store.saveMemory(memory)
    }

    func deleteMemory(_ id: String) {
        memory.removeAll { $0.id == id }
        store.saveMemory(memory)
    }

    func clearMemory() {
        memory = []
        store.saveMemory(memory)
    }

    /// Replace the list after an extraction pass.
    func setMemory(_ list: [MemoryEntry]) {
        memory = list.sorted { $0.updatedAt > $1.updatedAt }
        store.saveMemory(memory)
    }

    // MARK: Costs

    var todayCost: Double { costs.first(where: { $0.day == dayKey() })?.costUsd ?? 0 }

    func costSince(daysAgo: Int) -> Double {
        let cutoff = dayKey(nowMs() - Double(daysAgo) * 86_400_000)
        return costs.filter { $0.day >= cutoff }.reduce(0) { $0 + $1.costUsd }
    }

    /// One point per day for the last `days` days, oldest first, zero-filled.
    func dailySeries(days: Int) -> [DayPoint] {
        var byDay: [String: Double] = [:]
        for c in costs { byDay[c.day, default: 0] += c.costUsd }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var out: [DayPoint] = []
        for back in stride(from: days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            out.append(DayPoint(date: d, cost: byDay[dayKey(d.timeIntervalSince1970 * 1000)] ?? 0))
        }
        return out
    }

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

    // MARK: Backup reminder

    /// The PWA's nudge: after 200 messages, or 30 days since the last export with anything new.
    var exportNudgeDue: Bool {
        if let snooze = settings.exportNudgeSnoozedUntil, nowMs() < snooze { return false }
        let since = settings.messagesSinceExport ?? 0
        if since >= 200 { return true }
        let last = settings.lastExportAt ?? 0
        if last > 0 && since > 0 && nowMs() - last > 30 * 86_400_000 { return true }
        if last == 0 && since >= 60 { return true }
        return false
    }

    func snoozeExportNudge() {
        settings.exportNudgeSnoozedUntil = nowMs() + 7 * 86_400_000
    }

    // MARK: Model catalogue

    func model(_ id: String?) -> ORModel? {
        guard let id else { return nil }
        return modelsById[id]
    }

    func modelName(_ id: String?) -> String {
        if let m = model(id) { return m.shortName }
        return shortId(id ?? "")
    }

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
            let seen = Set(settings.seenModelIds ?? [])
            if seen.isEmpty {
                settings.seenModelIds = list.map(\.id)
            } else {
                newModelIds.formUnion(list.map(\.id).filter { !seen.contains($0) })
            }
            applyCatalogue(list, fetchedAt: fetchedAt)
            store.saveCatalogue(Catalogue(fetchedAt: fetchedAt, models: list))
            settings.lastSyncedModelsAt = fetchedAt
        } catch {
            modelsError = error.localizedDescription
        }
    }

    func acknowledgeNewModels() {
        settings.seenModelIds = models.map(\.id)
        newModelIds = []
    }

    func clearModelCache() async {
        store.deleteCatalogue()
        catalogueFetchedAt = 0
        await refreshModels(force: true)
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
                .max(by: { $0.created < $1.created })?.id
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
        Haptics.selection()
    }

    func touchRecent(_ id: String) {
        settings.recentModelIds = Array(([id] + settings.recentModelIds.filter { $0 != id }).prefix(8))
    }

    // MARK: Lifecycle

    func didEnterBackground() {
        for s in sessions.values { s.flushDraft() }
        persistSettings()
        let store = self.store
        let task = UIApplication.shared.beginBackgroundTask(withName: "quire.flush", expirationHandler: nil)
        Task {
            await store.flush()
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}

nonisolated struct DayPoint: Identifiable, Hashable, Sendable {
    var date: Date
    var cost: Double
    var id: Date { date }
}

/// "deepseek/deepseek-v4-flash" → "deepseek-v4-flash", for ids the catalogue doesn't know.
func shortId(_ id: String) -> String {
    guard let slash = id.firstIndex(of: "/") else { return id.isEmpty ? "No model" : id }
    return String(id[id.index(after: slash)...])
}
