import ActivityKit
import Foundation
import UIKit

/// Starts, feeds and ends the Live Activity for replies in progress: one per chat with a reply in
/// flight. ActivityKit only lets an app start one while it's in the foreground, so each reply gets
/// its activity as it starts. While Quire is on screen the system keeps it out of the Dynamic
/// Island, and a reply that finishes there ends it at once, so it's only ever seen after you leave.
final class ReplyActivities {
    static let shared = ReplyActivities()

    private var live: [String: Activity<ReplyActivityAttributes>] = [:]
    private var states: [String: ReplyActivityAttributes.ContentState] = [:]
    private var lastPush: [String: Date] = [:]

    func start(chatId: String, title: String, model: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let old = live.removeValue(forKey: chatId) {
            Task { await old.end(nil, dismissalPolicy: .immediate) }
        }
        let state = ReplyActivityAttributes.ContentState(phase: .waiting, title: title, tokens: 0, snippet: "",
                                                         startedAt: Date(), endedAt: nil)
        do {
            let activity = try Activity.request(attributes: ReplyActivityAttributes(chatId: chatId, model: model),
                                                content: ActivityContent(state: state, staleDate: nil),
                                                pushType: nil)
            live[chatId] = activity
            states[chatId] = state
            lastPush[chatId] = Date()
        } catch {
            // Not allowed right now (switched off, or too many running): the reply carries on without.
        }
    }

    /// Called as text streams in; sends at most about once a second, or at once when the phase changes.
    func update(chatId: String, phase: ReplyPhase, title: String, tokens: Int, text: String) {
        guard let activity = live[chatId], var state = states[chatId] else { return }
        let now = Date()
        if state.phase == phase, let last = lastPush[chatId], now.timeIntervalSince(last) < 1 { return }
        state.phase = phase
        state.title = title
        state.tokens = tokens
        state.snippet = Self.snippet(text)
        states[chatId] = state
        lastPush[chatId] = now
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.update(content) }
    }

    /// The reply is over. In Quire it goes at once; otherwise the outcome stays on the Lock Screen
    /// for half an hour (or until you come back), and a tap opens the chat.
    func end(chatId: String, phase: ReplyPhase, title: String, tokens: Int, text: String) {
        guard let activity = live.removeValue(forKey: chatId), var state = states.removeValue(forKey: chatId) else { return }
        lastPush[chatId] = nil
        state.phase = phase
        state.title = title
        state.tokens = tokens
        state.snippet = Self.snippet(text)
        state.endedAt = Date()
        let inForeground = UIApplication.shared.applicationState == .active
        let policy: ActivityUIDismissalPolicy = inForeground ? .immediate : .after(Date().addingTimeInterval(30 * 60))
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// Back in Quire: clears finished replies from the Lock Screen, and anything left over from a
    /// previous run. Replies still being written keep theirs.
    func dismissFinished() {
        let running = Set(live.values.map(\.id))
        for activity in Activity<ReplyActivityAttributes>.activities where !running.contains(activity.id) {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// The last stretch of the reply, flattened to one line.
    private static func snippet(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let flat = TextUtil.stripMarkdown(String(text.suffix(600)), max: 2000)
        return flat.count > 140 ? "…" + String(flat.suffix(140)) : flat
    }
}
