import Foundation

/// A failed OpenRouter call, carrying the server's own message verbatim.
nonisolated struct ORError: Error, LocalizedError, Sendable {
    var status: Int
    var code: String
    var message: String
    var metadata: JSONValue?
    var retryAfterMs: Double?

    var errorDescription: String? { message }
}

nonisolated struct StreamUsage: Sendable {
    var promptTokens: Int
    var completionTokens: Int
    var reasoningTokens: Int?
    var cost: Double?
    var webSearchCost: Double?
}

nonisolated struct StreamEvent: Sendable {
    var id: String?
    var model: String?
    var content: String?
    var reasoning: String?
    var finishReason: String?
    var usage: StreamUsage?
}

nonisolated struct CompletionResult: Sendable {
    var id: String
    var model: String
    var content: String
    var reasoning: String
    var finishReason: String?
    var usage: StreamUsage?
}

nonisolated struct GenerationStats: Sendable {
    var totalCost: Double
    var tokensPrompt: Int
    var tokensCompletion: Int
    var nativeTokensPrompt: Int
    var nativeTokensCompletion: Int
    var nativeTokensReasoning: Int
}

/// Pure parsing of OpenRouter's response shapes. No networking, so it is easy to reason about and test.
nonisolated enum ORParse {
    static func usage(_ u: JSONValue?) -> StreamUsage? {
        guard let u, u.objectValue != nil else { return nil }
        let costDetails = u["cost_details"]
        return StreamUsage(
            promptTokens: u["prompt_tokens"]?.intValue ?? 0,
            completionTokens: u["completion_tokens"]?.intValue ?? 0,
            reasoningTokens: u["completion_tokens_details"]?["reasoning_tokens"]?.intValue,
            cost: u["cost"]?.doubleValue,
            webSearchCost: costDetails == nil ? nil : (costDetails?["upstream_inference_cost"]?.doubleValue ?? 0)
        )
    }

    /// Providers disagree on where reasoning goes: `reasoning`, DeepSeek's `reasoning_content`,
    /// or an array of `reasoning_details` with `text` or `summary`. An empty `reasoning: ""`
    /// must fall through to the others; some providers send exactly that shape.
    static func reasoning(from delta: JSONValue) -> String {
        if let r = delta["reasoning"]?.stringValue, !r.isEmpty { return r }
        if let r = delta["reasoning_content"]?.stringValue, !r.isEmpty { return r }
        if let details = delta["reasoning_details"]?.arrayValue {
            return details.map { d in
                if let t = d["text"]?.stringValue, !t.isEmpty { return t }
                return d["summary"]?.stringValue ?? ""
            }.joined()
        }
        return ""
    }

    static func errorObject(_ e: JSONValue, fallback: String) -> ORError {
        ORError(status: e["code"]?.intValue ?? 500,
                code: e["code"]?.scalarString ?? "500",
                message: e["message"]?.stringValue ?? fallback,
                metadata: e["metadata"])
    }

    /// One parsed SSE chunk to an event. Throws on in-stream error objects.
    static func event(from c: JSONValue) throws -> StreamEvent? {
        guard c.objectValue != nil else { return nil }
        if let e = c["error"], e.objectValue != nil { throw errorObject(e, fallback: "Provider returned an error mid-stream") }
        var ev = StreamEvent()
        ev.id = c["id"]?.stringValue
        ev.model = c["model"]?.stringValue
        if let ch0 = c["choices"]?[0] {
            if let e = ch0["error"], e.objectValue != nil { throw errorObject(e, fallback: "Provider returned an error mid-stream") }
            let delta = ch0["delta"] ?? ch0["message"] ?? .object([:])
            if let t = delta["content"]?.stringValue, !t.isEmpty { ev.content = t }
            let r = reasoning(from: delta)
            if !r.isEmpty { ev.reasoning = r }
            ev.finishReason = ch0["finish_reason"]?.stringValue
        }
        ev.usage = usage(c["usage"])
        return ev
    }

    /// One SSE line. Returns nil for keep-alive comments, non-data lines and malformed JSON;
    /// `.done` for the terminator.
    nonisolated enum Line { case chunk(JSONValue), done }

    static func line(_ raw: String) -> Line? {
        var line = Substring(raw)
        if line.hasSuffix("\r") { line = line.dropLast() }
        if line.isEmpty || line.hasPrefix(":") { return nil }
        guard line.hasPrefix("data:") else { return nil }
        let data = line.dropFirst(5).drop(while: { $0 == " " })
        if data == "[DONE]" { return .done }
        guard let json = JSONValue.parse(String(data)) else { return nil }
        return .chunk(json)
    }

    static func model(_ r: JSONValue) -> ORModel? {
        guard let id = r["id"]?.stringValue, !id.isEmpty else { return nil }
        let arch = r["architecture"] ?? .object([:])
        let p = r["pricing"] ?? .object([:])
        let top = r["top_provider"] ?? .object([:])
        func strs(_ v: JSONValue?) -> [String] { v?.arrayValue?.compactMap(\.stringValue) ?? [] }
        func price(_ k: String) -> String { p[k]?.stringValue ?? p[k]?.scalarString ?? "0" }
        let inputs = strs(arch["input_modalities"])
        let outputs = strs(arch["output_modalities"])
        return ORModel(
            id: id,
            canonicalSlug: r["canonical_slug"]?.stringValue ?? id,
            name: r["name"]?.stringValue ?? id,
            created: r["created"]?.doubleValue ?? 0,
            description: r["description"]?.stringValue ?? "",
            contextLength: r["context_length"]?.intValue ?? 0,
            inputModalities: inputs.isEmpty ? ["text"] : inputs,
            outputModalities: outputs.isEmpty ? ["text"] : outputs,
            pricing: ModelPricing(prompt: price("prompt"), completion: price("completion"), request: price("request"),
                                  image: price("image"), webSearch: price("web_search"), internalReasoning: price("internal_reasoning"),
                                  cacheRead: price("input_cache_read"), cacheWrite: price("input_cache_write")),
            maxCompletionTokens: top["max_completion_tokens"]?.intValue,
            isModerated: top["is_moderated"]?.boolValue ?? false,
            supportedParameters: strs(r["supported_parameters"]),
            tokenizer: arch["tokenizer"]?.stringValue,
            topContextLength: top["context_length"]?.intValue
        )
    }
}

