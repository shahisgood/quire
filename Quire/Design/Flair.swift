import SwiftUI

// Small pieces shared by the composer, the model picker and the empty chat: provider names, the
// sliding segmented control, toggle chips, the context ring, entrance motion and the greeting.

// MARK: - Providers

/// Display names for OpenRouter's provider prefixes ("openai/…", "deepseek/…").
nonisolated enum ProviderStyle {
    private static let names: [String: String] = [
        "openai": "OpenAI", "anthropic": "Anthropic", "google": "Google", "meta-llama": "Meta",
        "mistralai": "Mistral", "deepseek": "DeepSeek", "x-ai": "xAI", "qwen": "Qwen",
        "moonshotai": "Moonshot", "z-ai": "Z.ai", "cohere": "Cohere", "perplexity": "Perplexity",
        "nvidia": "NVIDIA", "microsoft": "Microsoft", "amazon": "Amazon", "minimax": "MiniMax",
        "openrouter": "OpenRouter", "nousresearch": "Nous", "ai21": "AI21", "inflection": "Inflection",
        "baidu": "Baidu", "tencent": "Tencent", "thudm": "THUDM", "liquid": "Liquid",
        "ibm-granite": "IBM", "aion-labs": "Aion Labs", "arcee-ai": "Arcee", "bytedance": "ByteDance",
        "inception": "Inception", "morph": "Morph", "sao10k": "Sao10K", "thedrummer": "TheDrummer",
        "gryphe": "Gryphe", "alpindale": "Alpindale", "neversleep": "NeverSleep", "anthracite-org": "Anthracite",
        "cognitivecomputations": "Cognitive", "eleutherai": "EleutherAI", "allenai": "Ai2", "stepfun-ai": "StepFun",
    ]

    static func displayName(_ id: String) -> String {
        if let n = names[id] { return n }
        return id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

// MARK: - Controls

/// A compact segmented control whose selection pill slides between options.
struct SlidingSegments<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                segment(options[i].value, options[i].label)
            }
        }
        .padding(3)
        .background(Color.qRaised, in: .capsule)
        .overlay(Capsule().strokeBorder(Color.qRule, lineWidth: 1))
    }

    private func segment(_ value: Value, _ label: String) -> some View {
        let on = value == selection
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy) { selection = value }
        } label: {
            Text(label)
                .font(.footnote.weight(on ? .semibold : .medium))
                .foregroundStyle(on ? Color.qOnAccent : Color.qInk2)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if on {
                        Capsule()
                            .fill(Color.qAccent.gradient)
                            .matchedGeometryEffect(id: "selection", in: ns)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A filter chip that lights up when on: the accent fill grows in under the label, the icon gives
/// a small bounce, and a soft glow lifts it off the page.
struct ToggleChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .symbolEffect(.bounce, value: isOn)
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isOn ? Color.qOnAccent : Color.qInk)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background {
                ZStack {
                    Capsule().fill(Color.qRaised)
                    Capsule()
                        .fill(Color.qAccent.gradient)
                        .opacity(isOn ? 1 : 0)
                        .scaleEffect(isOn ? 1 : 0.85)
                }
            }
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.qRule, lineWidth: 1))
            .shadow(color: Color.qAccent.opacity(isOn ? 0.3 : 0), radius: 8, y: 3)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// How full the context window is, as a small ring.
struct ContextRing: View {
    var fraction: Double
    var warn = false
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(Color.qRule, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, fraction)))
                .stroke(warn ? Color.qWarn : Color.qAccent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Motion.quick, value: fraction)
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

private struct PopEffect: ViewModifier {
    var visible: Bool
    func body(content: Content) -> some View {
        content
            .scaleEffect(visible ? 1 : 0.6)
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 3)
    }
}

extension AnyTransition {
    /// Springs a small control into being: from 60% with a touch of blur, never from nothing.
    static var pop: AnyTransition { .modifier(active: PopEffect(visible: false), identity: PopEffect(visible: true)) }
}

/// Fades a block up into place, after `delay`, the first time `shown` turns true. Stagger a few of
/// these for an arrival that reads top to bottom. Reduce Motion keeps only the fade.
private struct Entrance: ViewModifier {
    let shown: Bool
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.entrance.delay(delay), value: shown)
    }
}

extension View {
    func entrance(_ shown: Bool, delay: Double = 0) -> some View { modifier(Entrance(shown: shown, delay: delay)) }
}

// MARK: - Greeting

