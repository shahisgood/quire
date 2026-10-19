import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// The message box, after Claude's: the text on top; underneath, attach, the model with its thinking
/// level, how full the context is, and a send button that only arrives once there's something to send.
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

    private var trimmedEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { !session.generating && loadingAttachments == 0 && (!trimmedEmpty || !attachments.isEmpty) }
    private var model: ORModel? { session.model }
    /// The round button exists only while it has a job: sending what's typed, or stopping a reply.
    private var showsAction: Bool { session.generating || !trimmedEmpty || !attachments.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty || loadingAttachments > 0 {
                attachmentStrip
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let note = noteText {
                noteRow(note)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

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
                                 onSend: send,
                                 onPasteImage: { img in
                                     Task { await add { try await AttachmentMaker.image(img, name: "pasted.jpg") } }
                                 })
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
            .onChange(of: text) { _, new in session.saveDraft(new) }

            controls
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
        .overlay {
            // A hairline that firms up while you're typing.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.qInk.opacity(focused ? 0.16 : 0.07), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : Motion.quick, value: attachments)
        .animation(reduceMotion ? nil : Motion.quick, value: noteText)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy, value: showsAction)
        .animation(Motion.quick, value: focused)
        .onChange(of: focused) { _, isFocused in
            if isFocused { onFocus() }
            onFocusChange(isFocused)
        }
        .onChange(of: session.prefill) { _, new in
            guard let new else { return }
            session.prefill = nil
            // An empty box (or one holding only another starter) takes it; otherwise it leads.
            let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || StarterGroup.isStarter(text) {
                text = new
            } else {
                text = new + text
            }
            focused = true
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

    private var placeholder: String {
        if !session.chat.memoryEnabled { return "Incognito message" }
        return session.path.isEmpty ? "Ask anything" : "Reply…"
    }

    // MARK: Bottom row

    private var controls: some View {
        HStack(spacing: 8) {
            attachMenu
            modelMenu
            Spacer(minLength: 4)
            contextButton
            if showsAction {
                actionButton
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
                .frame(width: 34, height: 34)
                .background(Color.qInk.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .accessibilityLabel("Attach")
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { a in pendingChip(a) }
                if loadingAttachments > 0 {
                    ProgressView()
                        .frame(width: 60, height: 60)
                        .card(radius: 12, fill: .qSunken)
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 6)
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
        HStack(spacing: 5) {
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
        .padding(.horizontal, 12)
        .frame(height: 34)
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
            HStack(spacing: 6) {
                ContextRing(fraction: fraction, warn: fraction > 0.85)
                    .frame(width: 15, height: 15)
                Text(contextText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)
            .frame(height: 34)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Context")
                    .font(.system(.headline, design: .serif))
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
        .padding(16)
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
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
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
        .padding(.horizontal, 6)
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
                    VStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text(a.name)
                            .font(.caption2)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    .padding(6)
                    .foregroundStyle(Color.qInk2)
                }
            }
            .frame(width: 60, height: 60)
            .background(Color.qSunken)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))

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
                .frame(width: 34, height: 34)
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
