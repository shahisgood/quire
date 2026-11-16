import SwiftUI
import UIKit
import WebKit

/// What a chat's PDF includes beyond the conversation itself.
nonisolated struct PDFOptions: Hashable, Sendable {
    /// The time of each message, by its speaker's name.
    var times = true
    /// A reply's reasoning, set small above it.
    var reasoning = false
    /// Dark pages, in the theme's dark colours: for reading on a screen at night. Light pages print.
    var dark = false
}

/// A chat set as a document, and nothing else: its title, when it was, who answered, then the
/// conversation. Written out as a page of HTML in the app's own typefaces and the theme's colours,
/// light (to print) or dark (to read at night), laid out by WebKit at the page's own width, then
/// printed into pages: A4, or US Letter where that's the local paper, numbered at the foot.
/// Your messages are set as panels under "You"; replies run the full measure under the model's
/// name, in the reading face, Markdown and all.
enum ChatPDF {
    nonisolated struct Result: Hashable, Sendable {
        let url: URL
        let pages: Int
        let bytes: Int
    }

    static var paper: CGSize {
        Locale.current.measurementSystem == .us ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89)
    }

    static var paperName: String { Locale.current.measurementSystem == .us ? "US Letter" : "A4" }

    /// Page margins. The foot holds the page number.
    static let margins = UIEdgeInsets(top: 52, left: 56, bottom: 28, right: 56)
    static let footer: CGFloat = 30

    static func make(_ session: ChatSession, app: AppModel, options: PDFOptions) async throws -> Result {
        let title = session.chat.title
        let page = html(session, app: app, options: options)
        let p = ThemeStore.shared.palette
        let (data, pages) = try await Typesetter().pdf(html: page, title: title,
                                                       paperColor: options.dark ? uiColor(p.base, dark: true) : .white,
                                                       ink2: uiColor(p.ink2, dark: options.dark))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDF", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(fileName(title)).pdf")
        try data.write(to: url, options: .atomic)
        return Result(url: url, pages: pages, bytes: data.count)
    }

    /// The chat's title as a file name people would recognise in Files or an email.
    private static func fileName(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Chat" : String(cleaned.prefix(64))
    }

    // MARK: Document

    static func html(_ session: ChatSession, app: AppModel, options: PDFOptions) -> String {
        let chat = session.chat
        let ui = app.settings.ui
        let thread = session.thread.filter { $0.role != .system }
        let started = Date(timeIntervalSince1970: chat.createdAt / 1000)

        // Only what you need to place it: when, and who answered.
        var meta: [String] = [started.formatted(date: .long, time: .shortened)]
        var models: [String] = []
        for m in thread where m.role == .assistant {
            let name = app.modelName(m.modelId ?? chat.modelId)
            if !models.contains(name) { models.append(name) }
        }
        meta += models

        var body = """
        <header class="head">
        <h1 class="title">\(esc(chat.title))</h1>
        <p class="meta">\(esc(meta.joined(separator: " · ")))</p>
        </header>

        """

        for m in thread {
            var stamp = ""
            if options.times { stamp = "<span class=\"time\">" + esc(time(m.createdAt, since: started)) + "</span>" }
            if m.role == .user {
                body += "<section class=\"turn you\">"
                body += "<div class=\"who\"><span class=\"name\">You</span>" + stamp + "</div>"
                if !m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    body += "<div class=\"said\">\(lines(m.content))</div>"
                }
                body += attachments(m.attachments)
                body += "</section>\n"
            } else {
                let name = app.modelName(m.modelId ?? chat.modelId)
                body += "<section class=\"turn reply\">"
                body += "<div class=\"who\"><span class=\"name model\">" + esc(name) + "</span>" + stamp + "</div>"
                if options.reasoning, let r = m.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
                    body += "<div class=\"thought\"><div class=\"label\">Reasoning</div>\(blocks(MarkdownParser.parse(r)))</div>"
                }
                if m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let e = m.error { body += "<p class=\"note\">No reply: \(esc(e.message))</p>" }
                    else if m.status == .interrupted { body += "<p class=\"note\">Stopped before it began.</p>" }
                } else {
                    body += "<div class=\"body\">\(blocks(MarkdownParser.parse(m.content)))</div>"
                    if m.status == .interrupted { body += "<p class=\"note\">Stopped here.</p>" }
                }
                body += attachments(m.attachments)
                body += sources(Source.of(m))
                body += "</section>\n"
            }
        }

        // The page is laid out at its own width, one CSS pixel to the point, so type is set at the
        // sizes given and nothing is scaled down to fit a phone's idea of a web page.
        return """
        <!doctype html>
        <html lang="\(esc(Locale.current.language.languageCode?.identifier ?? "en"))"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(chat.title))</title>
        <style>\(css(ui, dark: options.dark))</style>
        </head><body>\(body)</body></html>
        """
    }

    /// The time alone within the day the chat began; the date as well after that.
    private static func time(_ ms: Double, since start: Date) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        if Calendar.current.isDate(d, inSameDayAs: start) { return d.formatted(date: .omitted, time: .shortened) }
        return d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }


    // MARK: Sources

    /// A reply's sources under it, numbered, each with its site and the page's title.
    private static func sources(_ list: [Source]) -> String {
        guard !list.isEmpty else { return "" }
        var out = "<div class=\"sources\"><div class=\"label\">Sources</div><ol>"
        for s in list {
            out += "<li><span class=\"site\">\(esc(s.host))</span> \(esc(s.title ?? s.url.absoluteString))</li>"
        }
        return out + "</ol></div>"
    }

    // MARK: Attachments

    private static func attachments(_ list: [Attachment]?) -> String {
        guard let list, !list.isEmpty else { return "" }
        var out = "<div class=\"pics\">"
        for a in list {
            if a.kind == .image, a.dataUrl.hasPrefix("data:image/") {
                out += "<img class=\"pic\" src=\"\(esc(a.dataUrl))\" alt=\"\(esc(a.name))\">"
            } else {
                let size = a.size > 0 ? " · " + Fmt.bytes(a.size) : ""
                out += "<span class=\"file\">" + esc(a.name + size) + "</span>"
            }
        }
        return out + "</div>"
    }

    // MARK: Markdown

    /// Your own words, as typed: line breaks kept, nothing interpreted.
    private static func lines(_ text: String) -> String {
        esc(text.trimmingCharacters(in: .whitespacesAndNewlines)).replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func blocks(_ list: [MDBlock]) -> String {
        list.map { block($0) }.joined()
    }

    private static func block(_ b: MDBlock) -> String {
        switch b {
        case .heading(let level, let text):
            let tag = "h\(min(level + 1, 6))"
            return "<\(tag)>\(inline(text))</\(tag)>"
        case .paragraph(let text):
            return "<p>\(inline(text))</p>"
        case .code(let lang, let text):
            let lineCount = text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let caption = lang.isEmpty ? "" : "<figcaption>\(esc(lang.lowercased()))</figcaption>"
            return "<figure class=\"code\(lineCount <= 28 ? " keep" : "")\">\(caption)<pre><code>\(highlighted(text, lang: lang))</code></pre></figure>"
        case .math(let tex):
            return "<pre class=\"math\">\(esc(tex))</pre>"
        case .quote(let inner):
            return "<blockquote>\(blocks(inner))</blockquote>"
        case .list(let ordered, let start, let items):
            let open = ordered ? "<ol\(start != 1 ? " start=\"\(start)\"" : "")>" : "<ul>"
            var out = open
            for item in items {
                if let checked = item.checked {
                    out += "<li class=\"task\"><span class=\"box\(checked ? " on" : "")\"></span>\(blocks(item.blocks))</li>"
                } else {
                    out += "<li>\(blocks(item.blocks))</li>"
                }
            }
            return out + (ordered ? "</ol>" : "</ul>")
        case .table(let header, let alignments, let rows):
            func align(_ i: Int) -> String {
                let a = i < alignments.count ? alignments[i] : MDAlign.leading
                switch a {
                case .leading: return ""
                case .center: return " style=\"text-align:center\""
                case .trailing: return " style=\"text-align:right\""
                }
            }
            var out = "<table><thead><tr>"
            for (i, h) in header.enumerated() { out += "<th\(align(i))>\(inline(h))</th>" }
            out += "</tr></thead><tbody>"
            for row in rows {
                out += "<tr>"
                for i in header.indices { out += "<td\(align(i))>\(inline(i < row.count ? row[i] : ""))</td>" }
                out += "</tr>"
            }
            return out + "</tbody></table>"
        case .rule:
            return "<hr>"
        }
    }

    /// Inline Markdown through Foundation's parser, as the app reads it, written back out as HTML.
    private static func inline(_ source: String) -> String {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                          failurePolicy: .returnPartiallyParsedIfPossible)
        guard let a = try? AttributedString(markdown: source, options: opts) else { return lines(source) }
        var out = ""
        for run in a.runs {
            var piece = esc(String(a[run.range].characters)).replacingOccurrences(of: "\n", with: "<br>")
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { piece = "<code>\(piece)</code>" }
            if intent.contains(.strikethrough) { piece = "<s>\(piece)</s>" }
            if intent.contains(.emphasized) { piece = "<em>\(piece)</em>" }
            if intent.contains(.stronglyEmphasized) { piece = "<strong>\(piece)</strong>" }
            if let link = run.link {
                // A citation reads as a small pill with the site's name, as in the app.
                if let host = Site.host(link), Site.isCitation(String(a[run.range].characters), host: host) {
                    piece = "<a class=\"pill\" href=\"\(esc(link.absoluteString))\">\(esc(Site.name(host)))</a>"
                } else {
                    piece = "<a href=\"\(esc(link.absoluteString))\">\(piece)</a>"
                }
            }
            out += piece
        }
        return out
    }

    /// Code coloured as the app colours it, by the same highlighter.
    private static func highlighted(_ code: String, lang: String) -> String {
        let ns = code as NSString
        let spans = Highlighter.tokens(code, lang: lang.lowercased()).sorted { $0.range.location < $1.range.location }
        var out = ""
        var at = 0
        for s in spans where s.range.location >= at {
            if s.range.location > at { out += esc(ns.substring(with: NSRange(location: at, length: s.range.location - at))) }
            let cls: String
            switch s.kind {
            case .keyword: cls = "k"
            case .string: cls = "s"
            case .number: cls = "n"
            case .comment: cls = "c"
            }
            out += "<span class=\"\(cls)\">\(esc(ns.substring(with: s.range)))</span>"
            at = s.range.location + s.range.length
        }
        if at < ns.length { out += esc(ns.substring(from: at)) }
        return out
    }

    private static func esc(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    // MARK: Style

    /// A colour as the theme has it in the light (for printing) or in the dark.
    static func uiColor(_ c: Color, dark: Bool) -> UIColor {
        UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
    }

    private static func hex(_ c: Color, dark: Bool) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor(c, dark: dark).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// A face as a CSS font stack. Geist's cuts are embedded in the page (see `embedded`).
    private static func family(_ face: Face) -> String {
        switch face {
        case .newYork: "ui-serif, 'New York', Georgia, serif"
        case .sfPro: "-apple-system, system-ui, 'Helvetica Neue', sans-serif"
        case .sfRounded: "ui-rounded, -apple-system, system-ui, sans-serif"
        case .geistSans: "'Quire Geist Sans', -apple-system, system-ui, sans-serif"
        case .geistSerif: "'Quire Geist Serif', ui-serif, Georgia, serif"
        case .geistMono: "'Quire Geist Mono', ui-monospace, Menlo, monospace"
        case .geistPixel: "'Quire Geist Pixel', ui-monospace, Menlo, monospace"
        }
    }

    /// The bundled Geist files a page needs, as `@font-face` rules carrying the fonts themselves,
    /// so WebKit sets the PDF in the same cuts as the app. Missing weights are left for WebKit to
    /// make up from the nearest.
    private static func embedded(_ faces: Set<Face>) -> String {
        let files: [Face: [(file: String, weight: Int, italic: Bool)]] = [
            .geistSans: [("Geist-Regular", 400, false), ("Geist-Italic", 400, true), ("Geist-SemiBold", 600, false), ("Geist-Bold", 700, false)],
            .geistSerif: [("GeistSerif-Regular", 400, false)],
            .geistMono: [("GeistMono-Regular", 400, false), ("GeistMono-SemiBold", 600, false), ("GeistMono-Bold", 700, false)],
            .geistPixel: [("GeistPixel-Square", 400, false)],
        ]
        var out = ""
        for face in [Face.geistSans, .geistSerif, .geistMono, .geistPixel] where faces.contains(face) {
            for f in files[face] ?? [] {
                guard let url = Bundle.main.url(forResource: f.file, withExtension: "ttf"),
                      let data = try? Data(contentsOf: url) else { continue }
                out += "@font-face { font-family: 'Quire \(face.name)'; src: url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype'); "
                out += "font-weight: \(f.weight); font-style: \(f.italic ? "italic" : "normal"); }\n"
            }
        }
        return out
    }

    private static func css(_ ui: UISettings, dark: Bool) -> String {
        let p = ThemeStore.shared.palette
        func c(_ color: Color) -> String { hex(color, dark: dark) }
        let geist = ui.typeface == .geist
        let titles = family(ui.titleFace)
        let replies = family(ui.replyFace)
        // Labels and the small print: the typeface's own sans.
        let sans = family(geist ? .geistSans : (ui.typeface == .sfRounded ? .sfRounded : .sfPro))
        let mono = ui.codeFace == .geistMono ? family(.geistMono) : "ui-monospace, 'SF Mono', Menlo, monospace"
        var faces: Set<Face> = [ui.titleFace, ui.replyFace]
        if geist { faces.formUnion([.geistSans, .geistMono]) }
        // On a dark page your messages sit on a lifted panel; on paper, a sunken one.
        let panel = dark ? c(p.raised) : c(p.sunken)
        return embedded(faces) + """
        :root {
          --ink: \(c(p.ink)); --body: \(c(p.inkBody)); --strong: \(c(p.inkStrong)); --ink2: \(c(p.ink2));
          --rule: \(c(p.rule)); --accent: \(c(p.accent)); --soft: \(c(p.accentSoft)); --panel: \(panel);
          --kw: \(c(Color.qCodeKeyword)); --str: \(c(Color.qCodeString)); --num: \(c(Color.qCodeNumber)); --com: \(c(Color.qCodeComment));
        }
        * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        html, body { margin: 0; padding: 0; background: transparent; }
        body { font-family: \(replies); font-size: 11.5pt; line-height: 1.6; color: var(--body);
               -webkit-text-size-adjust: 100%; text-rendering: optimizeLegibility; font-kerning: normal;
               overflow-wrap: break-word; }

        .head { margin: 0 0 24pt; }
        h1.title { font-family: \(titles); font-size: 20pt; line-height: 1.2; font-weight: 600; letter-spacing: -0.01em;
                   color: var(--ink); margin: 0 0 6pt; }
        .meta { font-family: \(sans); font-size: 9pt; line-height: 1.5; color: var(--ink2); margin: 0; }

        .turn { margin: 0 0 16pt; }
        .turn.you { margin-top: 28pt; }
        .head + .turn.you { margin-top: 0; }
        .who { font-family: \(sans); font-size: 9pt; line-height: 1.3; margin: 0 0 6pt;
               display: flex; justify-content: space-between; align-items: baseline;
               break-after: avoid; page-break-after: avoid; }
        .who .name { font-weight: 600; color: var(--ink); }
        .who .model { color: var(--accent); }
        .who .time { color: var(--ink2); font-variant-numeric: tabular-nums; }
        .said { font-family: \(sans); font-size: 11pt; line-height: 1.55; color: var(--ink); background: var(--panel);
                border-radius: 10pt; padding: 10pt 12pt; }
        .body > :first-child { margin-top: 0; }
        .body > :last-child { margin-bottom: 0; }

        .pics { margin-top: 8pt; line-height: 0; }
        .pic { display: inline-block; vertical-align: top; max-width: 60%; max-height: 220pt; border-radius: 8pt; margin: 0 8pt 8pt 0; }
        .file { display: inline-block; font-family: \(sans); font-size: 9pt; line-height: 1.4; color: var(--ink2); background: var(--panel);
                border-radius: 6pt; padding: 4pt 8pt; margin: 0 8pt 8pt 0; }

        p { margin: 0 0 8pt; orphans: 3; widows: 3; }
        strong { color: var(--strong); font-weight: 600; }
        a { color: var(--accent); text-decoration: none; }
        h2, h3, h4, h5, h6 { font-family: \(titles); color: var(--ink); line-height: 1.3; font-weight: 600;
                             margin: 16pt 0 6pt; break-after: avoid; page-break-after: avoid; }
        h2 { font-size: 15pt; } h3 { font-size: 13pt; } h4 { font-size: 12pt; }
        h5, h6 { font-size: 11.5pt; color: var(--ink2); }
        ul, ol { margin: 0 0 8pt; padding-left: 18pt; }
        li { margin: 0 0 4pt; }
        li > p { margin: 0 0 4pt; }
        li > ul, li > ol { margin: 4pt 0 0; }
        li::marker { color: var(--ink2); }
        li.task { list-style: none; position: relative; }
        li.task .box { position: absolute; left: -16pt; top: 0.38em; width: 8pt; height: 8pt; border: 1pt solid var(--ink2); border-radius: 2pt; }
        li.task .box.on { background: var(--accent); border-color: var(--accent); }
        blockquote { margin: 0 0 8pt; padding: 0 0 0 12pt; border-left: 2pt solid var(--rule); color: var(--ink2); }
        code { font-family: \(mono); font-size: 0.86em; color: var(--ink); background: var(--panel); border-radius: 4pt; padding: 1pt 4pt; }
        figure.code { margin: 4pt 0 12pt; background: var(--panel); border-radius: 10pt; padding: 10pt 12pt; }
        figure.code.keep { break-inside: avoid; page-break-inside: avoid; }
        figure.code figcaption { font-family: \(sans); font-size: 8pt; font-weight: 600; color: var(--ink2); margin: 0 0 6pt; }
        pre { margin: 0; font-family: \(mono); font-size: 9pt; line-height: 1.5; color: var(--ink); white-space: pre-wrap; overflow-wrap: anywhere; }
        pre code { background: none; padding: 0; font-size: inherit; border-radius: 0; }
        .k { color: var(--kw); } .s { color: var(--str); } .n { color: var(--num); } .c { color: var(--com); font-style: italic; }
        pre.math { background: var(--panel); border-radius: 10pt; padding: 10pt 12pt; margin: 4pt 0 12pt; break-inside: avoid; }
        table { border-collapse: collapse; width: 100%; margin: 4pt 0 12pt; font-family: \(sans); font-size: 9.5pt; line-height: 1.45;
                color: var(--ink); break-inside: avoid; page-break-inside: avoid; }
        th { font-weight: 600; text-align: left; padding: 0 12pt 6pt 0; border-bottom: 1pt solid var(--ink2); vertical-align: bottom; }
        td { padding: 6pt 12pt 6pt 0; border-bottom: 0.5pt solid var(--rule); vertical-align: top; }
        tr:last-child td { border-bottom: 0; }
        hr { border: 0; height: 0.5pt; background: var(--rule); margin: 16pt 0; }
        .thought { font-family: \(sans); font-size: 9.5pt; line-height: 1.5; color: var(--ink2); border-left: 2pt solid var(--rule);
                   padding: 0 0 0 12pt; margin: 0 0 12pt; }
        .thought .label { font-weight: 600; margin-bottom: 4pt; }
        .thought p, .thought li { margin-bottom: 4pt; }
        .thought strong, .thought code { color: var(--ink2); }
        a.pill { font-family: \(sans); font-size: 8pt; font-weight: 500; color: var(--ink2); background: var(--panel);
                 border-radius: 999px; padding: 1pt 6pt; white-space: nowrap; }
        .sources { font-family: \(sans); font-size: 9pt; line-height: 1.5; color: var(--ink2); margin: 12pt 0 0;
                   break-inside: avoid; page-break-inside: avoid; }
        .sources .label { font-weight: 600; color: var(--ink); margin-bottom: 4pt; }
        .sources ol { margin: 0; padding-left: 16pt; }
        .sources li { margin: 0 0 2pt; }
        .sources .site { font-weight: 600; color: var(--accent); }
        .note { font-family: \(sans); font-size: 9.5pt; font-style: italic; color: var(--ink2); margin: 8pt 0 0; }
        """
    }
}

