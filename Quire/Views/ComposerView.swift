import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// The message box, after Claude's. At rest it folds down to one line, attach, the prompt, and
/// (while a reply is coming) stop, standing in from the sides and sitting down by the home
/// indicator. Tap it and it opens out to the full width as it rises with the keyboard: the text on
/// top; underneath, attach, the model with its thinking level, and a send button that only arrives
/// once there's something to send. The same text view serves both, so
/// the tap that opens it is the tap that brings up the keyboard.
struct ComposerView: View {
    let session: ChatSession
    let openModels: () -> Void
    let openSettings: () -> Void
    let onFocus: () -> Void
    /// Quire's own windows, which the attach and model buttons open, shared with the chat screen
    /// that draws them.
    let panels: ChatPanels
    var onFocusChange: (Bool) -> Void = { _ in }
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
    @State private var focused = false
    /// The model, arriving a beat after the box starts to open (see `body`).
    @State private var controlsShown = false
    /// The home indicator's inset, which the box sits down into while the keyboard is away.
    @State private var homeInset = HomeIndicator.inset
    @Namespace private var bar

    private var trimmedEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSend: Bool { !session.generating && loadingAttachments == 0 && (!trimmedEmpty || !attachments.isEmpty) }
    private var model: ORModel? { session.model }
    /// The round button exists only while it has a job: sending what's typed, or stopping a reply.
    private var showsAction: Bool { session.generating || !trimmedEmpty || !attachments.isEmpty }
    /// The open box's inner margin: its corner radius less a round button's. Open, it's also the
    /// space either side of the box, so the box runs nearly edge to edge.
    private static let inset = Radius.composer - Size.control / 2

    /// Where the box rests while you're not in it. Two numbers to tune by eye on a phone.
    private enum Rest {
        /// Folded, the box stands this far in from each side of the screen.
        static let side: CGFloat = Space.xl
        /// With the keyboard away, its bottom edge sits this far above the bottom of the screen,
        /// down beside the home indicator rather than a whole safe area above it.
        static let bottom: CGFloat = Space.xl
    }

    /// The space under the box. Typing, it sits just above the keyboard. Otherwise, on a phone
    /// with a home indicator, it reaches down into that inset to `Rest.bottom` from the screen's
    /// edge; on one without (or in a window with nothing below), it keeps a small margin.
    private var bottomSpace: CGFloat {
        guard !focused, homeInset > Rest.bottom - Space.s else { return Space.s }
        return Rest.bottom - homeInset
    }