/// The line that opens an empty chat. It follows the clock, the day of the week and a few days of
/// the year, and is picked from the pool by a seed, so it stays put instead of changing on every
/// redraw. Every line, the mark's included, sits on one line at the greeting's size even on the
/// narrowest iPhone, so keep new ones to about 28 characters.
nonisolated enum Greeting {
    static func line(at date: Date = Date(), seed: String, returning: Bool) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date)   // 1 is Sunday, 7 Saturday
        let month = cal.component(.month, from: date)
        let day = cal.component(.day, from: date)
        var pool: [String]
        switch hour {
        case 0..<4:
            pool = ["It's a late-night jam session.", "Burning the midnight oil?", "Quiet hours, good thinking.",
                    "Still up? Let's make it count.", "The world's asleep. Not us.", "Small hours, big thoughts?",
                    "Can't sleep, or won't?", "The night shift begins.", "Moonlight, blinking cursor.",
                    "Insomnia has its uses.", "The whispering hours.", "Midnight, and a blank page."]
        case 4..<7:
            pool = ["Up before the sun.", "An early start. Coffee first?", "The world's still quiet.",
                    "First light, first thoughts.", "The early bird asks first.", "Before the inbox wakes up.",
                    "A head start on the day.", "Still dark out. Bright idea?", "Dawn, and a fresh page."]
        case 7..<12:
            pool = ["Good morning.", "What's on your mind?", "Morning. A fresh page.",
                    "Morning. Where to start?", "Rise and write.", "A clean slate for the day.",
                    "Coffee in hand? Let's go.", "Morning thoughts welcome.", "The day's wide open.",
                    "What's first on the list?", "Morning light, clear head."]
        case 12..<17:
            pool = ["Good afternoon.", "Afternoon. Let's get into it.", "Midday thoughts welcome.",
                    "Halfway through the day.", "What needs untangling?", "A second wind, perhaps?",
                    "The post-lunch push.", "What's on your desk?", "Plenty of day left.",
                    "Afternoon light, clear mind."]
        case 17..<21:
            pool = ["Good evening.", "Unwinding, or gearing up?", "Nearly done. What's left?",
                    "Time to think it through.", "Golden hour, open page.", "Clocking off, or on?",
                    "One more thing, then rest?", "The evening's yours.", "Dusk settles. Ideas don't.",
                    "Supper's done? Let's begin."]
        default:
            pool = ["Night owl hours.", "A late one tonight?", "Settling in for the night.",
                    "Quiet house. Let's talk.", "Lamplight and loose ends.", "One last thought tonight?",
                    "Night has its own clarity.", "Late, but not too late.", "Tea, a blanket, a question?",
                    "Winding down with words."]
        }
        switch weekday {
        case 1: pool += ["Sunday thoughts?", "A Sunday kind of question?"]
        case 2: pool += ["Monday. Let's ease in.", "A new week, a fresh quire."]
        case 3: pool += ["Tuesday. Picking up speed."]
        case 4: pool += ["Midweek already."]
        case 5: pool += ["Almost Friday."]
        case 6: pool += ["Friday. Home stretch.", "Friday feeling?"]
        default: pool += ["Happy Saturday.", "A slow Saturday?"]
        }
        switch (month, day) {
        case (1, 1): pool += ["Happy New Year.", "A new year, a blank page."]
        case (2, 14): pool += ["Happy Valentine's Day."]
        case (10, 31): pool += ["Happy Halloween.", "Got a spooky question?"]
        case (12, 24), (12, 25), (12, 26): pool += ["Happy holidays.", "Season's greetings."]
        case (12, 31): pool += ["The year's last page."]
        default: break
        }
        if returning { pool += ["Welcome back.", "Good to see you again."] }
        var h: UInt64 = 5381
        for b in seed.utf8 { h = (h &* 33) &+ UInt64(b) }
        return pool[Int(h % UInt64(pool.count))]
    }

    /// What the new-chat mark says once it's been written out again (three taps). The first time
    /// you find it, it says so; keep at it and it notices. When it's drawn you a heart, it says
    /// something about that instead.
    @MainActor static func egg(withHeart: Bool = false) -> String {
        found += 1
        switch found {
        case 1: return "You found me."
        case 5: return "Okay, you really like this."
        case 10: return "Writer's cramp, honestly."
        case 20: return "We should talk about this."
        default: break
        }
        if withHeart {
            return ["Made you something.", "A little something for you.", "With love, Quire.", "From me, to you.",
                    "Heart-shaped, hand-typed.", "A heart. Don't tell anyone."].randomElement() ?? "Made you something."
        }
        return ["Freshly inked.", "Hand-lettered, just for you.", "Quire, at your service.", "Ahem. Where were we?",
                "That tickles.", "Writing myself in.", "Fresh page, fresh ink.", "Again? Show-off.",
                "Signed, sealed, typeset.", "Curiosity got the better of you?", "I practise this in secret.",
                "Practising my penmanship.", "Three taps. Bold move.", "Ink everywhere. Worth it.",
                "Shh, it's our little secret.", "Encore? Fine, one more.", "Look, no hands.",
                "Typing… typing… done!", "It all starts with a line.", "That was my best one yet.",
                "Careful, I'll start a novel.", "Do you poke every app?", "Calligraphy, in pixels.",
                "Ta-da.", "Still got it."].randomElement() ?? "Freshly inked."
    }

    @MainActor private static var found = 0
}

