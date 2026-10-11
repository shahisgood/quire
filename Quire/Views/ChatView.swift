import SwiftUI

struct ChatView: View {
    let session: ChatSession
    @Environment(AppModel.self) private var app
    @State private var position = ScrollPosition(edge: .bottom)
    @State private var pinned = true
    @State private var showInfo = false
    @State private var showModels = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if session.path.isEmpty {
                    EmptyChatView(session: session)
                        .containerRelativeFrame(.vertical, alignment: .center)
                }
                ForEach(session.path, id: \.self) { id in
                    if let m = session.messages[id] {
                        MessageRow(session: session, message: m)
                            .id(id)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .background(Color.qBase)
        // "Pinned" means within a short distance of the bottom. Only while pinned does new text
        // move the viewport; scrolling up to read stops the follow, the way the PWA does it.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 60
        } action: { _, atBottom in
            pinned = atBottom
        }
        .onChange(of: session.streamContent) {
            if pinned { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: session.streamReasoning) {
            if pinned { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: session.path.count) {
            pinned = true
            withAnimation(.smooth(duration: 0.25)) { position.scrollTo(edge: .bottom) }
        }
        .onAppear {
            if let h = session.highlightId {
                session.highlightId = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation { position.scrollTo(id: h, anchor: .center) }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !pinned && !session.path.isEmpty {
                Button {
                    pinned = true
                    withAnimation(.smooth(duration: 0.3)) { position.scrollTo(edge: .bottom) }
                } label: {
                    Label("Latest", systemImage: "arrow.down")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glass)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: pinned)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(session: session)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { showInfo = true } label: {
                    VStack(spacing: 1) {
                        Text(session.chat.title)
                            .font(.headline)
                            .foregroundStyle(Color.qInk)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 240)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Chat details")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showModels = true } label: { Image(systemName: "cpu") }
                    .accessibilityLabel("Choose model")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { app.startNewChat() } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New chat")
            }
        }
        .sheet(isPresented: $showInfo) { ChatInfoSheet(session: session) }
        .sheet(isPresented: $showModels) {
            ModelPickerView(selected: session.chat.modelId) { id in session.setModel(id) }
        }
    }

    private var subtitle: String {
        var parts = [session.model?.shortName ?? shortId(session.chat.modelId)]
        if app.settings.ui.showCosts {
            if let ctx = session.model?.contextLength, ctx > 0 {
                parts.append("\(Fmt.tokens(session.chat.tokenEstimate))/\(Fmt.context(ctx))")
            }
            if session.chat.totalCostUsd > 0 { parts.append(Fmt.usd(session.chat.totalCostUsd)) }
        }
        return parts.joined(separator: " · ")
    }
}

func shortId(_ id: String) -> String {
    guard let slash = id.firstIndex(of: "/") else { return id.isEmpty ? "No model" : id }
    return String(id[id.index(after: slash)...])
}

private struct EmptyChatView: View {
    let session: ChatSession
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.qInk2)
            Text(session.model?.shortName ?? shortId(session.chat.modelId))
                .font(.system(.title3, design: app.settings.ui.readingFace.design))
                .foregroundStyle(Color.qInk)
            if app.apiKey == nil {
                NavigationLink(value: Route.settings) {
                    Text("Add your OpenRouter key to start")
                        .font(.subheadline)
                }
            } else if let m = session.model {
                Text("\(Fmt.context(m.contextLength)) context · \(Pricing.perMillion(m.pricing.prompt)) in · \(Pricing.perMillion(m.pricing.completion)) out per M")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
