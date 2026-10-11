import SwiftUI
import UIKit

/// Renders parsed Markdown with native text. Inline formatting goes through `AttributedString`,
/// so links are tappable and text is selectable without a web view.
struct MarkdownView: View {
    let blocks: [MDBlock]
    var design: Font.Design = .serif

    init(_ text: String, design: Font.Design = .serif) {
        self.blocks = MarkdownParser.parse(text)
        self.design = design
    }

    init(blocks: [MDBlock], design: Font.Design) {
        self.blocks = blocks
        self.design = design
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block, design: design)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BlockView: View {
    let block: MDBlock
    let design: Font.Design

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Inline.text(text)
                .font(.system(headingStyle(level), design: design).weight(level <= 2 ? .bold : .semibold))
                .padding(.top, level <= 2 ? 6 : 2)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph(let text):
            Inline.text(text)
                .font(.system(.body, design: design))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let lang, let text):
            CodeBlockView(lang: lang, code: text)

        case .math(let tex):
            // Native math typesetting is a later pass; show the TeX source legibly instead.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(tex)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.qInk)
                    .padding(12)
            }
            .card(radius: 10)

        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.qRule).frame(width: 3)
                MarkdownView(blocks: inner, design: design)
                    .foregroundStyle(Color.qInk2)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        marker(ordered: ordered, number: start + n, checked: item.checked)
                        MarkdownView(blocks: item.blocks, design: design)
                    }
                }
            }

        case .table(let header, let alignments, let rows):
            TableBlockView(header: header, alignments: alignments, rows: rows, design: design)

        case .rule:
            Rectangle().fill(Color.qRule).frame(height: 1).padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func marker(ordered: Bool, number: Int, checked: Bool?) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color.qAccent : Color.qInk2)
                .font(.system(.body))
        } else if ordered {
            Text("\(number).")
                .font(.system(.body, design: design).monospacedDigit())
                .foregroundStyle(Color.qInk2)
                .frame(minWidth: 20, alignment: .trailing)
        } else {
            Text("•")
                .font(.system(.body, design: design))
                .foregroundStyle(Color.qInk2)
                .frame(minWidth: 12)
        }
    }

    private func headingStyle(_ level: Int) -> Font.TextStyle {
        switch level {
        case 1: .title2
        case 2: .title3
        case 3: .headline
        default: .subheadline
        }
    }
}

/// Inline Markdown via Foundation's parser, with code spans tinted.
enum Inline {
    static func text(_ source: String) -> Text {
        Text(attributed(source))
    }

    static func attributed(_ source: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                          failurePolicy: .returnPartiallyParsedIfPossible)
        guard var a = try? AttributedString(markdown: source, options: opts) else { return AttributedString(source) }
        for run in a.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                // Typed keys, because `.font`/`.foregroundColor` are ambiguous between the UIKit and SwiftUI scopes.
                a[run.range][AttributeScopes.SwiftUIAttributes.FontAttribute.self] = Font.system(.callout, design: .monospaced)
                a[run.range][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.qAccent
            }
        }
        return a
    }
}

private struct CodeBlockView: View {
    let lang: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.qInk2)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.qAccent : Color.qInk2)
                .sensoryFeedback(.success, trigger: copied) { _, new in new }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle().fill(Color.qRule).frame(height: 1)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.qInk)
                    .textSelection(.enabled)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .card(radius: 12)
    }
}

private struct TableBlockView: View {
    let header: [String]
    let alignments: [MDAlign]
    let rows: [[String]]
    let design: Font.Design

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { i, cell in
                        Inline.text(cell)
                            .font(.system(.subheadline, design: design).weight(.semibold))
                            .gridColumnAlignment(alignment(i))
                    }
                }
                Rectangle().fill(Color.qRule).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Inline.text(cell)
                                .font(.system(.subheadline, design: design))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 280, alignment: .leading)
                        }
                    }
                }
            }
            .padding(12)
        }
        .card(radius: 12)
    }

    private func alignment(_ i: Int) -> HorizontalAlignment {
        let a: MDAlign = i < alignments.count ? alignments[i] : .leading
        switch a {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
