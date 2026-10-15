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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Lazy, so each message is built (and drawn on its own layer) only as it nears the
                // screen: a long chat in one plain stack could outgrow what the GPU will draw.
                LazyVStack(alignment: .leading, spacing: density) {
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
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.qBase)
        // "Pinned" means following the bottom. Only while pinned does new text move the viewport;
        // scrolling up to read stops the follow, as in the PWA, and a "Latest" pill brings it back.
        // Only the reader's own scrolling un-pins: when a message is sent, the rows grow while the
        // scroll to the bottom is still animating, and treating that as "scrolled away" left the
        // pill stuck on screen at the bottom of the chat.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.visibleRect.maxY >= geo.contentSize.height - 40
        } action: { _, near in
            nearBottom = near
            updateFollow()
        }
        .onScrollPhaseChange { old, new in
            let wasDragging = Self.isUserPhase(old)
            userScrolling = Self.isUserPhase(new)
            // A drag or fling that comes to rest away from the bottom stops the follow, even if
            // the last position update arrived after the finger lifted.
            if wasDragging && !userScrolling && !atBottom { pinned = false }
            updateFollow()
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

    private func updateFollow() {
        if atBottom { pinned = true } else if userScrolling { pinned = false }
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
    /// once the first message is sent, that corner becomes the new-chat button. It's one toolbar
    /// item whose contents change, so the bar itself never rearranges.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ChatCornerAction(session: session)
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

// MARK: - Top bar

private struct ChatCornerAction: View {
    let session: ChatSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if session.path.isEmpty {
                IncognitoToggle(session: session)
                    .transition(reduceMotion ? .opacity : .pop)
            } else {
                NewChatButton()
                    .transition(reduceMotion ? .opacity : .pop)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy, value: session.path.isEmpty)
    }
}

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

private struct EmptyChatView: View {
    let session: ChatSession
    let openModels: () -> Void
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
            // A greeting that follows the clock, then the model you're about to talk to, then the
            // way into this chat's settings. Each arrives a beat after the one above it.
            VStack(spacing: 22) {
                VStack(spacing: 14) {
                    QuireMark(width: 48, breathing: true)
                        .entrance(shown)
                    Text(greeting)
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(Color.qInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .entrance(shown, delay: 0.06)
                    if !session.chat.memoryEnabled {
                        Label("Incognito. Nothing here is remembered.", systemImage: "eye.slash")
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            .entrance(shown, delay: 0.1)
                    }
                }
                modelCard
                    .entrance(shown, delay: 0.14)
                starters
                HStack(spacing: 10) {
                    if let p = session.persona {
                        Text("\(p.icon ?? "◦")  \(p.name)")
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Color.qAccentSoft, in: .capsule)
                            .foregroundStyle(Color.qInk)
                    }
                    Button(action: openSettings) { Label("Chat settings", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.glass)
                }
                .entrance(shown, delay: 0.46)
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .onAppear { shown = true }
        }
    }

    /// A few ways in. Each one only fills the message box (and brings up the keyboard); the rest of
    /// the sentence is yours, and nothing is sent until you send it.
    private var starters: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(StarterPrompt.all.enumerated()), id: \.element.id) { i, s in
                Button {
                    Haptics.selection()
                    session.prefill = s.text
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: s.symbol)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.qAccent)
                        Text(s.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.qRaised, in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.qRule, lineWidth: 1))
                    .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(s.title)
                .accessibilityHint("Starts your message with “\(s.text.trimmingCharacters(in: .whitespaces))”")
                .entrance(shown, delay: 0.2 + Double(i) * 0.04)
            }
        }
    }

    private var greeting: String {
        guard session.chat.memoryEnabled else { return "Off the record." }
        return Greeting.line(seed: session.chat.id, returning: app.chats.contains { $0.id != session.chat.id })
    }

    private var provider: String {
        session.model?.provider ?? session.chat.modelId.split(separator: "/").first.map(String.init) ?? ""
    }

    /// The model, where it's from, and what it costs and can do: tap to choose another.
    private var modelCard: some View {
        Button(action: openModels) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.modelName(session.chat.modelId))
                            .font(.headline)
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.qInk2)
                }
                if !tags.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        tagRow(tags)
                        tagRow(Array(tags.prefix(2)))
                        tagRow(Array(tags.prefix(1)))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 20)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Model: \(app.modelName(session.chat.modelId)). \(subtitle)")
        .accessibilityHint("Choose a different model")
    }

    private func tagRow(_ items: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { t in
                Text(t)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.qSunken, in: .capsule)
                    .foregroundStyle(Color.qInk2)
            }
        }
    }

    private var subtitle: String {
        guard let m = session.model else { return ProviderStyle.displayName(provider) }
        return "\(ProviderStyle.displayName(m.provider)) · \(Fmt.context(m.contextLength)) context"
    }

    private var tags: [String] {
        guard let m = session.model else { return [] }
        var t = [m.isFree ? "Free" : "\(Pricing.perMillion(m.pricing.prompt)) in · \(Pricing.perMillion(m.pricing.completion)) out"]
        if let thinking = session.thinkingLabel { t.append("Thinking: \(thinking)") }
        if m.acceptsImages { t.append("Sees images") }
        return t
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
