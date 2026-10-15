import SwiftUI

// A chat as a row in a list, with its swipe actions and menu, shared by the chat list and project
// screens. The alerts and sheets a row can ask for live on the screen, through `ListSheets`.

/// The screen-level prompts behind a list of chats: rename, delete, share, the project editor and
/// deleting a project.
@Observable
final class ListSheets {
    var renaming: Chat? = nil
    var renameText = ""
    var deletingChats: Set<String>? = nil
    var share: SharedFile? = nil
    var editor: ProjectEditorRequest? = nil
    var deletingProject: Project? = nil

    func rename(_ chat: Chat) {
        renameText = chat.title
        renaming = chat
    }
}

/// List actions that end in a toast with Undo.
enum ChatOps {
    static func archive(_ app: AppModel, _ ids: Set<String>, to archived: Bool) {
        guard !ids.isEmpty else { return }
        withAnimation(Motion.standard) { app.patchChats(ids) { $0.archived = archived } }
        Haptics.tap()
        let noun = ids.count == 1 ? "Chat" : "\(ids.count) chats"
        app.toasts.show(archived ? "\(noun) archived" : "\(noun) unarchived", symbol: "archivebox",
                        action: (label: "Undo", run: { [app] in
                            withAnimation(Motion.standard) { app.patchChats(ids) { $0.archived = !archived } }
                        }))
    }

    /// Into a project, or out of any with nil. Undo puts each chat back where it was.
    static func move(_ app: AppModel, _ ids: Set<String>, to projectId: String?) {
        let moving = app.chats.filter { ids.contains($0.id) && $0.folderId != projectId }
        guard !moving.isEmpty else { return }
        let before = Dictionary(grouping: moving, by: { $0.folderId ?? "" }).mapValues { Set($0.map(\.id)) }
        let from = app.project(moving.first?.folderId)
        withAnimation(Motion.standard) { app.moveChats(Set(moving.map(\.id)), toProject: projectId) }
        Haptics.tap()
        let noun = moving.count == 1 ? "Chat" : "\(moving.count) chats"
        let target = app.project(projectId)
        let text: String
        if let target { text = "\(noun) moved to \(target.name)" }
        else if let from, before.count == 1 { text = "\(noun) moved out of \(from.name)" }
        else { text = "\(noun) moved to your chat list" }
        app.toasts.show(text, symbol: target?.symbolName ?? "tray.and.arrow.up", action: (label: "Undo", run: { [app] in
            withAnimation(Motion.standard) {
                for (pid, group) in before { app.moveChats(group, toProject: pid.isEmpty ? nil : pid) }
            }
        }))
    }

    static func togglePin(_ app: AppModel, _ chat: Chat) {
        withAnimation(Motion.standard) { app.patchChat(chat.id) { $0.pinned.toggle() } }
        Haptics.selection()
    }
}

