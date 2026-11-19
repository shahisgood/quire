import Photos
import SwiftUI

// The message box's two windows, in place of system menus: attach (camera, photos, files, and the
// project the chat lives in) and the model (what's answering, how hard it thinks, the last few
// models, and the way into the full picker).

// MARK: - Attach

struct AttachPanel: View {
    let session: ChatSession
    let panels: ChatPanels
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Page.main

    private enum Page { case main, projects }

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch page {
            case .main:
                main
                    // Going on, it leaves to the left; coming back, it returns from there.
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            case .projects:
                projects
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(Space.m)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.32, bounce: 0), value: page)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let m = session.model, !m.acceptsImages {
                Label("\(m.shortName) doesn't list image input", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Color.qInk2)
                    .padding(.horizontal, Space.xs)
            }
            RecentPhotos { id in panels.ask(.asset(id)) }
            HStack(spacing: Space.s) {
                if CameraPicker.isAvailable {
                    PanelTile(title: "Camera", symbol: "camera") { panels.ask(.camera) }
                }
                PanelTile(title: "Photos", symbol: "photo.on.rectangle") { panels.ask(.photos) }
                PanelTile(title: "Files", symbol: "folder") { panels.ask(.files) }
                if UIPasteboard.general.hasImages {
                    PanelTile(title: "Paste", symbol: "doc.on.clipboard") { panels.ask(.paste) }
                }
            }
            projectRow
        }
    }

    /// The project this chat is in, or the way into one.
    private var projectRow: some View {
        let project = session.project
        return PanelRow(title: project?.name ?? "Add to project",
                        detail: project == nil ? "Its instructions apply from the next reply" : "This chat's project · change",
                        action: { page = .projects }) {
            if let project {
                ProjectTile(project: project, size: 28)
            } else {
                PanelSymbol(name: "folder.badge.plus")
            }
        } trailing: {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.qInk2)
        }
        .accessibilityHint("Shows your projects")
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Button { page = .main } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.qInk2)
                    Text("Projects")
                        .displayFont { .system(.headline, design: $0) }
                        .foregroundStyle(Color.qInk)
                }
                .padding(.horizontal, Space.xs)
                .frame(minHeight: 36)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            if app.projects.isEmpty {
                Text("No projects yet. Make one from the chat list, then put chats in it from here.")
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Space.xs)
                    .padding(.bottom, Space.xs)
            } else {
                VStack(spacing: 0) {
                    ForEach(app.projects) { p in
                        let on = p.id == session.chat.folderId
                        PanelRow(title: p.name, detail: chatCount(p), selected: on, action: { choose(p.id) }) {
                            ProjectTile(project: p, size: 28)
                        } trailing: {
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.qAccent)
                            }
                        }
                    }
                    if session.chat.folderId != nil {
                        PanelRow("Take out of the project", symbol: "tray.and.arrow.up") { choose(nil) }
                    }
                }
            }
        }
    }

    private func chatCount(_ p: Project) -> String {
        let n = app.chats.filter { $0.folderId == p.id && !$0.archived }.count
        return n == 1 ? "1 chat" : "\(n) chats"
    }

    private func choose(_ id: String?) {
        guard id != session.chat.folderId else {
            panels.close()
            return
        }
        Haptics.selection()
        withAnimation(Motion.standard) { session.setProject(id) }
        panels.close()
        if let p = app.project(id) {
            app.toasts.show("In \(p.name)", symbol: p.symbolName)
        } else {
            app.toasts.show("Out of the project", symbol: "tray.and.arrow.up")
        }
    }
}

// MARK: - Model

struct ModelPanel: View {
    let session: ChatSession
    let openModels: () -> Void
    let openSettings: () -> Void
    let close: () -> Void
    @Environment(AppModel.self) private var app

