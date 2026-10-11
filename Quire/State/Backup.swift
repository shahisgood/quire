import Foundation

/// The PWA's backup format, unchanged: `{ app: "quire", version: 1, chats, messages, ... }`.
/// A backup from the web app imports here, and a backup from here imports into the web app.
nonisolated struct BackupBundle: Codable, Sendable {
    var app: String = "quire"
    var version: Int = 1
    var exportedAt: Double = nowMs()
    var chats: [Chat] = []
    var messages: [Message] = []
    var folders: [JSONValue] = []
    var presets: [JSONValue] = []
    var memory: [JSONValue] = []
    var dayCosts: [DayCost] = []
    var settings: AppSettings?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = c.lenient(.app, "")
        version = c.lenient(.version, 1)
        exportedAt = c.lenient(.exportedAt, 0)
        chats = try c.decode([Chat].self, forKey: .chats)
        messages = try c.decode([Message].self, forKey: .messages)
        folders = c.lenient(.folders, [])
        presets = c.lenient(.presets, [])
        memory = c.lenient(.memory, [])
        dayCosts = c.lenient(.dayCosts, [])
        settings = c.lenient(.settings, nil)
    }
}

struct ImportResult {
    var chats: Int
    var messages: Int
}

enum BackupError: LocalizedError {
    case notJSON, notQuire
    var errorDescription: String? {
        switch self {
        case .notJSON: "That file is not valid JSON."
        case .notQuire: "That file is not a Quire backup."
        }
    }
}

extension AppModel {
    /// Write a full backup to a temporary file for the share sheet.
    func exportBackup(includeKey: Bool) async throws -> URL {
        for s in sessions.values { s.flushDraft() }
        await store.flush()
        var b = BackupBundle()
        b.chats = chats
        b.messages = chats.flatMap { store.loadMessages($0.id) }
        b.folders = extras.folders
        b.presets = extras.presets
        b.memory = extras.memory
        b.dayCosts = costs
        var s = settings
        s.apiKey = includeKey ? apiKey : nil
        b.settings = s
        let data = try JSONEncoder().encode(b)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quire-backup-\(dayKey()).json")
        try data.write(to: url, options: .atomic)
        settings.lastExportAt = nowMs()
        settings.messagesSinceExport = 0
        return url
    }

    func importBackup(_ data: Data, replace: Bool) async throws -> ImportResult {
        guard let probe = JSONValue.parse(data) else { throw BackupError.notJSON }
        guard probe["app"]?.stringValue == "quire", probe["chats"]?.arrayValue != nil, probe["messages"]?.arrayValue != nil else { throw BackupError.notQuire }
        let b = try JSONDecoder().decode(BackupBundle.self, from: data)

        for s in sessions.values { s.stop() }
        sessions = [:]
        path = []
        await store.flush()

        var byChat: [String: [Message]] = Dictionary(grouping: b.messages.map { (m: Message) -> Message in
            var m = m
            m.lc = m.role == .user ? m.content.lowercased() : nil
            return m
        }, by: \.chatId)

        if replace {
            for c in chats { store.deleteMessages(c.id) }
            chats = b.chats
            costs = b.dayCosts
            extras = BackupExtras(folders: b.folders, presets: b.presets, memory: b.memory)
        } else {
            for c in b.chats {
                if let i = chats.firstIndex(where: { $0.id == c.id }) { chats[i] = c } else { chats.append(c) }
                let existing = store.loadMessages(c.id)
                var merged = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                for m in byChat[c.id] ?? [] { merged[m.id] = m }
                byChat[c.id] = Array(merged.values)
            }
            func upsert(_ list: inout [JSONValue], _ incoming: [JSONValue]) {
                for item in incoming {
                    if let id = item["id"]?.stringValue, let i = list.firstIndex(where: { $0["id"]?.stringValue == id }) { list[i] = item }
                    else { list.append(item) }
                }
            }
            upsert(&extras.folders, b.folders)
            upsert(&extras.presets, b.presets)
            let known = Set(extras.memory.compactMap { $0["text"]?.stringValue?.lowercased() })
            extras.memory += b.memory.filter { !known.contains($0["text"]?.stringValue?.lowercased() ?? "") }
            for d in b.dayCosts where !costs.contains(where: { $0.day == d.day }) { costs.append(d) }
        }

        let chatIds = Set(chats.map(\.id))
        for (chatId, msgs) in byChat where chatIds.contains(chatId) { store.saveMessages(chatId, msgs) }
        chats.sort { $0.updatedAt > $1.updatedAt }
        store.saveChats(chats)
        store.saveCosts(costs)
        store.saveExtras(extras)

        if var s = b.settings {
            if let key = s.apiKey, !key.isEmpty { setAPIKey(key) }
            s.apiKey = nil
            s.keyMeta = nil
            // The web app couldn't use haptics on iOS, so its "off" says nothing about a preference here.
            s.ui.hapticsEnabled = settings.ui.hapticsEnabled
            settings = s
        }
        return ImportResult(chats: b.chats.count, messages: b.messages.count)
    }

    /// One chat's visible branch as Markdown, to a temporary file for the share sheet.
    func exportMarkdown(_ session: ChatSession) throws -> URL {
        let chat = session.chat
        let date = Date(timeIntervalSince1970: chat.createdAt / 1000).formatted(date: .abbreviated, time: .shortened)
        var lines = ["# \(chat.title)", "", "_\(date) · \(chat.modelId)_", ""]
        for m in session.thread {
            if m.role == .user {
                lines += ["## You", "", m.content, ""]
            } else if m.role == .assistant {
                lines += ["## \(m.modelId ?? "Assistant")", ""]
                if let r = m.reasoning, !r.isEmpty { lines += ["<details><summary>Reasoning</summary>", "", r, "", "</details>", ""] }
                lines += [m.content, ""]
            }
        }
        let slug = chat.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let name = String((slug.isEmpty ? "chat" : slug).prefix(40))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).md")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func wipeEverything() async {
        for s in sessions.values { s.stop() }
        sessions = [:]
        await store.wipe()
        chats = []
        costs = []
        extras = BackupExtras()
        setAPIKey(nil)
        settings = AppSettings()
        path = []
        startNewChat()
    }
}
