import Foundation
import Network
import Observation
import UIKit

/// Online/offline, from the system's network path monitor.
@Observable
final class Connectivity {
    private(set) var online = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor [weak self] in
                if self?.online != ok { self?.online = ok }
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.quire.network"))
    }
}

/// Haptics, gated by the user's setting. Each call is one short, specific signal.
enum Haptics {
    static var enabled = true

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
    }

    static func selection() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Short confirmations at the top of the screen, with an optional action ("Undo").
@Observable
final class ToastCenter {
    nonisolated struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var symbol: String?
        var actionLabel: String?
        /// Tapping the toast itself runs the action ("Open"). For Undo it only dismisses, so a tap
        /// meant for something else can't undo by accident.
        var tapRunsAction: Bool
        /// How long it stays, in seconds, if left alone.
        var duration: Double
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    private(set) var current: Toast? = nil
    /// When the current toast leaves, unless it's held.
    private(set) var endsAt = Date.distantFuture
    /// Time left while it's held (dragged), so the countdown stops where it was.
    private(set) var heldRemaining: Double? = nil
    @ObservationIgnored private var action: (() -> Void)? = nil
    @ObservationIgnored private var dismissTask: Task<Void, Never>? = nil

    var isHeld: Bool { heldRemaining != nil }

    func show(_ text: String, symbol: String? = nil, action: (label: String, run: () -> Void)? = nil,
              tapRunsAction: Bool = false) {
        dismissTask?.cancel()
        self.action = action?.run
        // Anything you can act on stays long enough to read and reach; longer with VoiceOver.
        var seconds: Double = action == nil ? 2.4 : 6
        if UIAccessibility.isVoiceOverRunning { seconds *= 2 }
        current = Toast(text: text, symbol: symbol, actionLabel: action?.label, tapRunsAction: tapRunsAction, duration: seconds)
        heldRemaining = nil
        endsAt = Date().addingTimeInterval(seconds)
        UIAccessibility.post(notification: .announcement, argument: action.map { "\(text). \($0.label) available." } ?? text)
        schedule(seconds)
    }

    /// Seconds left before it goes.
    func remaining(at date: Date) -> Double {
        heldRemaining ?? max(0, endsAt.timeIntervalSince(date))
    }

    func hold() {
        guard current != nil, heldRemaining == nil else { return }
        dismissTask?.cancel()
        heldRemaining = max(0, endsAt.timeIntervalSinceNow)
    }

    func release() {
        guard let left = heldRemaining else { return }
        heldRemaining = nil
        // Never snatch it away the moment you let go.
        let seconds = max(left, 1.2)
        endsAt = Date().addingTimeInterval(seconds)
        schedule(seconds)
    }

    func runAction() {
        let run = action
        let undo = current?.actionLabel == "Undo"
        dismiss()
        run?()
        if undo { show("Undone", symbol: "arrow.uturn.backward") }
    }

    func dismiss() {
        dismissTask?.cancel()
        action = nil
        heldRemaining = nil
        current = nil
    }

    private func schedule(_ seconds: Double) {
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