/// The OpenRouter HTTP client. Holds no state beyond the key and base URL it was made with.
struct OpenRouterClient {
    static let origin = "https://openrouter.ai"
    static let appTitle = "Quire"
    /// Sent as HTTP-Referer so requests are attributed to Quire on the OpenRouter activity page.
    static let referer = "https://github.com/shahisgood/quire"

    var apiKey: String?
    var baseURL: String?

    private var base: String {
        let b = (baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return Self.origin + "/api/v1" }
        var s = b
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func request(_ path: String, method: String = "GET", auth: Bool = true, body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: base + path) else { throw ORError(status: 0, code: "bad_url", message: "The API base URL is not valid.") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 120
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(Self.appTitle, forHTTPHeaderField: "X-Title")
        r.setValue(Self.referer, forHTTPHeaderField: "HTTP-Referer")
        if auth, let k = apiKey, !k.isEmpty { r.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization") }
        r.httpBody = body
        return r
    }

    private static func check(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        throw makeError(http, body: body)
    }

    static func makeError(_ http: HTTPURLResponse, body: Data) -> ORError {
        let text = String(decoding: body, as: UTF8.self)
        let err = JSONValue.parse(body)?["error"]
        let msg = err?["message"]?.stringValue ?? (text.isEmpty ? "\(http.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: http.statusCode))" : String(text.prefix(400)))
        var e = ORError(status: http.statusCode, code: err?["code"]?.scalarString ?? String(http.statusCode), message: msg, metadata: err?["metadata"])
        if let ra = http.value(forHTTPHeaderField: "Retry-After") {
            if let n = Double(ra) { e.retryAfterMs = n * 1000 }
            else {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let d = f.date(from: ra) { e.retryAfterMs = max(0, d.timeIntervalSinceNow * 1000) }
            }
        }
        return e
    }

    // MARK: Endpoints

    func models() async throws -> [ORModel] {
        let (data, resp) = try await URLSession.shared.data(for: request("/models", auth: false))
        try Self.check(resp, body: data)
        return (JSONValue.parse(data)?["data"]?.arrayValue ?? []).compactMap(ORParse.model)
    }

    func keyMeta() async throws -> KeyMeta {
        let (data, resp) = try await URLSession.shared.data(for: request("/key"))
        try Self.check(resp, body: data)
        let d = JSONValue.parse(data)?["data"] ?? .object([:])
        let rl = d["rate_limit"]
        return KeyMeta(
            label: d["label"]?.stringValue ?? "API key",
            usage: d["usage"]?.doubleValue ?? 0,
            limit: d["limit"]?.doubleValue,
            limitRemaining: d["limit_remaining"]?.doubleValue,
            isFreeTier: d["is_free_tier"]?.boolValue ?? false,
            rateLimit: rl?.objectValue == nil ? nil : RateLimit(requests: rl?["requests"]?.intValue ?? 0, interval: rl?["interval"]?.stringValue ?? ""),
            fetchedAt: nowMs()
        )
    }

    func generation(id: String) async throws -> GenerationStats {
        let q = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        let (data, resp) = try await URLSession.shared.data(for: request("/generation?id=\(q)"))
        try Self.check(resp, body: data)
        let d = JSONValue.parse(data)?["data"] ?? .object([:])
        return GenerationStats(
            totalCost: d["total_cost"]?.doubleValue ?? 0,
            tokensPrompt: d["tokens_prompt"]?.intValue ?? 0,
            tokensCompletion: d["tokens_completion"]?.intValue ?? 0,
            nativeTokensPrompt: d["native_tokens_prompt"]?.intValue ?? 0,
            nativeTokensCompletion: d["native_tokens_completion"]?.intValue ?? 0,
            nativeTokensReasoning: d["native_tokens_reasoning"]?.intValue ?? 0
        )
    }

    /// /generation lags the stream by a second or two, so poll with backoff.
    func generationWithRetry(id: String, attempts: Int = 4) async -> GenerationStats? {
        var delay = 1.2
        for _ in 0..<attempts {
            try? await Task.sleep(for: .seconds(delay))
            if Task.isCancelled { return nil }
            do {
                let g = try await generation(id: id)
                if g.totalCost > 0 || g.nativeTokensCompletion > 0 || g.tokensCompletion > 0 { return g }
            } catch let e as ORError where e.status == 401 {
                return nil
            } catch {}
            delay = min(delay * 1.8, 6)
        }
        return nil
    }

    /// Streaming completion. Calls `onEvent` for every parsed chunk, on the caller's actor.
    /// Cancelling the surrounding task stops the stream.
    func stream(body: [String: JSONValue], onEvent: (StreamEvent) -> Void) async throws {
        var b = body
        b["stream"] = true
        let req = try request("/chat/completions", method: "POST", body: JSONValue.object(b).data())
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 16_384 { break }
            }
            throw Self.makeError(http, body: data)
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let parsed = ORParse.line(line) else { continue }
            switch parsed {
            case .done: return
            case .chunk(let json):
                if let ev = try ORParse.event(from: json) { onEvent(ev) }
            }
        }
    }

