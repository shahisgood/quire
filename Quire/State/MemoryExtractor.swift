import Foundation

/// Runs memory extraction after replies, exactly as the PWA does: batched per chat, firing once
/// three exchanges have accumulated or 30 seconds have passed since the last run, after a short
/// delay so it never competes with the reply. Failures are dropped; the chat never waits on this.
final class MemoryExtractor {
    private struct ChatState {
        var turns = 0
        var lastAt: Double = 0
        var pending: [MemoryLogic.Exchange] = []
    }

    private var state: [String: ChatState] = [:]
    private var running = false

    func schedule(app: AppModel, chatId: String, user: Message, assistant: Message) {
        let mem = app.settings.memory
        guard mem.enabled, mem.autoExtract, app.apiKey != nil else { return }
        var st = state[chatId] ?? ChatState()
        st.turns += 1
        st.pending.append(MemoryLogic.Exchange(user: user.content, assistant: String(assistant.content.prefix(4000)), userId: user.id))
        let due = st.turns >= 3 || nowMs() - st.lastAt >= 30_000
        guard due else { state[chatId] = st; return }
        let batch = st.pending
        st.pending = []
        st.turns = 0
        st.lastAt = nowMs()
        state[chatId] = st
        Task { [weak self, weak app] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, let app else { return }
            await self.run(app: app, chatId: chatId, batch: batch)
        }
    }

    private func run(app: AppModel, chatId: String, batch: [MemoryLogic.Exchange]) async {
        // One extraction at a time; a second batch waits its turn.
        var waited = 0
        while running && waited < 12 {
            try? await Task.sleep(for: .seconds(5))
            waited += 1
        }
        guard !running else { return }
        running = true
        defer { running = false }

        let current = app.memory
        let body: [String: JSONValue] = [
            "model": .string(app.settings.memory.extractionModelId),
            "messages": [
                ["role": "system", "content": .string(MemoryLogic.extractionSystem)],
                ["role": "user", "content": .string(MemoryLogic.extractionPrompt(current: current, batch: batch))],
            ],
            "temperature": 0,
            "max_tokens": 600,
        ]
        guard let result = try? await app.client.complete(body: body) else { return }
        let ops = MemoryLogic.parseOperations(result.content)
        guard ops.contains(where: { $0.op != "none" }) else { return }
        // Apply to the list as it is now, in case the user edited memory while the call was out.
        let updated = MemoryLogic.apply(ops, to: app.memory, chatId: chatId, messageId: batch.last?.userId)
        if updated != app.memory { app.setMemory(updated) }
    }
}
