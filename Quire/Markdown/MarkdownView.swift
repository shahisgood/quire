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
    /// For a whole reply: blocks are built as they scroll near, each on its own layer. A very long
    /// reply drawn as one stack could outgrow the largest layer the GPU will draw, and everything
    /// past that point rendered as a blank black area.
    var lazy = false

    var body: some View {
        Group {
            if lazy {
                LazyVStack(alignment: .leading, spacing: compact ? 8 : 12) { content }
            } else {
                VStack(alignment: .leading, spacing: compact ? 8 : 12) { content }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
            BlockView(block: block, design: design, caret: caret && i == blocks.count - 1)
        }
        if caret && !lastBlockTakesCaret {
            Caret()
        }
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
            ParagraphText(text: text, caret: caret)
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
    @Environment(\.dynamicTypeSize) private var typeSize

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

            // Drawn in 60-line pieces: one text view for a long block outgrew what the GPU will
            // draw, and the whole block came out blank. The column is as wide as the longest line,
            // measured up front, so sideways scrolling doesn't shift as pieces load.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(Highlighter.chunks(code, lang: lang).enumerated()), id: \.offset) { _, piece in
                        Text(piece)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                }
                .font(.system(.footnote, design: .monospaced))
                .lineSpacing(3)
                .foregroundStyle(Color.qInk)
                .frame(minWidth: TextMetrics.monospacedWidth(code, style: .footnote, size: typeSize), alignment: .leading)
                .padding(12)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var available: CGFloat = 0

    private let spacing: CGFloat = 18
    private let inset: CGFloat = 14

    var body: some View {
        // Every column gets an exact width up front, so each row grows to its tallest wrapped cell.
        // (A Grid with capped widths measured long cells as one line and then drew them wrapped,
        // which is how rows ended up on top of each other.)
        let widths = columnWidths
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                row(header, widths: widths, bold: true)
                Rectangle().fill(Color.qRule).frame(height: 1)
                ForEach(Array(rows.enumerated()), id: \.offset) { n, cells in
                    if n > 0 {
                        Rectangle().fill(Color.qRule.opacity(0.5)).frame(height: 1)
                    }
                    row(cells, widths: widths, bold: false)
                }
            }
            .padding(inset)
        }
        .card(radius: 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
    }

    private func row(_ cells: [String], widths: [CGFloat], bold: Bool) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<header.count, id: \.self) { i in
                Text(Inline.attributed(i < cells.count ? cells[i] : ""))
                    .font(.system(.subheadline, design: design).weight(bold ? .semibold : .regular))
                    .foregroundStyle(Color.qInk)
                    .multilineTextAlignment(textAlignment(i))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: i < widths.count ? widths[i] : 80, alignment: frameAlignment(i))
            }
        }
    }

    /// Natural single-line widths (capped), then, if the table is wider than the message column,
    /// the widest columns give way until it fits: narrow columns keep their width and the rest share
    /// what's left. Only a table that still can't fit at a readable width scrolls sideways.
    private var columnWidths: [CGFloat] {
        let natural = TableMetrics.naturalWidths(header: header, rows: rows, design: design, size: typeSize)
        guard available > 0 else { return natural }
        let target = available - inset * 2 - spacing * CGFloat(max(0, natural.count - 1))
        return TableMetrics.fit(natural, into: target, floor: 88)
    }

    private func textAlignment(_ i: Int) -> TextAlignment {
        switch columnAlignment(i) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func frameAlignment(_ i: Int) -> Alignment {
        switch columnAlignment(i) {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func columnAlignment(_ i: Int) -> MDAlign {
        i < alignments.count ? alignments[i] : .leading
    }
}

/// Text measurement for tables, with UIKit's metrics at the reading size in effect.
private enum TableMetrics {
    static func naturalWidths(header: [String], rows: [[String]], design: Font.Design, size: DynamicTypeSize) -> [CGFloat] {
        let traits = UITraitCollection(preferredContentSizeCategory: TextMetrics.category(size))
        let base = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
        let regular = font(base, design: design, bold: false)
        let bold = font(base, design: design, bold: true)
        return header.indices.map { i in
            var w = measure(header[i], bold)
            for r in rows where i < r.count { w = max(w, measure(r[i], regular)) }
            return min(320, max(48, ceil(w) + 2))
        }
    }

    static func fit(_ natural: [CGFloat], into target: CGFloat, floor: CGFloat) -> [CGFloat] {
        guard target > 0, natural.reduce(0, +) > target else { return natural }
        var widths = natural
        var remaining = target
        var flexible = Array(natural.indices)
        var changed = true
        while changed && !flexible.isEmpty {
            changed = false
            let share = remaining / CGFloat(flexible.count)
            for i in flexible where natural[i] <= share {
                remaining -= natural[i]
                flexible.removeAll { $0 == i }
                changed = true
            }
        }
        let share = max(floor, remaining / CGFloat(max(1, flexible.count)))
        for i in flexible { widths[i] = share }
        return widths
    }

    private static func measure(_ cell: String, _ font: UIFont) -> CGFloat {
        let plain = String(Inline.attributed(cell).characters)
        return (plain as NSString).size(withAttributes: [.font: font]).width
    }

    private static func font(_ base: UIFont, design: Font.Design, bold: Bool) -> UIFont {
        var d = base.fontDescriptor
        if design == .serif, let serif = d.withDesign(.serif) { d = serif }
        if bold, let b = d.withSymbolicTraits(.traitBold) { d = b }
        return UIFont(descriptor: d, size: base.pointSize)
    }
}

/// Text measurement shared by tables and code blocks.
enum TextMetrics {
    /// The width of the longest line of `text` in the monospaced system font (tabs as four spaces).
    static func monospacedWidth(_ text: String, style: UIFont.TextStyle, size: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: category(size))
        let point = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
        let font = UIFont.monospacedSystemFont(ofSize: point, weight: .regular)
        let advance = ("M" as NSString).size(withAttributes: [.font: font]).width
        var longest = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var n = 0
            for ch in line { n += ch == "\t" ? 4 : 1 }
            longest = max(longest, n)
        }
        return ceil(CGFloat(longest) * advance) + 2
    }

    static func category(_ size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

/// Long text as a column of shorter text views. One text view taller than the largest layer the
/// GPU will draw comes out blank (all of it, not just the overflow), so anything long is split at
/// line breaks into pieces that each stay well inside that limit.
enum TextChunks {
    static func split(_ s: String, maxChars: Int = 2000) -> [String] {
        guard s.count > maxChars else { return [s] }
        var chunks: [String] = []
        var lines: [Substring] = []
        var size = 0
        func flush() {
            guard !lines.isEmpty else { return }
            chunks.append(lines.joined(separator: "\n"))
            lines = []
            size = 0
        }
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.count > maxChars {
                flush()
                chunks.append(contentsOf: wrap(line, maxChars))
                continue
            }
            if size + line.count > maxChars { flush() }
            lines.append(line)
            size += line.count + 1
        }
        flush()
        return chunks
    }

    /// One very long line, broken at spaces.
    private static func wrap(_ line: Substring, _ maxChars: Int) -> [String] {
        var out: [String] = []
        var rest = line
        while rest.count > maxChars {
            let limit = rest.index(rest.startIndex, offsetBy: maxChars)
            var cut = rest[..<limit].lastIndex(of: " ") ?? limit
            if cut == rest.startIndex { cut = limit }
            out.append(String(rest[..<cut]))
            rest = rest[cut...].drop(while: { $0 == " " })
        }
        if !rest.isEmpty { out.append(String(rest)) }
        return out
    }
}

/// Plain text that may be long (a reasoning trace, a pasted message): one text view when short,
/// a lazy column of pieces when not. Font and colour come from the caller.
struct ChunkedText: View {
    let text: String

    var body: some View {
        let pieces = TextChunks.split(text)
        if pieces.count == 1 {
            Text(text)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    Text(piece).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A paragraph, split the same way only when it's enormous; the caret goes on the last piece.
private struct ParagraphText: View {
    let text: String
    var caret = false

    var body: some View {
        let pieces = TextChunks.split(text, maxChars: 3000)
        if pieces.count == 1 {
            Text(Inline.attributed(text, caret: caret))
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                    Text(Inline.attributed(piece, caret: caret && i == pieces.count - 1))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
