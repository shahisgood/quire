import SwiftUI

// Small pieces shared by the composer, the model picker and the empty chat: provider marks, the
// sliding segmented control, toggle chips, the context ring, entrance motion and the greeting.

// MARK: - Providers

/// Display names and colours for OpenRouter's provider prefixes ("openai/…", "deepseek/…").
enum ProviderStyle {
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

    private static let palette: [Color] = [
        .qTileBlue, .qTileTeal, .qTileViolet, .qTileAmber, .qTileRose, .qTileSlate,
        Color(light: 0x2F6B8F, dark: 0x4A86A8), Color(light: 0x7A5C2E, dark: 0x9C7A45),
    ]

    static func displayName(_ id: String) -> String {
        if let n = names[id] { return n }
        return id.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func initial(_ id: String) -> String { String(displayName(id).prefix(1)).uppercased() }

    /// Stable across launches (unlike `hashValue`), so a provider keeps its colour.
    static func color(_ id: String) -> Color {
        var h: UInt64 = 5381
        for b in id.utf8 { h = (h &* 33) &+ UInt64(b) }
        return palette[Int(h % UInt64(palette.count))]
    }
}

/// A provider's monogram: one letter on that provider's colour, the same everywhere it appears.
struct ProviderMark: View {
    let provider: String
    var size: CGFloat = 32

    var body: some View {
        Text(ProviderStyle.initial(provider))
            .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ProviderStyle.color(provider).gradient, in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
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

/// The line that opens an empty chat. It follows the clock (and the weekend), and is picked from a
/// small pool by the chat's id, so it stays put for that chat instead of changing on every redraw.
nonisolated enum Greeting {
    static func line(at date: Date = Date(), seed: String, returning: Bool) -> String {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date)   // 1 is Sunday, 7 Saturday
        var pool: [String]
        switch hour {
        case 0..<4:
            pool = ["It's a late-night jam session.", "Burning the midnight oil?",
                    "The quiet hours. Good for thinking.", "Still up? Let's make it count."]
        case 4..<7:
            pool = ["Up before the sun.", "An early start. Coffee first?", "The world's still quiet. Let's begin."]
        case 7..<12:
            pool = ["Good morning.", "Morning. What's on your mind?", "A fresh page for the morning."]
        case 12..<17:
            pool = ["Good afternoon.", "Afternoon. Let's get into it.", "Midday thoughts welcome."]
        case 17..<21:
            pool = ["Good evening.", "Evening. Winding down or gearing up?", "The day's nearly done. What's left?"]
        default:
            pool = ["Night owl hours.", "A late one tonight?", "Settling in for the night."]
        }
        if weekday == 7 { pool.append("Happy Saturday.") }
        if weekday == 1 { pool.append("Sunday thoughts?") }
        if returning { pool.append("Welcome back.") }
        var h: UInt64 = 5381
        for b in seed.utf8 { h = (h &* 33) &+ UInt64(b) }
        return pool[Int(h % UInt64(pool.count))]
    }
}
