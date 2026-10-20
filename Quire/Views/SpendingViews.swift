import SwiftUI
import Charts

// MARK: - The card in Settings

/// The last 30 days at a glance: the total and how it compares with the 30 before, a bar for each
/// day (today's lit), and today, this week and the daily average underneath.
struct SpendingCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let series = app.dailySeries(days: 30)
        let total = series.reduce(0) { $0 + $1.cost }
        let before = max(0, app.costSince(daysAgo: 59) - total)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.usd(total))
                        .font(.system(.largeTitle, design: .serif).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.qInk)
                        .contentTransition(.numericText(value: total))
                    Text("Last 30 days")
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                }
                Spacer(minLength: 8)
                if before > 0 {
                    ChangeBadge(change: (total - before) / before, against: "the 30 before")
                }
            }

            Chart(series) { p in
                BarMark(x: .value("Day", p.date, unit: .day),
                        y: .value("Cost", grown ? p.cost : 0))
                    .foregroundStyle(Calendar.current.isDateInToday(p.date) ? Color.qAccent : Color.qAccent.opacity(0.4))
                    .cornerRadius(2)
            }
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .frame(height: 64)
            .accessibilityLabel("Spending each day for the last 30 days")
            .accessibilityValue("\(Fmt.usd(total)) in total")

            HStack(alignment: .top, spacing: 0) {
                stat("Today", app.todayCost)
                Spacer(minLength: 8)
                stat("7 days", app.costSince(daysAgo: 6))
                Spacer(minLength: 8)
                stat("Daily average", total / 30)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.entrance) { grown = true }
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.usd(value))
                .font(.system(.body, design: .serif).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.qInk)
                .contentTransition(.numericText(value: value))
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.qInk2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "▲ 12%" against an earlier period. Neutral ink: more spending isn't an error, just a change.
struct ChangeBadge: View {
    let change: Double
    let against: String

    var body: some View {
        let up = change >= 0
        HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.caption2.weight(.bold))
            Text(abs(change) >= 10 ? "\(Int(abs(change)))×" : "\(Int((abs(change) * 100).rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(Color.qInk2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.qSunken, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(up ? "Up" : "Down") \(Int((abs(change) * 100).rounded())) percent on \(against)")
    }
}

// MARK: - The full breakdown