    private var model: ORModel? { session.model }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            current
            if model?.supportsReasoning == true { thinking }
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    PanelHeading(text: "Recent")
                    VStack(spacing: 0) {
                        ForEach(recents, id: \.id) { m in
                            PanelRow(title: m.shortName, detail: Self.line(m), action: { use(m.id) }) {
                                EmptyView()
                            } trailing: {
                                EmptyView()
                            }
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                PanelRow("All models", symbol: "square.grid.2x2",
                         detail: app.models.isEmpty ? nil : "\(app.models.count.formatted()) on OpenRouter", action: openModels)
                PanelRow("Chat settings", symbol: "slider.horizontal.3", detail: "Prompt, persona, sampling", action: openSettings)
            }
        }
        .padding(Space.m)
    }

    /// What's answering in this chat, set out like a heading, with what it is underneath.
    private var current: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(app.modelName(session.chat.modelId))
                    .displayFont { .system(.title3, design: $0).weight(.semibold) }
                    .foregroundStyle(Color.qInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let model {
                    Text(Self.line(model))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In this chat: \(app.modelName(session.chat.modelId))")
    }

    /// The levels this model thinks at, in a track the selection slides along.
    private var thinking: some View {
        let style = ReasoningStyle.detect(model)
        let r = session.effectiveSettings.reasoning
        var options: [(value: String, label: String)] = []
        if style.canDisable { options.append((value: "off", label: "Off")) }
        for e in style.efforts where e != ReasoningEffort.none {
            options.append((value: e.rawValue, label: Self.short(e)))
        }
        let selected: String
        switch r?.mode {
        case .effort?: selected = (r?.effort ?? .medium).rawValue
        case .budget?: selected = "budget"
        default: selected = "off"
        }
        if selected == "budget" { options.append((value: "budget", label: "Budget")) }
        return VStack(alignment: .leading, spacing: Space.s) {
            PanelHeading(text: "Thinking", detail: session.thinkingLabel ?? "Off")
            SlidingSegments(options: options, selection: Binding(get: { selected }, set: { value in
                if value == "off" { session.setThinking(nil) }
                else if let e = ReasoningEffort(rawValue: value) { session.setThinking(e) }
            }))
            .accessibilityLabel("Thinking")
        }
    }

    private var recents: [ORModel] {
        Array(app.settings.recentModelIds
            .filter { $0 != session.chat.modelId }
            .compactMap { app.model($0) }
            .prefix(4))
    }

    private func use(_ id: String) {
        Haptics.selection()
        session.setModel(id)
        close()
    }

    /// "Anthropic · 200k · $3 / $15".
    static func line(_ m: ORModel) -> String {
        let price = m.isFree ? "Free" : "\(Pricing.perMillion(m.pricing.prompt)) / \(Pricing.perMillion(m.pricing.completion))"
        return "\(ProviderStyle.displayName(m.provider)) · \(Fmt.context(m.contextLength)) · \(price)"
    }

    private static func short(_ e: ReasoningEffort) -> String {
        switch e {
        case .none: "None"
        case .minimal: "Minimal"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "Max"
        }
    }
}

// MARK: - Recent photos

/// Your latest photos along the top of the attach window, each a tap from the message. Only once
/// you've let Quire see them: until then, a line offering to, and iOS asks only when that's
/// tapped, never because the window opened. Photos you've said no to, or a library Quire can't
/// see, leave nothing behind.
struct RecentPhotos: View {
    let pick: (String) -> Void
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Fetched as the view is made, not on appear: with access given and nothing fetched yet the
    /// strip is empty, and an empty view never appears to fetch.
    @State private var assets: [PHAsset] = RecentPhotos.latest()

    var body: some View {
        Group {
            switch status {
            case .authorized, .limited:
                if !assets.isEmpty { strip }
            case .notDetermined:
                PanelRow("Show recent photos here", symbol: "photo.stack", detail: "Pick one in a tap, without opening Photos") {
                    Task {
                        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        assets = Self.latest()
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(assets, id: \.localIdentifier) { a in
                    Button { pick(a.localIdentifier) } label: {
                        AssetThumb(asset: a)
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                    .accessibilityLabel(a.creationDate.map { "Photo from \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Photo")
                    .accessibilityHint("Attaches it")
                }
            }
        }
        .scrollClipDisabled()
    }

    /// The newest dozen photos Quire may see, or none.
    static func latest() -> [PHAsset] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 12
        let result = PHAsset.fetchAssets(with: .image, options: options)
        return result.count > 0 ? result.objects(at: IndexSet(integersIn: 0..<result.count)) : []
    }

    /// The photo itself, from the library (or iCloud, if it lives there), ready to attach. Off the
    /// main actor, since Photos calls back on a queue of its own.
    nonisolated static func data(for id: String) async throws -> Attachment {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            throw AttachmentMaker.Failure.unreadable("That photo")
        }
        let data: Data? = await withCheckedContinuation { c in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                c.resume(returning: data)
            }
        }
        guard let data else { throw AttachmentMaker.Failure.unreadable("That photo") }
        return try await AttachmentMaker.image(data, name: "photo.jpg")
    }
}

/// A square of one photo, filled in once its thumbnail has been made.
private struct AssetThumb: View {
    let asset: PHAsset
    @State private var image: UIImage? = nil

    var body: some View {
        Color.qInk.opacity(0.06)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(.rect(cornerRadius: Radius.s, style: .continuous))
            .animation(.easeOut(duration: 0.2), value: image != nil)
            .task(id: asset.localIdentifier) { image = await Self.thumbnail(asset) }
    }

    nonisolated private static func thumbnail(_ asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { c in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 216, height: 216),
                                                  contentMode: .aspectFill, options: options) { image, _ in
                c.resume(returning: image)
            }
        }
    }
}
