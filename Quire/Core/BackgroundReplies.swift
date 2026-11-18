import BackgroundTasks
import UIKit

/// Keeps a reply being written after you leave Quire. On its own, iOS gives an app half a minute
/// once it's in the background; a reply can take longer than that, a thinking model far longer. So
/// as a reply starts (you've just sent it, which is what the system asks for) it also asks for a
/// continued-processing task, which lets the reply carry on in the background with a card on the
/// Lock Screen and in the Dynamic Island showing it going, where you can stop it. When the system
/// won't give one, the half minute is still there.
///
/// Each reply gets an identifier of its own (a reply carried on from where it stopped is a new run),
/// since one can only be registered once. The system may hand the task over after a short reply
/// has already finished; then it's completed the moment it arrives, so no card is left behind.
@MainActor
final class BackgroundReplies {
    static let shared = BackgroundReplies()

    private final class Run {
        var task: BGContinuedProcessingTask? = nil
        var finished = false
        var succeeded = false
        var thinking = true
        var words = 0
        var lastSubtitle = Date.distantPast
        var heartbeat: Task<Void, Never>? = nil
        let title: String
        let model: String
        let onStop: () -> Void

        init(title: String, model: String, onStop: @escaping () -> Void) {
            self.title = title
            self.model = model
            self.onStop = onStop
        }
    }

    private var runs: [String: Run] = [:]

    /// Read from `BGTaskSchedulerPermittedIdentifiers` in the Info.plist itself (its `….reply.*`
    /// entry, without the star), so a run's identifier always matches what shipped, even when an
    /// installer has changed the bundle identifier since.
    private static let prefix: String? = {
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        guard let pattern = permitted.first(where: { $0.hasSuffix(".reply.*") }) else { return nil }
        return String(pattern.dropLast())
    }()

    /// Asks for a run for a reply that's starting. Returns its id to report progress against, or nil
    /// when there's none to be had (Quire isn't in front, the system said no).
    /// `chat` is the title the card shows; nil keeps it private (an incognito chat).
    func begin(chat: String?, model: String, onStop: @escaping () -> Void) -> String? {
        guard UIApplication.shared.applicationState == .active, let prefix = Self.prefix else { return nil }
        let id = UUID().uuidString.lowercased()
        let identifier = prefix + id
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            BackgroundReplies.shared.arrived(task, id: id)
        }
        guard registered else { return nil }
        let title = chat.flatMap { $0.isEmpty || $0 == "New chat" ? nil : $0 } ?? "Writing a reply"
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "\(model) · starting")
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            return nil
        }
        runs[id] = Run(title: title, model: model, onStop: onStop)
        return id
    }

    /// Whether the system has handed this run's task over, so the reply may outlast the half minute.
    func isRunning(_ id: String?) -> Bool {
        guard let id else { return false }
        return runs[id]?.task != nil
    }

    /// How far the reply has got, in characters of text and thinking. Replies have no known
    /// length, so the bar climbs steeply at first and ever more slowly, never quite arriving until
    /// the reply has.
    func progress(_ id: String?, written: Int, words: Int, thinking: Bool) {
        guard let id, let run = runs[id] else { return }
        run.thinking = thinking
        run.words = words
        guard let task = run.task else { return }
        let f = 1 - exp(-Double(written) / 9000)
        let units = Int64(20 + f * 960)
        if units > task.progress.completedUnitCount { task.progress.completedUnitCount = units }
        let now = Date()
        if now.timeIntervalSince(run.lastSubtitle) > 1 {
            run.lastSubtitle = now
            task.updateTitle(run.title, subtitle: subtitle(run))
        }
    }

    /// The reply has ended, well or not.
    func end(_ id: String?, success: Bool) {
        guard let id, let run = runs[id], !run.finished else { return }
        run.finished = true
        run.succeeded = success
        run.heartbeat?.cancel()
        if let task = run.task {
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.updateTitle(run.title, subtitle: success ? "\(run.model) · done" : "\(run.model) · stopped")
            task.setTaskCompleted(success: success)
            runs[id] = nil
        } else {
            // Not handed over yet: completed when it is. Forgotten if it never is.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                if self?.runs[id]?.task == nil { self?.runs[id] = nil }
            }
        }
    }

    // MARK: The system's side

    private func arrived(_ task: BGTask, id: String) {
        guard let task = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }
        guard let run = runs[id], !run.finished else {
            task.setTaskCompleted(success: runs[id]?.succeeded ?? true)
            runs[id] = nil
            return
        }
        run.task = task
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = 20
        task.expirationHandler = Self.expiry(id)
        task.updateTitle(run.title, subtitle: subtitle(run))
        // A model thinking without a word to show still moves the bar, slowly, so the system
        // doesn't take silence for being stuck.
        run.heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, let t = self.runs[id]?.task else { return }
                if t.progress.completedUnitCount < 980 { t.progress.completedUnitCount += 1 }
            }
        }
    }

    /// The expiration handler can be called from any queue; it hops to the main actor itself.
    nonisolated private static func expiry(_ id: String) -> () -> Void {
        return {
            Task { @MainActor in BackgroundReplies.shared.expired(id) }
        }
    }

    /// Stopped from its card, or by the system needing the room: the reply stops where it is, and
    /// what it has written is kept.
    private func expired(_ id: String) {
        guard let run = runs[id] else { return }
        runs[id] = nil
        run.heartbeat?.cancel()
        run.task?.setTaskCompleted(success: false)
        if !run.finished { run.onStop() }
    }

    private func subtitle(_ run: Run) -> String {
        if run.words == 0 { return run.thinking ? "\(run.model) · thinking" : "\(run.model) · starting" }
        return "\(run.model) · \(run.words.formatted()) words"
    }
}
