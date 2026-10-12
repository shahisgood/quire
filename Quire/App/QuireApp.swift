import SwiftUI

@main
struct QuireApp: App {
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
                    if newPhase == .background { app.didEnterBackground() }
                    if newPhase == .active { Task { await app.refreshModels() } }
                }
                .task { await app.refreshModels() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            ChatListView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .chat(let id): ChatScreen(chatId: id)
                    case .settings: SettingsView()
                    case .section(let s): SettingsSectionView(section: s)
                    case .memory: MemoryView()
                    }
                }
        }
        .overlay(alignment: .top) { ToastOverlay(center: app.toasts) }
        .background(Color.qBase.ignoresSafeArea())
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
