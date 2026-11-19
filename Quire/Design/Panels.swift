import SwiftUI
import UIKit

// Quire's own small windows: the ones a chat opens from its controls (attach and the model from the
// message box, the context from the ring in the bar), drawn in the app's glass rather than as a
// system menu. Each grows out of the control that opened it and goes back into it; a tap outside,
// a swipe back the way it came, or VoiceOver's escape closes it. They open many times a day, so
// they're quick, never bounce on a tap, and their contents arrive with them rather than after.

// MARK: - State

/// The windows a chat can open.
nonisolated enum ChatPanel: Hashable, Sendable {
    case attach, model, context

    /// Where it opens from: the message box's corner, or the bar's.
    var fromTop: Bool { self == .context }

    /// The corner it grows out of, nearest the control that opened it.
    var anchor: UnitPoint { fromTop ? .topTrailing : .bottomLeading }

    var title: String {
        switch self {
        case .attach: "Attach"
        case .model: "Model"
        case .context: "Context"
        }
    }
}

/// What the attach window asks the message box to do, once it has closed.
nonisolated enum AttachRequest: Equatable, Sendable {
    case photos, camera, files, paste
    /// One of the recent photos, by its library identifier.
    case asset(String)
}

/// Shared by the chat screen, which draws the windows, and the message box, which opens them and
/// carries out what they ask.
@Observable
final class ChatPanels {
    var open: ChatPanel? = nil
    /// Where each window's button is on screen, in global coordinates, for the window to grow out
    /// of. Kept out of observation: it changes as the message box moves, and nothing redraws for it.
    @ObservationIgnored var origins: [ChatPanel: CGRect] = [:]
    /// Set by the attach window; the message box takes it and clears it.
    var request: AttachRequest? = nil

    func toggle(_ panel: ChatPanel) {
        open = open == panel ? nil : panel
    }

    func close() { open = nil }

    /// Closes the window and hands the message box something to do.
    func ask(_ r: AttachRequest) {
        open = nil
        request = r
    }
}

// MARK: - Layer

/// The chat-wide layer the windows live in: a light veil over the conversation (tap it to close),
/// and the window itself, in the corner its control is in. Sits inside the chat's safe area, so a
/// window from the message box rests just above it and one from the bar just below that.
///
/// A window doesn't fade in over the chat: it grows out of the button that opened it. The glass
/// starts the button's own size, where the button is, and unfurls to the window on a spring with a
/// breath of give at the end, its contents rising out of that corner as it goes, so the button
/// reads as having opened into it. Closing, it folds straight back into the button, quicker and
/// without the give. One value, `progress`, drives the glass, the contents and the veil, so they
/// can never drift apart, and a close caught mid-open turns round from wherever it is.
struct PanelLayer<Content: View>: View {
    let panels: ChatPanels
    @ViewBuilder let content: (ChatPanel) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The window on screen: kept through its closing, after `panels.open` has let it go.
    @State private var shown: ChatPanel? = nil
    /// 0 folded into its button, 1 open.
    @State private var progress: CGFloat = 0
    /// Counts openings and closings, so a close that finishes late can't remove a newer window.
    @State private var turn = 0

