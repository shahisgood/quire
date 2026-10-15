import SwiftUI
import UIKit

struct MessageRow: View {
    let session: ChatSession
    let message: Message
    var highlighted = false
    let actions: MessageActions

    var body: some View {
        Group {
            if message.role == .user {
                UserMessageView(session: session, message: message, actions: actions)
            } else if message.role == .assistant {
                AssistantMessageView(session: session, message: message, actions: actions)
            }
        }
        .padding(highlighted ? 8 : 0)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.qAccentSoft)
                    .padding(-2)
            }
        }
    }
}

// MARK: - The user's own messages: a raised hairline card, right-aligned, in the UI sans.

private struct UserMessageView: View {
    let session: ChatSession
    let message: Message
    let actions: MessageActions

    var body: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 44)
            VStack(alignment: .trailing, spacing: 6) {
                VStack(alignment: .leading, spacing: 10) {
                    if let atts = message.attachments, !atts.isEmpty {
                        AttachmentStrip(attachments: atts, onTap: actions.viewImage)
                    }
                    if !message.content.isEmpty {
                        ChunkedText(text: message.content)
                            .font(.body)
                            .foregroundStyle(Color.qInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .card(radius: 20)
                .contentShape(.contextMenuPreview, .rect(cornerRadius: 20))
                .contextMenu { menu }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("You: \(message.content)")
                .accessibilityActions {
                    Button("Copy") { copy() }
                    Button("Edit and resend") { actions.edit(message) }
                }

                HStack(spacing: 10) {
                    if message.editedFrom != nil {
                        Text("edited")
                            .font(.caption2)
                            .foregroundStyle(Color.qInk2)
                    }
                    SiblingSwitcher(session: session, messageId: message.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var menu: some View {
        Button(action: copy) { Label("Copy", systemImage: "square.on.square") }
        Button { actions.selectText(message) } label: { Label("Select text", systemImage: "selection.pin.in.out") }
        Button { actions.edit(message) } label: { Label("Edit and resend", systemImage: "pencil") }
            .disabled(session.generating)
        Button { actions.branch(message) } label: { Label("Branch into a new chat", systemImage: "arrow.triangle.branch") }
            .disabled(!session.persisted)
        Divider()
        Button(role: .destructive) { actions.delete(message) } label: { Label("Delete from here", systemImage: "trash") }
            .disabled(session.generating)
    }

    private func copy() {
        UIPasteboard.general.string = message.content
        Haptics.tap()
    }
}

private struct AttachmentStrip: View {
    let attachments: [Attachment]
    let onTap: (Attachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { a in
                    if a.kind == .image, let img = ThumbnailCache.image(for: a) {
                        Button { onTap(a) } label: {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Image \(a.name)")
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).lineLimit(1)
                                Text(Fmt.bytes(a.size)).font(.caption2).foregroundStyle(Color.qInk2)
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.qInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .card(radius: 10, fill: .qSunken)
                    }
                }
            }
        }
    }
}

// MARK: - The model's reply: full width, in the reading face, under a small-caps folio line.

private struct AssistantMessageView: View {
    let session: ChatSession
    let message: Message
    let actions: MessageActions
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var justCopied = false

    private var isStreaming: Bool { session.streamingId == message.id }
    private var content: String { isStreaming ? session.streamContent : message.content }
    private var reasoning: String { isStreaming ? session.streamReasoning : (message.reasoning ?? "") }
    private var design: Font.Design { app.settings.ui.readingFace.design }
    private var modelId: String { message.modelId ?? session.chat.modelId }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            folio

            if !reasoning.isEmpty || reasoningTokens > 0 {
                ReasoningView(text: reasoning,
                              thinking: isStreaming && content.isEmpty,
                              streaming: isStreaming,
                              tokens: reasoningTokens,
                              cost: reasoningCost,
                              expandedByDefault: app.settings.ui.showReasoningByDefault)
            }

            if isStreaming && content.isEmpty && reasoning.isEmpty {
                WaitingIndicator(retryAt: session.retryAt, reason: session.retryReason)
            }

            if !content.isEmpty {
                MarkdownView(blocks: MarkdownCache.blocks(content, live: isStreaming), design: design, caret: isStreaming, lazy: true)
            }

            if !isStreaming { statusBlock }

            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .contextMenu {
            if !isStreaming { menuItems }
        } preview: {
            previewCard
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            Button("Copy") { copyPlain() }
            if !session.generating {
                Button("Regenerate") { session.regenerate(message.id) }
            }
            Button("Message details") { actions.info(message) }
        }
    }

    // MARK: Folio line: MODEL NAME ———— 2m

    private var folio: some View {
        HStack(spacing: 10) {
            Text(app.modelName(modelId).uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(isStreaming ? Color.qAccent : Color.qInk2)
                .lineLimit(1)
            Rectangle()
                .fill(Color.qRule)
                .frame(height: 1)
                .accessibilityHidden(true)
            if !isStreaming {
                Text(Fmt.relative(message.createdAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .animation(Motion.quick, value: isStreaming)
    }

    private var reasoningTokens: Int {
        if isStreaming { return session.streamReasoningTokens }
        return message.usage?.reasoningTokens ?? 0
    }

    private var reasoningCost: Double? {
        guard let m = app.model(modelId), reasoningTokens > 0 else { return nil }
        let p = Pricing.parse(m.pricing.internalReasoning)
        let rate = p > 0 ? p : Pricing.parse(m.pricing.completion)
        return Double(reasoningTokens) * rate
    }

    // MARK: Errors and interruptions

    @ViewBuilder
    private var statusBlock: some View {
        if message.status == .error {
            ErrorCard(message: message,
                      onRetry: { session.retry(message.id) },
                      onModel: { actions.regenerateWith(message) },
                      onKey: actions.fixKey,
                      onRouting: actions.openChatSettings,
                      busy: session.generating)
        } else if message.status == .interrupted {
            InlineNotice(text: message.error?.message ?? "Interrupted") {
                Button("Continue") { session.continueReply(message.id) }
                Button("Regenerate") { session.regenerate(message.id) }
            }
            .disabled(session.generating)
        } else if message.error?.code == "length" {
            InlineNotice(text: "Hit the output limit") {
                Button("Continue") { session.continueReply(message.id) }
            }
            .disabled(session.generating)
        }
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if isStreaming {
            if app.settings.ui.showCosts && session.streamCompletionTokens > 0 {
                Text("\(Fmt.tokens(session.streamCompletionTokens)) tokens · \(Fmt.usd(session.streamEstCost, estimate: true))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .contentTransition(.numericText())
            }
        } else if message.status != .error || !message.content.isEmpty {
            HStack(spacing: 4) {
                SiblingSwitcher(session: session, messageId: message.id)
                if app.settings.ui.showCosts, let u = message.usage {
                    Button { actions.info(message) } label: {
                        Text(usageText(u))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.qInk2)
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Usage: \(usageText(u)). Shows details")
                }
                Spacer(minLength: 8)
                FooterButton(symbol: justCopied ? "checkmark" : "square.on.square", label: justCopied ? "Copied" : "Copy",
                             tint: justCopied ? Color.qAccent : Color.qInk2, action: copyPlain)
                FooterButton(symbol: "arrow.clockwise", label: "Regenerate") { session.regenerate(message.id) }
                    .disabled(session.generating)
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 36, height: 32)
                        .contentShape(.rect)
                }
                .foregroundStyle(Color.qInk2)
                .accessibilityLabel("More actions")
            }
            .animation(Motion.quick, value: message.usage)
        }
    }

    private func usageText(_ u: Usage) -> String {
        "\(Fmt.tokens(u.completionTokens)) tokens · \(Fmt.usd(u.costUsd, estimate: u.authoritative != true))"
    }

    @ViewBuilder
    private var menuItems: some View {
        Section {
            Button(action: copyPlain) { Label("Copy text", systemImage: "square.on.square") }
            Button {
                UIPasteboard.general.string = message.content
                Haptics.tap()
            } label: { Label("Copy as Markdown", systemImage: "number") }
            Button { actions.selectText(message) } label: { Label("Select text", systemImage: "selection.pin.in.out") }
        }
        Section {
            Button { session.regenerate(message.id) } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                .disabled(session.generating)
            Button { actions.regenerateWith(message) } label: { Label("Regenerate with…", systemImage: "cpu") }
                .disabled(session.generating)
            if message.status == .interrupted || message.error?.code == "length" {
                Button { session.continueReply(message.id) } label: { Label("Continue", systemImage: "text.append") }
                    .disabled(session.generating)
            }
            Button { actions.branch(message) } label: { Label("Branch into a new chat", systemImage: "arrow.triangle.branch") }
                .disabled(!session.persisted)
            Button(action: actions.shareThread) { Label("Share thread", systemImage: "square.and.arrow.up") }
        }
        Section {
            Button { actions.info(message) } label: { Label("Tokens, cost & request", systemImage: "info.circle") }
            Button(role: .destructive) { actions.delete(message) } label: { Label("Delete", systemImage: "trash") }
                .disabled(session.generating)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.modelName(modelId).uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.qInk2)
            Text(String(content.prefix(500)) + (content.count > 500 ? "…" : ""))
                .font(.system(.callout, design: design))
                .foregroundStyle(Color.qInk)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(Color.qBase)
    }

    /// The button itself confirms (a checkmark for a moment) rather than a toast over the chat.
    private func copyPlain() {
        UIPasteboard.general.string = PlainText.from(markdown: message.content)
        Haptics.tap()
        withAnimation(Motion.quick) { justCopied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Motion.quick) { justCopied = false }
        }
    }
}

private struct FooterButton: View {
    let symbol: String
    let label: String
    var tint: Color = .qInk2
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.medium))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .foregroundStyle(tint)
        .accessibilityLabel(label)
    }
}

/// ‹ 2/3 › between regenerated replies or edited prompts, shown only when there is more than one.
struct SiblingSwitcher: View {
    let session: ChatSession
    let messageId: String

    var body: some View {
        let info = session.siblingInfo(messageId)
        if info.count > 1 {
            HStack(spacing: 2) {
                Button { withAnimation(Motion.quick) { session.switchBranch(messageId, by: -1) } } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28).contentShape(.rect)
                }
                .disabled(info.index == 0 || session.generating)
                .accessibilityLabel("Previous version")
                Text("\(info.index + 1)/\(info.count)")
                    .font(.caption.monospacedDigit())
                    .contentTransition(.numericText())
                Button { withAnimation(Motion.quick) { session.switchBranch(messageId, by: 1) } } label: {
                    Image(systemName: "chevron.right").frame(width: 28, height: 28).contentShape(.rect)
                }
                .disabled(info.index >= info.count - 1 || session.generating)
                .accessibilityLabel("Next version")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.qInk2)
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Version \(info.index + 1) of \(info.count)")
        }
    }
}