// MARK: - Heart

/// A little heart in type, which the new-chat mark draws you now and then after its trick. A pen
/// traces it from the point, up both sides at once and over the lobes into the dip, each character
/// landing with a small bounce; then it fills from the bottom up. It beats once, lub-dub, with a
/// soft tap for each, and lifts away. It takes no space and no touches, so it can't get in the way.
struct AsciiHeart: View {
    var onFinished: () -> Void = {}
    @State private var drawn: Double = 0
    @State private var beat: CGFloat = 1
    @State private var glow = false
    @State private var gone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much room it needs, so whoever places it can keep it clear of everything else.
    static var size: CGSize { HeartType.size }

    /// From the first stroke to the last of the fill.
    static let drawing = 2.4

    var body: some View {
        HeartType(drawn: drawn, bounces: !reduceMotion)
            .shadow(color: Color.qAccent.opacity(glow ? 0.45 : 0), radius: 9)
            .scaleEffect(beat)
            .opacity(gone ? 0 : 1)
            .offset(y: gone && !reduceMotion ? -16 : 0)
            .blur(radius: gone && !reduceMotion ? 3 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task { await play() }
    }

    private func play() async {
        // A moment for the eye to come up from the mark before the pen starts.
        guard await pause(0.12) else { return }
        withAnimation(.timingCurve(0.3, 0.1, 0.5, 1, duration: Self.drawing)) { drawn = 1 }
        guard await pause(Self.drawing + 0.35) else { return }
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.3)) { glow = true }
            // Lub…
            Haptics.soft()
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { beat = 1.14 }
            guard await pause(0.14) else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) { beat = 1 }
            guard await pause(0.12) else { return }
            // …dub.
            Haptics.soft()
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { beat = 1.08 }
            guard await pause(0.14) else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { beat = 1 }
            withAnimation(.easeInOut(duration: 0.6)) { glow = false }
        }
        guard await pause(0.8) else { return }
        withAnimation(.easeIn(duration: 0.6)) { gone = true }
        guard await pause(0.65) else { return }
        onFinished()
    }

    /// Waits, and says whether to carry on (not if the heart has left the screen meanwhile).
    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// The heart's characters, each set down at its turn as `drawn` runs from 0 to 1. The outline
/// goes first, in order of each character's angle around the heart's middle, measured from the
/// point; the inside follows, a row at a time from the bottom, as if the ink were pooling up.
/// A character lands a little large and dark, like wet ink, and settles to size and colour.
private struct HeartType: View, Animatable {
    var drawn: Double
    var bounces: Bool

    var animatableData: Double {
        get { drawn }
        set { drawn = newValue }
    }

    static let rows = [
        " .:::.   .:::. ",
        ":::::::.:::::::",
        ":::::::::::::::",
        "':::::::::::::'",
        "  ':::::::::'  ",
        "    ':::::'    ",
        "      ':'      ",
    ]

    /// One character's square on the page: rows are about twice as tall as a character is wide.
    static let cell = CGSize(width: 7.2, height: 13.2)
    static var size: CGSize {
        CGSize(width: cell.width * CGFloat(rows[0].count), height: cell.height * CGFloat(rows.count))
    }

    /// A character, where it sits, and when it's drawn (as shares of the whole drawing).
    nonisolated struct Stroke {
        let glyph: Character
        let at: CGPoint
        let start: Double
        let length: Double
    }

