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
    /// Following the bottom: new text moves the view only while this is on.
    @State private var pinned = true
    @State private var nearBottom = true
    @State private var tailVisible = true
    @State private var userScrolling = false
    @State private var tracker = ScrollTracker()
    /// The first message shown. Fixed once the chat opens, so the window never slides under you as
    /// messages arrive; "Show earlier" moves it back.
    @State private var windowStartId: String? = nil
    @State private var flashId: String? = nil
    @State private var composerFocused = false

    @State private var showSettings = false
    @State private var showModels = false
    @State private var editing: Message? = nil
    @State private var infoFor: Message? = nil
    @State private var regenFor: Message? = nil
    @State private var selecting: Message? = nil
    @State private var deleting: Message? = nil
    @State private var viewingImage: Attachment? = nil
    @State private var share: SharedFile? = nil

    /// Roughly how much text the thread lays out at once. Everything in the window is laid out in
    /// full (not lazily), so heights are exact: the scroll bar never jumps, a long chat opens at its
    /// real bottom, and nothing moves while you read. Older messages wait behind "Show earlier".
    private static let pageChars = 60_000

    private var windowStart: Int {
        if let id = windowStartId, let i = session.path.firstIndex(of: id) { return i }
        return budgetStart(before: session.path.count)
    }

    private var visiblePath: ArraySlice<String> { session.path[windowStart...] }
    private var hiddenCount: Int { windowStart }
    private var density: CGFloat { app.settings.ui.density == "compact" ? 18 : 30 }

    /// Starters sit just above the message box on an empty chat, until you start writing (a
    /// starter's opening on its own still counts as nothing yet, so you can swap it).
    private var showsStarters: Bool {
        guard session.path.isEmpty, app.apiKey != nil, !composerFocused else { return false }
        let d = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty || StarterGroup.isStarter(session.draft)
    }

    var body: some View {
        Group {
            if session.path.isEmpty {
                // Outside any scroll view, so it centres in the space between the bar and the
                // message box rather than in the whole screen.
                EmptyChatView(session: session, openSettings: { showSettings = true })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.qBase)
                    .transition(.opacity)
            } else {
                thread
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Motion.standard, value: session.path.isEmpty)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if showsStarters {
                    StarterMenu(session: session)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12)))
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
        .onAppear(perform: fixWindow)
        .onChange(of: session.path.first) { fixWindow() }
    }

    // MARK: Thread

    private var thread: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: density) {
                if hiddenCount > 0 {
                    Button(action: showEarlier) {
                        Label("Show earlier messages (\(hiddenCount))", systemImage: "arrow.up")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
                }
                ForEach(Array(visiblePath), id: \.self) { id in
                    if let m = session.messages[id] {
                        MessageView(session: session, message: m, highlighted: flashId == id, actions: actions)
                            .id(id)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 14)
            .environment(\.dynamicTypeSize, ReadingSize(scale: app.settings.ui.fontScale).apply(to: typeSize))
            .animation(reduceMotion ? nil : Motion.standard, value: session.path)

            Color.clear
                .frame(height: 1)
                .onScrollVisibilityChange(threshold: 0.01) { tailVisible = $0 }
                .accessibilityHidden(true)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        // While following, growth keeps the bottom in place, so new text rises into view. Once you
        // have hold of the thread, growth happens below you and the text you're reading stays put.
        .defaultScrollAnchor(pinned ? .bottom : .top, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.qBase)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentSize.height - geo.visibleRect.maxY <= 32
        } action: { _, near in
            nearBottom = near
        }
        // Which way your finger last moved the thread, kept out of view state (no redraw per frame).
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y
        } action: { old, new in
            if userScrolling, abs(new - old) > 0.5 { tracker.movedDown = new > old }
        }
        .onScrollPhaseChange { old, new in
            userScrolling = Self.isUserPhase(new)
            // Dragging the thread stops following outright: a reply still streaming never pulls the
            // page out from under you. A touch that doesn't drag changes nothing.
            if new == .interacting { pinned = false }
            // Following picks up again only if you scrolled down to the very end and let go there.
            if Self.isUserPhase(old), new == .idle, !pinned, nearBottom, tracker.movedDown {
                pinned = true
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
    }

    // MARK: Pieces

    private var composer: some View {
        ComposerView(session: session,
                     openModels: { showModels = true },
                     openSettings: { showSettings = true },
                     onFocus: {
                         if pinned && !session.path.isEmpty {
                             Task {
                                 try? await Task.sleep(for: .milliseconds(300))
                                 withAnimation(Motion.quick) { position.scrollTo(edge: .bottom) }
                             }
                         }
                     },
                     onFocusChange: { composerFocused = $0 })
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

    /// Never while the end of the thread is in view, whatever the follow state says.
    private var showsJumpPill: Bool { !pinned && !nearBottom && !tailVisible && !session.path.isEmpty }

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
                HStack(spacing: 7) {
                    if session.generating { LiveDot(size: 6) } else { Image(systemName: "arrow.down") }
                    Text(session.generating ? "Writing" : "Latest")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .buttonStyle(.glass)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            .accessibilityLabel(session.generating ? "Jump to the reply being written" : "Jump to latest")
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

    /// Where a window of about `pageChars` of text ending at `end` begins: at least six messages,
    /// at most sixty.
    private func budgetStart(before end: Int) -> Int {
        let path = session.path
        var i = min(end, path.count)
        var chars = 0
        var n = 0
        while i > 0 {
            chars += session.messages[path[i - 1]]?.content.utf8.count ?? 0
            n += 1
            i -= 1
            if (n >= 6 && chars > Self.pageChars) || n >= 60 { break }
        }
        return i
    }

    private func fixWindow() {
        guard windowStartId == nil || !session.path.contains(windowStartId ?? "") else { return }
        let start = budgetStart(before: session.path.count)
        windowStartId = start < session.path.count ? session.path[start] : nil
    }

    private func shareMarkdown() {
        guard !session.path.isEmpty, let url = try? app.exportMarkdown(session) else {
            app.toasts.show("Nothing to share yet")
            return
        }
        share = SharedFile(url: url)
    }

    private func showEarlier() {
        let anchor = visiblePath.first
        let start = budgetStart(before: windowStart)
        Haptics.tap()
        // Older messages go in above while the one at the top stays where it is on screen.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            pinned = false
            windowStartId = session.path[start]
        }
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
        if idx < windowStart { windowStartId = session.path[max(0, idx - 2)] }
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

/// Scroll bookkeeping that changes every frame and mustn't redraw the view when it does.
private final class ScrollTracker {
    var movedDown = false
}

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
/// The model lives in the message box and the starters just above it. It sits in the middle of the
/// space between the bar and the starters, and gives up its extras when that space is short (the
/// keyboard is up on a small phone, say).
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
            ViewThatFits(in: .vertical) {
                content(compact: false)
                content(compact: true)
            }
            .padding(.horizontal, 28)
            .animation(Motion.standard, value: session.chat.memoryEnabled)
            .onAppear { shown = true }
        }
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: 0) {
            if !compact {
                QuireMark(width: 40, breathing: true)
                    .padding(.bottom, 22)
                    .entrance(shown)
            }

            Text(greeting)
                .font(.system(compact ? .title2 : .title, design: .serif).weight(.semibold))
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

            if !compact, session.project != nil || session.persona != nil {
                contextChips
                    .padding(.top, 18)
                    .entrance(shown, delay: 0.14)
            }

            if !compact, let last = lastChat {
                pickUp(last)
                    .padding(.top, 24)
                    .entrance(shown, delay: 0.2)
            }
        }
        .frame(maxWidth: 360)
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
            VStack(spacing: 3) {
                Label("Continue", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.qAccent)
                Text(c.title)
                    .font(.subheadline)
                    .foregroundStyle(Color.qInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 300)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Continue your last chat, \(c.title)")
    }
}

/// Ways to begin, as quiet rows just above the message box, where your thumb already is. A row opens
/// into three more specific openings; picking one fills the message box (and brings up the
/// keyboard). Nothing is sent until you send it.
private struct StarterMenu: View {
    let session: ChatSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openId: String? = nil
    @State private var shown = false

    private var open: StarterGroup? { StarterGroup.all.first { $0.id == openId } }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let g = open {
                options(g)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 28)),
                        removal: .opacity.combined(with: .offset(x: 28))))
            } else {
                groups
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(x: -28)),
                        removal: .opacity.combined(with: .offset(x: -28))))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.standard, value: openId)
        .onAppear { shown = true }
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(StarterGroup.all.enumerated()), id: \.element.id) { i, g in
                Button {
                    Haptics.selection()
                    openId = g.id
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: g.symbol)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.qAccent)
                            .frame(width: 24)
                        Text(g.title)
                            .font(.body)
                            .foregroundStyle(Color.qInk)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.qInk2.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                    .contentShape(.rect)
                }
                .buttonStyle(StarterRowStyle())
                .accessibilityHint("Shows three ways to start")
                .opacity(shown ? 1 : 0)
                .offset(y: shown || reduceMotion ? 0 : 8)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.standard.delay(Double(i) * 0.04), value: shown)
            }
        }
    }

    private func options(_ g: StarterGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                openId = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.footnote.weight(.bold))
                    Image(systemName: g.symbol)
                        .font(.footnote.weight(.semibold))
                    Text(g.title)
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.qInk2)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .contentShape(.rect)
            }
            .buttonStyle(StarterRowStyle())
            .accessibilityLabel("Back to all starters")

            ForEach(g.options) { o in
                let on = session.draft == o.text
                Button {
                    Haptics.selection()
                    session.prefill = o.text
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(o.title)
                                .font(.body)
                                .foregroundStyle(Color.qInk)
                            Text("“\(o.text.trimmingCharacters(in: .whitespacesAndNewlines))…”")
                                .font(.footnote)
                                .foregroundStyle(Color.qInk2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: on ? "checkmark" : "arrow.up.left")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(on ? Color.qAccent : Color.qInk2.opacity(0.6))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 50)
                    .contentShape(.rect)
                }
                .buttonStyle(StarterRowStyle())
                .accessibilityHint("Starts your message with “\(o.text.trimmingCharacters(in: .whitespacesAndNewlines))”")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// A row that shows a soft wash under your finger, like a list row, without a list.
private struct StarterRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.qInk.opacity(configuration.isPressed ? 0.07 : 0), in: .rect(cornerRadius: 12, style: .continuous))
            .animation(Motion.press, value: configuration.isPressed)
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
