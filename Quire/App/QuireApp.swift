import SwiftUI

@main
struct QuireApp: App {
    @UIApplicationDelegateAdaptor(QuireAppDelegate.self) private var appDelegate
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        NavigationTypography.apply()
        OpticalSymbol.prepare("square.and.pencil")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.settings.ui.theme.colorScheme)
                .tint(Color.qAccent)
                .onChange(of: app.settings) { app.persistSettings() }
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .background {
                        app.didEnterBackground()
                        QuickActions.refresh(chats: app.chats)
                    }
                    if newPhase == .active { Task { await app.refreshModels() } }
                }
                .task { await app.refreshModels() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawer = SettingsDrawer()

    /// 0 with settings closed, 1 with it covering the chats; follows the finger mid-swipe, either way.
    private var reveal: CGFloat {
        let w = max(drawer.width, 1)
        let r: CGFloat
        if app.settingsOpen { r = 1 + drawer.closing / w }
        else if let opening = drawer.opening { r = opening / w }
        else { r = 0 }
        return min(1, max(0, r))
    }

    /// Settings is on screen while open, and while it's being pulled in over the chats.
    private var settingsShown: Bool { app.settingsOpen || drawer.opening != nil }

    private var settingsOffset: CGFloat {
        app.settingsOpen ? drawer.closing : (drawer.opening ?? 0) - drawer.width
    }

    /// Read as the new value lands: arriving uses `drawerIn`, leaving the quicker `drawerOut`.
    private var layerAnimation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return app.settingsOpen ? Motion.drawerIn : Motion.drawerOut
    }

    var body: some View {
        @Bindable var app = app
        ZStack {
            NavigationStack(path: $app.path) {
                ChatListView()
                    .navigationDestination(for: Route.self) { RouteDestination(route: $0, stack: app.path) }
            }
            .background(Color.qBase.ignoresSafeArea())
            // A push in mirror image: the chats give way a little in the direction settings travels,
            // and dim, so the two layers read as side by side rather than one replacing the other.
            .offset(x: reduceMotion ? 0 : reveal * drawer.width * 0.3)
            .overlay {
                Color.black.opacity(reduceMotion ? 0 : 0.12 * Double(reveal))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(!app.settingsOpen)
            .accessibilityHidden(app.settingsOpen)

            if settingsShown {
                SettingsLayer()
                    .offset(x: settingsOffset)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    .zIndex(1)
            }
        }
        .environment(drawer)
        .animation(layerAnimation, value: app.settingsOpen)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { drawer.width = $0 }
        .overlay(alignment: .top) { ToastOverlay(center: app.toasts) }
        .background(Color.qBase.ignoresSafeArea())
        // Home Screen quick actions, including one that launched the app before this view existed.
        .onChange(of: QuickActions.shared.pending, initial: true) { _, action in
            guard let action else { return }
            QuickActions.shared.pending = nil
            switch action {
            case .newChat: app.startNewChat()
            case .incognito: app.startNewChat(incognito: true)
            case .open(let id): if app.chat(id) != nil { app.openChat(id) }
            }
        }
    }
}

/// Settings with its own stack, shown over the chats. Its top level goes back to the chats the way
/// it came, toward the leading edge: with the back button, or a right-to-left swipe from anywhere
/// on it (deeper pages keep the system's back swipe instead).
private struct SettingsLayer: View {
    @Environment(AppModel.self) private var app
    @Environment(SettingsDrawer.self) private var drawer

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.settingsPath) {
            SettingsView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { app.closeSettings() } label: { Image(systemName: "chevron.backward") }
                            .accessibilityLabel("Chats")
                    }
                }
                .navigationDestination(for: Route.self) { RouteDestination(route: $0, stack: app.settingsPath) }
                .background {
                    StackSwipes(pull: .init(direction: -1,
                                            allowed: { [app] in app.settingsOpen && app.settingsPath.isEmpty },
                                            changed: { [drawer] in drawer.pushChanged($0) },
                                            ended: { [drawer, app] in drawer.pushEnded($0, velocity: $1, app: app) }))
                }
        }
        .background(Color.qBase.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            // Soft edge shadow, seen only while the layer is moving.
            LinearGradient(colors: [.black.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: 14)
                .offset(x: 14)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .accessibilityAction(.escape) { app.closeSettings() }
    }
}

/// Screens either stack can show. Memory leaves out its settings shortcut when Memory settings is
/// already the screen underneath, so the gear never leads back to where you just came from.
struct RouteDestination: View {
    let route: Route
    let stack: [Route]

    var body: some View {
        switch route {
        case .chat(let id): ChatScreen(chatId: id)
        case .project(let id): ProjectView(projectId: id)
        case .settings: SettingsView()
        case .section(let s): SettingsSectionView(section: s)
        case .memory: MemoryView(showsSettingsLink: !stack.contains(.section(.memory)))
        case .spending: SpendingView()
        }
    }
}

/// Resolves a chat id to its live session once the screen appears (not during a view update,
/// since creating a session mutates app state).
struct ChatScreen: View {
    let chatId: String
    @Environment(AppModel.self) private var app
    @State private var session: ChatSession? = nil
    @State private var resolved = false

    var body: some View {
        Group {
            if let session {
                ChatView(session: session)
                    .id(session.chat.id)
            } else if resolved {
                ContentUnavailableView("Chat not found", systemImage: "text.bubble",
                                       description: Text("It may have been deleted."))
            } else {
                Color.qBase.ignoresSafeArea()
            }
        }
        .onAppear {
            if session?.chat.id != chatId { session = app.session(for: chatId) }
            resolved = true
            app.markRead(chatId)
        }
        .onChange(of: chatId) { _, id in session = app.session(for: id) }
    }
}
