import SwiftUI
import PhotosUI

struct ComposerView: View {
    let session: ChatSession
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @State private var attachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var attachError: String? = nil
    @State private var sendCount = 0
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !session.generating && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    private var capabilityNote: String? {
        guard let m = session.model else { return nil }
        if attachments.contains(where: { $0.kind == .image }) && !m.acceptsImages { return "\(m.shortName) doesn't accept images." }
        if attachments.contains(where: { $0.kind == .file }) && !m.acceptsFiles { return "\(m.shortName) may not read files; OpenRouter will try to convert them." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { a in pendingChip(a) }
                    }
                    .padding(.horizontal, 2)
                }
            }
            if let note = capabilityNote ?? attachError {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(attachError != nil ? Color.qDanger : Color.qInk2)
            }
            HStack(alignment: .bottom, spacing: 10) {
                Menu {
                    Button { showPhotos = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
                    Button { showFiles = true } label: { Label("Files", systemImage: "folder") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .foregroundStyle(Color.qInk2)
                .accessibilityLabel("Attach")

                TextField("Message", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.body)
                    .foregroundStyle(Color.qInk)
                    .focused($focused)
                    .padding(.vertical, 8)
                    .onChange(of: text) { _, new in session.saveDraft(new) }

                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 4, matching: .images)
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for u in urls {
                    do { attachments.append(try AttachmentMaker.file(at: u)) }
                    catch { attachError = error.localizedDescription }
                }
            case .failure(let e):
                attachError = e.localizedDescription
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
        .onAppear { text = session.draft }
        .sensoryFeedback(.impact(weight: .light), trigger: sendCount) { _, _ in app.settings.ui.hapticsEnabled }
    }

    private var sendButton: some View {
        ZStack {
            if session.generating {
                Button { session.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("Stop")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.glassProminent)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: session.generating)
    }

    private func pendingChip(_ a: Attachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if a.kind == .image, let img = ThumbnailCache.image(for: a) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "doc")
                        Text(a.name).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .padding(6)
                    .foregroundStyle(Color.qInk2)
                }
            }
            .frame(width: 64, height: 64)
            .background(Color.qRaised)
            .clipShape(.rect(cornerRadius: 10))

            Button {
                attachments.removeAll { $0.id == a.id }
                attachError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.qOnAccent, Color.qInk2)
                    .font(.system(size: 18))
            }
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove \(a.name)")
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
    }

    private func send() {
        guard canSend else { return }
        session.send(text, attachments: attachments)
        text = ""
        attachments = []
        attachError = nil
        sendCount += 1
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        photoItems = []
        for (n, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                attachments.append(try AttachmentMaker.image(data, name: "image-\(n + 1).jpg"))
            } catch {
                attachError = error.localizedDescription
            }
        }
    }
}
