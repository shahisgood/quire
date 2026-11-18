import SwiftUI

// Quire's own small windows: the ones a chat opens from its controls (attach and the model from the
// message box, the context from the ring in the bar), drawn in the app's glass rather than as a
// system menu. Each grows out of the control that opened it and goes back into it; a tap outside,
// a swipe back the way it came, or VoiceOver's escape closes it. They open many times a day, so
// they're quick, never bounce on a tap, and their contents arrive with them rather than after.

// MARK: - State

/// The windows a chat can open.
nonisolated enum ChatPanel: Equatable, Sendable {
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
struct PanelLayer<Content: View>: View {
    let panel: ChatPanel?
    let close: () -> Void
    @ViewBuilder let content: (ChatPanel) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: panel?.fromTop == true ? .topTrailing : .bottomLeading) {
                if panel != nil {
                    Color.black.opacity(0.16)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture(perform: close)
                        .transition(.opacity.animation(.easeOut(duration: 0.18)))
                        .accessibilityHidden(true)
                }
                if let panel {
                    PanelCard(panel: panel, maxHeight: max(160, geo.size.height - Space.xl), onClose: close) {
                        content(panel)
                    }
                    .padding(.horizontal, Space.m)
                    .padding(panel.fromTop ? .top : .bottom, Space.s)
                    .transition(.panel(from: panel.anchor, reduceMotion: reduceMotion))
                    .id(panel)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: panel?.fromTop == true ? .topTrailing : .bottomLeading)
        }
        .allowsHitTesting(panel != nil)
    }
}

// MARK: - Card

/// The window: glass with a hairline, as tall as what's in it up to the room there is, scrolling
/// past that. While a finger drags it back toward where it came from, it follows; let go far or
/// fast enough and it closes, otherwise it springs home.
struct PanelCard<Content: View>: View {
    let panel: ChatPanel
    let maxHeight: CGFloat
    let onClose: () -> Void
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0
    @State private var drag: CGFloat = 0
    @AccessibilityFocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.panel, style: .continuous) }
    /// Positive is back toward where it came from.
    private var direction: CGFloat { panel.fromTop ? -1 : 1 }

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { new in
                    // The first measure sets it; later ones (a page sliding in) ease to it.
                    if height == 0 || reduceMotion { height = new }
                    else { withAnimation(.spring(duration: 0.3, bounce: 0)) { height = new } }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // Only scrolls when there's more than fits, so a swipe on a short window moves the window.
        .scrollDisabled(height <= maxHeight)
        .frame(height: min(max(height, 1), maxHeight))
        .frame(maxWidth: 440)
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .overlay {
            shape.strokeBorder(Color.qInk.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.14), radius: 28, y: panel.fromTop ? 14 : 10)
        .offset(y: offset)
        .gesture(swipe)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(panel.title)
        .accessibilityFocused($focused)
        .accessibilityAction(.escape, onClose)
        .onAppear { focused = true }
    }

    /// Toward home it follows the finger; the other way it gives a little and resists.
    private var offset: CGFloat {
        let toward = drag * direction
        if toward >= 0 { return drag }
        let c: CGFloat = 0.55, limit: CGFloat = 24
        return direction * -(abs(toward) * limit * c / (limit + c * abs(toward)))
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { drag = $0.translation.height }
            .onEnded { v in
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

// MARK: - Motion

/// Grows from the corner of the control that opened it, from a little smaller and clear, so it
/// reads as coming out of that control; leaves the same way, quicker and with less travel.
private struct PanelEmergence: ViewModifier {
    let shown: Bool
    let anchor: UnitPoint
    let leaving: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : (leaving ? 0.97 : 0.92), anchor: anchor)
            .opacity(shown ? 1 : 0)
    }
}

extension AnyTransition {
    static func panel(from anchor: UnitPoint, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity.animation(.easeOut(duration: 0.15)) }
        return .asymmetric(
            insertion: .modifier(active: PanelEmergence(shown: false, anchor: anchor, leaving: false),
                                 identity: PanelEmergence(shown: true, anchor: anchor, leaving: false))
                .animation(.spring(duration: 0.28, bounce: 0)),
            removal: .modifier(active: PanelEmergence(shown: false, anchor: anchor, leaving: true),
                               identity: PanelEmergence(shown: true, anchor: anchor, leaving: true))
                .animation(.smooth(duration: 0.17)))
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
                leading
                    .frame(width: 28)
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
