import SwiftUI
import UIKit

struct ChatInfoSheet: View {
    let session: ChatSession
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var prompt = ""
    @State private var showModels = false
    @State private var confirmDelete = false
    @State private var share: SharedFile? = nil
    @State private var showRequest = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                        .onSubmit { session.rename(title) }
                }

                Section("Model") {
                    Button { showModels = true } label: {
                        HStack {
                            Text(session.model?.shortName ?? shortId(session.chat.modelId)).foregroundStyle(Color.qInk)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.qInk2)
                        }
                    }
                }

                Section {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 120)
                        .font(.body)
                } header: {
                    Text("System prompt for this chat")
                } footer: {
                    Text(prompt.isEmpty
                         ? (app.settings.globalSystemPrompt.isEmpty ? "Empty, and no global prompt is set." : "Empty, so the global prompt from Settings applies.")
                         : "Overrides the global prompt for this chat only.")
                }

                Section("Usage") {
                    LabeledContent("Messages shown", value: "\(session.path.count)")
                    LabeledContent("Context (estimate)") {
                        Text(contextText).monospacedDigit()
                    }
                    LabeledContent("Cost") { Text(Fmt.usd(session.chat.totalCostUsd)).monospacedDigit() }
                    LabeledContent("Started", value: Date(timeIntervalSince1970: session.chat.createdAt / 1000).formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    Button {
                        if let url = try? app.exportMarkdown(session) { share = SharedFile(url: url) }
                    } label: { Label("Export as Markdown", systemImage: "square.and.arrow.up") }
                    .disabled(session.path.isEmpty)

                    if lastRequest != nil {
                        Button { showRequest = true } label: { Label("Last request sent", systemImage: "curlybraces") }
                    }

                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete chat", systemImage: "trash") }
                        .disabled(!session.persisted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.qBase)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commit(); dismiss() }
                }
            }
            .onDisappear { commit() }
            .onAppear {
                title = session.chat.title
                prompt = session.chat.systemPromptInline ?? ""
            }
            .sheet(isPresented: $showModels) {
                ModelPickerView(selected: session.chat.modelId) { id in session.setModel(id) }
            }
            .sheet(item: $share) { f in ShareSheet(items: [f.url]) }
            .sheet(isPresented: $showRequest) {
                NavigationStack {
                    ScrollView {
                        Text(lastRequest ?? "")
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Request")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showRequest = false } }
                    }
                }
            }
            .confirmationDialog("Delete this chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    let id = session.chat.id
                    dismiss()
                    app.deleteChats([id])
                }
            } message: {
                Text("Its messages are removed from this device. This can't be undone.")
            }
        }
    }

    private var contextText: String {
        let est = Fmt.tokens(session.contextTokens)
        if let ctx = session.model?.contextLength, ctx > 0 { return "\(est) of \(Fmt.context(ctx))" }
        return est
    }

    /// The request snapshot of the latest reply on this branch, with attachments shown as placeholders.
    private var lastRequest: String? {
        session.thread.last(where: { $0.role == .assistant && $0.requestSnapshot != nil })?.requestSnapshot
    }

    private func commit() {
        guard !session.deleted else { return }
        if title != session.chat.title { session.rename(title) }
        if prompt != (session.chat.systemPromptInline ?? "") { session.setSystemPrompt(prompt) }
    }
}

struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// UIKit's share sheet, for handing a file to Files, AirDrop, Mail and so on.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