    private var opening: Animation { reduceMotion ? .easeOut(duration: 0.18) : .spring(duration: 0.42, bounce: 0.14) }
    private var closing: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.26, bounce: 0) }

    var body: some View {
        GeometryReader { geo in
            let alignment: Alignment = shown?.fromTop == true ? .topTrailing : .bottomLeading
            ZStack(alignment: alignment) {
                Color.black.opacity(0.16 * min(1, max(0, progress)))
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { panels.close() }
                    .allowsHitTesting(panels.open != nil)
                    .accessibilityHidden(true)
                if let shown {
                    // Always leaves a band of veil to tap, even with the keyboard up.
                    PanelCard(panel: shown,
                              width: min(440, geo.size.width - 2 * Space.m),
                              maxHeight: max(160, geo.size.height - 56),
                              progress: progress,
                              seed: seed(for: shown, in: geo.frame(in: .global)),
                              onClose: panels.close,
                              onReady: { withAnimation(opening) { progress = 1 } }) {
                        content(shown)
                    }
                    .padding(.horizontal, Space.m)
                    .padding(shown.fromTop ? .top : .bottom, Space.s)
                    .id(shown)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
        }
        .allowsHitTesting(shown != nil)
        .onChange(of: panels.open) { _, open in present(open) }
    }

    private func present(_ open: ChatPanel?) {
        turn += 1
        let mine = turn
        if let open {
            guard open != shown else {
                withAnimation(opening) { progress = 1 }
                return
            }
            // A new window (or one in place of another) starts folded; it unfurls once its
            // contents have been measured (see `PanelCard.onReady`).
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                progress = 0
                shown = open
            }
        } else {
            withAnimation(closing) { progress = 0 } completion: {
                if turn == mine { shown = nil }
            }
        }
    }

    /// Where the window's button is, relative to the corner the window grows from: the bottom-left
    /// corner of the message box's buttons, the top-right corner of the bar's ring, each as an
    /// offset from that corner of the window, with the button's size.
    private func seed(for panel: ChatPanel, in layer: CGRect) -> PanelSeed? {
        guard let button = panels.origins[panel], !button.isEmpty, !reduceMotion else { return nil }
        if panel.fromTop {
            let corner = CGPoint(x: layer.maxX - Space.m, y: layer.minY + Space.s)
            return PanelSeed(size: button.size, dx: button.maxX - corner.x, dy: button.minY - corner.y)
        }
        let corner = CGPoint(x: layer.minX + Space.m, y: layer.maxY - Space.s)
        return PanelSeed(size: button.size, dx: button.minX - corner.x, dy: button.maxY - corner.y)
    }
}

/// The button a window grows out of: its size, and how far its corner sits from the window's.
struct PanelSeed: Equatable {
    var size: CGSize
    var dx: CGFloat
    var dy: CGFloat
}

// MARK: - Card

/// The window: glass with a hairline, as tall as what's in it up to the room there is, scrolling
/// past that. Its contents are laid out at their full size from the start and the glass opens
/// over them, so nothing reflows as it grows. While a finger drags it back toward where it came
/// from, it follows; let go far or fast enough and it closes, otherwise it springs home.
struct PanelCard<Content: View>: View {
    let panel: ChatPanel
    let width: CGFloat
    let maxHeight: CGFloat
    let progress: CGFloat
    let seed: PanelSeed?
    let onClose: () -> Void
    /// Called once the contents have been measured, which is when the window can unfurl to them.
    let onReady: () -> Void
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0
    @State private var drag: CGFloat = 0
    /// Decided by a drag's first move: up or down, or sideways.
    @State private var vertical: Bool? = nil
    @AccessibilityFocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Positive is back toward where it came from.
    private var direction: CGFloat { panel.fromTop ? -1 : 1 }
    private var corner: Alignment { panel.fromTop ? .topTrailing : .bottomLeading }
    private var fullHeight: CGFloat { min(max(height, 1), maxHeight) }

    var body: some View {
        let p = progress
        let start = seed?.size ?? CGSize(width: width, height: fullHeight)
        let w = start.width + (width - start.width) * p
        let h = start.height + (fullHeight - start.height) * p
        // From the button's round ends to the window's corners; without a button, the corners
        // stay as they are and only the fade plays.
        let radius = seed == nil ? Radius.panel
            : min(start.width, start.height) / 2 + (Radius.panel - min(start.width, start.height) / 2) * p
        let shape = RoundedRectangle(cornerRadius: max(0, radius), style: .continuous)
        ScrollView {
            content
                // Scrolling inside (the recent photos, sideways) stays on whatever this does.
                .environment(\.isScrollEnabled, true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                    // The first measure sets it, and only then does the window unfurl, so the spring
                    // knows how tall it's going; later ones (a page sliding in) ease to it.
                    if height == 0 {
                        height = new
                        if new > 0 { onReady() }
                    } else if reduceMotion {
                        height = new
                    } else {
                        withAnimation(.spring(duration: 0.3, bounce: 0)) { height = new }
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Only scrolls when there's more than fits, so a swipe on a short window moves the window.
        .scrollDisabled(height <= maxHeight)
        .frame(width: width, height: fullHeight)
        // The contents rise out of the button's corner as the glass opens over them.
        .scaleEffect(seed == nil ? 1 : 0.9 + 0.1 * p, anchor: panel.anchor)
        .opacity(seed == nil ? 1 : p)
        .frame(width: max(1, w), height: max(1, h), alignment: corner)
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .overlay {
            shape.strokeBorder(Color.qInk.opacity(0.08 * p), lineWidth: 1)
                .allowsHitTesting(false)
        }
        // Without a button to grow from (or with Reduce Motion), it simply fades.
        .opacity(seed == nil ? p : 1)
        .offset(x: (seed?.dx ?? 0) * (1 - p), y: (seed?.dy ?? 0) * (1 - p) + dragOffset)
        .frame(width: width, height: fullHeight, alignment: corner)
        .gesture(swipe)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(panel.title)
        .accessibilityFocused($focused)
        .accessibilityAction(.escape, onClose)
        .onAppear { focused = true }
    }

    /// Toward home it follows the finger; the other way it gives a little and resists.
    private var dragOffset: CGFloat {
        let toward = drag * direction
        if toward >= 0 { return drag }
        let c: CGFloat = 0.55, limit: CGFloat = 24
        return direction * -(abs(toward) * limit * c / (limit + c * abs(toward)))
    }

    /// Only a mostly-vertical drag moves the window, so a sideways one is left to what's inside.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                if vertical == nil { vertical = abs(v.translation.height) >= abs(v.translation.width) }
                guard vertical == true else { return }
                drag = v.translation.height
            }
            .onEnded { v in
                defer { vertical = nil }
                guard vertical == true else { return }
                let toward = v.translation.height * direction
                let fling = v.predictedEndTranslation.height * direction
                if toward > 64 || fling > 170 {
                    onClose()
                } else {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.3, bounce: 0.15)) { drag = 0 }
                }
            }
    }
}