    /// Folded to one line: nothing typed, attached or quoted, nothing to say, and the keyboard away.
    private var collapsed: Bool {
        !focused && text.isEmpty && attachments.isEmpty && loadingAttachments == 0 && noteText == nil && session.quote == nil
            && panels.open != .model
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

            if let quote = session.quote {
                quoteRow(quote)
                    .padding(.bottom, Space.m)
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
                    // The row itself arrives as it is, so the attach and send buttons it carries
                    // travel down into it without dipping; the model inside it makes its own
                    // entrance. Folding, it all goes at once, and quickly.
                    controls
                        .transition(.asymmetric(insertion: .identity,
                                                removal: .opacity.animation(reduceMotion ? .easeOut(duration: 0.15) : Motion.quick)))
                }
            }
        }
        // Concentric with the box: open, the round buttons sit the box's radius less their own in
        // from its edge; folded, the box is a capsule around them.
        .padding(.horizontal, collapsed ? Space.s : Self.inset)
        .padding(.top, collapsed ? Space.s : Self.inset + Space.xs)
        .padding(.bottom, collapsed ? Space.s : Self.inset)
        // Folded, the glass answers a touch the moment it lands, as a native bar does.
        .glassEffect(.regular.interactive(collapsed), in: .rect(cornerRadius: Radius.composer, style: .continuous))
        .overlay {
            // A hairline that firms up while you're typing.
            RoundedRectangle(cornerRadius: Radius.composer, style: .continuous)
                .strokeBorder(Color.qInk.opacity(focused ? 0.16 : 0.07), lineWidth: 1)
                .allowsHitTesting(false)
        }
        // Folded, the whole bar is the place to tap, not just the line of text in it.
        .contentShape(.rect(cornerRadius: Radius.composer, style: .continuous))
        .gesture(TapGesture().onEnded { focused = true }, including: collapsed ? .all : .subviews)
        .padding(.horizontal, collapsed ? Rest.side : Self.inset)
        .padding(.bottom, bottomSpace)
        .background { HomeIndicator.Probe(inset: $homeInset) }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.morph, value: collapsed)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.morph, value: focused)
        .animation(reduceMotion ? nil : Motion.quick, value: attachments)
        .animation(reduceMotion ? nil : Motion.quick, value: noteText)
        .animation(reduceMotion ? nil : Motion.quick, value: session.quote)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : Motion.bouncy, value: showsAction)
        .onChange(of: focused) { _, isFocused in
            if isFocused { onFocus() }
            onFocusChange(isFocused)
        }
        .onChange(of: collapsed) { _, folded in
            // The box leads; the model follows it in a beat behind, once there's room for it.
            // Folding, it's already on its way out with its row.
            if folded {
                controlsShown = false
            } else {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : Motion.morph.delay(0.09)) { controlsShown = true }
            }
        }
        .onAppear {
            text = session.draft
            controlsShown = !collapsed
        }
        // A passage quoted from a message: the box opens on it, ready for the question.
        .onChange(of: session.quote) { _, quote in
            if quote != nil { focused = true }
        }
        // What the attach window asked for, once it has closed.
        .onChange(of: panels.request) { _, request in
            guard let request else { return }
            panels.request = nil
            switch request {
            case .photos: showPhotos = true
            case .camera: showCamera = true
            case .files: showFiles = true
            case .paste: pasteImage()
            case .asset(let id):
                Task { await add { try await RecentPhotos.data(for: id) } }
            }
        }
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
                    .font(.system(.body, design: typedFace))
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
                             face: typedFace,
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

    /// What you type is set in Allo when that's the typeface; otherwise in SF Pro.
    private var typedFace: Face { app.settings.ui.typedFace }

    private var placeholder: String {
        if session.quote != nil { return "Ask about this…" }
        if !session.chat.memoryEnabled { return "Incognito message" }
        return session.path.isEmpty ? "Ask anything" : "Reply…"
    }

    // MARK: Bottom row

    private var controls: some View {
        HStack(spacing: Space.s) {
            attachMenu
                .matchedGeometryEffect(id: "attach", in: bar)
            modelMenu
                .modifier(Arrival(shown: controlsShown, reduceMotion: reduceMotion))
            Spacer(minLength: 4)
            if showsAction {
                actionButton
                    .matchedGeometryEffect(id: "action", in: bar)
                    .transition(reduceMotion ? .opacity : .pop)
            }
        }
    }

    // MARK: Attach

    /// Always here, and opens Quire's attach window. A model that doesn't list image input still
    /// gets the choice, with a note there saying so, rather than a button that silently disappears.
    /// The plus turns to a cross while the window is open, so the same button closes it.
    private var attachMenu: some View {
        let open = panels.open == .attach
        return Button {
            Haptics.selection()
            panels.toggle(.attach)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.qInk)
                .rotationEffect(.degrees(open ? 45 : 0))
                .frame(width: Size.control, height: Size.control)
                .background(Color.qInk.opacity(open ? 0.14 : 0.08), in: .circle)
                .contentShape(.circle)
                .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0), value: open)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .accessibilityLabel(open ? "Close attach" : "Attach")
        .accessibilityHint(open ? "" : "Photos, camera, files and projects")
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

    /// "DeepSeek V4 Flash · High". Opens the model window: the thinking levels, the last few
    /// models you've used, and the way into the full picker.
    private var modelMenu: some View {
        Button {
            Haptics.selection()
            panels.toggle(.model)
        } label: {
            modelPill
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(modelAccessibilityLabel)
        .accessibilityHint("Thinking level, recent models, or another model")
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
            Image(systemName: "chevron.up")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.qInk2)
                .rotationEffect(.degrees(panels.open == .model ? 180 : 0))
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, Space.m)
        .frame(height: Size.control)
        .background(Color.qInk.opacity(panels.open == .model ? 0.14 : 0.08), in: .capsule)
        .animation(reduceMotion ? nil : .spring(duration: 0.28, bounce: 0), value: panels.open)
        .contentShape(.capsule)
        .animation(Motion.quick, value: session.chat.modelId)
        .animation(Motion.quick, value: session.thinkingLabel)
    }

    private var modelAccessibilityLabel: String {
        "Model: \(app.modelName(session.chat.modelId))\(session.thinkingLabel.map { ", thinking \($0)" } ?? "")"
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

    // MARK: Quote

    /// The passage being quoted, as it will read in your message: under a rule, a few lines of
    /// it, with a way to take it back out.
    private func quoteRow(_ quote: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Capsule()
                .fill(Color.qAccent)
                .frame(width: 3)
            Text(quote)
                .font(.system(.subheadline, design: typedFace))
                .foregroundStyle(Color.qInk2)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                session.quote = nil
                Haptics.tap()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.qInk2)
                    .frame(width: 28, height: 28)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove quote")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Space.l - Self.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quoting: \(quote)")
    }

    /// Markdown's quote: each line of the passage behind "> ", then a blank line.
    private static func quoted(_ passage: String) -> String {
        passage.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n") + "\n\n"
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
        .shadow(color: Color.qGlow.opacity(0.35), radius: 8, y: 2)
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
        session.send(session.quote.map { Self.quoted($0) + text } ?? text, attachments: attachments)
        session.quote = nil
        text = ""
        attachments = []
        attachNote = nil
    }
}

/// How the model comes into the opening box: up a few points out of a slight blur,
/// so they read as settling into place rather than switching on. Reduce Motion keeps the fade.
private struct Arrival: ViewModifier {
    let shown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .blur(radius: shown || reduceMotion ? 0 : 2)
    }
}

/// The window's bottom safe-area inset: the home indicator's strip, or nothing on a phone with a
/// Home button. Read from the window, which the keyboard never changes, and kept current through
/// rotation by a probe view.
enum HomeIndicator {
    static var inset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }

    struct Probe: UIViewRepresentable {
        @Binding var inset: CGFloat

        func makeUIView(context: Context) -> ProbeView {
            let v = ProbeView()
            v.isUserInteractionEnabled = false
            v.report = { new in if inset != new { inset = new } }
            return v
        }

        func updateUIView(_ v: ProbeView, context: Context) {
            v.report = { new in if inset != new { inset = new } }
        }
    }

    final class ProbeView: UIView {
        var report: (CGFloat) -> Void = { _ in }
        private var last: CGFloat = -1

        override func didMoveToWindow() {
            super.didMoveToWindow()
            send()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            send()
        }

        /// Outside the view update that laid this out, since it writes SwiftUI state.
        private func send() {
            guard let value = window?.safeAreaInsets.bottom, value != last else { return }
            last = value
            DispatchQueue.main.async { [weak self] in self?.report(value) }
        }
    }
}
