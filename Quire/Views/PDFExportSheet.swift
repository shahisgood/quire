import SwiftUI
import PDFKit

/// Which chat to set as a PDF, for a list's sheet.
nonisolated struct PDFRequest: Identifiable, Hashable, Sendable {
    let chatId: String
    var id: String { chatId }
}

/// A chat as a PDF, shown page by page before it goes anywhere. The pages sit on the sheet's own
/// ground like paper on a desk; the bar underneath says how many there are and hands the file on.
/// The options re-set the type in place, keeping the pages you're looking at until the new ones
/// are ready.
struct PDFExportSheet: View {
    let chatId: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var options = PDFOptions()
    @State private var result: ChatPDF.Result? = nil
    @State private var failure: String? = nil
    @State private var working = false
    @State private var hasReasoning = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.qSunken.ignoresSafeArea()
                if let result {
                    PDFPreview(url: result.url)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.opacity)
                } else if let failure {
                    ContentUnavailableView {
                        Label("Couldn't make the PDF", systemImage: "doc.badge.ellipsis")
                    } description: {
                        Text(failure)
                    } actions: {
                        Button("Try again") { Task { await build() } }
                            .buttonStyle(.glass)
                    }
                    .transition(.opacity)
                } else {
                    setting
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Motion.standard, value: result)
            .animation(reduceMotion ? nil : Motion.standard, value: failure)
            .navigationTitle("PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { optionsMenu }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let result { bar(result).transition(.opacity) }
            }
        }
        .task(id: options) { await build() }
    }

    /// While the first pages are being set.
    private var setting: some View {
        VStack(spacing: 16) {
            QuireMark(width: 40, breathing: true)
            Text("Setting the type…")
                .displayFont { .system(.subheadline, design: $0).italic() }
                .foregroundStyle(Color.qInk2)
        }
        .accessibilityElement(children: .combine)
    }

    private var optionsMenu: some View {
        Menu {
            Toggle(isOn: $options.times) { Label("Times", systemImage: "clock") }
            if hasReasoning {
                Toggle(isOn: $options.reasoning) { Label("Reasoning", systemImage: "brain") }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("What to include")
        .disabled(result == nil && failure == nil)
    }

    private func bar(_ r: ChatPDF.Result) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(r.pages) page\(r.pages == 1 ? "" : "s")")
                    .displayFont { .system(.headline, design: $0).monospacedDigit() }
                    .foregroundStyle(Color.qInk)
                    .contentTransition(.numericText(value: Double(r.pages)))
                Text("\(ChatPDF.paperName) · \(Fmt.bytes(r.bytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
                    .contentTransition(.opacity)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if working {
                ProgressView()
                    .transition(.opacity)
            }
            ShareLink(item: r.url) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 6)
                    .frame(minHeight: 36)
            }
            .buttonStyle(.glassProminent)
        }
        .padding(.leading, 22)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .animation(Motion.quick, value: working)
    }

    private func build() async {
        guard let session = app.sessions[chatId] ?? app.session(for: chatId) else {
            failure = "This chat couldn't be found."
            return
        }
        hasReasoning = session.thread.contains { !($0.reasoning ?? "").isEmpty }
        working = true
        defer { working = false }
        do {
            let r = try await ChatPDF.make(session, app: app, options: options)
            guard !Task.isCancelled else { return }
            failure = nil
            result = r
        } catch {
            guard !Task.isCancelled else { return }
            if result == nil { failure = error.localizedDescription }
            Haptics.warning()
        }
    }
}

/// The pages, one under another, scaled to the width.
private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.pageShadowsEnabled = true
        v.backgroundColor = .clear
        v.pageBreakMargins = UIEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        guard v.document?.documentURL != url else { return }
        // Keep the reader where they were as the pages are set again.
        let page = v.currentPage.flatMap { v.document?.index(for: $0) }
        v.document = PDFDocument(url: url)
        if let page, let target = v.document?.page(at: min(page, max(0, (v.document?.pageCount ?? 1) - 1))) {
            v.go(to: target)
        }
    }
}
