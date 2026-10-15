import Foundation
import Observation
import UIKit

/// One open thread and its stream engine. Messages form a tree (`parentId`), and `path` is the
/// branch currently shown, from the root to `chat.activeLeafId`. Regenerating or editing adds a
/// sibling rather than overwriting, so earlier versions are never lost.
@Observable
final class ChatSession {
    unowned let app: AppModel

    private(set) var chat: Chat
    private(set) var messages: [String: Message] = [:]
    private(set) var path: [String] = []
    private(set) var persisted: Bool
    private(set) var generating = false
    /// Set when the chat is deleted, so late callbacks (cost reconciliation, a sheet closing) can't resurrect it.
    @ObservationIgnored private(set) var deleted = false
    /// A title request is in flight (so the send-time and reply-time attempts don't race).
    @ObservationIgnored private var titling = false
    /// Text for the message box to take (a starter prompt); the composer consumes it and clears it.
    var prefill: String? = nil

    // Live view of the streaming reply, published at most 20 times a second so the message list
    // doesn't re-render per token.
    private(set) var streamingId: String? = nil
    private(set) var streamContent = ""
    private(set) var streamReasoning = ""
    private(set) var streamCompletionTokens = 0
    private(set) var streamReasoningTokens = 0
    private(set) var streamEstCost: Double = 0
    private(set) var streamFirstTokenAt: Double? = nil
    /// When a 429/5xx retry is waiting: the time it fires and the reason.
    private(set) var retryAt: Double? = nil
    private(set) var retryReason: String? = nil

    /// A message to scroll to and briefly mark when the chat opens (from search or memory).
    var highlightId: String? = nil
    var draft: String

    @ObservationIgnored private var task: Task<Void, Never>? = nil
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>? = nil
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(app: AppModel, chat: Chat, persisted: Bool) {
        self.app = app
        self.chat = chat
        self.persisted = persisted
        self.draft = chat.draft ?? ""
        guard persisted else { return }
        var loaded: [String: Message] = [:]
        var repaired = false
        for var m in app.store.loadMessages(chat.id) {
            // Anything left mid-stream by a killed app becomes interrupted.
            if m.status == .streaming {
                m.status = m.content.isEmpty ? .error : .interrupted
                m.error = MessageError(code: "interrupted", message: "Interrupted before the reply finished")
                repaired = true
            }
            loaded[m.id] = m
        }
        messages = loaded
        var leaf = chat.activeLeafId
        if let l = leaf, loaded[l] == nil { leaf = nil }
        if leaf == nil { leaf = children(of: nil).last.map { deepest(from: $0.id) } }
        path = computePath(to: leaf)
        if repaired { saveMessages() }
    }

    var thread: [Message] { path.compactMap { messages[$0] } }
    var model: ORModel? { app.model(chat.modelId) }
    var persona: Preset? { app.preset(chat.systemPromptId) }
    var project: Project? { app.project(chat.folderId) }

    // MARK: Tree helpers

    func children(of parentId: String?) -> [Message] {
        messages.values.filter { $0.parentId == parentId }.sorted { $0.createdAt < $1.createdAt }
    }

    private func deepest(from id: String) -> String {
        var cur = id
        while let last = children(of: cur).last { cur = last.id }
        return cur
    }

    private func computePath(to leaf: String?) -> [String] {
        var out: [String] = []
        var cur: Message? = nil
        if let leaf { cur = messages[leaf] }
        while let m = cur {
            out.append(m.id)
            if let p = m.parentId { cur = messages[p] } else { cur = nil }
        }
        return out.reversed()
    }

    func siblingInfo(_ id: String) -> (index: Int, count: Int) {
        guard let m = messages[id] else { return (0, 1) }
        let sibs = children(of: m.parentId)
        return (sibs.firstIndex(where: { $0.id == id }) ?? 0, sibs.count)
    }

    // MARK: Settings resolution (global → persona → chat)

    /// Global settings with the persona's on top: what this chat inherits.
    var inheritedSettings: GenerationSettings {
        app.settings.globalSettings.merged(with: persona?.settings)
    }

