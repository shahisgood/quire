import SwiftUI

// How full a chat's context is: a ring in the bar once the chat has begun, and the window it opens,
// which sets the context out as a hundred squares (one per cent of what the model can take) in
// the colours of what fills them, the way Claude Code shows it, with the figures beside.

/// The ring in the bar. Shown only once something has been said; at nothing it has nothing to say.
struct ContextRingButton: View {
    let session: ChatSession
    let action: () -> Void

    var body: some View {
        let used = session.contextUse.total
        let limit = session.model?.contextLength ?? 0
        let fraction = limit > 0 ? Double(used) / Double(limit) : 0
        Button(action: action) {
            ContextRing(fraction: fraction, warn: fraction > 0.85, lineWidth: 2.5)
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .accessibilityLabel("Context window")
        .accessibilityValue(limit > 0
                            ? "\(Int((fraction * 100).rounded())) percent full, \(Fmt.tokens(used)) of \(Fmt.tokens(limit)) tokens"
                            : "\(Fmt.tokens(used)) tokens")
        .accessibilityHint("Shows what fills it")
    }
}

/// The context window, laid out.
struct ContextPanel: View {
    let session: ChatSession
    let openSettings: () -> Void
    let startFresh: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        let use = session.contextUse
        let limit = session.model?.contextLength ?? 0
        let fraction = limit > 0 ? Double(use.total) / Double(limit) : 0
        VStack(alignment: .leading, spacing: Space.l) {
            header(use, limit: limit, fraction: fraction)
            ContextGrid(use: use, limit: limit)
            legend(use, limit: limit)
            if fraction > 0.8 { nearlyFull(fraction) }
            footnote
            HStack(spacing: Space.s) {
                Button(action: openSettings) {
                    Label("Chat settings", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.qInk)
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 36)
                        .background(Color.qInk.opacity(0.07), in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                Spacer(minLength: 0)
                if app.settings.ui.showCosts && session.chat.totalCostUsd > 0 {
                    Text("Spent \(Fmt.usd(session.chat.totalCostUsd))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                }
            }
        }
        .padding(Space.l)
        .animation(.smooth(duration: 0.25), value: use)
    }

    private func header(_ use: ContextUse, limit: Int, fraction: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("CONTEXT WINDOW")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.qInk2)
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(Fmt.tokens(use.total))
                        .displayFont { .system(.title2, design: $0).weight(.semibold).monospacedDigit() }
                        .foregroundStyle(Color.qInk)
                        .contentTransition(.numericText(value: Double(use.total)))
                    Text(limit > 0 ? "of \(Fmt.context(limit)) tokens" : "tokens")
                        .font(.subheadline)
                        .foregroundStyle(Color.qInk2)
                }
            }
            Spacer(minLength: 8)
            if limit > 0 {
                Text(fraction < 0.01 ? "<1%" : "\(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(fraction > 0.85 ? Color.qWarn : Color.qAccent)
                    .padding(.horizontal, Space.s)
                    .padding(.vertical, Space.xxs)
                    .background((fraction > 0.85 ? Color.qWarn : Color.qAccent).opacity(0.12), in: .capsule)
                    .contentTransition(.numericText(value: fraction))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Each kind with what it holds, as tokens and as a share of the window.
    private func legend(_ use: ContextUse, limit: Int) -> some View {
        let denominator = Double(limit > 0 ? limit : max(1, use.total))
        let kinds = ContextUse.Kind.allCases.filter { use[$0] > 0 }
        return VStack(spacing: Space.s) {
            ForEach(kinds, id: \.self) { kind in
                legendRow(swatch: RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(kind.color),
                          name: kind.name, tokens: use[kind], share: Double(use[kind]) / denominator)
            }
            if limit > 0 {
                legendRow(swatch: RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(ContextGrid.freeColor),
                          name: "Free", tokens: max(0, limit - use.total), share: max(0, 1 - Double(use.total) / denominator))
            }
        }
    }

    private func legendRow<S: View>(swatch: S, name: String, tokens: Int, share: Double) -> some View {
        HStack(spacing: Space.s) {
            swatch.frame(width: 10, height: 10)
            Text(name)
                .font(.footnote)
                .foregroundStyle(Color.qInk)
            Spacer(minLength: 8)
            Text(Fmt.tokens(tokens))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.qInk)
            Text(share < 0.001 && tokens > 0 ? "<0.1%" : String(format: "%.1f%%", share * 100))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Color.qInk2)
                .frame(minWidth: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Past four fifths: what that means, and a clean way on.
    private func nearlyFull(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(fraction >= 1
                 ? "Full. The model can't take all of this; the request may be refused or trimmed by the provider."
                 : "Nearly full. Long chats get slower and dearer as they grow, and may soon be trimmed.")
                .font(.footnote)
                .foregroundStyle(Color.qInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: startFresh) {
                Label("Start a new chat", systemImage: "square.and.pencil")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.qAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.qWarn.opacity(0.1), in: .rect(cornerRadius: Radius.m, style: .continuous))
    }

    private var footnote: some View {
        var text = "Estimated from the text, as the next message would go."
        if let real = session.lastPromptTokens, real > 0 {
            text += " The last reply's prompt came to \(real.formatted()) tokens by the provider's count."
        }
        if (session.model?.contextLength ?? 0) == 0 {
            text += " This model doesn't list its context size, so the squares show only what's in it."
        }
        return Text(text)
            .font(.caption)
            .foregroundStyle(Color.qInk2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A hundred squares in five rows, each one per cent of the window, filled in the order the
/// context is built (instructions, memory, then the conversation), the rest left empty. Anything
/// there at all gets at least a square, so nothing small disappears.
struct ContextGrid: View {
    let use: ContextUse
    let limit: Int
    static let columns = 20
    static let rows = 5
    static var freeColor: Color { Color.qInk.opacity(0.09) }

    var body: some View {
        let cells = Self.cells(use, limit: limit, count: Self.columns * Self.rows)
        VStack(spacing: 3) {
            ForEach(0..<Self.rows, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<Self.columns, id: \.self) { c in
                        let kind = cells[r * Self.columns + c]
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(kind?.color ?? Self.freeColor)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Largest remainder, with a floor of one square for anything present.
    static func cells(_ use: ContextUse, limit: Int, count: Int) -> [ContextUse.Kind?] {
        let kinds = ContextUse.Kind.allCases.filter { use[$0] > 0 }
        guard !kinds.isEmpty else { return Array(repeating: nil, count: count) }
        let denominator = Double(limit > 0 ? max(limit, use.total) : use.total)
        let exact = kinds.map { Double(use[$0]) / denominator * Double(count) }
        var n = exact.map { max(1, Int($0)) }
        let filled = min(count, max(n.reduce(0, +), Int((Double(use.total) / denominator * Double(count)).rounded())))
        var left = filled - n.reduce(0, +)
        let order = exact.indices.sorted { (exact[$0] - floor(exact[$0])) > (exact[$1] - floor(exact[$1])) }
        var i = 0
        while left > 0 {
            n[order[i % order.count]] += 1
            left -= 1
            i += 1
        }
        while n.reduce(0, +) > count, let j = n.indices.max(by: { n[$0] < n[$1] }), n[j] > 1 { n[j] -= 1 }
        var out: [ContextUse.Kind?] = []
        for (k, c) in zip(kinds, n) { out += Array(repeating: k, count: c) }
        if out.count < count { out += Array(repeating: nil, count: count - out.count) }
        return Array(out.prefix(count))
    }
}

extension ContextUse.Kind {
    /// One colour each; under Pitch, greys stepped far enough apart to tell neighbours by lightness.
    var color: Color {
        switch self {
        case .instructions: .tone(.qTileViolet, mono: Color(light: 0x111111, dark: 0xF2F2F2))
        case .memory: .tone(.qTileTeal, mono: Color(light: 0x3A3A3A, dark: 0xC6C6C6))
        case .yours: .tone(.qAccent, mono: Color(light: 0x5E5E5E, dark: 0x9C9C9C))
        case .replies: .tone(.qTileSlate, mono: Color(light: 0x828282, dark: 0x747474))
        case .attachments: .tone(.qTileAmber, mono: Color(light: 0xA6A6A6, dark: 0x545454))
        case .draft: .tone(.qTileRose, mono: Color(light: 0xC4C4C4, dark: 0x3E3E3E))
        }
    }
}
