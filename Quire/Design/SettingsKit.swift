import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

// The pieces settings pages are built from, in the manner of the Spending page: cards on the page,
// a small label over each, rows divided by hairlines, figures in the display face. Explanations
// open under their row instead of in an alert, and sliders are Quire's own.

// MARK: - Page

/// A scrolling settings page with a large title that hands over to the bar as it scrolls (or an
/// inline one, in a sheet).
struct SettingsPage<Content: View>: View {
    let title: String
    var inlineTitle = false
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) { content }
                .padding(.horizontal, 18)
                .padding(.top, inlineTitle ? 12 : 6)
                .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.qBase)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(inlineTitle ? .inline : .large)
    }
}

// MARK: - Group

/// A small label, a card of rows divided by hairlines, and an optional note under it.
struct SettingsGroup<Content: View>: View {
    var label: String? = nil
    var footer: Text? = nil
    @ViewBuilder var content: Content
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let label {
                SectionLabel(text: label)
                    .padding(.horizontal, 4)
            }
            Group(subviews: content) { rows in
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            Rectangle()
                                .fill(Color.qRule)
                                .frame(height: 1 / displayScale)
                        }
                        row
                    }
                }
            }
            .padding(.horizontal, 16)
            .card(radius: 20)
            if let footer {
                footer
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .contentTransition(.opacity)
            }
        }
    }
}

// MARK: - Row

/// One setting: its name, an optional line under it, and its control at the trailing edge. An (i)
/// opens the explanation underneath, full width, and closes it again. In an editor that overrides
/// another level (a chat over a persona over the defaults), a dot marks a value set here, with
/// Inherit beside it to go back. `below` holds anything wider than the row (a slider, a picker).
struct SettingRow<Control: View, Below: View>: View {
    let title: String
    var detail: String? = nil
    var help: String? = nil
    var overridden = false
    var onInherit: (() -> Void)? = nil
    let control: Control
    let below: Below
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, detail: String? = nil, help: String? = nil, overridden: Bool = false,
         onInherit: (() -> Void)? = nil, @ViewBuilder control: () -> Control, @ViewBuilder below: () -> Below) {
        self.title = title
        self.detail = detail
        self.help = help
        self.overridden = overridden
        self.onInherit = onInherit
        self.control = control()
        self.below = below()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if overridden {
                            Circle()
                                .fill(Color.qAccent)
                                .frame(width: 6, height: 6)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityLabel("Set here")
                        }
                        Text(title)
                            .foregroundStyle(Color.qInk)
                        if help != nil { infoButton }
                    }
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(2)
                            .contentTransition(.opacity)
                    }
                }
                Spacer(minLength: 8)
                if overridden, let onInherit {
                    InheritButton(action: onInherit)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                control
            }
            below
            if open, let help {
                Text(help)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.qSunken, in: .rect(cornerRadius: 12, style: .continuous))
                    // Fades in a beat behind the space opening for it, and out ahead of it closing.
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -3)).animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.26).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .padding(.vertical, 13)
        .animation(Motion.quick, value: overridden)
    }

    /// Opens or closes the explanation inside one transaction, so the row, the rows under it and
    /// the card around them all move together.
    private var infoButton: some View {
        Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.reveal) { open.toggle() }
        } label: {
            Image(systemName: "info.circle")
                .symbolVariant(open ? .fill : .none)
                .font(.footnote.weight(.medium))
                .foregroundStyle(open ? Color.qAccent : Color.qInk2)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, -6)
        .accessibilityLabel("About \(title)")
        .accessibilityHint(open ? "Hides the explanation" : "Explains this setting")
    }
}

extension SettingRow where Below == EmptyView {
    init(_ title: String, detail: String? = nil, help: String? = nil, overridden: Bool = false,
         onInherit: (() -> Void)? = nil, @ViewBuilder control: () -> Control) {
        self.init(title, detail: detail, help: help, overridden: overridden, onInherit: onInherit,
                  control: control, below: { EmptyView() })
    }
}

/// "Inherit": go back to the value from the level above.
struct InheritButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.quick) { action() }
        } label: {
            Label("Inherit", systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.qAccent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.qAccentSoft, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Goes back to the inherited value")
    }
}

/// A row that goes somewhere: its name, a value or detail, and a chevron.
struct LinkRow: View {
    let title: String
    var detail: String? = nil
    var value: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.qInk)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.qInk2)
        }
        .padding(.vertical, 13)
        .contentShape(.rect)
    }
}

/// Press feedback for a row inside a card: a quick dim, nothing that moves the layout.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == RowPressStyle {
    static var row: RowPressStyle { RowPressStyle() }
}

// MARK: - Slider