    var effectiveSettings: GenerationSettings {
        inheritedSettings.merged(with: chat.settingsOverride)
    }

    var inheritedSystemPrompt: String {
        if let p = persona { return p.systemPrompt }
        return app.settings.globalSystemPrompt
    }

    var effectiveSystemPrompt: String {
        if let inline = chat.systemPromptInline, !inline.isEmpty { return inline }
        return inheritedSystemPrompt
    }

    /// The project's instructions as the model reads them, after the chat's own system prompt. They
    /// stay out of `effectiveSystemPrompt` so editing a chat's prompt never copies them into it.
    var projectInstructions: String? {
        guard let p = project, p.hasInstructions else { return nil }
        return "Project instructions (\(p.name)). Follow these in this conversation:\n\(p.trimmedInstructions)"
    }

    var contextTokens: Int {
        var n = Tokens.estimate(effectiveSystemPrompt) + Tokens.estimate(projectInstructions ?? "")
        for m in thread {
            n += Tokens.estimate(m.content) + 4
            for a in m.attachments ?? [] { n += Tokens.estimate(a) }
        }
        return n
    }

    /// Context use including whatever is streaming right now, for the meter.
    var liveContextTokens: Int { contextTokens + (streamingId == nil ? 0 : streamCompletionTokens + streamReasoningTokens) }

    // MARK: Persistence

    func markDeleted() {
        deleted = true
        stop()
    }

    private func saveMessages() {
        guard persisted, !deleted else { return }
        app.store.saveMessages(chat.id, Array(messages.values))
    }

    private func saveChat() {
        guard persisted, !deleted else { return }
        app.upsertChat(chat)
    }

    private func ensurePersisted() {
        guard !persisted else { return }
        persisted = true
        app.settings.lastChatId = chat.id
    }

    /// Called by the app model when the chat was edited from elsewhere (list, cost reconciliation).
    func chatDidChangeExternally(_ updated: Chat) {
        var c = updated
        c.activeLeafId = chat.activeLeafId
        c.draft = chat.draft
        chat = c
    }