/// A chat row that opens the chat, with archive and delete on a trailing swipe, pin on a leading
/// one, and everything else in its menu.
struct ChatListRow: View {
    let chat: Chat
    let sheets: ListSheets
    var showsProject = false
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: Route.chat(chat.id)) {
            ChatRow(chat: chat, showsProject: showsProject)
        }
        .listRowBackground(Color.qRaised)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { ChatOps.archive(app, [chat.id], to: !chat.archived) } label: {
                Label(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            .tint(Color.qTileSlate)
            Button(role: .destructive) { sheets.deletingChats = [chat.id] } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { ChatOps.togglePin(app, chat) } label: {
                Label(chat.pinned ? "Unpin" : "Pin", systemImage: chat.pinned ? "pin.slash" : "pin")
            }
            .tint(Color.qAccent)
        }
        .contextMenu {
            Button { sheets.rename(chat) } label: { Label("Rename", systemImage: "pencil") }
            Button { ChatOps.togglePin(app, chat) } label: {
                Label(chat.pinned ? "Unpin" : "Pin", systemImage: chat.pinned ? "pin.slash" : "pin")
            }
            ProjectMoveMenu(app, ids: [chat.id]) { sheets.editor = ProjectEditorRequest(moving: [chat.id]) }
            Button {
                if app.duplicateChat(chat.id) != nil { app.toasts.show("Duplicated", symbol: "plus.square.on.square") }
            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button {
                if let url = try? app.exportChats([chat.id]) { sheets.share = SharedFile(url: url) }
            } label: { Label("Export as JSON", systemImage: "square.and.arrow.up") }
            Button { ChatOps.archive(app, [chat.id], to: !chat.archived) } label: {
                Label(chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
            }
            Divider()
            Button(role: .destructive) { sheets.deletingChats = [chat.id] } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// "Move to project": every project (a check on the one the chats are already in), out of any
/// project, or a new one made for them. Takes the app model directly rather than from the
/// environment, since it's built inside context menus.
struct ProjectMoveMenu: View {
    let app: AppModel
    let ids: Set<String>
    var title = "Move to project"
    var onMoved: () -> Void = {}
    let newProject: () -> Void

    init(_ app: AppModel, ids: Set<String>, title: String = "Move to project", onMoved: @escaping () -> Void = {},
         newProject: @escaping () -> Void) {
        self.app = app
        self.ids = ids
        self.title = title
        self.onMoved = onMoved
        self.newProject = newProject
    }

    var body: some View {
        let homes = Set(app.chats.filter { ids.contains($0.id) }.map { app.project($0.folderId)?.id ?? "" })
        let current = homes.count == 1 ? homes.first.flatMap { $0.isEmpty ? nil : $0 } : nil
        Menu {
            if homes.contains(where: { !$0.isEmpty }) {
                Button { move(to: nil) } label: { Label("Remove from project", systemImage: "tray.and.arrow.up") }
            }
            Section {
                ForEach(app.projects) { p in
                    Button { move(to: p.id) } label: {
                        Label(p.name, systemImage: p.id == current ? "checkmark" : p.symbolName)
                    }
                    .disabled(p.id == current)
                }
            }
            Button(action: newProject) { Label("New project…", systemImage: "plus") }
        } label: {
            Label(title, systemImage: "folder")
        }
    }

    private func move(to id: String?) {
        ChatOps.move(app, ids, to: id)
        onMoved()
    }
}

/// Hosts everything in `ListSheets` for one screen.
private struct ListSheetsHost: ViewModifier {
    @Bindable var sheets: ListSheets
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content
            .alert("Rename chat", isPresented: Binding(get: { sheets.renaming != nil }, set: { if !$0 { sheets.renaming = nil } })) {
                TextField("Title", text: $sheets.renameText)
                Button("Rename") {
                    if let c = sheets.renaming {
                        let t = sheets.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { app.patchChat(c.id) { $0.title = t; $0.titleAuto = false } }
                    }
                    sheets.renaming = nil
                }
                Button("Cancel", role: .cancel) { sheets.renaming = nil }
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { sheets.deletingChats != nil }, set: { if !$0 { sheets.deletingChats = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let ids = sheets.deletingChats {
                        withAnimation(Motion.standard) { app.deleteChats(ids) }
                        Haptics.warning()
                    }
                    sheets.deletingChats = nil
                }
            } message: {
                Text("Every message and branch is removed from this iPhone. This can't be undone.")
            }
            .sheet(item: $sheets.share) { f in ShareSheet(items: [f.url]).presentationDetents([.medium, .large]) }
            .sheet(item: $sheets.editor) { r in
                ProjectEditor(project: r.project, focusInstructions: r.focusInstructions,
                              newTint: .suggested(after: app.folders.count),
                              onSave: { p in saved(p, request: r) },
                              onDelete: { p in
                                  sheets.editor = nil
                                  // Let the sheet go before the confirmation comes up.
                                  Task {
                                      try? await Task.sleep(for: .milliseconds(450))
                                      sheets.deletingProject = p
                                  }
                              })
            }
            .projectDeletion($sheets.deletingProject)
    }

    private var deleteTitle: String {
        let n = sheets.deletingChats?.count ?? 0
        return n == 1 ? "Delete this chat?" : "Delete \(n) chats?"
    }

    private func saved(_ p: Project, request r: ProjectEditorRequest) {
        guard r.project == nil else { return }
        if !r.moving.isEmpty {
            ChatOps.move(app, r.moving, to: p.id)
        } else if r.openAfterCreate {
            // Into the new project once its sheet is down, so it zooms out of its fresh row.
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                app.push(.project(p.id))
            }
        }
    }
}

extension View {
    func listSheets(_ sheets: ListSheets) -> some View { modifier(ListSheetsHost(sheets: sheets)) }
}