    static let strokes: [Stroke] = {
        let grid = HeartType.rows.map { Array($0) }
        let cell = HeartType.cell
        func inked(_ r: Int, _ c: Int) -> Bool {
            grid.indices.contains(r) && grid[r].indices.contains(c) && grid[r][c] != " "
        }
        func place(_ r: Int, _ c: Int) -> CGPoint {
            CGPoint(x: (Double(c) + 0.5) * cell.width, y: (Double(r) + 0.5) * cell.height)
        }
        let cx = Double(grid[0].count - 1) / 2, cy = 2.6
        var outline: [(glyph: Character, at: CGPoint, turn: Double)] = []
        var inside: [(glyph: Character, at: CGPoint, rise: Double)] = []
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() where ch != " " {
                let dx = abs(Double(c) - cx)
                if inked(r - 1, c) && inked(r + 1, c) && inked(r, c - 1) && inked(r, c + 1) {
                    // Rows up from the bottom, and a touch later the further from the middle.
                    inside.append((ch, place(r, c), Double(grid.count - 1 - r) + dx * 0.08))
                } else {
                    outline.append((ch, place(r, c), atan2(dx, (Double(r) - cy) * 2)))
                }
            }
        }
        // The pen takes the first 60%, each character a short stroke; the fill starts a little
        // before the outline closes, each character pooling in more slowly.
        let pen = 0.07, outlineEnd = 0.6, fillStart = 0.5, pool = 0.16
        let lastTurn = max(outline.map { $0.turn }.max() ?? 1, 0.001)
        let lastRise = max(inside.map { $0.rise }.max() ?? 1, 0.001)
        return outline.map { Stroke(glyph: $0.glyph, at: $0.at, start: $0.turn / lastTurn * (outlineEnd - pen), length: pen) }
            + inside.map { Stroke(glyph: $0.glyph, at: $0.at, start: fillStart + $0.rise / lastRise * (1 - fillStart - pool), length: pool) }
    }()

    var body: some View {
        let strokes = Self.strokes
        let drawn = self.drawn, bounces = self.bounces
        let ink = Color.qAccent, wet = Color.qInk
        let font = Font.system(size: 12, weight: .bold, design: .monospaced)
        Canvas { context, _ in
            var dry: [Character: GraphicsContext.ResolvedText] = [:]
            var fresh: [Character: GraphicsContext.ResolvedText] = [:]
            for stroke in strokes {
                let t = min(1, max(0, (drawn - stroke.start) / stroke.length))
                guard t > 0 else { continue }
                let glyph = dry[stroke.glyph] ?? context.resolve(Text(String(stroke.glyph)).font(font).foregroundStyle(ink))
                dry[stroke.glyph] = glyph
                var g = context
                g.translateBy(x: stroke.at.x, y: stroke.at.y)
                if bounces {
                    // Back-out easing: a touch past full size just after halfway, then settles.
                    let u = t - 1, k = 1.9
                    let s = 0.35 + 0.65 * (1 + (k + 1) * u * u * u + k * u * u)
                    g.scaleBy(x: s, y: s)
                }
                g.opacity = min(1, t * 1.8)
                g.draw(glyph, at: .zero, anchor: .center)
                if t < 1 {
                    let shine = fresh[stroke.glyph] ?? context.resolve(Text(String(stroke.glyph)).font(font).foregroundStyle(wet))
                    fresh[stroke.glyph] = shine
                    g.opacity = (1 - t) * min(1, t * 3) * 0.7
                    g.draw(shine, at: .zero, anchor: .center)
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

// MARK: - Layout

extension VerticalAlignment {
    private nonisolated enum OpticalCenter: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height * 0.42 }
    }

    /// A touch above true centre, where the eye expects "centred" to be. In a full-height frame this
    /// leaves the space above and below a block in a 42:58 ratio instead of 50:50.
    static let opticalCenter = VerticalAlignment(OpticalCenter.self)
}

// MARK: - Live

/// A small accent dot that breathes while something is happening (a reply being written). Holds
/// still under Reduce Motion.
struct LiveDot: View {
    var size: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dot = Circle().fill(Color.qAccent).frame(width: size, height: size)
        if reduceMotion {
            dot.accessibilityHidden(true)
        } else {
            dot
                .phaseAnimator([false, true]) { view, bright in
                    view
                        .opacity(bright ? 1 : 0.35)
                        .scaleEffect(bright ? 1 : 0.75)
                } animation: { _ in .easeInOut(duration: 0.7) }
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Starter prompts

/// Ways to begin a chat, in a few groups that each open into three. Picking one only fills the
/// message box; you finish the sentence and send it yourself.
struct StarterGroup: Identifiable, Hashable {
    let title: String
    let symbol: String
    let options: [StarterOption]
    var id: String { title }

    static let all: [StarterGroup] = [
        StarterGroup(title: "Write or edit", symbol: "pencil.line", options: [
            StarterOption(title: "Help me write something", text: "Help me write "),
            StarterOption(title: "Rewrite this to read better", text: "Rewrite this so it reads more clearly:\n\n"),
            StarterOption(title: "Proofread and fix mistakes", text: "Proofread this and fix any mistakes:\n\n"),
        ]),
        StarterGroup(title: "Explain something", symbol: "lightbulb", options: [
            StarterOption(title: "Explain it simply", text: "Explain in simple terms: "),
            StarterOption(title: "Walk me through it, step by step", text: "Walk me through, step by step, how "),
            StarterOption(title: "Compare two things", text: "What's the difference between "),
        ]),
    ]

    /// Whether the message box holds nothing but a starter's opening.
    static func isStarter(_ text: String) -> Bool {
        all.contains { $0.options.contains { $0.text == text } }
    }
}

struct StarterOption: Identifiable, Hashable {
    let title: String
    let text: String
    var id: String { text }
}
