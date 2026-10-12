import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ComposerView: View {
    let session: ChatSession
    let openModels: () -> Void
    let openSettings: () -> Void
    let onFocus: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var text = ""
    @State private var attachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var attachNote: String? = nil
    @State private var loadingAttachments = 0
    @FocusState private var focused: Bool

    private var trimmedEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { !session.generating && loadingAttachments == 0 && (!trimmedEmpty || !attachments.isEmpty) }
    private var model: ORModel? { session.model }
    private var canAttachImages: Bool { model?.acceptsImages ?? true }
    private var canAttachFiles: Bool { model?.acceptsFiles ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            metaRow

            if !attachments.isEmpty || loadingAttachments > 0 {
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
                    .padding(.trailing, 6)
                }
                .transition(.opacity)
            }

            if let note = attachNote ?? capabilityNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(attachNote != nil ? Color.qDanger : Color.qWarn)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if canAttachImages || canAttachFiles { attachMenu }

                TextField(session.chat.memoryEnabled ? "Message" : "Incognito message", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .foregroundStyle(Color.qInk)
                    .tint(Color.qAccent)
                    .focused($focused)
                    .padding(.vertical, 8)
                    .onChange(of: text) { _, new in session.saveDraft(new) }
                    .onKeyPress(.return, phases: .down) { press in
                        // A hardware keyboard's Return sends (Shift+Return for a new line), like the PWA's
                        // "send on Enter". The on-screen keyboard always inserts a line.
                        guard app.settings.ui.sendOnEnter, !press.modifiers.contains(.shift) else { return .ignored }
                        send()
                        return .handled
                    }
                    .accessibilityLabel("Message")

                sendButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : Motion.quick, value: attachments)
        .animation(reduceMotion ? nil : Motion.quick, value: attachNote)
        .onChange(of: focused) { _, isFocused in if isFocused { onFocus() } }
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

    // MARK: Meta row: model · offline · context meter · cost · settings

    private var metaRow: some View {
        HStack(spacing: 10) {
            Button(action: openModels) {
                HStack(spacing: 4) {
                    Text(app.modelName(session.chat.modelId))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.generating ? Color.qAccent : Color.qInk)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Model: \(app.modelName(session.chat.modelId))")
            .accessibilityHint("Choose a different model")

            if !app.connectivity.online {
                Label("Offline", systemImage: "wifi.slash")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.qWarn)
                    .transition(.opacity)
            }

            Spacer(minLength: 6)

            Button(action: openSettings) {
                HStack(spacing: 6) {
                    if contextLimit > 0 {
                        MeterBar(fraction: Double(used) / Double(contextLimit), warn: Double(used) / Double(contextLimit) > 0.85, height: 3)
                            .frame(width: 40)
                    }
                    Text(contextText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if app.settings.ui.showCosts && session.chat.totalCostUsd > 0 {
                        Text("·")
                        Text(Fmt.usd(session.chat.totalCostUsd))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.qInk2)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(contextLimit > 0 ? "Context \(Fmt.tokens(used)) of \(Fmt.tokens(contextLimit)) tokens" : "Context \(Fmt.tokens(used)) tokens")
            .accessibilityHint("Opens chat settings")
        }
        .animation(Motion.quick, value: app.connectivity.online)
    }

    private var used: Int { session.liveContextTokens + Tokens.estimate(text) }
    private var contextLimit: Int { model?.contextLength ?? 0 }
    private var contextText: String {
        contextLimit > 0 ? "\(Fmt.tokens(used))/\(Fmt.context(contextLimit))" : Fmt.tokens(used)
    }

    private var capabilityNote: String? {
        guard let m = model else { return nil }
        if attachments.contains(where: { $0.kind == .image }) && !m.acceptsImages { return "\(m.shortName) doesn't list image input; this will likely fail." }
        if attachments.contains(where: { $0.kind == .file }) && !m.acceptsFiles { return "\(m.shortName) may not read files; OpenRouter's parser may be used and billed." }
        return nil
    }

    // MARK: Attach

    private var attachMenu: some View {
        Menu {
            if canAttachImages {
                Button { showPhotos = true } label: { Label("Photo library", systemImage: "photo.on.rectangle") }
                if CameraPicker.isAvailable {
                    Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                }
                if UIPasteboard.general.hasImages {
                    Button(action: pasteImage) { Label("Paste image", systemImage: "doc.on.clipboard") }
                }
            }
            if canAttachFiles {
                Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 36, height: 36)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Attach")
    }

    private var allowedFileTypes: [UTType] {
        var t: [UTType] = [.pdf, .plainText, .commaSeparatedText, .json, .sourceCode]
        if let md = UTType(filenameExtension: "md") { t.append(md) }
        if canAttachImages { t.append(.image) }
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

    private var sendButton: some View {
        Button {
            if session.generating {
                session.stop()
                Haptics.tap()
            } else {
                send()
            }
        } label: {
            Image(systemName: session.generating ? "stop.fill" : "arrow.up")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 22, height: 22)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .disabled(!session.generating && !canSend)
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
