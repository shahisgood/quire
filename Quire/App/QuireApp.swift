import SwiftUI

@main
struct QuireApp: App {
    @UIApplicationDelegateAdaptor(QuireAppDelegate.self) private var appDelegate
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var phase

    init() {
        NavigationTypography.apply()
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
    @State private var width: CGFloat = 390
    /// How far the settings layer has been swiped back toward the leading edge (≤ 0).
    @State private var dragX: CGFloat = 0

    /// 0 with settings closed, 1 with it covering the chats; follows the finger mid-swipe.
    private var reveal: CGFloat {
        guard app.settingsOpen else { return 0 }
        return min(1, max(0, 1 + dragX / max(width, 1)))
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
            .offset(x: reduceMotion ? 0 : reveal * width * 0.3)
            .overlay {
                Color.black.opacity(reduceMotion ? 0 : 0.12 * Double(reveal))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .allowsHitTesting(!app.settingsOpen)
            .accessibilityHidden(app.settingsOpen)

            if app.settingsOpen {
                SettingsLayer(dismissDrag: dismissDrag)
                    .offset(x: dragX)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    .zIndex(1)
            }
        }
        .animation(layerAnimation, value: app.settingsOpen)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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

    /// Swipe settings away from its trailing edge, the mirror of the system's back swipe. A quick
    /// flick is enough; a slow drag has to cover about a third of the screen.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { v in dragX = min(0, v.translation.width) }
            .onEnded { v in
                let w = max(width, 1)
                if -v.translation.width > w * 0.35 || v.predictedEndTranslation.width < -w * 0.5 {
                    withAnimation(Motion.drawerOut) { dragX = -w } completion: {
                        // Already off screen, so remove it without a second slide.
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            app.closeSettings()
                            dragX = 0
                        }
                    }
                } else {
                    withAnimation(Motion.drawerIn) { dragX = 0 }
                }
            }
    }
}

/// Settings with its own stack, shown over the chats. Its top level has a back button (and a swipe
/// from the trailing edge) that returns to the chats the way it came, toward the leading edge.
private struct SettingsLayer<G: Gesture>: View {
    let dismissDrag: G
    @Environment(AppModel.self) private var app

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
        }
        .background(Color.qBase.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            ZStack(alignment: .trailing) {
                // Soft edge shadow, visible only while the layer is moving.
                LinearGradient(colors: [.black.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 14)
                    .offset(x: 14)
                    .allowsHitTesting(false)
                // Edge strip for the swipe back, only at the top level: deeper pages keep the
                // system's own back swipe from the leading edge.
                if app.settingsPath.isEmpty {
                    Color.clear
                        .frame(width: 20)
                        .contentShape(.rect)
                        .gesture(dismissDrag)
                }
            }
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
        }
        .onChange(of: chatId) { _, id in session = app.session(for: id) }
    }
}
