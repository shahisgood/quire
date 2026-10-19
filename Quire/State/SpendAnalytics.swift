import Foundation
import SwiftUI

// Spending, broken down: every reply's usage read from the chats on this iPhone, set against the
// day totals (which also count what isn't in a chat any more: titles, memory, deleted chats).

/// One reply's usage.
nonisolated struct SpendRecord: Sendable {
    let time: Double
    let modelId: String
    let chatId: String
    let cost: Double
    let prompt: Int
    let completion: Int
    let reasoning: Int
}

nonisolated private struct LiteUsage: Decodable {
    let promptTokens: Int?
    let completionTokens: Int?
    let reasoningTokens: Int?
    let costUsd: Double?
}

/// Just the fields the breakdown needs; the rest of each message is skipped.
nonisolated private struct LiteMessage: Decodable {
    let chatId: String?
    let role: String?
    let modelId: String?
    let usage: LiteUsage?
    let createdAt: Double?
}

nonisolated enum SpendScan {
    /// Reads every message file off the main thread.
    @concurrent
    static func run(in dir: URL) async -> [SpendRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var out: [SpendRecord] = []
        let decoder = JSONDecoder()
        for f in files where f.pathExtension == "json" {
            if Task.isCancelled { return [] }
            guard let data = try? Data(contentsOf: f), let msgs = try? decoder.decode([LiteMessage].self, from: data) else { continue }
            for m in msgs where m.role == "assistant" {
                guard let u = m.usage, let t = m.createdAt else { continue }
                out.append(SpendRecord(time: t, modelId: m.modelId ?? "unknown", chatId: m.chatId ?? "",
                                       cost: max(0, u.costUsd ?? 0), prompt: u.promptTokens ?? 0,
                                       completion: u.completionTokens ?? 0, reasoning: u.reasoningTokens ?? 0))
            }
        }
        return out.sorted { $0.time < $1.time }
    }
}

// MARK: - Choices

nonisolated enum SpendRange: String, CaseIterable, Hashable, Sendable {
    case week, month, quarter, all

    var label: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .all: return "All"
        }
    }

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .all: return nil
        }
    }

    var phrase: String {
        switch self {
        case .week: return "the last 7 days"
        case .month: return "the last 30 days"
        case .quarter: return "the last 90 days"
        case .all: return "all time"
        }
    }
}

nonisolated enum SpendMetric: String, CaseIterable, Hashable, Sendable {
    case cost, tokens, replies

    var label: String {
        switch self {
        case .cost: return "Cost"
        case .tokens: return "Tokens"
        case .replies: return "Replies"
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .cost: return Fmt.usd(v)
        case .tokens: return Fmt.tokens(Int(v.rounded()))
        case .replies: return Int(v.rounded()).formatted()
        }
    }
}

// MARK: - Colours

/// The chart palette: eight hues in a fixed order checked for colour-blind separation on Quire's
/// surfaces, light and dark. A model keeps its colour whatever the range or measure, because
/// colours go by all-time spend, not by rank in what's on screen.
enum SpendPalette {
    static let slots: [Color] = [
        Color(light: 0x2A78D6, dark: 0x3987E5),   // blue
        Color(light: 0xEB6834, dark: 0xD95926),   // orange
        Color(light: 0x1BAF7A, dark: 0x199E70),   // aqua
        Color(light: 0xEDA100, dark: 0xC98500),   // yellow
        Color(light: 0xE87BA4, dark: 0xD55181),   // magenta
        Color(light: 0x008300, dark: 0x008300),   // green
        Color(light: 0x6250D6, dark: 0x9085E9),   // violet
    ]
    static let otherModels = Color(light: 0x9A9DA3, dark: 0x6B6F77)
    static let outside = Color(light: 0xC9CBCE, dark: 0x3E424A)
}

/// A coloured series in the chart: a model, all the smaller models together, or spending that
/// isn't in any chat.
nonisolated struct SpendSeries: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: Color
    /// Order in a stack and the legend: models by all-time spend, then the two grey groups.
    let rank: Int

    static let otherId = "_other"
    static let outsideId = "_outside"
}

// MARK: - The report

nonisolated struct SpendBar: Identifiable, Sendable {
    let date: Date
    let series: SpendSeries
    let value: Double
    var id: String { "\(date.timeIntervalSince1970)|\(series.id)" }
}

