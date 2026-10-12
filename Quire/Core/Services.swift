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
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    private(set) var current: Toast? = nil
    @ObservationIgnored private var action: (() -> Void)? = nil
    @ObservationIgnored private var dismissTask: Task<Void, Never>? = nil

    func show(_ text: String, symbol: String? = nil, action: (label: String, run: () -> Void)? = nil) {
        dismissTask?.cancel()
        self.action = action?.run
        current = Toast(text: text, symbol: symbol, actionLabel: action?.label)
        UIAccessibility.post(notification: .announcement, argument: text)
        let seconds: Double = action == nil ? 2.2 : 5
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func runAction() {
        let a = action
        dismiss()
        a?()
    }

    func dismiss() {
        dismissTask?.cancel()
        action = nil
        current = nil
    }
}
