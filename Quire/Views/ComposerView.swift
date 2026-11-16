import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// The message box, after Claude's. At rest it folds down to one line, attach, the prompt, and
/// (while a reply is coming) stop. Tap it and it opens out: the text on top; underneath, attach, the
/// model with its thinking level, how full the context is, and a send button that only arrives once
/// there's something to send. The same text view serves both, so the tap that opens it is the tap
/// that brings up the keyboard.
struct ComposerView: View {
    let session: ChatSession
    let openModels: () -> Void
    let openSettings: () -> Void
    let onFocus: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var text = ""
    @State private var attachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var showContext = false
    @State private var attachNote: String? = nil
    @State private var loadingAttachments = 0
    @State private var focused = false
    @Namespace private var bar

    private var trimmedEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { !session.generating && loadingAttachments == 0 && (!trimmedEmpty || !attachments.isEmpty) }
    private var model: ORModel? { session.model }
    /// The round button exists only while it has a job: sending what's typed, or stopping a reply.
    private var showsAction: Bool { session.generating || !trimmedEmpty || !attachments.isEmpty }
    /// The open box's inner margin: its corner radius less a round button's.
    private static let inset = Radius.composer - Size.control / 2

    /// Folded to one line: nothing typed, nothing attached, nothing to say, and the keyboard away.
    private var collapsed: Bool {
        !focused && text.isEmpty && attachments.isEmpty && loadingAttachments == 0 && noteText == nil
    }