    func complete(body: [String: JSONValue]) async throws -> CompletionResult {
        var b = body
        b["stream"] = false
        let (data, resp) = try await URLSession.shared.data(for: request("/chat/completions", method: "POST", body: JSONValue.object(b).data()))
        try Self.check(resp, body: data)
        guard let j = JSONValue.parse(data) else { throw ORError(status: 0, code: "parse", message: "OpenRouter returned something that isn't JSON.") }
        if let e = j["error"], e.objectValue != nil { throw ORParse.errorObject(e, fallback: "Request failed") }
        let ch0 = j["choices"]?[0]
        let msg = ch0?["message"] ?? .object([:])
        var content = msg["content"]?.stringValue ?? ""
        if content.isEmpty, let parts = msg["content"]?.arrayValue { content = parts.compactMap { $0["text"]?.stringValue }.joined() }
        return CompletionResult(id: j["id"]?.stringValue ?? "", model: j["model"]?.stringValue ?? "", content: content,
                                reasoning: ORParse.reasoning(from: msg), finishReason: ch0?["finish_reason"]?.stringValue,
                                usage: ORParse.usage(j["usage"]))
    }

    // MARK: Sign in with OpenRouter (PKCE, code-display flow)

    /// OpenRouter documents a flow without a callback URL: the user signs in on openrouter.ai,
    /// is shown a code, and pastes it back here. That avoids depending on custom URL schemes,
    /// which OpenRouter's docs don't mention.
    static func authURL(challenge: String) -> URL? {
        var c = URLComponents(string: origin + "/auth")
        c?.queryItems = [
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "key_label", value: "Quire for iPhone"),
        ]
        return c?.url
    }

    func exchange(code: String, verifier: String) async throws -> String {
        let body: JSONValue = ["code": .string(code), "code_verifier": .string(verifier), "code_challenge_method": "S256"]
        let (data, resp) = try await URLSession.shared.data(for: request("/auth/keys", method: "POST", auth: false, body: body.data()))
        try Self.check(resp, body: data)
        guard let key = JSONValue.parse(data)?["key"]?.stringValue, !key.isEmpty else {
            throw ORError(status: 0, code: "no_key", message: "OpenRouter did not return a key.")
        }
        return key
    }
}