    func saveDraft(_ text: String) {
        draft = text
        draftSaveTask?.cancel()
        draftSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flushDraft()
        }
    }

    func flushDraft() {
        guard !deleted, (chat.draft ?? "") != draft else { return }
        chat.draft = draft
        if persisted { app.upsertChat(chat) }
    }

    // MARK: Chat-level edits

    func setModel(_ id: String) {
        chat.modelId = id
        app.touchRecent(id)
        saveChat()
    }

    func rename(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != chat.title else { return }
        chat.title = t
        chat.titleAuto = false
        saveChat()
    }

    func setSystemPrompt(_ text: String?) {
        let t = text ?? ""
        chat.systemPromptInline = t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : t
        saveChat()
    }

    /// Switching persona also switches to its pinned model, if it has one.
    func setPersona(_ id: String?) {
        chat.systemPromptId = id
        if let p = app.preset(id), let m = p.modelId { chat.modelId = m }
        saveChat()
    }

    /// Moves the chat into a project (or out, with nil). Its instructions apply from the next reply.
    func setProject(_ id: String?) {
        chat.folderId = id
        saveChat()
    }

    func setMemoryEnabled(_ on: Bool) {
        chat.memoryEnabled = on
        saveChat()
    }

    func setOverrides(_ o: GenerationSettings) {
        chat.settingsOverride = o.isEmpty ? nil : o
        saveChat()
    }

    func resetOverrides() {
        chat.settingsOverride = nil
        chat.systemPromptInline = nil
        saveChat()
    }

    /// What sits next to the model name in the composer: the effort level or the budget, or nothing
    /// when thinking is off or the model can't think.
    var thinkingLabel: String? {
        guard model?.supportsReasoning == true, let r = effectiveSettings.reasoning else { return nil }
        switch r.mode {
        case .off: return nil
        case .effort:
            let e = r.effort ?? .medium
            return e == ReasoningEffort.none ? nil : e.label
        case .budget: return r.maxTokens.map { "\(Fmt.tokens($0)) budget" } ?? "Budget"
        }
    }

    /// Quick switch from the composer: thinking off (nil), or effort mode at a level. Stored as this
    /// chat's override, keeping any budget and "hide the trace" choice already made.
    func setThinking(_ effort: ReasoningEffort?) {
        var o = chat.settingsOverride ?? GenerationSettings()
        var r = effectiveSettings.reasoning ?? ReasoningSettings()
        if let effort {
            r.mode = .effort
            r.effort = effort
        } else {
            r.mode = .off
        }
        o.reasoning = r
        setOverrides(o)
    }

    // MARK: Actions

    func send(_ text: String, attachments: [Attachment] = []) {
        guard !generating else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        let now = nowMs()
        let user = Message(chatId: chat.id, parentId: path.last, role: .user, content: trimmed,
                           attachments: attachments.isEmpty ? nil : attachments, createdAt: now, status: .complete)
        let asst = Message(chatId: chat.id, parentId: user.id, role: .assistant, content: "", modelId: chat.modelId, createdAt: now + 1, status: .streaming)
        // The opening message names the chat (First message and Smart both start here; Smart then
        // asks for a better name). A chat you've renamed keeps your name.
        let opening = path.isEmpty && chat.titleAuto != false
        if opening && titleMode != .off {
            chat.title = TextUtil.stripMarkdown(trimmed.isEmpty ? (attachments.first?.name ?? "New chat") : trimmed, max: 48)
        }
        messages[user.id] = user
        messages[asst.id] = asst
        path += [user.id, asst.id]
        chat.updatedAt = now
        chat.activeLeafId = asst.id
        chat.lastPreview = TextUtil.stripMarkdown(trimmed, max: 100)
        draft = ""
        chat.draft = ""
        ensurePersisted()
        saveChat()
        saveMessages()
        app.touchRecent(chat.modelId)
        startGeneration(assistantId: asst.id, modelId: chat.modelId)
        // Name it now from the opening message, rather than after the whole reply has arrived.
        if opening && !trimmed.isEmpty {
            Task { [weak self] in await self?.smartTitle(userText: trimmed, assistantText: nil) }
        }
    }

    func stop() { task?.cancel() }

    func regenerate(_ assistantId: String, modelId: String? = nil) {
        guard !generating, let old = messages[assistantId] else { return }
        let mid = modelId ?? chat.modelId
        let asst = Message(chatId: chat.id, parentId: old.parentId, role: .assistant, content: "", modelId: mid, status: .streaming)
        messages[asst.id] = asst
        path = computePath(to: asst.id)
        chat.activeLeafId = asst.id
        if modelId != nil {
            chat.modelId = mid
            app.touchRecent(mid)
        }
        saveChat()
        saveMessages()
        startGeneration(assistantId: asst.id, modelId: mid)
    }

    /// Edit a sent message and resend it. The original stays as a sibling branch.
    func editResend(_ userId: String, text: String) {
        guard !generating, let old = messages[userId], old.role == .user else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !(old.attachments ?? []).isEmpty else { return }
        let now = nowMs()
        var user = Message(chatId: chat.id, parentId: old.parentId, role: .user, content: trimmed,
                           attachments: old.attachments, createdAt: now, status: .complete)
        user.editedFrom = old.id
        let asst = Message(chatId: chat.id, parentId: user.id, role: .assistant, content: "", modelId: chat.modelId, createdAt: now + 1, status: .streaming)
        messages[user.id] = user
        messages[asst.id] = asst
        path = computePath(to: asst.id)
        chat.activeLeafId = asst.id
        chat.updatedAt = now
        saveChat()
        saveMessages()
        startGeneration(assistantId: asst.id, modelId: chat.modelId)
    }

    func retry(_ assistantId: String) {
        guard !generating, var m = messages[assistantId] else { return }
        // The failed attempt's cost stays counted: that money was spent.
        m.content = ""
        m.reasoning = nil
        m.error = nil
        m.usage = nil
        m.status = .streaming
        messages[assistantId] = m
        path = computePath(to: assistantId)
        saveMessages()
        startGeneration(assistantId: assistantId, modelId: m.modelId ?? chat.modelId)
    }

    func continueReply(_ assistantId: String) {
        guard !generating, let m = messages[assistantId] else { return }
        if path.last != assistantId { path = computePath(to: assistantId) }
        startGeneration(assistantId: assistantId, modelId: m.modelId ?? chat.modelId, continueMode: true)
    }

    func switchBranch(_ messageId: String, by dir: Int) {
        guard let m = messages[messageId] else { return }
        let sibs = children(of: m.parentId)
        guard let i = sibs.firstIndex(where: { $0.id == messageId }), sibs.indices.contains(i + dir) else { return }
        let leaf = deepest(from: sibs[i + dir].id)
        path = computePath(to: leaf)
        chat.activeLeafId = leaf
        saveChat()
        Haptics.selection()
    }

    /// Delete a message and everything under it. If the shown branch was inside, fall back to the
    /// nearest surviving sibling or parent.
    func delete(_ id: String) {
        guard let m = messages[id], streamingId != id else { return }
        var doomed: Set<String> = []
        var stack = [id]
        while let cur = stack.popLast() {
            doomed.insert(cur)
            stack += children(of: cur).map(\.id)
        }
        for d in doomed { messages[d] = nil }
        var leaf = chat.activeLeafId
        if let l = leaf, doomed.contains(l) { leaf = nil }
        if leaf == nil {
            if let parent = m.parentId { leaf = deepest(from: parent) }
            else { leaf = children(of: nil).last.map { deepest(from: $0.id) } }
        }
        path = computePath(to: leaf)
        chat.activeLeafId = leaf
        saveChat()
        saveMessages()
    }

    /// Copy the branch up to this message into a new chat. Returns the new chat's id.
    func branch(from messageId: String) -> String? {
        let ids = computePath(to: messageId)
        guard !ids.isEmpty, persisted else { return nil }
        var idMap: [String: String] = [:]
        for i in ids { idMap[i] = newID() }
        let newChatId = newID()
        let copies: [Message] = ids.compactMap { (i: String) -> Message? in
            guard var m = messages[i] else { return nil }
            m.id = idMap[i] ?? newID()
            m.chatId = newChatId
            m.parentId = m.parentId.flatMap { idMap[$0] }
            m.editedFrom = nil
            if m.status == .streaming { m.status = .interrupted }
            return m
        }
        let now = nowMs()
        var c = chat
        c.id = newChatId
        c.title = "\(chat.title) (branch)"
        c.createdAt = now
        c.updatedAt = now
        c.pinned = false
        c.archived = false
        c.activeLeafId = idMap[messageId]
        c.draft = ""
        c.totalCostUsd = 0
        c.titleAuto = false
        c.lastPreview = copies.last.map { TextUtil.stripMarkdown($0.content, max: 100) }
        app.insertChat(c, messages: copies)
        return newChatId
    }

    // MARK: Stream engine

    private func startGeneration(assistantId: String, modelId: String, continueMode: Bool = false) {
        generating = true
        task = Task { [weak self] in
            await self?.generate(assistantId: assistantId, modelId: modelId, continueMode: continueMode)
        }
    }

    private func requestMessages(upTo assistantId: String, continueMode: Bool) -> [JSONValue] {
        var history: [Message] = []
        for id in path {
            if id == assistantId { break }
            guard let m = messages[id] else { continue }
            if m.role == .assistant && m.content.isEmpty { continue }
            history.append(m)
        }
        var system: [String] = []
        let sp = effectiveSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sp.isEmpty { system.append(sp) }
        if let pi = projectInstructions { system.append(pi) }
        if chat.memoryEnabled && app.settings.memory.enabled {
            let lastUser = history.last(where: { $0.role == .user })?.content ?? ""
            let plan = MemoryLogic.plan(app.memory, userText: lastUser, budget: app.settings.memory.maxInjectedChars)
            let block = MemoryLogic.block(plan.entries)
            if !block.isEmpty { system.append(block) }
        }
        var out: [JSONValue] = []
        if !system.isEmpty { out.append(["role": "system", "content": .string(system.joined(separator: "\n\n"))]) }
        for m in history { out.append(Self.param(for: m)) }
        if continueMode, let existing = messages[assistantId], !existing.content.isEmpty {
            out.append(["role": "assistant", "content": .string(existing.content)])
        }
        return out
    }

    /// File attachments are sent as `{type: file, file: {filename, file_data}}`, images as `image_url`.
    static func param(for m: Message) -> JSONValue {
        guard let atts = m.attachments, !atts.isEmpty else {
            return ["role": .string(m.role.rawValue), "content": .string(m.content)]
        }
        var parts: [JSONValue] = []
        if !m.content.isEmpty { parts.append(["type": "text", "text": .string(m.content)]) }
        for a in atts {
            if a.kind == .image { parts.append(["type": "image_url", "image_url": ["url": .string(a.dataUrl)]]) }
            else { parts.append(["type": "file", "file": ["filename": .string(a.name), "file_data": .string(a.dataUrl)]]) }
        }
        return ["role": .string(m.role.rawValue), "content": .array(parts)]
    }

    private static func estimatePrompt(_ msgs: [JSONValue]) -> Int {
        var n = 0
        for m in msgs {
            n += 4
            if let s = m["content"]?.stringValue { n += Tokens.estimate(s); continue }
            for p in m["content"]?.arrayValue ?? [] {
                switch p["type"]?.stringValue ?? "" {
                case "text": n += Tokens.estimate(p["text"]?.stringValue ?? "")
                case "image_url": n += 1000
                default: n += 2000
                }
            }
        }
        return n
    }

    private func generate(assistantId: String, modelId: String, continueMode: Bool) async {
        defer {
            generating = false
            task = nil
        }
        guard let apiKey = app.apiKey, !apiKey.isEmpty else {
            finishWithError(assistantId, MessageError(code: "401", message: "No API key set. Add one in Settings → Connection."))
            return
        }
        guard app.connectivity.online else {
            finishWithError(assistantId, MessageError(code: "offline", message: "You're offline. The message is kept; retry when you're back online."))
            return
        }
        let client = OpenRouterClient(apiKey: apiKey, baseURL: app.settings.proxyBaseUrl)
        let model = app.model(modelId)
        let settings = effectiveSettings
        let msgs = requestMessages(upTo: assistantId, continueMode: continueMode)
        let body = RequestBuilder.body(modelId: modelId, model: model, settings: settings, messages: msgs)
        let lastUser = thread.last(where: { $0.role == .user && $0.id != assistantId })

        let promptEst = Self.estimatePrompt(msgs)
        let pPrompt = Pricing.parse(model?.pricing.prompt)
        let pComp = Pricing.parse(model?.pricing.completion)
        let pReasonRaw = Pricing.parse(model?.pricing.internalReasoning)
        let pReason = pReasonRaw > 0 ? pReasonRaw : pComp

        let existing = messages[assistantId]
        let base = continueMode ? (existing?.content ?? "") : ""
        let baseReason = continueMode ? (existing?.reasoning ?? "") : ""
        var content = base
        var reasoning = baseReason
        var generationId = existing?.generationId
        var usage: StreamUsage? = nil
        var finish: String? = nil

        update(assistantId) {
            $0.status = .streaming
            $0.modelId = modelId
            $0.settingsSnapshot = settings
            $0.requestSnapshot = Self.snapshot(body)
        }
        streamingId = assistantId
        streamContent = content
        streamReasoning = reasoning
        streamCompletionTokens = 0
        streamReasoningTokens = 0
        streamEstCost = 0
        streamFirstTokenAt = nil
        retryAt = nil
        retryReason = nil

        // A reply in flight gets the ~30 seconds iOS allows after backgrounding, instead of the PWA's
        // immediate abort. If time runs out, the stream is cancelled and the partial reply kept.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "quire.reply") { [weak self] in
            self?.task?.cancel()
            self?.endBackgroundTask()
        }
        defer { endBackgroundTask() }

        var lastPublish = Date.distantPast
        var lastPersist = Date()
        func publish(force: Bool = false) {
            let now = Date()
            if force || now.timeIntervalSince(lastPublish) > 0.05 {
                lastPublish = now
                let ct = Tokens.estimate(String(content.dropFirst(base.count)))
                let rt = Tokens.estimate(String(reasoning.dropFirst(baseReason.count)))
                streamContent = content
                streamReasoning = reasoning
                streamCompletionTokens = ct
                streamReasoningTokens = rt
                streamEstCost = Double(promptEst) * pPrompt + Double(ct) * pComp + Double(rt) * pReason
            }
            if now.timeIntervalSince(lastPersist) > 1.5 {
                lastPersist = now
                let c = content
                let r = reasoning
                let g = generationId
                update(assistantId) {
                    $0.content = c
                    $0.reasoning = r.isEmpty ? nil : r
                    $0.generationId = g
                }
                saveMessages()
            }
        }

        var attempt = 0
        var finalError: ErrorInfo? = nil
        var aborted = false
        retryLoop: while true {
            do {
                if settings.stream ?? true {
                    try await client.stream(body: body) { ev in
                        if generationId == nil, let id = ev.id { generationId = id }
                        if let t = ev.content { content += t }
                        if let r = ev.reasoning { reasoning += r }
                        if let f = ev.finishReason { finish = f }
                        if let u = ev.usage { usage = u }
                        if ev.content != nil || ev.reasoning != nil {
                            if streamFirstTokenAt == nil { streamFirstTokenAt = nowMs() }
                            publish()
                        }
                    }
                } else {
                    let r = try await client.complete(body: body)
                    if !r.id.isEmpty { generationId = r.id }
                    content += r.content
                    reasoning += r.reasoning
                    finish = r.finishReason
                    usage = r.usage
                    streamFirstTokenAt = nowMs()
                }
                break retryLoop
            } catch {
                let info = ErrorInfo(error)
                if info.aborted { aborted = true; break retryLoop }
                let retriable = [429, 408, 502, 503, 504].contains(info.status) && content == base && attempt < 3
                guard retriable else { finalError = info; break retryLoop }
                attempt += 1
                let wait = max((info.retryAfterMs ?? 0) / 1000, 1.5 * pow(2, Double(attempt - 1)))
                retryAt = nowMs() + wait * 1000
                retryReason = info.message
                do { try await Task.sleep(for: .seconds(wait)) } catch { aborted = true; break retryLoop }
                retryAt = nil
                retryReason = nil
            }
        }
        publish(force: true)

        // Final accounting: usage from the stream when present, otherwise an estimate. The
        // authoritative /generation figure replaces it a few seconds later.
        let completionTokens = usage?.completionTokens ?? Tokens.estimate(String(content.dropFirst(base.count)))
        let newReasoning = String(reasoning.dropFirst(baseReason.count))
        let reasoningTokens: Int? = usage?.reasoningTokens ?? (newReasoning.isEmpty ? nil : Tokens.estimate(newReasoning))
        let promptTokens = usage?.promptTokens ?? promptEst
        let est = Double(promptTokens) * pPrompt + Double(completionTokens) * pComp + Double(reasoningTokens ?? 0) * pReason
        let cost: Double
        if let c = usage?.cost { cost = c + (usage?.webSearchCost ?? 0) } else { cost = est }
        let finalUsage = Usage(promptTokens: promptTokens, completionTokens: completionTokens, reasoningTokens: reasoningTokens,
                               costUsd: cost, authoritative: false, estimated: usage?.cost == nil, webSearchCostUsd: usage?.webSearchCost)
        let prevCost = existing?.usage?.costUsd ?? 0

        let status: MessageStatus
        var err: MessageError? = nil
        if let fe = finalError {
            status = content.isEmpty ? .error : .interrupted
            err = MessageError(code: fe.code, message: fe.message)
        } else if aborted {
            status = content.isEmpty && reasoning.isEmpty ? .error : .interrupted
            let bg = UIApplication.shared.applicationState == .background
            err = MessageError(code: "interrupted", message: bg ? "Interrupted when the app was in the background too long" : "Stopped")
        } else {
            status = .complete
            if finish == "length" { err = MessageError(code: "length", message: "Reply hit the max output token limit") }
        }
        let finalContent = content
        let finalReasoning = reasoning
        let finalGenerationId = generationId
        update(assistantId) {
            $0.content = finalContent
            $0.reasoning = finalReasoning.isEmpty ? nil : finalReasoning
            $0.generationId = finalGenerationId
            $0.usage = finalUsage
            $0.status = status
            $0.error = err
        }
        streamingId = nil
        streamContent = ""
        streamReasoning = ""
        retryAt = nil
        retryReason = nil

        let now = nowMs()
        chat.updatedAt = now
        chat.lastPreview = TextUtil.stripMarkdown(content.isEmpty ? (err?.message ?? "") : content, max: 100)
        chat.tokenEstimate = contextTokens
        saveChat()
        saveMessages()
        app.applyCostDelta(chatId: chat.id, delta: cost - prevCost, countMessage: true)
        if status == .complete && !deleted { app.replyFinished(chatId: chat.id, title: chat.title) }
        app.settings.messagesSinceExport = (app.settings.messagesSinceExport ?? 0) + 2

        if status == .complete {
            Haptics.soft()
            if UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: "Reply finished")
            }
        } else if finalError != nil {
            Haptics.warning()
        }

        let webSearchCost = usage?.webSearchCost
        if let gid = finalGenerationId, status != .error {
            Task { [weak self] in
                guard let g = await client.generationWithRetry(id: gid) else { return }
                let authoritative = Usage(
                    promptTokens: g.nativeTokensPrompt > 0 ? g.nativeTokensPrompt : (g.tokensPrompt > 0 ? g.tokensPrompt : promptTokens),
                    completionTokens: g.nativeTokensCompletion > 0 ? g.nativeTokensCompletion : (g.tokensCompletion > 0 ? g.tokensCompletion : completionTokens),
                    reasoningTokens: g.nativeTokensReasoning > 0 ? g.nativeTokensReasoning : reasoningTokens,
                    costUsd: g.totalCost, authoritative: true, estimated: false, webSearchCostUsd: webSearchCost)
                self?.applyAuthoritative(assistantId, authoritative)
            }
        }
        if status == .complete, let lastUser {
            // Belt and braces: a chat that reached its first reply still unnamed takes its opening line.
            if titleMode != .off, chat.titleAuto != false, chat.title == "New chat", !lastUser.content.isEmpty {
                chat.title = TextUtil.stripMarkdown(lastUser.content, max: 48)
                saveChat()
            }
            if chat.titleAuto != false && !continueMode {
                let userText = lastUser.content
                Task { [weak self] in await self?.smartTitle(userText: userText, assistantText: finalContent) }
            }
            if chat.memoryEnabled, let final = messages[assistantId] {
                app.extractor.schedule(app: app, chatId: chat.id, user: lastUser, assistant: final)
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func finishWithError(_ id: String, _ e: MessageError) {
        update(id) {
            $0.status = .error
            $0.error = e
        }
        saveMessages()
        Haptics.warning()
    }

    private func update(_ id: String, _ mutate: (inout Message) -> Void) {
        guard var m = messages[id] else { return }
        mutate(&m)
        messages[id] = m
    }

    private func applyAuthoritative(_ id: String, _ usage: Usage) {
        guard !deleted, let m = messages[id] else { return }
        let prev = m.usage?.costUsd ?? 0
        update(id) { $0.usage = usage }
        saveMessages()
        app.applyCostDelta(chatId: chat.id, delta: (usage.costUsd ?? 0) - prev)
    }

    private var titleMode: ChatTitleMode { app.settings.chatTitles ?? .smart }

    /// A short title for the chat, written by the titles model (then this chat's own model, which has
    /// just been shown to work, if that one fails). Runs as soon as the first message is sent, and
    /// again after a reply only while the chat still carries its first-message name. Never touches a
    /// chat you've renamed; if every attempt fails, the first-message name stays.
    private func smartTitle(userText: String, assistantText: String?) async {
        let fallback = TextUtil.stripMarkdown(userText, max: 48)
        guard titleMode == .smart, !titling, chat.titleAuto != false,
              chat.title == "New chat" || chat.title == fallback else { return }
        titling = true
        defer { titling = false }
        var exchange = "User: \(userText.prefix(2000))"
        if let assistantText, !assistantText.isEmpty { exchange += "\n\nAssistant: \(assistantText.prefix(1500))" }
        var candidates = [app.settings.memory.extractionModelId]
        if chat.modelId != candidates[0] { candidates.append(chat.modelId) }
        for modelId in candidates {
            let body: [String: JSONValue] = [
                "model": .string(modelId),
                "messages": [
                    ["role": "system", "content": "Write a title for this conversation: two to six words, sentence case, no quotes, no trailing punctuation. Reply with the title only."],
                    ["role": "user", "content": .string(exchange)],
                ],
                "max_tokens": 40,
                "temperature": 0.3,
            ]
            guard let r = try? await app.client.complete(body: body) else { continue }
            var title = r.content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? ""
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”.*#").union(.whitespaces))
            guard !title.isEmpty else { continue }
            // The chat may have been renamed (or deleted) while we waited.
            guard chat.titleAuto != false, !deleted, chat.title == "New chat" || chat.title == fallback else { return }
            chat.title = String(title.prefix(60))
            saveChat()
            return
        }
    }

    private static func snapshot(_ body: [String: JSONValue]) -> String {
        var b = body
        if let msgs = body["messages"]?.arrayValue {
            b["messages"] = .array(msgs.map { (m: JSONValue) -> JSONValue in
                if m["content"]?.stringValue != nil { return m }
                let parts = m["content"]?.arrayValue ?? []
                let text = parts.map { (p: JSONValue) -> String in
                    p["type"]?.stringValue == "text" ? (p["text"]?.stringValue ?? "") : "[\(p["type"]?.stringValue ?? "part")]"
                }.joined(separator: "\n")
                return ["role": m["role"] ?? "user", "content": .string(text)]
            })
        }
        return JSONValue.object(b).text(pretty: true)
    }
}

/// A thrown error, reduced to what the UI shows and what the retry logic needs.
struct ErrorInfo {
    var status = 0
    var code = "unknown"
    var message = ""
    var retryAfterMs: Double? = nil
    var aborted = false

    init(_ error: Error) {
        if error is CancellationError {
            aborted = true; code = "aborted"; message = "Stopped"
            return
        }
        if let e = error as? ORError {
            status = e.status
            code = e.status != 0 ? String(e.status) : e.code
            var msg = e.message
            if e.status == 403, let reasons = e.metadata?["reasons"]?.arrayValue?.compactMap(\.stringValue), !reasons.isEmpty {
                msg += " (\(reasons.joined(separator: ", ")))"
            }
            if e.status == 403, let flagged = e.metadata?["flagged_input"]?.stringValue { msg += "\nFlagged input: \(flagged)" }
            if let provider = e.metadata?["provider_name"]?.stringValue { msg += " [\(provider)]" }
            message = msg
            retryAfterMs = e.retryAfterMs
            return
        }
        if let u = error as? URLError {
            if u.code == .cancelled {
                aborted = true; code = "aborted"; message = "Stopped"
                return
            }
            code = "network"
            switch u.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                message = "You're offline. The message is kept; retry when you're back online."
            case .timedOut:
                message = "The request timed out."
            default:
                message = "Network error: \(u.localizedDescription)"
            }
            return
        }
        message = error.localizedDescription
    }
}
