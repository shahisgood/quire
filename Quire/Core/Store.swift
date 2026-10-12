import Foundation
import os

nonisolated let storeLog = Logger(subsystem: "app.quire", category: "store")

/// Everything on disk, as plain JSON files in Application Support:
///
///     settings.json            AppSettings (never the API key)
///     chats.json               [Chat]
///     messages/<chatId>.json   [Message], one file per chat
///     presets.json             [Preset]   (personas)
///     memory.json              [MemoryEntry]
///     folders.json             [Folder]
///     catalogue.json           cached /models response
///     costs.json               [DayCost]
///
/// The shapes are the PWA's backup shapes, so import and export are a straight copy with no
/// migration layer. Reads are synchronous (small files, read once at launch or when a chat
/// opens). Writes are coalesced per file for 300 ms, so dragging a slider or streaming a reply
/// doesn't rewrite a file dozens of times a second, then encoded and written off the main thread
/// in the order they were made.
final class Store {
    let root: URL
    private let writer = DiskWriter()
    private var tail: Task<Void, Never>?
    private var pending: [URL: @Sendable () async -> Void] = [:]
    private var pendingOrder: [URL] = []
    private var debounce: Task<Void, Never>?

    init() {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        root = base.appendingPathComponent("Quire", isDirectory: true)
        try? FileManager.default.createDirectory(at: messagesDir, withIntermediateDirectories: true)
    }

    var messagesDir: URL { root.appendingPathComponent("messages", isDirectory: true) }
    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    private func messagesURL(_ chatId: String) -> URL {
        // Ids are UUIDs here, but imported ids are whatever the PWA made; keep them filename-safe.
        let safe = chatId.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? String($0) : "_" }.joined()
        return messagesDir.appendingPathComponent("\(safe).json")
    }

    // MARK: Reading

    private func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            storeLog.error("Could not decode \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func loadSettings() -> AppSettings { read(AppSettings.self, at: url("settings.json")) ?? AppSettings() }
    func loadChats() -> [Chat] { read([Chat].self, at: url("chats.json")) ?? [] }
    func loadMessages(_ chatId: String) -> [Message] { read([Message].self, at: messagesURL(chatId)) ?? [] }
    func loadCatalogue() -> Catalogue? { read(Catalogue.self, at: url("catalogue.json")) }
    func loadCosts() -> [DayCost] { read([DayCost].self, at: url("costs.json")) ?? [] }
    func loadPresets() -> [Preset] { read([Preset].self, at: url("presets.json")) ?? [] }
    func loadMemory() -> [MemoryEntry] { read([MemoryEntry].self, at: url("memory.json")) ?? [] }
    func loadFolders() -> [Folder] { read([Folder].self, at: url("folders.json")) ?? [] }

    // MARK: Writing

    private func enqueue(_ op: @escaping @Sendable () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await op()
        }
    }

    /// Replace any pending write to the same file with this one, and flush shortly.
    private func schedule(_ url: URL, _ op: @escaping @Sendable () async -> Void) {
        if pending[url] == nil { pendingOrder.append(url) }
        pending[url] = op
        guard debounce == nil else { return }
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.movePendingToQueue()
        }
    }

    private func movePendingToQueue() {
        debounce?.cancel()
        debounce = nil
        let order = pendingOrder
        let ops = pending
        pending = [:]
        pendingOrder = []
        for u in order {
            if let op = ops[u] { enqueue(op) }
        }
    }

    private func write<T: Encodable & Sendable>(_ value: T, to url: URL) {
        let writer = self.writer
        schedule(url) { await writer.write(value, to: url) }
    }

    func saveSettings(_ s: AppSettings) {
        var copy = s
        copy.apiKey = nil
        write(copy, to: url("settings.json"))
    }
    func saveChats(_ chats: [Chat]) { write(chats, to: url("chats.json")) }
    func saveMessages(_ chatId: String, _ messages: [Message]) { write(messages, to: messagesURL(chatId)) }
    func saveCatalogue(_ c: Catalogue) { write(c, to: url("catalogue.json")) }
    func saveCosts(_ c: [DayCost]) { write(c, to: url("costs.json")) }
    func savePresets(_ p: [Preset]) { write(p, to: url("presets.json")) }
    func saveMemory(_ m: [MemoryEntry]) { write(m, to: url("memory.json")) }
    func saveFolders(_ f: [Folder]) { write(f, to: url("folders.json")) }

    func deleteMessages(_ chatId: String) {
        let u = messagesURL(chatId)
        let writer = self.writer
        schedule(u) { await writer.delete(u) }
    }

    func deleteCatalogue() {
        let u = url("catalogue.json")
        let writer = self.writer
        schedule(u) { await writer.delete(u) }
    }

    /// Write everything pending now and wait for it: before export, search, or backgrounding.
    func flush() async {
        movePendingToQueue()
        await tail?.value
    }

    func wipe() async {
        await flush()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: messagesDir, withIntermediateDirectories: true)
    }

    func diskUsage() -> Int {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let u as URL in e { total += (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total
    }
}

actor DiskWriter {
    func write<T: Encodable & Sendable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            storeLog.error("Write failed for \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Search

nonisolated struct SearchHit: Identifiable, Hashable, Sendable {
    var id: String { messageId }
    var chatId: String
    var messageId: String
    var snippet: String
    var createdAt: Double
}

nonisolated enum Search {
    /// A lowercase scan over every message file, off the main thread. The PWA's benchmark holds:
    /// fine to roughly 5,000 messages; beyond that, an index belongs here.
    @concurrent
    static func run(_ query: String, in dir: URL, limit: Int = 60) async -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var hits: [SearchHit] = []
        for f in files where f.pathExtension == "json" {
            if Task.isCancelled { return [] }
            guard let data = try? Data(contentsOf: f), let msgs = try? JSONDecoder().decode([Message].self, from: data) else { continue }
            for m in msgs where m.role != .system {
                let hay = m.lc ?? m.content.lowercased()
                guard let r = hay.range(of: q) else { continue }
                hits.append(SearchHit(chatId: m.chatId, messageId: m.id, snippet: snippet(m.content, hay: hay, match: r), createdAt: m.createdAt))
            }
        }
        hits.sort { $0.createdAt > $1.createdAt }
        return Array(hits.prefix(limit))
    }

    /// ~40 characters of context either side of the match, on one line.
    static func snippet(_ content: String, hay: String, match: Range<String.Index>) -> String {
        // `hay` is `content.lowercased()`, which can differ in length for a few scripts; fall back to a prefix then.
        guard hay.count == content.count else { return String(content.prefix(120)) }
        let startOffset = hay.distance(from: hay.startIndex, to: match.lowerBound)
        let endOffset = hay.distance(from: hay.startIndex, to: match.upperBound)
        let s = max(0, startOffset - 40)
        let e = min(content.count, endOffset + 60)
        let a = content.index(content.startIndex, offsetBy: s)
        let b = content.index(content.startIndex, offsetBy: e)
        let body = content[a..<b].split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return (s > 0 ? "…" : "") + body + (e < content.count ? "…" : "")
    }
}