// MARK: - Typesetting

/// Lays the page out in an out-of-sight web view, then prints it into PDF pages.
private final class Typesetter: NSObject, WKNavigationDelegate {
    enum Failure: LocalizedError {
        case timedOut, empty
        var errorDescription: String? {
            switch self {
            case .timedOut: "Laying out the pages took too long."
            case .empty: "There was nothing to print."
            }
        }
    }

    private var loaded: CheckedContinuation<Void, Error>?

    func pdf(html: String, title: String, paperColor: UIColor, ink2: UIColor) async throws -> (Data, Int) {
        let paper = ChatPDF.paper
        let m = ChatPDF.margins
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: paper.width - m.left - m.right, height: paper.height), configuration: config)
        web.navigationDelegate = self
        web.isUserInteractionEnabled = false
        web.accessibilityElementsHidden = true
        // WebKit lays out and decodes images reliably only in a window: put it in one, off to the side.
        if let window = Self.window {
            web.frame.origin = CGPoint(x: -web.frame.width * 2 - 100, y: 0)
            window.addSubview(web)
        }
        defer { web.removeFromSuperview() }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loaded = c
            web.loadHTMLString(html, baseURL: nil)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(20))
                if let pending = self?.loaded {
                    self?.loaded = nil
                    pending.resume(throwing: Failure.timedOut)
                }
            }
        }
        // A beat for images and fonts to settle after the load event.
        try? await Task.sleep(for: .milliseconds(150))

        let renderer = PageRenderer(paper: paper, margins: m, footer: ChatPDF.footer, ink2: ink2)
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let pages = renderer.numberOfPages
        guard pages > 0 else { throw Failure.empty }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Quire"]
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: paper), format: format).pdfData { ctx in
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
            for i in 0..<pages {
                ctx.beginPage()
                // The page's colour, edge to edge; the text is laid over it with no background of
                // its own, so there's one colour and no seams at the margins.
                paperColor.setFill()
                ctx.fill(ctx.pdfContextBounds)
                renderer.drawPage(at: i, in: ctx.pdfContextBounds)
            }
        }
        return (data, pages)
    }

    private static var window: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !($0 is ToastWindow) }
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }
}

/// Pages of a fixed size and margin, each numbered at its foot.
private final class PageRenderer: UIPrintPageRenderer {
    private let paper: CGRect
    private let printable: CGRect
    private let ink2: UIColor

    init(paper: CGSize, margins: UIEdgeInsets, footer: CGFloat, ink2: UIColor) {
        self.paper = CGRect(origin: .zero, size: paper)
        self.printable = self.paper.inset(by: margins)
        self.ink2 = ink2
        super.init()
        headerHeight = 0
        footerHeight = footer
    }

    override var paperRect: CGRect { paper }
    override var printableRect: CGRect { printable }

    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        guard numberOfPages > 1 else { return }
        let folio = NSAttributedString(string: "\(pageIndex + 1) / \(numberOfPages)", attributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: ink2,
        ])
        let size = folio.size()
        folio.draw(at: CGPoint(x: footerRect.maxX - size.width, y: footerRect.maxY - size.height))
    }
}