/// A slider in Quire's own manner: a slim track, the stretch from its neutral point filled in the
/// accent (from the middle for a penalty, from the start otherwise), a tick where the inherited
/// or default value sits, and a thumb that grows a little under the finger. It moves only for a
/// sideways drag, so a page still scrolls over it; a tap on the track jumps there; the thumb clicks
/// into the tick and the ends. VoiceOver adjusts it a step at a time.
struct ParamSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var neutral: Double? = nil
    var mark: Double? = nil
    var ends: (String, String)? = nil
    let label: String
    var format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...2))) }
    @State private var width: CGFloat = 1
    @State private var start: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let thumb: CGFloat = 26

    var body: some View {
        VStack(spacing: 6) {
            track
            if let ends {
                HStack {
                    Text(ends.0)
                    Spacer()
                    Text(ends.1)
                }
                .font(.caption2)
                .foregroundStyle(Color.qInk2)
                .accessibilityHidden(true)
            }
        }
    }

    private var track: some View {
        let travel = max(1, width - thumb)
        let at = { (v: Double) -> CGFloat in thumb / 2 + CGFloat(fraction(v)) * travel }
        let x = at(value)
        let from = neutral.map(at) ?? 0
        let active = start != nil
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.qSunken)
                .frame(height: 6)
            Capsule()
                .fill(Color.qAccent)
                .frame(width: max(0, abs(x - from)), height: 6)
                .offset(x: min(x, from))
            if let mark {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.qInk2.opacity(0.55))
                    .frame(width: 2, height: 14)
                    .offset(x: at(mark) - 1)
            }
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.22), radius: active ? 5 : 3, y: 1.5)
                .frame(width: thumb, height: thumb)
                .scaleEffect(active ? 1.12 : 1)
                .offset(x: x - thumb / 2)
                .animation(reduceMotion ? nil : Motion.press, value: active)
        }
        .frame(height: thumb + 6)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
        .gesture(SpatialTapGesture().onEnded { tap in
            let f = Double((tap.location.x - thumb / 2) / travel)
            set(range.lowerBound + f * (range.upperBound - range.lowerBound), animated: true)
        })
        .gesture(SidewaysPan { phase, dx in
            switch phase {
            case .began:
                start = value
            case .changed:
                guard let start else { return }
                let span = range.upperBound - range.lowerBound
                set(start + Double(dx / travel) * span, animated: false)
            case .ended:
                start = nil
            }
        })
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + step, animated: true)
            case .decrement: set(value - step, animated: true)
            @unknown default: break
            }
        }
    }

    private func fraction(_ v: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (v - range.lowerBound) / span))
    }

    /// Snaps to the step, clamps to the range, and clicks into the tick and the ends.
    private func set(_ raw: Double, animated: Bool) {
        let snapped = ((raw / step).rounded() * step * 10_000).rounded() / 10_000
        let next = min(range.upperBound, max(range.lowerBound, snapped))
        guard next != value else { return }
        let detents = [range.lowerBound, range.upperBound] + (mark.map { [$0] } ?? [])
        if detents.contains(where: { abs($0 - next) < step / 2 }) { Haptics.selection() }
        if animated && !reduceMotion {
            withAnimation(Motion.quick) { value = next }
        } else {
            value = next
        }
    }
}

/// A pan that begins only when the finger moves sideways, so the page around it still scrolls
/// for anything steeper. The page's scrolling waits for it to decide, which takes a few points.
struct SidewaysPan: UIGestureRecognizerRepresentable {
    enum Phase { case began, changed, ended }
    let onChange: (Phase, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> SidewaysPanRecognizer {
        let pan = SidewaysPanRecognizer()
        pan.maximumNumberOfTouches = 1
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: SidewaysPanRecognizer, context: Context) {
        let dx = pan.translation(in: pan.view).x
        switch pan.state {
        case .began: onChange(.began, dx)
        case .changed: onChange(.changed, dx)
        case .ended, .cancelled, .failed: onChange(.ended, dx)
        default: break
        }
    }
}

/// Gives up as soon as a touch moves more up or down than across, and asks scroll views to wait
/// for that decision. Built into the recognizer rather than a delegate, so nothing can unset it.
final class SidewaysPanRecognizer: UIPanGestureRecognizer {
    private var origin: CGPoint?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if origin == nil { origin = touches.first?.location(in: view) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let origin, let point = touches.first?.location(in: view) {
            let dx = abs(point.x - origin.x), dy = abs(point.y - origin.y)
            if max(dx, dy) > 4 && dy > dx {
                state = .failed
                return
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        origin = nil
    }

    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer && other.view is UIScrollView
    }
}

// MARK: - Choices

/// A row of choices in a sunken well, the chosen one lifted out in the accent, sliding between
/// them as you choose. For the few-options settings (mode, density, reply face).
struct ChoiceStrip<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var label: String = ""
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.select) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.qOnAccent : Color.qInk2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if on {
                                Capsule()
                                    .fill(Color.qAccent)
                                    .matchedGeometryEffect(id: "choice", in: ns)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.qSunken, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}