/// Where the money (or the tokens, or the replies) went: over a range you pick, by day, by model
/// and by chat. Every model keeps one colour throughout. Tap or drag across the chart to read a
/// day; tap a model to pick it out.
struct SpendingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var records: [SpendRecord] = []
    @State private var loaded = false
    @State private var report: SpendReport? = nil
    @State private var range: SpendRange = .month
    @State private var metric: SpendMetric = .cost
    @State private var focus: String? = nil
    @State private var selected: Date? = nil
    @State private var grown = false

    nonisolated private struct Key: Equatable {
        var range: SpendRange
        var metric: SpendMetric
        var loaded: Bool
        var costs: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                controls
                if let report {
                    if report.total == 0 && report.replies == 0 {
                        EmptyState(title: "Nothing in \(range.phrase)",
                                   message: "Spending shows up here as replies come in.", showMark: false) { EmptyView() }
                            .padding(.vertical, 40)
                    } else {
                        hero(report)
                        chartCard(report)
                        breakdown(report)
                        tokenMix(report)
                        if !report.chats.isEmpty { topChats(report) }
                        footnote
                    }
                } else {
                    loading
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.qBase)
        .navigationTitle("Spending")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await app.store.flush()
            let found = await SpendScan.run(in: app.store.messagesDir)
            records = found
            loaded = true
        }
        .task(id: Key(range: range, metric: metric, loaded: loaded, costs: app.costs.count)) {
            guard loaded else { return }
            let next = SpendReport.make(records: records, costs: app.costs, range: range, metric: metric,
                                        name: { app.modelName($0) })
            selected = nil
            if focus != nil, !next.rows.contains(where: { $0.series.id == focus || chartId($0) == focus }) { focus = nil }
            withAnimation(reduceMotion ? nil : Motion.standard) { report = next }
            if !grown {
                withAnimation(reduceMotion ? nil : Motion.entrance.delay(0.05)) { grown = true }
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 10) {
            SlidingSegments(options: SpendRange.allCases.map { (value: $0, label: $0.label) }, selection: $range)
                .accessibilityLabel("Range")
            SlidingSegments(options: SpendMetric.allCases.map { (value: $0, label: $0.label) }, selection: $metric)
                .accessibilityLabel("Measure")
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Reading your chats…")
                .font(.footnote)
                .foregroundStyle(Color.qInk2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: Headline

    private func hero(_ r: SpendReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(metric.format(r.total))
                    .font(.system(size: 46, weight: .semibold, design: .serif))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .foregroundStyle(Color.qInk)
                    .contentTransition(.numericText(value: r.total))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(metric.label) over \(r.range.phrase)")
                        .font(.subheadline)
                        .foregroundStyle(Color.qInk2)
                    if let change = r.change {
                        ChangeBadge(change: change, against: "the period before")
                    }
                }
            }
            HStack(alignment: .top, spacing: 0) {
                figure(metric.format(r.dailyAverage), "Daily average")
                Spacer(minLength: 8)
                figure(r.busiest.map { metric.format($0.value) } ?? "—",
                       r.busiest.map { "Busiest, \(label(for: $0.date, unit: r.unit))" } ?? "Busiest")
                Spacer(minLength: 8)
                figure(r.replies.formatted(), r.replies == 1 ? "Reply" : "Replies")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.body, design: .serif).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.qInk)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption)
                .foregroundStyle(Color.qInk2)
                .lineLimit(1)
        }
    }

    // MARK: Chart

    private func chartCard(_ r: SpendReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            readout(r)
                .frame(minHeight: 54, alignment: .topLeading)

            Chart {
                ForEach(r.bars) { b in
                    BarMark(x: .value("Date", b.date, unit: r.unit),
                            y: .value(metric.label, grown ? b.value : 0))
                        .foregroundStyle(b.series.color)
                        .opacity(focus == nil || focus == b.series.id ? 1 : 0.18)
                        .cornerRadius(2)
                }
                if let s = selectedBucket(r) {
                    RuleMark(x: .value("Date", s, unit: r.unit))
                        .foregroundStyle(Color.qInk2.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.qRule)
                    AxisValueLabel {
                        if let d = v.as(Double.self) {
                            Text(axisLabel(d))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.qInk2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { v in
                    AxisValueLabel {
                        if let d = v.as(Date.self) {
                            Text(label(for: d, unit: r.unit))
                                .font(.caption2)
                                .foregroundStyle(Color.qInk2)
                        }
                    }
                }
            }
            .frame(height: 210)
            .animation(reduceMotion ? nil : Motion.quick, value: focus)
            .onChange(of: selectedBucket(r)) { _, day in if day != nil { Haptics.selection() } }

            legend(r)
        }
        .padding(16)
        .card(radius: 20)
    }

    /// Above the chart: the day (or week, or month) under your finger, with what it was made of;
    /// otherwise a hint.
    @ViewBuilder
    private func readout(_ r: SpendReport) -> some View {
        if let s = selectedBucket(r) {
            let parts = r.bars.filter { $0.date == s }.sorted { $0.value > $1.value }
            let sum = parts.reduce(0) { $0 + $1.value }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label(for: s, unit: r.unit, long: true))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qInk)
                    Spacer()
                    Text(metric.format(sum))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.qInk)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(parts.prefix(4)) { p in
                            HStack(spacing: 5) {
                                Circle().fill(p.series.color).frame(width: 7, height: 7)
                                Text("\(p.series.name) \(metric.format(p.value))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Color.qInk2)
                                    .lineLimit(1)
                            }
                        }
                        if parts.isEmpty {
                            Text("Nothing on this \(unitWord(r.unit))")
                                .font(.caption)
                                .foregroundStyle(Color.qInk2)
                        }
                    }
                }
            }
            .transition(.opacity)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("By \(unitWord(r.unit))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.qInk)
                Text("Touch and drag across the chart to read each \(unitWord(r.unit)).")
                    .font(.caption)
                    .foregroundStyle(Color.qInk2)
            }
            .transition(.opacity)
        }
    }

    private func legend(_ r: SpendReport) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(r.series) { s in
                    let on = focus == s.id
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.quick) { focus = on ? nil : s.id }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(s.color).frame(width: 8, height: 8)
                            Text(s.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.qInk)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(on ? Color.qAccentSoft : Color.qSunken, in: .capsule)
                        .overlay(Capsule().strokeBorder(on ? Color.qAccent.opacity(0.5) : Color.clear, lineWidth: 1))
                        .opacity(focus == nil || on ? 1 : 0.55)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(s.name)
                    .accessibilityHint(on ? "Shows every model again" : "Picks out this one in the chart")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: By model

    private func breakdown(_ r: SpendReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "By model")
            VStack(spacing: 0) {
                ForEach(Array(r.rows.enumerated()), id: \.element.id) { i, row in
                    if i > 0 { Rectangle().fill(Color.qRule).frame(height: 1).padding(.leading, 34) }
                    modelRow(row, r)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .card(radius: 18)
        }
    }

    private func modelRow(_ row: SpendRow, _ r: SpendReport) -> some View {
        let id = chartId(row)
        let on = focus == id
        return Button {
            Haptics.selection()
            withAnimation(Motion.quick) { focus = on ? nil : id }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(row.series.color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.series.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(metric.format(row.value))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.qInk)
                    }
                    Capsule()
                        .fill(Color.qSunken)
                        .frame(height: 5)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(row.series.color)
                                .scaleEffect(x: grown ? max(0.015, row.share) : 0, anchor: .leading)
                        }
                        .accessibilityHidden(true)
                    Text(detail(row))
                        .font(.caption)
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 11)
            .opacity(focus == nil || on ? 1 : 0.5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint("Picks it out in the chart")
    }

    private func detail(_ row: SpendRow) -> String {
        let share = "\(Int((row.share * 100).rounded()))%"
        if row.series.id == SpendSeries.outsideId {
            return "\(share) · titles, memory and chats since deleted"
        }
        switch metric {
        case .cost:
            let per = row.replies > 0 ? Fmt.usd(row.cost / Double(row.replies)) : "—"
            return "\(share) · \(row.replies) \(row.replies == 1 ? "reply" : "replies") · \(per) a reply"
        case .tokens:
            var t = "\(share) · \(Fmt.tokens(row.prompt)) in · \(Fmt.tokens(row.completion)) out"
            if row.reasoning > 0 { t += " · \(Fmt.tokens(row.reasoning)) thinking" }
            return t
        case .replies:
            return "\(share) · \(Fmt.usd(row.cost)) · \(Fmt.tokens(row.prompt + row.completion + row.reasoning)) tokens"
        }
    }

    // MARK: Tokens

    private func tokenMix(_ r: SpendReport) -> some View {
        let total = max(1, r.prompt + r.completion + r.reasoning)
        let parts = [
            TokenPart(name: "Sent", count: r.prompt, color: Color.qAccent.opacity(0.4)),
            TokenPart(name: "Written", count: r.completion, color: Color.qAccent),
            TokenPart(name: "Thinking", count: r.reasoning, color: Color.qAccent.opacity(0.7)),
        ].filter { $0.count > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Tokens")
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts) { p in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(p.color)
                                .frame(width: max(3, (geo.size.width - CGFloat(parts.count - 1) * 2) * CGFloat(p.count) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Spacer(minLength: 8) }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2).fill(p.color).frame(width: 8, height: 8)
                                Text(p.name)
                                    .font(.caption)
                                    .foregroundStyle(Color.qInk2)
                            }
                            Text(Fmt.tokens(p.count))
                                .font(.system(.body, design: .serif).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.qInk)
                            Text("\(Int((Double(p.count) / Double(total) * 100).rounded()))%")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.qInk2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Sent counts everything a reply was given to read: your message, the thread before it, the system prompt and memory. It's usually most of the tokens.")
                    .font(.caption)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .card(radius: 18)
        }
    }

    // MARK: Chats

    private func topChats(_ r: SpendReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Costliest chats")
            VStack(spacing: 0) {
                ForEach(Array(r.chats.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Rectangle().fill(Color.qRule).frame(height: 1) }
                    let chat = app.chat(c.chatId)
                    Button {
                        guard chat != nil else { return }
                        Haptics.tap()
                        app.openChat(c.chatId)
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(i + 1)")
                                .font(.system(.subheadline, design: .serif).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.qInk2)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chat?.title ?? "Deleted chat")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(chat == nil ? Color.qInk2 : Color.qInk)
                                    .lineLimit(1)
                                Text("\(c.replies) \(c.replies == 1 ? "reply" : "replies") · mostly \(app.modelName(c.topModel))")
                                    .font(.caption)
                                    .foregroundStyle(Color.qInk2)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(Fmt.usd(c.cost))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.qInk)
                            if chat != nil {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.qInk2.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 11)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(chat == nil)
                    .accessibilityHint(chat == nil ? "" : "Opens the chat")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
            .card(radius: 18)
        }
    }

    private var footnote: some View {
        Text("Counted from the replies in chats on this iPhone. “Outside chats” is the rest of each day's total: chat titles, memory, and chats you've since deleted.")
            .font(.caption)
            .foregroundStyle(Color.qInk2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Helpers

    /// The chart series a row belongs to: a model outside the top colours is in "Other models".
    private func chartId(_ row: SpendRow) -> String {
        if row.series.rank < 100 || row.series.id == SpendSeries.outsideId { return row.series.id }
        return SpendSeries.otherId
    }

    private func selectedBucket(_ r: SpendReport) -> Date? {
        guard let selected else { return nil }
        return Calendar.current.dateInterval(of: r.unit, for: selected)?.start
    }

    private func unitWord(_ unit: Calendar.Component) -> String {
        switch unit {
        case .month: return "month"
        case .weekOfYear: return "week"
        default: return "day"
        }
    }

    private func label(for date: Date, unit: Calendar.Component, long: Bool = false) -> String {
        switch unit {
        case .month:
            return date.formatted(.dateTime.month(long ? .wide : .abbreviated).year(long ? .defaultDigits : .twoDigits))
        case .weekOfYear:
            return (long ? "Week of " : "") + date.formatted(.dateTime.month(.abbreviated).day())
        default:
            return long ? date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                        : date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func axisLabel(_ v: Double) -> String {
        switch metric {
        case .cost:
            if v == 0 { return "$0" }
            if v < 0.1 { return String(format: "$%.2f", v) }
            if v < 10 { return String(format: "$%.1f", v) }
            return String(format: "$%.0f", v)
        case .tokens: return Fmt.tokens(Int(v.rounded()))
        case .replies: return Int(v.rounded()).formatted()
        }
    }
}

nonisolated private struct TokenPart: Identifiable, Sendable {
    let name: String
    let count: Int
    let color: Color
    var id: String { name }
}
