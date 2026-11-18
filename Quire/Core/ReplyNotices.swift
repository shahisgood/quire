import UIKit
import UserNotifications

/// "Reply ready" notifications, for a reply that finishes while you're away from Quire (it can
/// now carry on in the background; see `BackgroundReplies`). Off until you turn it on in Settings,
/// which is when iOS asks.
enum ReplyNotices {
    /// Asks iOS, the first time; afterwards, says what was decided.
    static func authorize() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// One notice per chat: a newer reply in the same chat replaces the older one.
    static func post(chatId: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "Reply ready" : title
        content.body = body.isEmpty ? "Your reply is ready." : body
        content.sound = .default
        content.threadIdentifier = chatId
        content.userInfo = ["chat": chatId]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "reply.\(chatId)", content: content, trigger: nil))
    }
}

/// Opens the chat a tapped notice is about, by way of the same queue the Home Screen's quick
/// actions use, so it works whether Quire was running or not. While you're in Quire, notices
/// aren't shown at all: the toast says it there.
final class ReplyNoticeDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReplyNoticeDelegate()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["chat"] as? String else { return }
        await MainActor.run { QuickActions.shared.pending = .open(chatId: id) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        []
    }
}
