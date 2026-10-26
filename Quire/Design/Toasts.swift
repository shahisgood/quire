import SwiftUI
import UIKit

// MARK: - Window

/// Toasts float in a window of their own, above the app and anything it presents. The window
/// takes a touch only where a toast is actually drawn, so everything else passes straight through
/// to the app underneath, and a tap on Undo can never land on the button behind it.
final class ToastWindow: UIWindow {
    private static var shared: ToastWindow?

    /// The toast's frame in this window; empty while there's none.
    var hitFrame: CGRect = .zero

    static func install(app: AppModel) {
        guard shared == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let window = ToastWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: AnyView(ToastHost(window: window).environment(app)))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        shared = window
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !hitFrame.isEmpty, hitFrame.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// The window's content: the app's toasts, in the app's theme, mode and typeface.
private struct ToastHost: View {
    let window: ToastWindow
    @Environment(AppModel.self) private var app

    var body: some View {
        ToastOverlay(center: app.toasts) { window.hitFrame = $0 }
            .environment(\.displayDesign, app.settings.ui.typeface.design)
            .fontDesign(app.settings.ui.typeface.interfaceDesign)
            .tint(Color.qAccent)
            .preferredColorScheme(app.settings.ui.theme.colorScheme)
    }
}

// MARK: - Toast

/// A toast drops in under the Dynamic Island: what happened, and the one thing you can do about it.
/// A ring around its icon runs down the time left; dragging it holds the clock, and a flick up
/// sends it away. Undo is a real button, and confirms itself once it's done.
struct ToastOverlay: View {
    let center: ToastCenter
    var onFrame: (CGRect) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let t = center.current {
                ToastCard(toast: t, center: center)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onFrame($0) }
                    .transition(reduceMotion ? .opacity : .toast)
                    .id(t.id)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.8),
                   value: center.current)
        .onChange(of: center.current == nil) { _, gone in if gone { onFrame(.zero) } }
    }
}

private struct ToastCard: View {
    let toast: ToastCenter.Toast
    let center: ToastCenter
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            badge
            Text(toast.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.qInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let label = toast.actionLabel {
                Button {
                    Haptics.tap()
                    center.runAction()
                } label: {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qOnAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Color.qAccent, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityHint(label == "Undo" ? "Reverses what just happened" : "")
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, toast.actionLabel == nil ? 18 : 9)
        .padding(.vertical, 8)
        .frame(minHeight: 54)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .frame(maxWidth: 460)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        // Up moves freely; down gives a little and springs back.
        .offset(y: drag < 0 ? drag : drag / 5)
        .gesture(swipe)
        .onTapGesture {
            if toast.tapRunsAction { center.runAction() } else { center.dismiss() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { center.dismiss() }
    }

    /// The symbol, ringed by the time left when there's something to act on.
    private var badge: some View {
        ZStack {
            Circle().fill(Color.qAccentSoft)
            if toast.actionLabel != nil {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: center.isHeld)) { context in
                    let left = center.remaining(at: context.date) / max(toast.duration, 0.1)
                    Circle()
                        .trim(from: 0, to: min(1, max(0, left)))
                        .stroke(Color.qAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1)
                }
            }
            Image(systemName: toast.symbol ?? "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.qAccent)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                center.hold()
                drag = v.translation.height
            }
            .onEnded { v in
                if v.translation.height < -24 || v.predictedEndTranslation.height < -90 {
                    Haptics.selection()
                    center.dismiss()
                } else {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.bouncy) { drag = 0 }
                    center.release()
                }
            }
    }
}

extension AnyTransition {
    /// Drops in from the top with a little give; leaves the way it came, a touch quicker.
    static var toast: AnyTransition {
        .asymmetric(insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .top)),
                    removal: .move(edge: .top).combined(with: .opacity))
    }
}
