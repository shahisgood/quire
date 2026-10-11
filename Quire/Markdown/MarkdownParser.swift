import Foundation

/// A small block-level Markdown parser covering what models actually emit: headings, paragraphs,
/// fenced code, block quotes, nested lists (with task boxes), GFM tables, rules and `$$` math.
/// Inline syntax (bold, italic, code, links, strikethrough) is left to `AttributedString(markdown:)`.
///
/// It is deliberately forgiving of partial input, because it re-parses a streaming reply many
/// times a second: an unclosed fence is code to the end, an unclosed `$$` is math to the end.
nonisolated enum MDBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(lang: String, text: String)
    case math(String)
    case quote([MDBlock])
    case list(ordered: Bool, start: Int, items: [MDListItem])
    case table(header: [String], alignments: [MDAlign], rows: [[String]])
    case rule
}

nonisolated enum MDAlign: Hashable, Sendable { case leading, center, trailing }

nonisolated struct MDListItem: Hashable, Sendable {
    var checked: Bool?   // nil: not a task item
    var blocks: [MDBlock]
}

nonisolated enum MarkdownParser {
    static func parse(_ text: String) -> [MDBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return parse(lines: lines[...])
    }

    // MARK: Line classifiers

    static func indent(_ l: Substring) -> Int {
        var n = 0
        for ch in l {
            if ch == " " { n += 1 } else if ch == "\t" { n += 4 } else { break }
        }
        return n
    }

    static func isBlank(_ l: Substring) -> Bool { l.allSatisfy { $0 == " " || $0 == "\t" } }

    /// Opening fence: up to 3 spaces, then ``` or ~~~ (3+), then an optional info string.
    static func fence(_ l: Substring) -> (char: Character, count: Int, info: String)? {
        guard indent(l) <= 3 else { return nil }
        let t = l.drop(while: { $0 == " " })
        guard let c = t.first, c == "`" || c == "~" else { return nil }
        let run = t.prefix(while: { $0 == c }).count
        guard run >= 3 else { return nil }
        let info = t.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if c == "`" && info.contains("`") { return nil }
        return (c, run, info)
    }

    static func heading(_ l: Substring) -> (Int, String)? {
        guard indent(l) <= 3 else { return nil }
        let t = l.drop(while: { $0 == " " })
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var body = rest.trimmingCharacters(in: .whitespaces)
        // Optional closing hashes: "## Title ##"
        while body.hasSuffix("#") { body.removeLast() }
        return (hashes, body.trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ l: Substring) -> Bool {
        guard indent(l) <= 3 else { return false }
        let t = l.filter { $0 != " " && $0 != "\t" }
        guard t.count >= 3, let c = t.first, c == "-" || c == "*" || c == "_" else { return false }
        return t.allSatisfy { $0 == c }
    }

    static func isQuote(_ l: Substring) -> Bool { indent(l) <= 3 && l.drop(while: { $0 == " " }).first == ">" }

    static func stripQuote(_ l: Substring) -> Substring {
        var t = l.drop(while: { $0 == " " })
        if t.first == ">" { t = t.dropFirst() }
        if t.first == " " { t = t.dropFirst() }
        return t
    }

    nonisolated struct ItemMarker { var indent: Int; var ordered: Bool; var number: Int; var contentIndent: Int; var text: Substring }

    static func listMarker(_ l: Substring) -> ItemMarker? {
        let ind = indent(l)
        let t = l.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = t.first else { return nil }
        if first == "-" || first == "*" || first == "+" {
            let after = t.dropFirst()
            guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
            // "---" and "***" are rules, not items.
            if isRule(l) { return nil }
            let text = after.drop(while: { $0 == " " || $0 == "\t" })
            return ItemMarker(indent: ind, ordered: false, number: 0, contentIndent: ind + 2, text: text)
        }
        let digits = t.prefix(while: { $0.isASCII && $0.isNumber })
        guard (1...9).contains(digits.count) else { return nil }
        let rest = t.dropFirst(digits.count)
        guard let d = rest.first, d == "." || d == ")" else { return nil }
        let after = rest.dropFirst()
        guard after.isEmpty || after.first == " " || after.first == "\t" else { return nil }
        let text = after.drop(while: { $0 == " " || $0 == "\t" })
        return ItemMarker(indent: ind, ordered: true, number: Int(digits) ?? 1, contentIndent: ind + digits.count + 2, text: text)
    }

    static func isTableDelimiter(_ l: Substring) -> Bool {
        let t = l.trimmingCharacters(in: .whitespaces)
        guard t.contains("-") else { return false }
        let cells = splitRow(Substring(t))
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { c in
            let s = c.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return false }
            let core = s.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
    }

    static func splitRow(_ l: Substring) -> [String] {
        var t = l.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var cur = ""
        var inCode = false
        var prev: Character = " "
        for ch in t {
            if ch == "`" { inCode.toggle() }
            if ch == "|" && !inCode && prev != "\\" { cells.append(cur); cur = "" }
            else { cur.append(ch) }
            prev = ch
        }
        cells.append(cur)
        return cells.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|") }
    }

    static func startsBlock(_ l: Substring) -> Bool {
        fence(l) != nil || heading(l) != nil || isQuote(l) || isRule(l) || listMarker(l) != nil
            || l.trimmingCharacters(in: .whitespaces).hasPrefix("$$")
    }

    // MARK: Block parser

    static func parse(lines: ArraySlice<String>) -> [MDBlock] {
        var out: [MDBlock] = []
        var i = lines.startIndex
        let end = lines.endIndex

        while i < end {
            let line = Substring(lines[i])
            if isBlank(line) { i += 1; continue }

            // Fenced code
            if let f = fence(line) {
                var body: [String] = []
                let fenceIndent = indent(line)
                i += 1
                while i < end {
                    let l = Substring(lines[i])
                    if let close = fence(l), close.char == f.char, close.count >= f.count, close.info.isEmpty { i += 1; break }
                    // Strip up to the fence's own indentation from content lines.
                    var s = l
                    var k = 0
                    while k < fenceIndent, s.first == " " { s = s.dropFirst(); k += 1 }
                    body.append(String(s))
                    i += 1
                }
                let lang = f.info.split(separator: " ").first.map(String.init) ?? ""
                out.append(.code(lang: lang, text: body.joined(separator: "\n")))
                continue
            }

            // Display math: $$ … $$ (single line or multi-line)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("$$") {
                let afterOpen = String(trimmed.dropFirst(2))
                if let r = afterOpen.range(of: "$$") {
                    out.append(.math(String(afterOpen[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)))
                    i += 1
                    continue
                }
                var body: [String] = afterOpen.isEmpty ? [] : [afterOpen]
                i += 1
                while i < end {
                    let l = lines[i]
                    if let r = l.range(of: "$$") {
                        let before = String(l[..<r.lowerBound])
                        if !before.trimmingCharacters(in: .whitespaces).isEmpty { body.append(before) }
                        i += 1
                        break
                    }
                    body.append(l)
                    i += 1
                }
                out.append(.math(body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                continue
            }

            if let h = heading(line) {
                out.append(.heading(level: h.0, text: h.1))
                i += 1
                continue
            }

            if isRule(line) {
                out.append(.rule)
                i += 1
                continue
            }

            if isQuote(line) {
                var inner: [String] = []
                while i < end {
                    let l = Substring(lines[i])
                    if isQuote(l) { inner.append(String(stripQuote(l))) }
                    else if !isBlank(l), !startsBlock(l), !inner.isEmpty { inner.append(String(l)) }   // lazy continuation
                    else { break }
                    i += 1
                }
                out.append(.quote(parse(lines: inner[...])))
                continue
            }

            if let first = listMarker(line) {
                let (block, next) = parseList(lines, from: i, first: first)
                out.append(block)
                i = next
                continue
            }

            // GFM table: a row with pipes followed by a delimiter row.
            if line.contains("|"), i + 1 < end, isTableDelimiter(Substring(lines[i + 1])) {
                let header = splitRow(line)
                let aligns: [MDAlign] = splitRow(Substring(lines[i + 1])).map { c in
                    let s = c.trimmingCharacters(in: .whitespaces)
                    if s.hasPrefix(":") && s.hasSuffix(":") { return .center }
                    if s.hasSuffix(":") { return .trailing }
                    return .leading
                }
                var rows: [[String]] = []
                i += 2
                while i < end {
                    let l = Substring(lines[i])
                    if isBlank(l) || !l.contains("|") { break }
                    var cells = splitRow(l)
                    if cells.count < header.count { cells += Array(repeating: "", count: header.count - cells.count) }
                    rows.append(Array(cells.prefix(header.count)))
                    i += 1
                }
                out.append(.table(header: header, alignments: aligns, rows: rows))
                continue
            }

            // Paragraph: until a blank line or the start of another block.
            var para: [String] = [String(line)]
            i += 1
            while i < end {
                let l = Substring(lines[i])
                if isBlank(l) || startsBlock(l) { break }
                if l.contains("|"), i + 1 < end, isTableDelimiter(Substring(lines[i + 1])) { break }
                para.append(String(l))
                i += 1
            }
            out.append(.paragraph(joinParagraph(para)))
        }
        return out
    }

    /// Soft line breaks become spaces (as in the PWA's renderer); a trailing backslash or two
    /// trailing spaces force a hard break.
    static func joinParagraph(_ lines: [String]) -> String {
        var out = ""
        for (n, raw) in lines.enumerated() {
            var l = raw
            let hard = l.hasSuffix("  ") || l.hasSuffix("\\")
            if l.hasSuffix("\\") { l.removeLast() }
            l = l.trimmingCharacters(in: .whitespaces)
            out += l
            if n < lines.count - 1 { out += hard ? "\n" : " " }
        }
        return out
    }

    private static func parseList(_ lines: ArraySlice<String>, from start: Int, first: ItemMarker) -> (MDBlock, Int) {
        var items: [MDListItem] = []
        var current: [String] = []
        var contentIndent = first.contentIndent
        var i = start
        let end = lines.endIndex

        func flush() {
            guard !current.isEmpty else { return }
            var text = current
            var checked: Bool?
            if let head = text.first {
                let h = head.trimmingCharacters(in: .whitespaces)
                if h.hasPrefix("[ ] ") || h == "[ ]" { checked = false; text[0] = String(h.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                else if h.lowercased().hasPrefix("[x] ") || h.lowercased() == "[x]" { checked = true; text[0] = String(h.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
            }
            items.append(MDListItem(checked: checked, blocks: parse(lines: text[...])))
            current = []
        }

        while i < end {
            let l = Substring(lines[i])
            if isBlank(l) {
                // A blank line continues the list only if more of it follows.
                var j = i + 1
                while j < end, isBlank(Substring(lines[j])) { j += 1 }
                guard j < end else { break }
                let nl = Substring(lines[j])
                let nm = listMarker(nl)
                let continues = (nm != nil && nm!.indent < contentIndent && nm!.ordered == first.ordered) || indent(nl) >= contentIndent
                guard continues else { break }
                current.append("")
                i += 1
                continue
            }
            if let m = listMarker(l), m.indent < contentIndent {
                guard m.ordered == first.ordered, m.indent <= first.indent + 3 else { break }
                flush()
                current = [String(m.text)]
                contentIndent = m.contentIndent
                i += 1
                continue
            }
            if indent(l) >= contentIndent {
                // Continuation or nested block: de-indent by the item's content offset.
                var s = l
                var k = 0
                while k < contentIndent, let c = s.first, c == " " || c == "\t" { s = s.dropFirst(); k += c == "\t" ? 4 : 1 }
                current.append(String(s))
                i += 1
                continue
            }
            if !current.isEmpty, !startsBlock(l), !(current.last?.isEmpty ?? true) {
                current.append(String(l))   // lazy paragraph continuation
                i += 1
                continue
            }
            break
        }
        flush()
        return (.list(ordered: first.ordered, start: first.number, items: items), i)
    }
}