nonisolated struct SpendRow: Identifiable, Sendable {
    let series: SpendSeries
    let value: Double
    let share: Double
    let replies: Int
    let cost: Double
    let prompt: Int
    let completion: Int
    let reasoning: Int
    var id: String { series.id }
}

nonisolated struct SpendChat: Identifiable, Sendable {
    let chatId: String
    let cost: Double
    let replies: Int
    let topModel: String
    var id: String { chatId }
}

/// Everything the spending screen shows for one range and measure.
struct SpendReport {
    let range: SpendRange
    let metric: SpendMetric
    let unit: Calendar.Component
    let start: Date
    let end: Date
    let bars: [SpendBar]
    let rows: [SpendRow]
    let total: Double
    let previous: Double?
    let replies: Int
    let prompt: Int
    let completion: Int
    let reasoning: Int
    let chats: [SpendChat]
    let busiest: (date: Date, value: Double)?
    let series: [SpendSeries]

    /// Change against the period of the same length just before, when there was one.
    var change: Double? {
        guard let previous, previous > 0 else { return nil }
        return (total - previous) / previous
    }

    var dailyAverage: Double {
        let days = max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
        return total / Double(days)
    }

    @MainActor
    static func make(records: [SpendRecord], costs: [DayCost], range: SpendRange, metric: SpendMetric,
                     name: (String) -> String) -> SpendReport {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? now

        // Series: the seven models with the most spend of all time get a colour each.
        var allTime: [String: Double] = [:]
        for r in records { allTime[r.modelId, default: 0] += r.cost }
        let ranked = allTime.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        var seriesFor: [String: SpendSeries] = [:]
        for (i, id) in ranked.prefix(SpendPalette.slots.count).enumerated() {
            seriesFor[id] = SpendSeries(id: id, name: name(id), color: SpendPalette.slots[i], rank: i)
        }
        let other = SpendSeries(id: SpendSeries.otherId, name: "Other models", color: SpendPalette.otherModels, rank: 100)
        let outside = SpendSeries(id: SpendSeries.outsideId, name: "Outside chats", color: SpendPalette.outside, rank: 101)
        func series(_ modelId: String) -> SpendSeries { seriesFor[modelId] ?? other }

        // The span shown, and how finely it's bucketed.
        let firstDay: Date = {
            if let d = range.days { return cal.date(byAdding: .day, value: -(d - 1), to: todayStart) ?? todayStart }
            let firstRecord = records.first.map { Date(timeIntervalSince1970: $0.time / 1000) }
            let firstCost = costs.compactMap { Self.date(fromKey: $0.day) }.min()
            return cal.startOfDay(for: [firstRecord, firstCost].compactMap { $0 }.min() ?? todayStart)
        }()
        let spanDays = cal.dateComponents([.day], from: firstDay, to: end).day ?? 1
        let unit: Calendar.Component = spanDays > 730 ? .month : (spanDays > 120 ? .weekOfYear : .day)
        func bucket(_ d: Date) -> Date { cal.dateInterval(of: unit, for: d)?.start ?? cal.startOfDay(for: d) }

        func value(_ r: SpendRecord) -> Double {
            switch metric {
            case .cost: return r.cost
            case .tokens: return Double(r.prompt + r.completion + r.reasoning)
            case .replies: return 1
            }
        }

        let startMs = firstDay.timeIntervalSince1970 * 1000
        let endMs = end.timeIntervalSince1970 * 1000
        let inRange = records.filter { $0.time >= startMs && $0.time < endMs }

        // Bars: per bucket, per series.
        var cells: [Date: [String: Double]] = [:]
        var seriesSeen: [String: SpendSeries] = [:]
        var rowAcc: [String: (v: Double, n: Int, cost: Double, p: Int, c: Int, r: Int)] = [:]
        var chatAcc: [String: (cost: Double, n: Int, models: [String: Double])] = [:]
        var recordedByDay: [String: (cost: Double, n: Int)] = [:]
        var tp = 0, tc = 0, tr = 0
        for r in inRange {
            let s = series(r.modelId)
            let v = value(r)
            let b = bucket(Date(timeIntervalSince1970: r.time / 1000))
            cells[b, default: [:]][s.id, default: 0] += v
            seriesSeen[s.id] = s
            let key = s.id == SpendSeries.otherId ? r.modelId : s.id
            var acc = rowAcc[key] ?? (0, 0, 0, 0, 0, 0)
            acc.v += v; acc.n += 1; acc.cost += r.cost; acc.p += r.prompt; acc.c += r.completion; acc.r += r.reasoning
            rowAcc[key] = acc
            var ch = chatAcc[r.chatId] ?? (0, 0, [:])
            ch.cost += r.cost; ch.n += 1; ch.models[r.modelId, default: 0] += r.cost
            chatAcc[r.chatId] = ch
            let dk = dayKey(r.time)
            var d = recordedByDay[dk] ?? (0, 0)
            d.cost += r.cost; d.n += 1
            recordedByDay[dk] = d
            tp += r.prompt; tc += r.completion; tr += r.reasoning
        }

        // What the day totals hold beyond these replies: titles, memory, chats since deleted.
        var outsideTotal = 0.0
        if metric != .tokens {
            for dc in costs {
                guard let day = Self.date(fromKey: dc.day), day >= firstDay, day < end else { continue }
                let rec = recordedByDay[dc.day] ?? (0, 0)
                let extra = metric == .cost ? dc.costUsd - rec.cost : Double(dc.messages - rec.n)
                guard extra > (metric == .cost ? 0.0005 : 0.5) else { continue }
                cells[bucket(day), default: [:]][outside.id, default: 0] += extra
                seriesSeen[outside.id] = outside
                outsideTotal += extra
            }
        }

        var bars: [SpendBar] = []
        let ordered = seriesSeen.values.sorted { $0.rank < $1.rank }
        for (date, byId) in cells.sorted(by: { $0.key < $1.key }) {
            for s in ordered {
                if let v = byId[s.id], v > 0 { bars.append(SpendBar(date: date, series: s, value: v)) }
            }
        }

        let total = rowAcc.values.reduce(0) { $0 + $1.v } + outsideTotal
        var rows: [SpendRow] = rowAcc.map { key, a in
            let s = seriesFor[key] ?? SpendSeries(id: key, name: name(key), color: SpendPalette.otherModels, rank: 100)
            return SpendRow(series: s, value: a.v, share: total > 0 ? a.v / total : 0, replies: a.n, cost: a.cost,
                            prompt: a.p, completion: a.c, reasoning: a.r)
        }
        if outsideTotal > 0 {
            rows.append(SpendRow(series: outside, value: outsideTotal, share: total > 0 ? outsideTotal / total : 0,
                                 replies: 0, cost: metric == .cost ? outsideTotal : 0, prompt: 0, completion: 0, reasoning: 0))
        }
        rows.sort { $0.value > $1.value }

        // The same measure for the period just before, for the change.
        var previous: Double? = nil
        if let d = range.days, let prevStart = cal.date(byAdding: .day, value: -d, to: firstDay) {
            let ps = prevStart.timeIntervalSince1970 * 1000
            let prev = records.filter { $0.time >= ps && $0.time < startMs }
            var p = prev.reduce(0) { $0 + value($1) }
            if metric != .tokens {
                var byDay: [String: (cost: Double, n: Int)] = [:]
                for r in prev {
                    let k = dayKey(r.time)
                    var e = byDay[k] ?? (0, 0)
                    e.cost += r.cost; e.n += 1
                    byDay[k] = e
                }
                for dc in costs {
                    guard let day = Self.date(fromKey: dc.day), day >= prevStart, day < firstDay else { continue }
                    let rec = byDay[dc.day] ?? (0, 0)
                    let extra = metric == .cost ? dc.costUsd - rec.cost : Double(dc.messages - rec.n)
                    if extra > 0 { p += extra }
                }
            }
            previous = p
        }

        let chats = chatAcc.map { id, a in
            SpendChat(chatId: id, cost: a.cost, replies: a.n, topModel: a.models.max { $0.value < $1.value }?.key ?? "")
        }
        .sorted { $0.cost > $1.cost }
        .prefix(5)

        let busiest = cells.map { (date: $0.key, value: $0.value.values.reduce(0, +)) }.max { $0.value < $1.value }

        return SpendReport(range: range, metric: metric, unit: unit, start: firstDay, end: end, bars: bars, rows: rows,
                           total: total, previous: previous, replies: inRange.count, prompt: tp, completion: tc,
                           reasoning: tr, chats: Array(chats), busiest: busiest, series: ordered)
    }

    nonisolated static func date(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
