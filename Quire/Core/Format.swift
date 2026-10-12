import Foundation

/// Per-token USD prices arrive from OpenRouter as decimal strings.
nonisolated enum Pricing {
    static func parse(_ s: String?) -> Double {
        guard let s, let n = Double(s), n.isFinite, n >= 0 else { return 0 }
        return n
    }

    /// "$3", "$0.15", "free" — price per million tokens.
    static func perMillion(_ s: String?) -> String {
        let n = parse(s)
        if n == 0 { return "free" }
        let v = n * 1_000_000
        if v >= 100 { return "$" + String(format: "%.0f", v) }
        if v >= 10 { return "$" + String(format: "%.1f", v) }
        if v >= 1 { return "$" + String(format: "%.2f", v) }
        var t = String(format: "%.3f", v)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return "$" + t
    }
}

nonisolated enum Fmt {
    static func usd(_ n: Double?, estimate: Bool = false) -> String {
        guard let n, n.isFinite else { return "—" }
        let p = estimate ? "~" : ""
        if n == 0 { return p + "$0" }
        if n < 0.0001 { return p + "<$0.0001" }
        if n < 0.01 { return p + "$" + String(format: "%.4f", n) }
        if n < 1 { return p + "$" + String(format: "%.3f", n) }
        return p + "$" + String(format: "%.2f", n)
    }

    static func tokens(_ n: Int?) -> String {
        guard let n else { return "—" }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000 { return "\(Int((Double(n) / 1000).rounded()))k" }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return String(n)
    }

    static func context(_ n: Int) -> String {
        if n >= 1_000_000 { return n % 1_000_000 == 0 ? "\(n / 1_000_000)M" : String(format: "%.1fM", Double(n) / 1_000_000) }
        return "\(Int((Double(n) / 1000).rounded()))k"
    }

    static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    static func relative(_ ms: Double, now: Double = nowMs()) -> String {
        let s = max(0, (now - ms) / 1000)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        let d = Int(s / 86400)
        if d < 7 { return "\(d)d" }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    nonisolated enum DayGroup: String, CaseIterable, Hashable, Sendable { case today = "Today", yesterday = "Yesterday", week = "This week", earlier = "Earlier" }

    static func dayGroup(_ ms: Double) -> DayGroup {
        let cal = Calendar.current
        let date = Date(timeIntervalSince1970: ms / 1000)
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let startOfToday = cal.startOfDay(for: Date())
        if let weekAgo = cal.date(byAdding: .day, value: -6, to: startOfToday), date >= weekAgo { return .week }
        return .earlier
    }
}

nonisolated enum Tokens {
    /// Cheap estimate: ~4 characters per token for prose, a little denser for code-like text.
    static func estimate(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        return Int(max(Double(text.count) / 4, Double(words) * 1.3).rounded(.up))
    }

    static func estimate(_ a: Attachment) -> Int {
        a.kind == .image ? 1000 : Int((Double(a.size) / 4).rounded(.up))
    }
}

nonisolated enum TextUtil {
    nonisolated(unsafe) private static let codeFence = try! NSRegularExpression(pattern: "```[\\s\\S]*?```")
    nonisolated(unsafe) private static let inlineCode = try! NSRegularExpression(pattern: "`([^`]*)`")
    nonisolated(unsafe) private static let image = try! NSRegularExpression(pattern: "!\\[[^\\]]*\\]\\([^)]*\\)")
    nonisolated(unsafe) private static let link = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]\\([^)]*\\)")
    nonisolated(unsafe) private static let heading = try! NSRegularExpression(pattern: "^#{1,6}\\s+", options: .anchorsMatchLines)
    nonisolated(unsafe) private static let marks = try! NSRegularExpression(pattern: "[*_~>]+")
    nonisolated(unsafe) private static let space = try! NSRegularExpression(pattern: "\\s+")

    /// Markdown to a one-line preview.
    static func stripMarkdown(_ s: String, max: Int = 120) -> String {
        var t = s
        func sub(_ re: NSRegularExpression, _ with: String) {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: with)
        }
        sub(codeFence, " [code] ")
        sub(inlineCode, "$1")
        sub(image, "[image]")
        sub(link, "$1")
        sub(heading, "")
        sub(marks, "")
        sub(space, " ")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > max ? String(t.prefix(max - 1)) + "…" : t
    }

    /// Substring matches score highest; otherwise an in-order subsequence with a contiguity bonus.
    static func fuzzyScore(_ query: String, _ text: String) -> Double {
        let q = query.lowercased()
        let t = text.lowercased()
        if q.isEmpty { return 1 }
        if let r = t.range(of: q) {
            let idx = t.distance(from: t.startIndex, to: r.lowerBound)
            return 100 - Double(min(idx, 50)) + Double(q.count)
        }
        var ti = t.startIndex
        var score = 0.0
        var streak = 0.0
        for ch in q {
            guard let j = t[ti...].firstIndex(of: ch) else { return 0 }
            streak = j == ti ? streak + 1 : 0
            score += 1 + streak
            ti = t.index(after: j)
        }
        return score
    }
}
