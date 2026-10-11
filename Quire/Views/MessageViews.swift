import SwiftUI
import UIKit

struct MessageRow: View {
    let session: ChatSession
    let message: Message

    var body: some View {
        if message.role == .user {
            UserMessageView(session: session, message: message)
        } else if message.role == .assistant {
            AssistantMessageView(session: session, message: message)
        }
    }
}

// MARK: - The user's own messages: a raised hairline card, right-aligned, in the UI sans.

private struct UserMessageView: View {
    let session: ChatSession
    let message: Message

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .leading, spacing: 8) {
                    if let atts = message.attachments, !atts.isEmpty {
                        AttachmentStrip(attachments: atts)
                    }
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.body)
                            .foregroundStyle(Color.qInk)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .card(radius: 18)
                .contextMenu {
                    Button { UIPasteboard.general.string = message.content } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Divider()
                    Button(role: .destructive) { session.delete(message.id) } label: { Label("Delete from here", systemImage: "trash") }
                        .disabled(session.generating)
                }
                SiblingSwitcher(session: session, messageId: message.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct AttachmentStrip: View {
    let attachments: [Attachment]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { a in
                    if a.kind == .image, let img = ThumbnailCache.image(for: a) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(.rect(cornerRadius: 10))
                    } else {
                        Label(a.name, systemImage: "doc")
                            .font(.footnote)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .card(radius: 10)
                    }
                }
            }
        }
    }
}

// MARK: - The model's reply: full width, in the reading face, with the model label.

private struct AssistantMessageView: View {
    let session: ChatSession
    let message: Message
    @Environment(AppModel.self) private var app
    @State private var regenerateWithModel = false

    private var isStreaming: Bool { session.streamingId == message.id }
    private var content: String { isStreaming ? session.streamContent : message.content }
    private var reasoning: String { isStreaming ? session.streamReasoning : (message.reasoning ?? "") }
    private var design: Font.Design { app.settings.ui.readingFace.design }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(modelLabel.uppercased())
                .font(.caption.weight(.medium))
                .tracking(0.6)
                .foregroundStyle(Color.qInk2)

            if !reasoning.isEmpty || (isStreaming && content.isEmpty && (message.usage?.reasoningTokens ?? 0) > 0) {
                ReasoningView(text: reasoning, live: isStreaming && content.isEmpty,
                              expandedByDefault: app.settings.ui.showReasoningByDefault)
            } else if !isStreaming, (message.usage?.reasoningTokens ?? 0) > 0, message.reasoning == nil {
                Text("Reasoned with \(Fmt.tokens(message.usage?.reasoningTokens)) tokens; the provider didn't return the trace.")
                    .font(.caption)
                    .foregroundStyle(Color.qInk2)
            }

            if isStreaming && content.isEmpty && reasoning.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(session.retryNote ?? "Waiting for the first token…")
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                }
            }

            if !content.isEmpty {
                MarkdownView(blocks: MarkdownCache.blocks(content, live: isStreaming), design: design)
                    .foregroundStyle(Color.qInk)
                    .textSelection(.enabled)
            }

            if let err = message.error, !isStreaming {
                ErrorBanner(error: err, status: message.status,
                            onRetry: { session.retry(message.id) },
                            onContinue: { session.continueReply(message.id) })
            }

            if !isStreaming {
                footer
            } else if app.settings.ui.showCosts && session.streamCompletionTokens > 0 {
                Text("\(Fmt.tokens(session.streamCompletionTokens)) tokens · \(Fmt.usd(session.streamEstCost, estimate: true))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $regenerateWithModel) {
            ModelPickerView(selected: message.modelId ?? session.chat.modelId) { id in session.regenerate(message.id, modelId: id) }
        }
    }

    private var modelLabel: String {
        let id = message.modelId ?? session.chat.modelId
        return app.model(id)?.shortName ?? shortId(id)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            SiblingSwitcher(session: session, messageId: message.id)
            Button { UIPasteboard.general.string = message.content } label: { Image(systemName: "doc.on.doc") }
                .accessibilityLabel("Copy")
            Menu {
                Button { session.regenerate(message.id) } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                Button { regenerateWithModel = true } label: { Label("Regenerate with…", systemImage: "cpu") }
                if message.status == .interrupted || message.error?.code == "length" {
                    Button { session.continueReply(message.id) } label: { Label("Continue", systemImage: "text.append") }
                }
                Divider()
                Button(role: .destructive) { session.delete(message.id) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(session.generating)
            .accessibilityLabel("Regenerate")
            Spacer()
            if app.settings.ui.showCosts, let u = message.usage {
                Text(usageText(u))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.qInk2)
        .buttonStyle(.plain)
    }

    private func usageText(_ u: Usage) -> String {
        var parts = ["\(Fmt.tokens(u.promptTokens)) in", "\(Fmt.tokens(u.completionTokens)) out"]
        if let r = u.reasoningTokens, r > 0 { parts.append("\(Fmt.tokens(r)) think") }
        parts.append(Fmt.usd(u.costUsd, estimate: u.authoritative != true))
        return parts.joined(separator: " · ")
    }
}

/// ‹ 2/3 › between regenerated replies (or edited prompts), shown only when there is more than one.
private struct SiblingSwitcher: View {
    let session: ChatSession
    let messageId: String

    var body: some View {
        let info = session.siblingInfo(messageId)
        if info.count > 1 {
            HStack(spacing: 6) {
                Button { session.switchBranch(messageId, by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(info.index == 0 || session.generating)
                Text("\(info.index + 1)/\(info.count)")
                    .font(.caption.monospacedDigit())
                Button { session.switchBranch(messageId, by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(info.index >= info.count - 1 || session.generating)
            }
            .font(.caption)
            .foregroundStyle(Color.qInk2)
            .buttonStyle(.plain)
        }
    }
}

private struct ReasoningView: View {
    let text: String
    let live: Bool
    let expandedByDefault: Bool
    @State private var expanded: Bool? = nil

    var body: some View {
        // While the model is still thinking the trace stays open; once the answer starts it
        // collapses unless the user prefers it open.
        let isOpen = expanded ?? (live || expandedByDefault)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded = !isOpen }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                    Text(live ? "Thinking…" : "Reasoning")
                    if live { ProgressView().controlSize(.mini) }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.qInk2)
            }
            .buttonStyle(.plain)

            if isOpen && !text.isEmpty {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.qRule).frame(width: 2)
                    }
                    .transition(.opacity)
            }
        }
    }
}

private struct ErrorBanner: View {
    let error: MessageError
    let status: MessageStatus
    let onRetry: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.message)
                .font(.footnote)
                .foregroundStyle(error.code == "length" || error.code == "interrupted" ? Color.qInk2 : Color.qDanger)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if status == .error || (status == .interrupted && error.code != "interrupted") {
                    Button("Retry", action: onRetry)
                }
                if status == .interrupted || error.code == "length" {
                    Button("Continue", action: onContinue)
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.qAccent)
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 12)
    }
}

/// Parsed Markdown for finished messages, so scrolling a long chat doesn't re-parse every row.
/// A live (streaming) reply is parsed fresh each time since its text changes constantly.
enum MarkdownCache {
    private static var store: [String: [MDBlock]] = [:]

    static func blocks(_ text: String, live: Bool) -> [MDBlock] {
        if live { return MarkdownParser.parse(text) }
        if let hit = store[text] { return hit }
        let parsed = MarkdownParser.parse(text)
        if store.count > 300 { store.removeAll(keepingCapacity: true) }
        store[text] = parsed
        return parsed
    }
}