// MARK: - Reasoning

private struct ReasoningView: View {
    let text: String
    let thinking: Bool
    let streaming: Bool
    let tokens: Int
    let cost: Double?
    let expandedByDefault: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var userChoice: Bool? = nil

    var body: some View {
        // Open while the model is thinking; once the answer starts it folds away unless the user
        // prefers traces open. A tap overrides both.
        let isOpen = userChoice ?? (thinking || expandedByDefault)
        VStack(alignment: .leading, spacing: 8) {
            if text.isEmpty {
                Label("Reasoned with \(Fmt.tokens(tokens)) tokens · the provider didn't return the trace", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(Color.qInk2)
            } else {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.standard) { userChoice = !isOpen }
                    Haptics.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .symbolEffect(.pulse, options: .repeating, isActive: thinking && !reduceMotion)
                        Text(thinking ? "Thinking" : "Reasoning")
                            .fontWeight(.medium)
                        if tokens > 0 {
                            Text("· \(Fmt.tokens(tokens)) tokens\(costSuffix)")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .font(.footnote)
                    .foregroundStyle(thinking ? Color.qAccent : Color.qInk2)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

                if isOpen {
                    ChunkedText(text: text)
                        .font(.footnote)
                        .lineSpacing(2)
                        .foregroundStyle(Color.qInk2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(thinking ? Color.qAccent.opacity(0.6) : Color.qRule).frame(width: 2)
                        }
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: streaming) { _, nowStreaming in
            if nowStreaming { userChoice = nil }
        }
    }

    private var costSuffix: String {
        guard app.settings.ui.showCosts, let cost, cost > 0 else { return "" }
        return " · \(Fmt.usd(cost))"
    }
}

/// Before the first token: the Quire cursor, breathing; or a retry countdown.
private struct WaitingIndicator: View {
    let retryAt: Double?
    let reason: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        if let retryAt {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let s = max(0, Int(((retryAt - ctx.date.timeIntervalSince1970 * 1000) / 1000).rounded(.up)))
                let suffix = reason.map { " · " + String($0.prefix(80)) } ?? ""
                Label {
                    Text("Retrying in \(s)s" + suffix)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
                .font(.footnote)
                .foregroundStyle(Color.qAccent)
            }
        } else {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.qAccent)
                .frame(width: 8, height: 18)
                .opacity(dim ? 0.25 : 1)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
                }
                .accessibilityLabel("Waiting for the first token")
        }
    }
}

