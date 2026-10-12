import SwiftUI
import UIKit

/// Renders parsed Markdown with native text. Inline formatting goes through `AttributedString`, so
/// links open in Safari and nothing needs a web view. While a reply streams, `caret` draws Quire's
/// accent cursor at the end of the text, the same mark as the app icon.
struct MarkdownView: View {
    let blocks: [MDBlock]
    var design: Font.Design = .serif
    var caret = false
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                BlockView(block: block, design: design, caret: caret && i == blocks.count - 1)
            }
            if caret && !lastBlockTakesCaret {
                Caret()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lastBlockTakesCaret: Bool {
        switch blocks.last {
        case .paragraph?, .heading?: true
        default: false
        }
    }
}

/// The streaming cursor on its own line (after a code block, list or table).
private struct Caret: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.qAccent)
            .frame(width: 8, height: 16)
            .accessibilityHidden(true)
    }
}

private struct BlockView: View {
    let block: MDBlock
    let design: Font.Design
    var caret = false

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(Inline.attributed(text, caret: caret))
                .font(.system(headingStyle(level), design: design).weight(level <= 2 ? .bold : .semibold))
                .foregroundStyle(Color.qInk)
                .padding(.top, level <= 2 ? 6 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(Inline.attributed(text, caret: caret))
                .font(.system(.body, design: design))
                .lineSpacing(4)
                .foregroundStyle(Color.qInk)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let lang, let text):
            CodeBlockView(lang: lang, code: text)

        case .math(let tex):
            MathBlockView(tex: tex)

        case .quote(let inner):
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.qAccent.opacity(0.5)).frame(width: 3)
                MarkdownView(blocks: inner, design: design)
                    .foregroundStyle(Color.qInk2)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .list(let ordered, let start, let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ListMarker(ordered: ordered, number: start + n, checked: item.checked, design: design)
                        MarkdownView(blocks: item.blocks, design: design, compact: true)
                    }
                }
            }

        case .table(let header, let alignments, let rows):
            TableBlockView(header: header, alignments: alignments, rows: rows, design: design)

        case .rule:
            Rectangle().fill(Color.qRule).frame(height: 1).padding(.vertical, 6)
                .accessibilityHidden(true)
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

private struct ListMarker: View {
    let ordered: Bool
    let number: Int
    let checked: Bool?
    let design: Font.Design

    var body: some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color.qAccent : Color.qInk2)
                .accessibilityLabel(checked ? "Done" : "Not done")
        } else if ordered {
            Text("\(number).")
                .font(.system(.body, design: design).monospacedDigit())
                .foregroundStyle(Color.qInk2)
                .frame(minWidth: 22, alignment: .trailing)
        } else {
            Text("•")
                .font(.system(.body, design: design))
                .foregroundStyle(Color.qInk2)
                .frame(minWidth: 12)
                .accessibilityHidden(true)
        }
    }
}

/// Inline Markdown via Foundation's parser, cached by source so a streaming reply only re-parses
/// the paragraph that is still growing.
enum Inline {
    private static var cache: [String: AttributedString] = [:]

    static func attributed(_ source: String, caret: Bool = false) -> AttributedString {
        var a: AttributedString
        if let hit = cache[source] {
            a = hit
        } else {
            a = parse(source)
            if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
            cache[source] = a
        }
        if caret {
            var c = AttributedString(" ▍")
            c[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.qAccent
            a.append(c)
        }
        return a
    }

    private static func parse(_ source: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                          failurePolicy: .returnPartiallyParsedIfPossible)
        guard var a = try? AttributedString(markdown: source, options: opts) else { return AttributedString(source) }
        for run in a.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                a[run.range][AttributeScopes.SwiftUIAttributes.FontAttribute.self] = Font.system(.callout, design: .monospaced)
                a[run.range][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Color.qAccentSoft
            }
            if run.link != nil {
                a[run.range][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.qAccent
                a[run.range][AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = Text.LineStyle(pattern: .solid, color: Color.qAccent.opacity(0.4))
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
                Text(lang.isEmpty ? "code" : lang.lowercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.qInk2)
                Spacer()
                Button(action: copy) {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "square.on.square")
                        .font(.caption.weight(.medium))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Color.qAccent : Color.qInk2)
                .accessibilityLabel(copied ? "Copied" : "Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Rectangle().fill(Color.qRule).frame(height: 1)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(Highlighter.highlight(code, lang: lang))
                    .font(.system(.footnote, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(Color.qInk)
                    .padding(12)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .card(radius: 12, fill: .qSunken)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Code block, \(lang.isEmpty ? "plain text" : lang)")
    }

    private func copy() {
        UIPasteboard.general.string = code
        Haptics.tap()
        withAnimation(Motion.quick) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(Motion.quick) { copied = false }
        }
    }
}

/// Display math. Native typesetting is a later pass; this shows the TeX legibly, labelled, and copyable.
private struct MathBlockView: View {
    let tex: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TeX")
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(Color.qInk2)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(tex)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.qInk)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 12, fill: .qSunken)
        .contextMenu {
            Button { UIPasteboard.general.string = tex } label: { Label("Copy TeX", systemImage: "square.on.square") }
        }
    }
}

private struct TableBlockView: View {
    let header: [String]
    let alignments: [MDAlign]
    let rows: [[String]]
    let design: Font.Design

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { i, cell in
                        Text(Inline.attributed(cell))
                            .font(.system(.subheadline, design: design).weight(.semibold))
                            .foregroundStyle(Color.qInk)
                            .gridColumnAlignment(alignment(i))
                    }
                }
                Rectangle().fill(Color.qRule).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(Inline.attributed(cell))
                                .font(.system(.subheadline, design: design))
                                .foregroundStyle(Color.qInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 260, alignment: .leading)
                        }
                    }
                }
            }
            .padding(14)
        }
        .card(radius: 12)
    }

    private func alignment(_ i: Int) -> HorizontalAlignment {
        let a: MDAlign = i < alignments.count ? alignments[i] : .leading
        switch a {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Parsed Markdown for finished messages, so scrolling a long chat doesn't re-parse every row.
/// A streaming reply is parsed fresh each frame since its text changes constantly.
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

/// Markdown to plain text for "Copy text": code fences keep their code, headings and emphasis lose their marks.
enum PlainText {
    static func from(markdown s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "```[^\\n]*\\n([\\s\\S]*?)```", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        return t
    }
}
