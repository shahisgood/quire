import ActivityKit
import Foundation

/// The Live Activity that follows a reply being written, on the Lock Screen and in the Dynamic
/// Island. Compiled into both the app (which starts, feeds and ends it) and the QuireLive widget
/// extension (which draws it); ActivityKit pairs the two by this type's name.
nonisolated struct ReplyActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var phase: ReplyPhase
        /// The chat's name. It can change mid-reply (the automatic title arrives a moment in).
        var title: String
        /// Output so far, estimated while streaming.
        var tokens: Int
        /// The latest stretch of the reply on one line (empty for incognito chats).
        var snippet: String
        var startedAt: Date
        var endedAt: Date?
    }

    var chatId: String
    var model: String
}

nonisolated enum ReplyPhase: String, Codable, Hashable {
    case waiting, thinking, writing, done, stopped, paused, failed

    var isLive: Bool { self == .waiting || self == .thinking || self == .writing }

    var label: String {
        switch self {
        case .waiting: "Waiting"
        case .thinking: "Thinking"
        case .writing: "Writing"
        case .done: "Reply ready"
        case .stopped: "Stopped"
        case .paused: "Paused"
        case .failed: "Didn't finish"
        }
    }
}
