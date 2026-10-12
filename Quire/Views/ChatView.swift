import SwiftUI

/// Requests a message row makes of its screen (sheets and navigation live at screen level).
struct MessageActions {
    var edit: (Message) -> Void
    var info: (Message) -> Void
    var regenerateWith: (Message) -> Void
    var branch: (Message) -> Void
    var selectText: (Message) -> Void
    var delete: (Message) -> Void
    var shareThread: () -> Void
    var openChatSettings: () -> Void
    var fixKey: () -> Void
    var viewImage: (Attachment) -> Void
}

struct ChatView: View {
    let session: ChatSession
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var pinned = true
    @State private var atBottom = true
    @State private var userScrolling = false
    @State private var visibleCount = 40
    @State private var flashId: String? = nil

    @State private var showSettings = false
    @State private var showModels = false
    @State private var editing: Message? = nil
    @State private var infoFor: Message? = nil
    @State private var regenFor: Message? = nil
    @State private var selecting: Message? = nil
    @State private var deleting: Message? = nil
    @State private var viewingImage: Attachment? = nil
    @State private var share: SharedFile? = nil
    @State private var renaming = false
    @State private var renameText = ""
    @State private var confirmDeleteChat = false

    private var visiblePath: ArraySlice<String> { session.path.suffix(visibleCount) }
    private var hiddenCount: Int { max(0, session.path.count - visibleCount) }
    private var density: CGFloat { app.settings.ui.density == "compact" ? 16 : 26 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density) {
                if session.path.isEmpty {
                    EmptyChatView(session: session, openModels: { showModels = true }, openSettings: { showSettings = true })
                        .containerRelativeFrame(.vertical, alignment: .center)
                }
                if hiddenCount > 0 {
                    Button(action: showEarlier) {
                        Label("Show \(min(40, hiddenCount)) earlier of \(hiddenCount)", systemImage: "arrow.up")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
                }
                ForEach(Array(visiblePath), id: \.self) { id in
                    if let m = session.messages[id] {
                        MessageRow(session: session, message: m, highlighted: flashId == id, actions: actions)
                            .id(id)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .environment(\.dynamicTypeSize, ReadingSize(scale: app.settings.ui.fontScale).apply(to: typeSize))
            .animation(reduceMotion ? nil : Motion.standard, value: session.path)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.qBase)
        // "Pinned" means following the bottom. Only while pinned does new text move the viewport;
        // scrolling up to read stops the follow, as in the PWA, and a "Latest" pill brings it back.
        // Only the reader's own scrolling un-pins: when a message is sent, the rows grow while the
        // scroll to the bottom is still animating, and treating that as "scrolled away" left the
        // pill stuck on screen at the bottom of the chat.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 60
        } action: { _, near in
            atBottom = near
            if near { pinned = true } else if userScrolling { pinned = false }
        }
        .onScrollPhaseChange { _, phase in
            userScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
        }
        .onChange(of: session.streamContent) { if pinned { position.scrollTo(edge: .bottom) } }
        .onChange(of: session.streamReasoning) { if pinned { position.scrollTo(edge: .bottom) } }
        .onChange(of: session.path.count) { old, new in
            if new > old {
                pinned = true
                withAnimation(reduceMotion ? nil : Motion.standard) { position.scrollTo(edge: .bottom) }
            }
        }
        .onAppear(perform: jumpToHighlight)
        .overlay(alignment: .bottom) {
            ZStack { jumpPill }
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.quick, value: showsJumpPill)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(session: session,
                         openModels: { showModels = true },
                         openSettings: { showSettings = true },
                         onFocus: {
                             if pinned {
                                 Task {
                                     try? await Task.sleep(for: .milliseconds(300))
                                     withAnimation(Motion.quick) { position.scrollTo(edge: .bottom) }
                                 }
                             }
                         })
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) { ChatSettingsSheet(session: session) }
        .sheet(isPresented: $showModels) {
            ModelPickerView(title: "Model for this chat", selected: session.chat.modelId) { id in session.setModel(id) }
        }
        .sheet(item: $editing) { m in EditMessageSheet(session: session, message: m) }
        .sheet(item: $infoFor) { m in MessageInfoSheet(session: session, message: m) }
        .sheet(item: $regenFor) { m in
            ModelPickerView(title: "Regenerate with", selected: m.modelId ?? session.chat.modelId) { id in session.regenerate(m.id, modelId: id) }
        }
        .sheet(item: $selecting) { m in SelectTextSheet(text: m.content) }
        .sheet(item: $share) { f in ShareSheet(items: [f.url]).presentationDetents([.medium, .large]) }
        .fullScreenCover(item: $viewingImage) { a in ImageViewer(attachment: a) }
        .confirmationDialog("Delete this message?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let m = deleting { withAnimation(Motion.standard) { session.delete(m.id) } }
                deleting = nil
            }
        } message: {
            Text("Later messages on this branch are deleted with it.")
        }
        .confirmationDialog("Delete this chat?", isPresented: $confirmDeleteChat, titleVisibility: .visible) {
            Button("Delete chat", role: .destructive) { app.deleteChats([session.chat.id]) }
        } message: {
            Text("Every message and branch in it is removed. This can't be undone.")
        }
        .alert("Rename chat", isPresented: $renaming) {
            TextField("Title", text: $renameText)
            Button("Rename") { session.rename(renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Pieces

    private var actions: MessageActions {
        MessageActions(
            edit: { editing = $0 },
            info: { infoFor = $0 },
            regenerateWith: { regenFor = $0 },
            branch: { m in
                if let id = session.branch(from: m.id) {
                    Haptics.success()
                    app.openChat(id)
                    app.toasts.show("Branched into a new chat", symbol: "arrow.triangle.branch")
                }
            },
            selectText: { selecting = $0 },
            delete: { deleting = $0 },
            shareThread: shareMarkdown,
            openChatSettings: { showSettings = true },
            fixKey: { app.push(.section(.connection)) },
            viewImage: { viewingImage = $0 }
        )
    }

    /// Never while the bottom is already in view, whatever the follow state says.
    private var showsJumpPill: Bool { !pinned && !atBottom && !session.path.isEmpty }

    @ViewBuilder
    private var jumpPill: some View {
        if showsJumpPill {
            Button {
                pinned = true
                withAnimation(reduceMotion ? nil : Motion.standard) { position.scrollTo(edge: .bottom) }
                Haptics.tap()
            } label: {
                Label(session.generating ? "Streaming" : "Latest", systemImage: "arrow.down")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.glass)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            .accessibilityLabel("Jump to latest")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Menu { titleMenu } label: { titleLabel }
                .accessibilityLabel("\(session.chat.title), chat options")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .accessibilityLabel("Chat settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            NewChatButton()
        }
    }

    private var titleLabel: some View {
        VStack(spacing: 1) {
            HStack(spacing: 5) {
                if !session.chat.memoryEnabled {
                    Image(systemName: "eye.slash").font(.caption).foregroundStyle(Color.qInk2)
                }
                Text(session.chat.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.qInk2)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(session.generating ? Color.qAccent : Color.qInk2)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: 250)
        .animation(Motion.quick, value: session.generating)
    }

    private var subtitle: String {
        if session.generating { return session.streamFirstTokenAt == nil ? "Waiting for \(app.modelName(session.chat.modelId))" : "Writing…" }
        if let p = session.persona { return "\(p.icon ?? "◦") \(p.name) · \(app.modelName(session.chat.modelId))" }
        return app.modelName(session.chat.modelId)
    }

    @ViewBuilder
    private var titleMenu: some View {
        Section {
            Button { renameText = session.chat.title; renaming = true } label: { Label("Rename", systemImage: "pencil") }
            Button { showSettings = true } label: { Label("Chat settings", systemImage: "slider.horizontal.3") }
            Button { showModels = true } label: { Label("Model: \(app.modelName(session.chat.modelId))", systemImage: "cpu") }
            Toggle(isOn: Binding(get: { session.chat.memoryEnabled }, set: { session.setMemoryEnabled($0) })) {
                Label("Memory for this chat", systemImage: "brain")
            }
        }
        if session.persisted {
            Section {
                Menu {
                    Button { app.patchChat(session.chat.id) { $0.folderId = nil } } label: { Label("No folder", systemImage: "tray") }
                    ForEach(app.folders) { f in
                        Button { app.patchChat(session.chat.id) { $0.folderId = f.id } } label: {
                            Label(f.name, systemImage: session.chat.folderId == f.id ? "checkmark" : "folder")
                        }
                    }
                } label: {
                    Label("Folder: \(app.folder(session.chat.folderId)?.name ?? "None")", systemImage: "folder")
                }
                Button { app.patchChat(session.chat.id) { $0.pinned.toggle() } } label: {
                    Label(session.chat.pinned ? "Unpin" : "Pin", systemImage: session.chat.pinned ? "pin.slash" : "pin")
                }
                Button {
                    let archived = !session.chat.archived
                    app.patchChat(session.chat.id) { $0.archived = archived }
                    app.toasts.show(archived ? "Archived" : "Unarchived", symbol: "archivebox")
                } label: {
                    Label(session.chat.archived ? "Unarchive" : "Archive", systemImage: "archivebox")
                }
            }
            Section {
                Button(action: shareMarkdown) { Label("Share as Markdown", systemImage: "doc.richtext") }
                Button {
                    if let url = try? app.exportChats([session.chat.id]) { share = SharedFile(url: url) }
                } label: { Label("Export as JSON", systemImage: "curlybraces") }
                Button {
                    if let id = app.duplicateChat(session.chat.id) { app.openChat(id) }
                } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            }
            Section {
                Button(role: .destructive) { confirmDeleteChat = true } label: { Label("Delete chat", systemImage: "trash") }
            }
        }
    }

    // MARK: Behaviour

    private func shareMarkdown() {
        guard !session.path.isEmpty, let url = try? app.exportMarkdown(session) else {
            app.toasts.show("Nothing to share yet")
            return
        }
        share = SharedFile(url: url)
    }

    private func showEarlier() {
        let anchor = visiblePath.first
        visibleCount += 40
        Haptics.tap()
        if let anchor {
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                position.scrollTo(id: anchor, anchor: .top)
            }
        }
    }

    private func jumpToHighlight() {
        guard let h = session.highlightId else { return }
        session.highlightId = nil
        guard let idx = session.path.firstIndex(of: h) else { return }
        let needed = session.path.count - idx + 3
        if needed > visibleCount { visibleCount = needed }
        pinned = false
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(reduceMotion ? nil : Motion.standard) { position.scrollTo(id: h, anchor: .center) }
            withAnimation(Motion.quick) { flashId = h }
            try? await Task.sleep(for: .seconds(1.8))
            withAnimation(Motion.standard) { flashId = nil }
        }
    }
}

// MARK: - Empty chat

private struct EmptyChatView: View {
    let session: ChatSession
    let openModels: () -> Void
    let openSettings: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.apiKey == nil {
            EmptyState(title: "Quire needs an OpenRouter key",
                       message: "It's stored in this iPhone's Keychain and only ever sent to openrouter.ai.") {
                Button { app.push(.section(.connection)) } label: { Label("Add key", systemImage: "key") }
                    .buttonStyle(.glassProminent)
            }
        } else {
            EmptyState(title: "Talking to \(app.modelName(session.chat.modelId)).", message: message) {
                VStack(spacing: 10) {
                    if let p = session.persona {
                        Text("\(p.icon ?? "◦")  \(p.name)")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.qAccentSoft, in: .capsule)
                            .foregroundStyle(Color.qInk)
                    }
                    HStack(spacing: 10) {
                        Button(action: openModels) { Label("Change model", systemImage: "cpu") }
                            .buttonStyle(.glass)
                        Button(action: openSettings) { Label("Settings", systemImage: "slider.horizontal.3") }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    private var message: String {
        if !session.chat.memoryEnabled { return "Incognito. Nothing from this chat is remembered or recalled." }
        if let m = session.model {
            return "\(Fmt.context(m.contextLength)) context · \(Pricing.perMillion(m.pricing.prompt)) in · \(Pricing.perMillion(m.pricing.completion)) out per million tokens."
        }
        return "Type below, or pick any of the models OpenRouter offers."
    }
}

// MARK: - Small sheets

/// Range-selectable text for copying part of a message.
struct SelectTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .background(Color.qBase)
                .navigationTitle("Select text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            UIPasteboard.general.string = text
                            Haptics.tap()
                            dismiss()
                        } label: { Label("Copy all", systemImage: "square.on.square") }
                    }
                }
        }
    }
}

/// A full-screen look at an attached image, with pinch to zoom.
struct ImageViewer: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = ThumbnailCache.image(for: attachment) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale * pinch)
                    .gesture(
                        MagnifyGesture()
                            .updating($pinch) { value, state, _ in state = value.magnification }
                            .onEnded { value in scale = min(4, max(1, scale * value.magnification)) }
                    )
                    .onTapGesture(count: 2) { withAnimation(Motion.standard) { scale = scale > 1 ? 1 : 2.5 } }
                    .accessibilityLabel(attachment.name)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
            }
            .buttonStyle(.glass)
            .padding()
            .accessibilityLabel("Close")
        }
    }
}