// MARK: - Pieces

/// A small heading inside a window.
struct PanelHeading: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(Color.qInk2)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
        }
        .padding(.horizontal, Space.xs)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A big square choice: a symbol over its name, on a quiet tile.
struct PanelTile: View {
    let title: String
    let symbol: String
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .regular))
                    .frame(height: 26)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(dimmed ? Color.qInk2 : Color.qInk)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(Color.qInk.opacity(0.06), in: .rect(cornerRadius: Radius.m, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.m, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityLabel(title)
    }
}

/// A row in a window: a symbol, a name with an optional line under it, and something at the end
/// (a tick, a chevron, a value). Highlights under the finger like a menu row.
struct PanelRow<Leading: View, Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var selected = false
    let action: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                if Leading.self != EmptyView.self {
                    leading
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(selected ? .semibold : .regular))
                        .foregroundStyle(Color.qInk)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(PanelRowStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension PanelRow where Leading == PanelSymbol, Trailing == EmptyView {
    init(_ title: String, symbol: String, detail: String? = nil, selected: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, detail: detail, selected: selected, action: action,
                  leading: { PanelSymbol(name: symbol) }, trailing: { EmptyView() })
    }
}

/// A row's symbol, in the quiet ink.
struct PanelSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Color.qInk2)
            .accessibilityHidden(true)
    }
}

/// A row lights up the moment the finger lands, as a menu's does.
struct PanelRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.qInk.opacity(configuration.isPressed ? 0.08 : 0), in: .rect(cornerRadius: Radius.s, style: .continuous))
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - The bar

/// While one of the chat's windows is open, a tap up in the bar closes it: with the keyboard up
/// there's little veil left to tap, and the bar is where a thumb goes next. The recogniser sits on
/// the navigation controller's view, answers only touches above the bar's bottom edge, and is
/// switched on only while a window is open, so the bar behaves as ever the rest of the time.
struct BarTapCatcher: UIViewRepresentable {
    var active: Bool
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StackSwipes.Probe {
        let probe = StackSwipes.Probe()
        let coordinator = context.coordinator
        probe.onAttach = { [weak coordinator] nav in coordinator?.attach(to: nav) }
        return probe
    }

    func updateUIView(_ probe: StackSwipes.Probe, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.tap.isEnabled = active
    }

    static func dismantleUIView(_ probe: StackSwipes.Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let tap = UITapGestureRecognizer()
        var onTap: () -> Void = {}
        private weak var nav: UINavigationController?

        override init() {
            super.init()
            tap.addTarget(self, action: #selector(tapped))
            tap.delegate = self
            tap.isEnabled = false
        }

        func attach(to nav: UINavigationController) {
            guard self.nav !== nav else { return }
            detach()
            self.nav = nav
            nav.view.addGestureRecognizer(tap)
        }

        func detach() {
            tap.view?.removeGestureRecognizer(tap)
            nav = nil
        }

        @objc private func tapped() { onTap() }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let bar = nav?.navigationBar else { return false }
            return touch.location(in: bar).y <= bar.bounds.maxY
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
