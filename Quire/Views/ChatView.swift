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
    @State private var nearBottom = true
    /// Close to the bottom, though not at it: letting go here mid-reply rejoins the stream.
    @State private var withinReach = true
    @State private var tailVisible = true
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

    private var visiblePath: ArraySlice<String> { session.path.suffix(visibleCount) }
    private var hiddenCount: Int { max(0, session.path.count - visibleCount) }
    private var density: CGFloat { app.settings.ui.density == "compact" ? 16 : 26 }

    /// Two independent signals, either of which counts: scroll geometry, and whether the marker at
    /// the very end of the thread is on screen. The marker needs no inset arithmetic, so the pill
    /// can't get stuck when the geometry reads differently (with the keyboard, say).
    private var atBottom: Bool { nearBottom || tailVisible }

    /// The thread as rows: a message you sent is one, a reply is several (see `ThreadRow`).
    private var rows: [ThreadRow] {
        visiblePath.flatMap { id -> [ThreadRow] in
            guard let m = session.messages[id] else { return [] }
            return ThreadRow.rows(for: m, in: session)
        }
    }

    /// Starters sit just above the message box on an empty chat, until you've written something of
    /// your own (a starter's opening still counts as nothing yet, so you can swap it for another).
    private var showsStarters: Bool {
        guard session.path.isEmpty, app.apiKey != nil else { return false }
        let d = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty || StarterPrompt.all.contains { $0.text == session.draft }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // One lazy list of small rows (a reply is split into its blocks), so only what's
                // near the screen is built, each row on its own layer, and rows above the screen
                // settle at their real height quickly instead of shifting the view as they load.
                LazyVStack(alignment: .leading, spacing: 0) {
                    if session.path.isEmpty {
                        EmptyChatView(session: session, openSettings: { showSettings = true })
                            .containerRelativeFrame(.vertical, alignment: Alignment(horizontal: .center, vertical: .opticalCenter))
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
                        .padding(.top, 4)
                    }
                    ForEach(rows) { row in
                        ThreadRowView(row: row, session: session, highlighted: flashId == row.messageId,
                                      gap: density, actions: actions)
                            .id(row.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
                .environment(\.dynamicTypeSize, ReadingSize(scale: app.settings.ui.fontScale).apply(to: typeSize))
                .animation(reduceMotion ? nil : Motion.standard, value: session.path)

                Color.clear
                    .frame(height: 1)
                    .onScrollVisibilityChange(threshold: 0.01) { visible in
                        tailVisible = visible
                        updateFollow()
                    }
                    .accessibilityHidden(true)
            }
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        // While following, growth keeps the bottom in place (new text pushes up into view). While
        // you're reading further up, growth happens below you and the text you're on stays still.
        .defaultScrollAnchor(pinned ? .bottom : .top, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.qBase)
        // "Pinned" means following the bottom. Only while pinned does new text move the viewport.
        // The moment your finger takes hold of the thread, following stops, so a streaming reply
        // never pulls the page out from under you; it picks up again if you let go at the bottom.
        .onScrollGeometryChange(for: BottomReach.self) { geo in
            let gap = geo.contentSize.height - geo.visibleRect.maxY
            return gap <= 40 ? .at : (gap <= 160 ? .near : .away)
        } action: { _, reach in
            nearBottom = reach == .at
            withinReach = reach != .away
            updateFollow()
        }
        .onScrollPhaseChange { old, new in
            userScrolling = Self.isUserPhase(new)
            if new == .tracking || new == .interacting { pinned = false }
            // Let go at the bottom, or (while a reply streams) just short of it, and following picks
            // up again; a reply moving on under your thumb shouldn't strand you above it.
            if Self.isUserPhase(old) && new == .idle && (atBottom || (session.generating && withinReach)) {
                pinned = true
                if !atBottom { withAnimation(reduceMotion ? nil : Motion.quick) { position.scrollTo(edge: .bottom) } }
            }
        }
        .onChange(of: session.streamContent) { followIfPinned() }
        .onChange(of: session.streamReasoning) { followIfPinned() }
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
            VStack(spacing: 10) {
                if showsStarters {
                    StarterRow(session: session)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 10)))
                }
                composer
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.standard, value: showsStarters)
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
    }

    // MARK: Pieces

    private var composer: some View {
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

    /// Resumes following when the bottom comes into view by itself (not mid-drag).
    private func updateFollow() {
        if atBottom && !userScrolling { pinned = true }
    }

    private func followIfPinned() {
        guard pinned, !userScrolling else { return }
        position.scrollTo(edge: .bottom)
    }

    private static func isUserPhase(_ phase: ScrollPhase) -> Bool {
        phase == .tracking || phase == .interacting || phase == .decelerating
    }

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

    /// No title, no settings button: the bar stays quiet. A new chat offers incognito in the corner;
    /// once the first message is sent, that corner becomes the new-chat button. Each is a toolbar
    /// item of its own, so each gets the bar's own button and sits centred in it.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if session.path.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                IncognitoToggle(session: session)
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                NewChatButton(projectId: session.chat.folderId)
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

/// How far the end of the thread is from the bottom of the screen, in the three steps that matter.
nonisolated private enum BottomReach: Equatable { case at, near, away }

// MARK: - Top bar

/// Before anything is said: make this chat incognito (nothing read from or written to memory), or
/// not. The eye fills in with the accent while it's on.
private struct IncognitoToggle: View {
    let session: ChatSession

    var body: some View {
        let on = !session.chat.memoryEnabled
        Button {
            Haptics.selection()
            withAnimation(Motion.standard) { session.setMemoryEnabled(on) }
        } label: {
            Image(systemName: on ? "eye.slash.fill" : "eye.slash")
                .foregroundStyle(on ? Color.qAccent : Color.qInk)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel("Incognito")
        .accessibilityValue(on ? "On" : "Off")
        .accessibilityHint(on ? "This chat won't use or add to memory" : "Keep this chat out of memory")
    }
}

// MARK: - Empty chat

/// A new chat says only what you need before you start: a greeting, what's different about this
/// chat (incognito, a project, a persona) if anything, and a way back to what you were last doing.
/// The model lives in the message box, the starters sit just above it, and the rest of the screen is
/// left quiet.
private struct EmptyChatView: View {
    let session: ChatSession
    let openSettings: () -> Void
    @Environment(AppModel.self) private var app
    @State private var shown = false

    var body: some View {
        if app.apiKey == nil {
            EmptyState(title: "Quire needs an OpenRouter key",
                       message: "It's stored in this iPhone's Keychain and only ever sent to openrouter.ai.") {
                Button { app.push(.section(.connection)) } label: { Label("Add key", systemImage: "key") }
                    .buttonStyle(.glassProminent)
            }
        } else {
            VStack(spacing: 0) {
                QuireMark(width: 40, breathing: true)
                    .padding(.bottom, 22)
                    .entrance(shown)

                Text(greeting)
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.qInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityAddTraits(.isHeader)
                    .entrance(shown, delay: 0.06)

                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(Color.qInk2)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                        .transition(.opacity)
                        .entrance(shown, delay: 0.1)
                }

                if session.project != nil || session.persona != nil {
                    contextChips
                        .padding(.top, 18)
                        .entrance(shown, delay: 0.14)
                }

                if let last = lastChat {
                    pickUp(last)
                        .padding(.top, 28)
                        .entrance(shown, delay: 0.2)
                }
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .animation(Motion.standard, value: session.chat.memoryEnabled)
            .onAppear { shown = true }
        }
    }

    private var greeting: String {
        guard session.chat.memoryEnabled else { return "Off the record." }
        return Greeting.line(seed: session.chat.id, returning: app.chats.contains { $0.id != session.chat.id })
    }

    private var note: String? {
        session.chat.memoryEnabled ? nil : "Nothing in this chat is remembered."
    }

    /// The project and persona this chat starts with. Either opens chat settings, where both change.
    private var contextChips: some View {
        HStack(spacing: 8) {
            if let p = session.project {
                chip {
                    HStack(spacing: 7) {
                        ProjectTile(project: p, size: 20)
                        Text(p.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                        if p.hasInstructions {
                            Image(systemName: "text.quote")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(p.tintColor)
                                .accessibilityLabel("with instructions")
                        }
                    }
                }
                .accessibilityLabel(p.hasInstructions ? "Project \(p.name), following its instructions" : "Project \(p.name)")
            }
            if let persona = session.persona {
                chip {
                    Text("\(persona.icon ?? "◦")  \(persona.name)")
                        .fontWeight(.medium)
                        .foregroundStyle(Color.qInk)
                        .lineLimit(1)
                }
                .accessibilityLabel("Persona \(persona.name)")
            }
        }
        .font(.footnote)
    }

    private func chip<Content: View>(@ViewBuilder _ label: () -> Content) -> some View {
        Button(action: openSettings) {
            label()
                .padding(.leading, 7)
                .padding(.trailing, 12)
                .frame(minHeight: 32)
                .background(Color.qRaised, in: .capsule)
                .overlay(Capsule().strokeBorder(Color.qRule, lineWidth: 1))
                .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens chat settings")
    }

    // MARK: Pick up where you left off

    /// The chat you were last in, if it was recent: in this chat's project when there is one.
    private var lastChat: Chat? {
        let dayAgo = nowMs() - 86_400_000
        return app.chats.first {
            $0.id != session.chat.id && !$0.archived && $0.folderId == session.chat.folderId
                && $0.updatedAt > dayAgo && $0.title != "New chat"
        }
    }

    private func pickUp(_ c: Chat) -> some View {
        Button {
            Haptics.tap()
            app.openChat(c.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.qAccent)
                Text("Continue \(Text(c.title).foregroundStyle(Color.qInk))")
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Continue your last chat, \(c.title)")
    }
}

/// Ways to begin, just above the message box where your thumb already is. Each only fills the box
/// (and brings up the keyboard); the rest of the sentence is yours, and nothing is sent until you
/// send it. The one you picked stays lit, and another one swaps it.
private struct StarterRow: View {
    let session: ChatSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(StarterPrompt.all.enumerated()), id: \.element.id) { i, s in
                        chip(s)
                            .opacity(shown ? 1 : 0)
                            .offset(y: shown || reduceMotion ? 0 : 6)
                            .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.standard.delay(Double(i) * 0.035), value: shown)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
        }
        // The row fades into the edges instead of being cut off by them, which also says it scrolls.
        .mask {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                   .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .onAppear { shown = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ways to start")
    }

    private func chip(_ s: StarterPrompt) -> some View {
        let on = session.draft == s.text
        return Button {
            Haptics.selection()
            session.prefill = s.text
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(on ? Color.qOnAccent : Color.qAccent)
                    .symbolEffect(.bounce, value: on)
                Text(s.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(on ? Color.qOnAccent : Color.qInk)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .glassEffect(on ? .regular.tint(Color.qAccent).interactive() : .regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(Motion.quick, value: on)
        .accessibilityLabel(s.title)
        .accessibilityHint("Starts your message with “\(s.text.trimmingCharacters(in: .whitespaces))”")
        .accessibilityAddTraits(on ? .isSelected : [])
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