// MARK: - Notices

private struct InlineNotice<Actions: View>: View {
    let text: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.qInk2)
            HStack(spacing: 8) { actions() }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

private struct ErrorCard: View {
    let message: Message
    let onRetry: () -> Void
    let onModel: () -> Void
    let onKey: () -> Void
    let onRouting: () -> Void
    let busy: Bool

    private var code: String { message.error?.code ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(code.isEmpty || code == "unknown" ? "Request failed" : "Request failed (\(code))")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.subheadline)
            .foregroundStyle(Color.qDanger)

            Text(message.error?.message ?? "Something went wrong.")
                .font(.footnote)
                .foregroundStyle(Color.qInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if code == "401" {
                    Button("Fix API key", action: onKey).buttonStyle(.borderedProminent)
                }
                if code == "402" {
                    Link("Add credits", destination: URL(string: "https://openrouter.ai/settings/credits")!)
                        .buttonStyle(.borderedProminent)
                }
                if code != "401" && code != "403" {
                    Button("Retry", action: onRetry).buttonStyle(.bordered).disabled(busy)
                }
                if code != "401" && code != "402" {
                    Button("Different model", action: onModel).buttonStyle(.bordered).disabled(busy)
                }
                if ["502", "408", "504", "503"].contains(code) {
                    Button("Routing", action: onRouting).buttonStyle(.bordered)
                }
            }
            .font(.footnote.weight(.semibold))
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }
}
