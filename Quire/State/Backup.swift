import Foundation

/// The PWA's backup format, unchanged: `{ app: "quire", version: 1, chats, messages, folders,
/// presets, memory, dayCosts, settings }`. A backup from the web app imports here and the reverse.
nonisolated struct BackupBundle: Codable, Sendable {
    var app: String = "quire"
    var version: Int = 1
    var exportedAt: Double = nowMs()
    var chats: [Chat] = []
    var messages: [Message] = []
    var folders: [Folder] = []
    var presets: [Preset] = []
    var memory: [MemoryEntry] = []
    var dayCosts: [DayCost] = []
    var settings: AppSettings? = nil

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

/// The PWA's personas file: `{ app: "quire-presets", presets }`.
nonisolated struct PresetsFile: Codable, Sendable {
    var app: String = "quire-presets"
    var presets: [Preset]
}

struct ImportResult {
    var chats: Int
    var messages: Int
    var memory: Int
    var presets: Int
}

nonisolated enum BackupError: LocalizedError {
    case notJSON, notQuire, notPersonas
    var errorDescription: String? {
        switch self {
        case .notJSON: "That file isn't valid JSON."
        case .notQuire: "That file isn't a Quire backup."
        case .notPersonas: "That file isn't a Quire personas file."
        }
    }
}

extension AppModel {
    private func writeTemp(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func slug(_ s: String) -> String {
        let t = s.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String((t.isEmpty ? "chat" : t).prefix(40))
    }

    /// Every message of a chat: from its live session if open, else from disk.
    func allMessages(_ chatId: String) -> [Message] {
        if let s = sessions[chatId] { return Array(s.messages.values) }
        return store.loadMessages(chatId)
    }

    /// A full backup, to a temporary file for the share sheet.
    func exportBackup(includeKey: Bool) async throws -> URL {
        for s in sessions.values { s.flushDraft() }
        await store.flush()
        var b = BackupBundle()
        b.chats = chats
        b.messages = chats.flatMap { allMessages($0.id) }
        b.folders = folders
        b.presets = presets
        b.memory = memory
        b.dayCosts = costs
        var s = settings
        s.apiKey = includeKey ? apiKey : nil
        b.settings = s
        let url = try writeTemp(try JSONEncoder().encode(b), name: "quire-backup-\(dayKey()).json")
        settings.lastExportAt = nowMs()
        settings.messagesSinceExport = 0
        settings.exportNudgeSnoozedUntil = nil
        return url
    }

    /// Selected chats as a backup bundle. Unlike the PWA, this carries only those chats (and the
    /// personas they use): no memory, no settings, so sharing a chat never leaks anything else.
    func exportChats(_ ids: Set<String>) throws -> URL {
        var b = BackupBundle()
        b.chats = chats.filter { ids.contains($0.id) }
        b.messages = b.chats.flatMap { allMessages($0.id) }
        let used = Set(b.chats.compactMap(\.systemPromptId))
        b.presets = presets.filter { used.contains($0.id) }
        let name = b.chats.count == 1 ? Self.slug(b.chats[0].title) : "quire-\(b.chats.count)-chats"
        return try writeTemp(try JSONEncoder().encode(b), name: "\(name).json")
    }

    func importBackup(_ data: Data, replace: Bool) async throws -> ImportResult {
        guard let probe = JSONValue.parse(data) else { throw BackupError.notJSON }
        guard probe["app"]?.stringValue == "quire", probe["chats"]?.arrayValue != nil, probe["messages"]?.arrayValue != nil else {
            throw BackupError.notQuire
        }
        let b = try JSONDecoder().decode(BackupBundle.self, from: data)

        for s in sessions.values { s.stop() }
        sessions = [:]
        path = []
        await store.flush()

        var byChat: [String: [Message]] = [:]
        for var m in b.messages {
            m.lc = m.role == .user ? m.content.lowercased() : nil
            byChat[m.chatId, default: []].append(m)
        }

        var addedMemory = 0
        if replace {
            for c in chats { store.deleteMessages(c.id) }
            chats = b.chats
            costs = b.dayCosts
            folders = b.folders.sorted { $0.order < $1.order }
            presets = b.presets
            memory = b.memory
            addedMemory = b.memory.count
        } else {
            for c in b.chats {
                if let i = chats.firstIndex(where: { $0.id == c.id }) { chats[i] = c } else { chats.append(c) }
                var merged: [String: Message] = [:]
                for m in store.loadMessages(c.id) { merged[m.id] = m }
                for m in byChat[c.id] ?? [] { merged[m.id] = m }
                byChat[c.id] = Array(merged.values)
            }
            for f in b.folders {
                if let i = folders.firstIndex(where: { $0.id == f.id }) { folders[i] = f } else { folders.append(f) }
            }
            for p in b.presets {
                if let i = presets.firstIndex(where: { $0.id == p.id }) { presets[i] = p } else { presets.append(p) }
            }
            let known = Set(memory.map { $0.text.lowercased() })
            for var e in b.memory where !known.contains(e.text.lowercased()) {
                e.id = newID()
                memory.append(e)
                addedMemory += 1
            }
            for d in b.dayCosts where !costs.contains(where: { $0.day == d.day }) { costs.append(d) }
        }

        let chatIds = Set(chats.map(\.id))
        for (chatId, msgs) in byChat where chatIds.contains(chatId) { store.saveMessages(chatId, msgs) }
        chats.sort { $0.updatedAt > $1.updatedAt }
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        memory.sort { $0.updatedAt > $1.updatedAt }
        store.saveChats(chats)
        store.saveCosts(costs)
        store.saveFolders(folders)
        store.savePresets(presets)
        store.saveMemory(memory)

        if var s = b.settings {
            if let key = s.apiKey, !key.isEmpty { setAPIKey(key) }
            s.apiKey = nil
            s.keyMeta = nil
            // The web app couldn't use haptics on iOS, so its "off" says nothing about a preference here.
            s.ui.hapticsEnabled = settings.ui.hapticsEnabled
            s.lastChatId = settings.lastChatId
            settings = s
        }
        await store.flush()
        return ImportResult(chats: b.chats.count, messages: b.messages.count, memory: addedMemory, presets: b.presets.count)
    }

    // MARK: Personas file

    func exportPresets() throws -> URL {
        try writeTemp(try JSONEncoder().encode(PresetsFile(presets: presets)), name: "quire-personas.json")
    }

    /// Import personas; an id that already exists gets a fresh one so nothing is overwritten.
    func importPresets(_ data: Data) throws -> Int {
        guard let probe = JSONValue.parse(data) else { throw BackupError.notJSON }
        guard probe["presets"]?.arrayValue != nil else { throw BackupError.notPersonas }
        let file = try JSONDecoder().decode(PresetsFile.self, from: data)
        for var p in file.presets {
            if presets.contains(where: { $0.id == p.id }) { p.id = newID() }
            savePreset(p)
        }
        return file.presets.count
    }

    // MARK: One chat as Markdown

    func markdown(for session: ChatSession) -> String {
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
        return lines.joined(separator: "\n")
    }

    func exportMarkdown(_ session: ChatSession) throws -> URL {
        try writeTemp(Data(markdown(for: session).utf8), name: "\(Self.slug(session.chat.title)).md")
    }

    func wipeEverything() async {
        for s in sessions.values { s.markDeleted() }
        sessions = [:]
        await store.wipe()
        chats = []
        costs = []
        presets = []
        memory = []
        folders = []
        setAPIKey(nil)
        settings = AppSettings()
        path = []
        startNewChat()
    }
}
