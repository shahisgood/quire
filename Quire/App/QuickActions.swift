import Observation
import SwiftUI
import UIKit

/// Home Screen quick actions (press and hold the icon). New chat and Incognito chat are fixed in
/// Info.plist; up to two recent chats are offered as well, refreshed each time Quire goes to the
/// background.
enum QuickAction: Equatable {
    case newChat
    case incognito
    case open(chatId: String)

    static let newChatType = "app.quire.new"
    static let incognitoType = "app.quire.incognito"
    static let chatType = "app.quire.chat"

    init?(_ item: UIApplicationShortcutItem) {
        switch item.type {
        case Self.newChatType: self = .newChat
        case Self.incognitoType: self = .incognito
        case Self.chatType:
            guard let id = item.userInfo?["id"] as? String else { return nil }
            self = .open(chatId: id)
        default: return nil
        }
    }
}

/// Where a chosen action waits until the interface is ready to act on it (at a cold launch it
/// arrives before any view exists).
@Observable
final class QuickActions {
    static let shared = QuickActions()
    var pending: QuickAction? = nil

    /// The two most recent chats with real names, as "Continue" actions.
    static func refresh(chats: [Chat]) {
        let recent = chats
            .filter { !$0.archived && $0.title != "New chat" }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(2)
        UIApplication.shared.shortcutItems = recent.map { c in
            UIApplicationShortcutItem(type: QuickAction.chatType,
                                      localizedTitle: c.title,
                                      localizedSubtitle: "Continue",
                                      icon: UIApplicationShortcutIcon(systemImageName: "text.bubble"),
                                      userInfo: ["id": c.id as NSString])
        }
    }
}

/// Picks up a quick action used to launch Quire, and installs the scene delegate that receives the
/// ones used while it's already running.
final class QuireAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { QuickActions.shared.pending = QuickAction(item) }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuireSceneDelegate.self
        return config
    }
}

final class QuireSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let action = QuickAction(shortcutItem)
        QuickActions.shared.pending = action
        completionHandler(action != nil)
    }
}
