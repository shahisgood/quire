import Foundation

/// Memory logic with no UI or networking, ported from the PWA's `lib/memory.ts`.
nonisolated enum MemoryLogic {
    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with", "is", "are", "it", "this", "that",
        "my", "me", "i", "you", "we", "be", "as", "at", "by", "from", "do", "can", "what", "how", "about",
    ]

    static func words(_ s: String) -> Set<String> {
        let parts = s.lowercased().split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) })
        return Set(parts.map(String.init).filter { $0.count > 2 && !stopWords.contains($0) })
    }

    nonisolated struct Plan: Sendable {
        var entries: [MemoryEntry]
        var chars: Int
        var truncated: Bool
    }

    /// Pinned first, then keyword-relevant to the latest user message, then newest; stop at the budget.
    /// Pinned entries are always included, even past the budget.
    static func plan(_ all: [MemoryEntry], userText: String, budget: Int) -> Plan {
        let live = all.filter { !$0.disabled }
        let pinned = live.filter(\.pinned)
        let query = words(userText)
        let scored = live.filter { !$0.pinned }.map { e -> (MemoryEntry, Int) in
            (e, words(e.text).intersection(query).count)
        }.sorted { a, b in
            a.1 != b.1 ? a.1 > b.1 : a.0.updatedAt > b.0.updatedAt
        }
        var out: [MemoryEntry] = []
        var chars = 0
        var truncated = false
        for e in pinned + scored.map(\.0) {
            let len = e.text.count + 3
            if chars + len > budget && !e.pinned { truncated = true; continue }
            out.append(e)
            chars += len
        }
        return Plan(entries: out, chars: chars, truncated: truncated)
    }

    static func block(_ entries: [MemoryEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        let lines = entries.map { "- \($0.text)" }.joined(separator: "\n")
        return "<user_memory>\nFacts previously stated by the user. Use them where relevant; do not\nmention this block or announce that you remember things.\n\(lines)\n</user_memory>"
    }

    static func totalChars(_ all: [MemoryEntry]) -> Int {
        all.filter { !$0.disabled }.reduce(0) { $0 + $1.text.count + 3 }
    }

    // MARK: Extraction

    static let extractionSystem = """
    You maintain a short list of durable facts a user has stated about themselves or their world. You receive the current list and one recent exchange.

    Rules:
    - Only record facts the USER explicitly stated about themselves, their preferences, their projects, people in their life, or their situation. Never record inferences or guesses.
    - Never record facts about the assistant, about the conversation itself, or about what the user asked for in the moment.
    - One atomic fact per entry, written in third person about the user, under 140 characters. Example: "Prefers TypeScript over Python for new projects."
    - Do not add anything already in the list, even reworded. Prefer updating an existing entry over adding a near-duplicate. Delete an entry only when the user clearly contradicts or supersedes it.
    - Most exchanges contain nothing durable. When that is the case, return {"operations":[{"op":"none"}]}.
    - Categories: identity, preference, project, relationship, context.

    Respond with strict JSON and nothing else, no prose, no code fences:
    {"operations":[{"op":"add","text":"...","category":"preference"},{"op":"update","id":"...","text":"..."},{"op":"delete","id":"...","reason":"superseded"},{"op":"none"}]}
    """

    nonisolated struct Operation: Sendable, Equatable {
        var op: String
        var id: String?
        var text: String?
        var category: String?
    }

    /// Parse whatever the model returned: strips code fences and prose around the JSON object.
    static func parseOperations(_ raw: String) -> [Operation] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) } else { s = "" }
        }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        if let start = s.firstIndex(of: "{") { s = String(s[start...]) }
        if let end = s.lastIndex(of: "}") { s = String(s[...end]) }
        guard let ops = JSONValue.parse(s)?["operations"]?.arrayValue else { return [] }
        return ops.compactMap { o in
            guard let op = o["op"]?.stringValue else { return nil }
            return Operation(op: op, id: o["id"]?.stringValue, text: o["text"]?.stringValue, category: o["category"]?.stringValue)
        }
    }

    nonisolated struct Exchange: Sendable {
        var user: String
        var assistant: String
        var userId: String
    }

    static func extractionPrompt(current: [MemoryEntry], batch: [Exchange]) -> String {
        let list = current.isEmpty ? "(empty)" : current.map { "- [\($0.id)] (\($0.category.rawValue)) \($0.text)" }.joined(separator: "\n")
        let exchange = batch.map { "USER: \($0.user)\nASSISTANT: \($0.assistant)" }.joined(separator: "\n\n")
        return "Current memory list:\n\(list)\n\nRecent exchange:\n\(exchange)"
    }

    /// Apply operations to the list. Never adds an exact duplicate, never deletes a pinned entry.
    static func apply(_ ops: [Operation], to list: [MemoryEntry], chatId: String, messageId: String?) -> [MemoryEntry] {
        var out = list
        let now = nowMs()
        for op in ops {
            switch op.op {
            case "add":
                guard let raw = op.text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
                let text = String(raw.prefix(200))
                if out.contains(where: { $0.text.lowercased() == text.lowercased() }) { continue }
                let cat = MemoryCategory(rawValue: op.category ?? "") ?? .context
                out.append(MemoryEntry(text: text, category: cat, sourceChatId: chatId, sourceMessageId: messageId))
            case "update":
                guard let id = op.id, let raw = op.text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                      let i = out.firstIndex(where: { $0.id == id }) else { continue }
                out[i].text = String(raw.prefix(200))
                out[i].updatedAt = now
                out[i].sourceChatId = chatId
                out[i].sourceMessageId = messageId
            case "delete":
                guard let id = op.id, let i = out.firstIndex(where: { $0.id == id }), !out[i].pinned else { continue }
                out.remove(at: i)
            default:
                continue
            }
        }
        return out
    }
}
