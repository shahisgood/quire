import SwiftUI
import UIKit

/// Edit a sent message and resend it. The original stays as a branch, reachable with ‹ ›.
struct EditMessageSheet: View {
    let session: ChatSession
    let message: Message
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var unchanged: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines) == message.content.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (message.attachments ?? []).isEmpty }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .card(radius: 14)
                    .focused($focused)
                if let n = message.attachments?.count, n > 0 {
                    Label("\(n) attachment\(n == 1 ? "" : "s") will be sent again", systemImage: "paperclip")
                        .font(.footnote)
                        .foregroundStyle(Color.qInk2)
                }
                Label("The original stays as a branch. Switch between them with ‹ ›.", systemImage: "arrow.triangle.branch")
                    .font(.footnote)
                    .foregroundStyle(Color.qInk2)
            }
            .padding(16)
            .background(Color.qBase)
            .navigationTitle("Edit and resend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        session.editResend(message.id, text: text)
                        Haptics.tap()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(empty || unchanged || session.generating)
                }
            }
            .onAppear {
                text = message.content
                focused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Tokens, cost and the exact request for one reply; or the raw text of any message.
struct MessageInfoSheet: View {
    let session: ChatSession
    let message: Message
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .details

    nonisolated enum Tab: String, CaseIterable, Identifiable, Hashable {
        case details = "Details", request = "Request", raw = "Raw"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(availableTabs) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                switch tab {
                case .details: details
                case .request: SelectableTextView(text: message.requestSnapshot ?? "No request was recorded.", monospaced: true)
                case .raw: SelectableTextView(text: message.content, monospaced: true)
                }
            }
            .background(Color.qBase)
            .navigationTitle(message.role == .user ? "Your message" : app.modelName(message.modelId))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = tab == .request ? (message.requestSnapshot ?? "") : message.content
                        Haptics.tap()
                    } label: { Label("Copy", systemImage: "square.on.square") }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var availableTabs: [Tab] {
        message.requestSnapshot == nil ? [.details, .raw] : Tab.allCases
    }

    private var details: some View {
        Form {
            Group {
            Section {
                LabeledContent("Model", value: message.modelId ?? "—")
                LabeledContent("Sent", value: Date(timeIntervalSince1970: message.createdAt / 1000).formatted(date: .abbreviated, time: .standard))
                LabeledContent("Status", value: statusText)
                if message.editedFrom != nil { LabeledContent("Edited", value: "Yes, the original is a sibling branch") }
            }
            if let u = message.usage {
                Section {
                    LabeledContent("Prompt") { Text(u.promptTokens.formatted()).monospacedDigit() }
                    LabeledContent("Completion") { Text(u.completionTokens.formatted()).monospacedDigit() }
                    if let r = u.reasoningTokens, r > 0 { LabeledContent("Reasoning") { Text(r.formatted()).monospacedDigit() } }
                    if let w = u.webSearchCostUsd, w > 0 { LabeledContent("Web search") { Text(Fmt.usd(w)).monospacedDigit() } }
                    LabeledContent("Cost") { Text(Fmt.usd(u.costUsd, estimate: u.authoritative != true)).monospacedDigit() }
                } header: {
                    SectionLabel(text: "Tokens and cost")
                } footer: {
                    Text(u.authoritative == true ? "From OpenRouter's generation record." : u.estimated == true ? "Estimated from token counts and the model's prices; OpenRouter's figure replaces it shortly after the reply." : "From the stream's usage report.")
                }
            }
            if let g = message.generationId {
                Section {
                    Button {
                        UIPasteboard.general.string = g
                        Haptics.tap()
                    } label: {
                        LabeledContent("Generation") {
                            Text(g).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .foregroundStyle(Color.qInk)
                } footer: {
                    Text("Tap to copy. Look it up on openrouter.ai/activity.")
                }
            }
            if let s = message.settingsSnapshot {
                Section {
                    if let t = s.temperature { LabeledContent("Temperature", value: String(format: "%.2f", t)) }
                    if let p = s.topP { LabeledContent("Top P", value: String(format: "%.2f", p)) }
                    if let m = s.maxTokens { LabeledContent("Max tokens", value: m.formatted()) }
                    if let r = s.reasoning, r.mode != .off {
                        LabeledContent("Reasoning", value: r.mode == .effort ? (r.effort ?? .medium).label : "\(r.maxTokens ?? 0) tokens")
                    }
                    if s.webSearch?.enabled == true { LabeledContent("Web search", value: "On") }
                } header: {
                    SectionLabel(text: "Settings used")
                }
            }
            }
            .listRowBackground(Color.qRaised)
        }
        .scrollContentBackground(.hidden)
    }

    private var statusText: String {
        switch message.status {
        case .complete: return message.error?.code == "length" ? "Hit the output limit" : "Complete"
        case .streaming: return "Streaming"
        case .interrupted: return "Interrupted"
        case .error: return "Failed"
        }
    }
}