    var body: some View {
        let layout = collapsed
            ? AnyLayout(HStackLayout(alignment: .center, spacing: Space.s))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty || loadingAttachments > 0 {
                attachmentStrip
                    .padding(.bottom, Space.m)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let note = noteText {
                noteRow(note)
                    .padding(.bottom, Space.s)
                    .transition(.opacity)
            }

            layout {
                if collapsed {
                    attachMenu
                        .matchedGeometryEffect(id: "attach", in: bar)
                }
                textArea
                if collapsed {
                    if showsAction {
                        actionButton
                            .matchedGeometryEffect(id: "action", in: bar)
                            .transition(reduceMotion ? .opacity : .pop)
                    }
                } else {
                    controls
                        .transition(.opacity.combined(with: .offset(y: 6)))
                }
            }
        }
        // Concentric with the box: open, the round buttons sit the box's radius less their own in
        // from its edge; folded, the box is a capsule around them.
        .padding(.horizontal, collapsed ? Space.s : Self.inset)
        .padding(.top, collapsed ? Space.s : Self.inset + Space.xs)
        .padding(.bottom, collapsed ? Space.s : Self.inset)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.composer, style: .continuous))
        .overlay {
            // A hairline that firms up while you're typing.
            RoundedRectangle(cornerRadius: Radius.composer, style: .continuous)
                .strokeBorder(Color.qInk.opacity(focused ? 0.16 : 0.07), lineWidth: 1)
                .allowsHitTesting(false)
        }
        // Folded, the whole bar is the place to tap, not just the line of text in it.
        .contentShape(.rect(cornerRadius: Radius.composer, style: .continuous))
        .gesture(TapGesture().onEnded { focused = true }, including: collapsed ? .all : .subviews)
        .padding(.horizontal, Self.inset)
        .padding(.bottom, Space.s)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.morph, value: collapsed)
        .animation(reduceMotion ? nil : Motion.quick, value: attachments)
        .animation(reduceMotion ? nil : Motion.quick, value: noteText)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy, value: showsAction)
        .onChange(of: focused) { _, isFocused in
            if isFocused { onFocus() }
            onFocusChange(isFocused)
        }
        .onAppear { text = session.draft }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 6, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await loadPhotos(items) }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: allowedFileTypes, allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await loadFiles(urls) }
            case .failure(let e): attachNote = e.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                Task { await add { try await AttachmentMaker.image(img, name: "photo.jpg") } }
            }
            .ignoresSafeArea()
        }
    }

    /// The prompt and the text you type, one line folded, growing to eight open.
    private var textArea: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(Color.qInk2.opacity(0.85))
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // A hardware keyboard's Return sends (Shift+Return for a new line), like the PWA's
            // "send on Enter". The on-screen keyboard always inserts a line.
            ComposerTextView(text: $text, focused: $focused,
                             sendOnHardwareReturn: app.settings.ui.sendOnEnter,
                             hint: placeholder,
                             rounded: app.settings.ui.typeface == .sfRounded,
                             theme: app.settings.ui.colorTheme,
                             onSend: send,
                             onPasteImage: { img in
                                 Task { await add { try await AttachmentMaker.image(img, name: "pasted.jpg") } }
                             })
        }
        // Open, the text starts a standard space in from the box's edge.
        .padding(.horizontal, collapsed ? Space.xxs : Space.l - Self.inset)
        .padding(.bottom, collapsed ? 0 : Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text) { _, new in session.saveDraft(new) }
    }

    private var placeholder: String {
        if !session.chat.memoryEnabled { return "Incognito message" }
        return session.path.isEmpty ? "Ask anything" : "Reply…"
    }

    // MARK: Bottom row

    private var controls: some View {
        HStack(spacing: Space.s) {
            attachMenu
                .matchedGeometryEffect(id: "attach", in: bar)
            modelMenu
            Spacer(minLength: 4)
            if app.settings.ui.showContext {
                contextButton
                    .transition(.opacity)
            }
            if showsAction {
                actionButton
                    .matchedGeometryEffect(id: "action", in: bar)
                    .transition(reduceMotion ? .opacity : .pop)
            }
        }
    }

    // MARK: Attach

    /// Always here. A model that doesn't list image input still gets the choice, with a note saying
    /// so (and a way to switch) rather than a button that silently disappears.
    private var attachMenu: some View {
        Menu {
            Section {
                Button { showPhotos = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
                }
                if UIPasteboard.general.hasImages {
                    Button(action: pasteImage) { Label("Paste image", systemImage: "doc.on.clipboard") }
                }
            } header: {
                if let m = model, !m.acceptsImages { Text("\(m.shortName) doesn't list image input") }
            }
            Section {
                Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.qInk)
                .frame(width: Size.control, height: Size.control)
                .background(Color.qInk.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .accessibilityLabel("Attach")
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.m) {
                ForEach(attachments) { a in pendingChip(a) }
                if loadingAttachments > 0 {
                    ProgressView()
                        .frame(width: 60, height: 60)
                        .card(radius: Radius.s, fill: .qSunken)
                }
            }
            .padding(.top, Space.s)
            .padding(.horizontal, Space.s)
        }
    }

    // MARK: Model and thinking

    /// "DeepSeek V4 Flash · High". For a model that can think, a short menu: the thinking levels and
    /// a way into the model picker. For one that can't, a tap goes straight to the picker.
    @ViewBuilder
    private var modelMenu: some View {
        if model?.supportsReasoning == true {
            let style = ReasoningStyle.detect(model)
            Menu {
                Section("Thinking") {
                    if style.canDisable {
                        Button {
                            session.setThinking(nil)
                            Haptics.selection()
                        } label: {
                            checkLabel("Off", on: currentReasoning?.mode == nil || currentReasoning?.mode == .off)
                        }
                    }
                    ForEach(style.efforts.filter { $0 != ReasoningEffort.none }, id: \.self) { e in
                        Button {
                            session.setThinking(e)
                            Haptics.selection()
                        } label: {
                            checkLabel(e.label, on: currentReasoning?.mode == .effort && (currentReasoning?.effort ?? .medium) == e)
                        }
                    }
                }
                Button(action: openModels) { Label("Change model…", systemImage: "square.grid.2x2") }
                Button(action: openSettings) { Label("Chat settings…", systemImage: "slider.horizontal.3") }
            } label: {
                modelPill
            }
            .accessibilityLabel(modelAccessibilityLabel)
            .accessibilityHint("Choose a thinking level or change model")
        } else {
            Button(action: openModels) { modelPill }
                .buttonStyle(.pressable)
                .accessibilityLabel(modelAccessibilityLabel)
                .accessibilityHint("Change model")
        }
    }

    private var modelPill: some View {
        HStack(spacing: Space.xs) {
            Text(app.modelName(session.chat.modelId))
                .foregroundStyle(Color.qInk)
                .lineLimit(1)
                .contentTransition(.opacity)
            if let t = session.thinkingLabel {
                Text(t)
                    .foregroundStyle(Color.qInk2)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.opacity)
                    .transition(.opacity)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.qInk2)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Space.m)
        .frame(height: Size.control)
        .background(Color.qInk.opacity(0.08), in: .capsule)
        .contentShape(.capsule)
        .animation(Motion.quick, value: session.chat.modelId)
        .animation(Motion.quick, value: session.thinkingLabel)
    }

    private var modelAccessibilityLabel: String {
        "Model: \(app.modelName(session.chat.modelId))\(session.thinkingLabel.map { ", thinking \($0)" } ?? "")"
    }

    private var currentReasoning: ReasoningSettings? { session.effectiveSettings.reasoning }

    @ViewBuilder
    private func checkLabel(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    // MARK: Context

    private var used: Int { session.liveContextTokens + Tokens.estimate(text) }
    private var contextLimit: Int { model?.contextLength ?? 0 }
    private var fraction: Double { contextLimit > 0 ? Double(used) / Double(contextLimit) : 0 }
    private var contextText: String {
        contextLimit > 0 ? "\(Fmt.tokens(used))/\(Fmt.context(contextLimit))" : Fmt.tokens(used)
    }

    private var contextButton: some View {
        Button { showContext = true } label: {
            HStack(spacing: Space.s) {
                ContextRing(fraction: fraction, warn: fraction > 0.85)
                    .frame(width: 15, height: 15)
                Text(contextText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Space.xs)
            .frame(height: Size.control)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $showContext, arrowEdge: .bottom) {
            contextDetails
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(contextLimit > 0 ? "Context \(Fmt.tokens(used)) of \(Fmt.tokens(contextLimit)) tokens" : "Context \(Fmt.tokens(used)) tokens")
        .accessibilityHint("Shows context details")
    }

    private var contextDetails: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Context")
                    .displayFont { .system(.headline, design: $0) }
                    .foregroundStyle(Color.qInk)
                Spacer()
                if contextLimit > 0 {
                    Text(fraction < 0.01 ? "<1%" : "\(Int((fraction * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                }
            }
            if contextLimit > 0 {
                MeterBar(fraction: fraction, warn: fraction > 0.85, height: 6)
            }
            Text(contextLimit > 0 ? "\(used.formatted()) of \(contextLimit.formatted()) tokens" : "\(used.formatted()) tokens so far")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.qInk2)
            if app.settings.ui.showCosts && session.chat.totalCostUsd > 0 {
                Text("Spent in this chat: \(Fmt.usd(session.chat.totalCostUsd))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
            Divider()
            Button {
                showContext = false
                // Let the popover finish leaving before the sheet comes up.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    openSettings()
                }
            } label: {
                Label("Chat settings", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.qAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(Space.l)
        .frame(width: 270)
    }

    // MARK: Notes

    private var capabilityNote: String? {
        guard let m = model else { return nil }
        if attachments.contains(where: { $0.kind == .image }) && !m.acceptsImages { return "\(m.shortName) doesn't list image input; this will likely fail." }
        if attachments.contains(where: { $0.kind == .file }) && !m.acceptsFiles { return "\(m.shortName) may not read files; OpenRouter's parser may be used and billed." }
        return nil
    }

    private var noteText: String? {
        if let attachNote { return attachNote }
        if let c = capabilityNote { return c }
        if !app.connectivity.online { return "You're offline. Your draft is kept." }
        return nil
    }

    private func noteRow(_ note: String) -> some View {
        let isError = attachNote != nil
        let isCapability = !isError && capabilityNote != nil
        return HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : (isCapability ? "info.circle.fill" : "wifi.slash"))
            Text(note)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if isCapability {
                Button("Switch model", action: openModels)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.qAccent)
                    .buttonStyle(.plain)
            }
        }
        .font(.caption)
        .foregroundStyle(isError ? Color.qDanger : Color.qWarn)
        .padding(.horizontal, Space.s)
    }

    private var allowedFileTypes: [UTType] {
        var t: [UTType] = [.pdf, .plainText, .commaSeparatedText, .json, .sourceCode]
        if let md = UTType(filenameExtension: "md") { t.append(md) }
        t.append(.image)
        return t
    }

    private func pendingChip(_ a: Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if a.kind == .image, let img = ThumbnailCache.image(for: a) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    VStack(spacing: Space.xs) {
                        Image(systemName: "doc.text")
                        Text(a.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(Space.s)
                    .foregroundStyle(Color.qInk2)
                }
            }
            .frame(width: 60, height: 60)
            .background(Color.qSunken)
            .clipShape(.rect(cornerRadius: Radius.s, style: .continuous))

            Button {
                attachments.removeAll { $0.id == a.id }
                attachNote = nil
                Haptics.tap()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.qOnAccent, Color.qInk2)
                    .font(.system(size: 20))
            }
            .offset(x: 7, y: -7)
            .accessibilityLabel("Remove \(a.name)")
        }
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func add(_ make: () async throws -> Attachment) async {
        loadingAttachments += 1
        defer { loadingAttachments -= 1 }
        do {
            let a = try await make()
            attachments.append(a)
            attachNote = nil
            Haptics.selection()
        } catch {
            attachNote = error.localizedDescription
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for (n, item) in items.enumerated() {
            await add {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw AttachmentMaker.Failure.unreadable("That photo") }
                return try await AttachmentMaker.image(data, name: "image-\(n + 1).jpg")
            }
        }
    }

    private func loadFiles(_ urls: [URL]) async {
        for u in urls {
            await add { try await AttachmentMaker.file(at: u) }
        }
    }

    private func pasteImage() {
        guard let img = UIPasteboard.general.image else { return }
        Task { await add { try await AttachmentMaker.image(img, name: "pasted.jpg") } }
    }

    // MARK: Send / stop

    /// Accent, round, and only here while it has something to do; it springs in on the first
    /// character and becomes a stop button while a reply is coming.
    private var actionButton: some View {
        Button {
            if session.generating {
                session.stop()
                Haptics.tap()
            } else {
                send()
            }
        } label: {
            Image(systemName: session.generating ? "stop.fill" : "arrow.up")
                .font(.system(size: session.generating ? 13 : 16, weight: .bold))
                .foregroundStyle(Color.qOnAccent)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Size.control, height: Size.control)
                .background(Color.qAccent.gradient, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .disabled(!session.generating && !canSend)
        .opacity(!session.generating && !canSend ? 0.5 : 1)
        .shadow(color: Color.qAccent.opacity(0.35), radius: 8, y: 2)
        .animation(Motion.quick, value: session.generating)
        .accessibilityLabel(session.generating ? "Stop" : "Send")
    }

    private func send() {
        guard canSend else { return }
        guard app.connectivity.online else {
            app.toasts.show("You're offline. Your draft is saved.", symbol: "wifi.slash")
            Haptics.warning()
            return
        }
        Haptics.tap()
        session.send(text, attachments: attachments)
        text = ""
        attachments = []
        attachNote = nil
    }
}
