import SwiftUI
import UIKit
import WebKit

/// What a chat's PDF includes beyond the conversation itself.
nonisolated struct PDFOptions: Hashable, Sendable {
    /// The time of each message, by its speaker's name.
    var times = true
    /// A reply's reasoning, set small above it.
    var reasoning = false
}

/// A chat set as a document. The conversation is written out as a page of HTML in the app's own
/// typefaces and the theme's colours (always on white, so it prints), laid out by WebKit, then
/// printed into pages: A4, or US Letter where that's the local paper, with the chat's title and
/// a folio at the foot of each. Your messages sit on the right in a soft panel, as they do in the
/// app; replies run the full measure in the reading face, Markdown and all.
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

    /// Page margins. The foot holds the running title and the folio.
    static let margins = UIEdgeInsets(top: 50, left: 58, bottom: 30, right: 58)
    static let footer: CGFloat = 34

    static func make(_ session: ChatSession, app: AppModel, options: PDFOptions) async throws -> Result {
        let title = session.chat.title
        let page = html(session, app: app, options: options)
        let (data, pages) = try await Typesetter().pdf(html: page, title: title, ink2: Self.uiColor(ThemeStore.shared.palette.ink2))
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

        var meta: [String] = [started.formatted(date: .long, time: .shortened)]
        let count = thread.count
        meta.append("\(count) message\(count == 1 ? "" : "s")")
        var models: [String] = []
        for m in thread where m.role == .assistant {
            let name = app.modelName(m.modelId ?? chat.modelId)
            if !models.contains(name) { models.append(name) }
        }
        if models.count == 1 { meta.append(models[0]) } else if models.count > 1 { meta.append("\(models.count) models") }
        var context: [String] = []
        if let p = session.persona { context.append("Persona: \(p.name)") }
        if let p = session.project { context.append("Project: \(p.name)") }
        if !chat.memoryEnabled { context.append("Incognito") }

        var body = """
        <header class="masthead">
        \(mark(width: 26))
        <h1 class="title">\(esc(chat.title))</h1>
        <p class="meta">\(esc(meta.joined(separator: " · ")))</p>
        """
        if !context.isEmpty { body += "<p class=\"meta\">\(esc(context.joined(separator: " · ")))</p>" }
        body += "</header>\n"

        for m in thread {
            var stamp = ""
            if options.times { stamp = "<span class=\"time\"> · " + esc(time(m.createdAt, since: started)) + "</span>" }
            if m.role == .user {
                body += "<section class=\"turn you\">"
                body += "<div class=\"who\">You" + stamp + "</div>"
                if !m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    body += "<div class=\"bubble\">\(lines(m.content))</div>"
                }
                body += attachments(m.attachments)
                body += "</section>\n"
            } else {
                let name = app.modelName(m.modelId ?? chat.modelId)
                body += "<section class=\"turn reply\">"
                body += "<div class=\"who\"><span class=\"model\">" + esc(name) + "</span>" + stamp + "</div>"
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
                body += "</section>\n"
            }
        }

        body += """
        <footer class="end">\(mark(width: 16))<p>Exported from Quire on \(esc(Date().formatted(date: .long, time: .omitted))).</p></footer>
        """

        return """
        <!doctype html>
        <html lang="\(esc(Locale.current.language.languageCode?.identifier ?? "en"))"><head><meta charset="utf-8">
        <title>\(esc(chat.title))</title>
        <style>\(css(ui))</style>
        </head><body>\(body)</body></html>
        """
    }

    /// The time alone within the day the chat began; the date as well after that.
    private static func time(_ ms: Double, since start: Date) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        if Calendar.current.isDate(d, inSameDayAs: start) { return d.formatted(date: .omitted, time: .shortened) }
        return d.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// The Quire mark: three lines of type and the accent block of the cursor.
    private static func mark(width w: Double) -> String {
        let h = w * 0.1
        let centers = [h * 0.5, h * 2.9, h * 5.565]
        let lengths = [w, w * 0.8, w * 0.5]
        let caretW = h * 0.87, caretH = h * 1.53, gap = h * 0.67
        var rects = ""
        for i in 0..<3 {
            rects += "<rect class=\"i\" x=\"0\" y=\"\(f(centers[i] - h / 2))\" width=\"\(f(lengths[i]))\" height=\"\(f(h))\" rx=\"\(f(h / 2))\"/>"
        }
        rects += "<rect class=\"a\" x=\"\(f(lengths[2] + gap))\" y=\"\(f(centers[2] - caretH / 2))\" width=\"\(f(caretW))\" height=\"\(f(caretH))\" rx=\"\(f(caretW * 0.3))\"/>"
        return "<svg class=\"mark\" width=\"\(f(w + gap + caretW))\" height=\"\(f(h * 6.33))\" viewBox=\"0 0 \(f(w + gap + caretW)) \(f(h * 6.33))\" aria-hidden=\"true\">\(rects)</svg>"
    }

    private static func f(_ v: Double) -> String { String(format: "%.2f", v) }

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
        list.map(block).joined()
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
            if let link = run.link { piece = "<a href=\"\(esc(link.absoluteString))\">\(piece)</a>" }
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

    /// A colour as the theme has it in the light, where printed things live.
    static func uiColor(_ c: Color) -> UIColor {
        UIColor(c).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }

    private static func hex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    private static func css(_ ui: UISettings) -> String {
        let p = ThemeStore.shared.palette
        let serif = "ui-serif, 'New York', Georgia, serif"
        let sans = ui.typeface == .sfRounded ? "ui-rounded, -apple-system, system-ui, sans-serif" : "-apple-system, system-ui, 'Helvetica Neue', sans-serif"
        let titles = ui.typeface == .newYork ? serif : sans
        let replies = ui.readingFace == .serif ? serif : sans
        let mono = "ui-monospace, 'SF Mono', Menlo, monospace"
        return """
        :root {
          --ink: \(hex(p.ink)); --body: \(hex(p.inkBody)); --strong: \(hex(p.inkStrong)); --ink2: \(hex(p.ink2));
          --rule: \(hex(p.rule)); --accent: \(hex(p.accent)); --soft: \(hex(p.accentSoft)); --sunken: \(hex(p.sunken));
          --kw: \(hex(Color.qCodeKeyword)); --str: \(hex(Color.qCodeString)); --num: \(hex(Color.qCodeNumber)); --com: \(hex(Color.qCodeComment));
        }
        * { box-sizing: border-box; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
        html, body { margin: 0; padding: 0; background: #FFFFFF; }
        body { font-family: \(replies); font-size: 11pt; line-height: 1.58; color: var(--body);
               -webkit-text-size-adjust: none; text-rendering: optimizeLegibility; font-kerning: normal;
               hanging-punctuation: first; overflow-wrap: break-word; }
        .masthead { margin: 4pt 0 30pt; }
        .mark .i { fill: var(--ink); } .mark .a { fill: var(--accent); }
        .masthead .mark { display: block; margin-bottom: 20pt; }
        h1.title { font-family: \(titles); font-size: 25pt; line-height: 1.12; font-weight: 600; letter-spacing: -0.015em;
                   color: var(--ink); margin: 0 0 9pt; }
        .meta { font-family: \(sans); font-size: 8.8pt; line-height: 1.5; color: var(--ink2); margin: 0; }
        .turn { margin: 0 0 20pt; }
        .turn.you { margin-top: 26pt; }
        .you .who { text-align: right; }
        .who { font-family: \(sans); font-size: 8pt; line-height: 1.3; font-weight: 600; color: var(--ink);
               margin: 0 0 5pt; break-after: avoid; page-break-after: avoid; }
        .who .model { color: var(--accent); }
        .who .time { font-weight: 400; color: var(--ink2); }
        .bubble { font-family: \(sans); font-size: 10.5pt; line-height: 1.5; color: var(--ink); background: var(--sunken);
                  border-radius: 13pt; padding: 8pt 13pt 9pt; width: -webkit-fit-content; width: fit-content; max-width: 82%;
                  margin-left: auto; break-inside: avoid; page-break-inside: avoid; }
        .pics { margin-top: 7pt; line-height: 0; }
        .you .pics { text-align: right; }
        .pic { display: inline-block; vertical-align: top; max-width: 230pt; max-height: 230pt; border-radius: 9pt; margin: 0 0 6pt 6pt; }
        .reply .pic { margin: 0 6pt 6pt 0; }
        .file { display: inline-block; font-family: \(sans); font-size: 8.5pt; line-height: 1.4; color: var(--ink2); background: var(--sunken);
                border-radius: 7pt; padding: 3pt 9pt; margin: 0 0 6pt 6pt; }
        .body > :first-child { margin-top: 0; }
        .body > :last-child { margin-bottom: 0; }
        p { margin: 0 0 7.5pt; orphans: 3; widows: 3; }
        strong { color: var(--strong); font-weight: 600; }
        a { color: var(--accent); text-decoration: none; }
        h2, h3, h4, h5, h6 { font-family: \(titles); color: var(--ink); line-height: 1.25; font-weight: 600;
                             margin: 14pt 0 5pt; break-after: avoid; page-break-after: avoid; }
        h2 { font-size: 15pt; letter-spacing: -0.01em; } h3 { font-size: 13pt; } h4 { font-size: 11.5pt; }
        h5, h6 { font-size: 11pt; color: var(--ink2); }
        ul, ol { margin: 0 0 7.5pt; padding-left: 16pt; }
        li { margin: 0 0 3pt; }
        li > p { margin: 0 0 3pt; }
        li > ul, li > ol { margin: 3pt 0 0; }
        li::marker { color: var(--ink2); }
        li.task { list-style: none; position: relative; }
        li.task .box { position: absolute; left: -15pt; top: 0.36em; width: 8pt; height: 8pt; border: 1pt solid var(--ink2); border-radius: 2.2pt; }
        li.task .box.on { background: var(--accent); border-color: var(--accent); }
        blockquote { margin: 0 0 7.5pt; padding: 1pt 0 1pt 12pt; border-left: 2.5pt solid var(--soft); color: var(--ink2); }
        code { font-family: \(mono); font-size: 0.84em; color: var(--ink); background: var(--sunken); border-radius: 3pt; padding: 0.5pt 3.5pt; }
        figure.code { margin: 3pt 0 10pt; background: var(--sunken); border-radius: 9pt; padding: 9pt 12pt 10pt; }
        figure.code.keep { break-inside: avoid; page-break-inside: avoid; }
        figure.code figcaption { font-family: \(sans); font-size: 7.5pt; font-weight: 600; color: var(--ink2); margin: 0 0 5pt; }
        pre { margin: 0; font-family: \(mono); font-size: 8.3pt; line-height: 1.5; color: var(--ink); white-space: pre-wrap; overflow-wrap: anywhere; }
        pre code { background: none; padding: 0; font-size: inherit; border-radius: 0; }
        .k { color: var(--kw); } .s { color: var(--str); } .n { color: var(--num); } .c { color: var(--com); font-style: italic; }
        pre.math { background: var(--sunken); border-radius: 9pt; padding: 9pt 12pt; margin: 3pt 0 10pt; break-inside: avoid; }
        table { border-collapse: collapse; width: 100%; margin: 4pt 0 11pt; font-family: \(sans); font-size: 8.8pt; line-height: 1.4;
                color: var(--ink); break-inside: avoid; page-break-inside: avoid; }
        th { font-weight: 600; text-align: left; padding: 0 10pt 5pt 0; border-bottom: 1pt solid var(--ink2); vertical-align: bottom; }
        td { padding: 5pt 10pt 5pt 0; border-bottom: 0.5pt solid var(--rule); vertical-align: top; }
        tr:last-child td { border-bottom: 0; }
        hr { border: 0; height: 0.5pt; background: var(--rule); margin: 13pt 0; }
        .thought { font-family: \(sans); font-size: 8.8pt; line-height: 1.5; color: var(--ink2); border-left: 2pt solid var(--rule);
                   padding: 0 0 0 11pt; margin: 0 0 10pt; }
        .thought .label { font-weight: 600; margin-bottom: 3pt; }
        .thought p, .thought li { margin-bottom: 3pt; }
        .thought strong, .thought code { color: var(--ink2); }
        .note { font-family: \(sans); font-size: 9pt; font-style: italic; color: var(--ink2); margin: 6pt 0 0; }
        .end { margin-top: 38pt; text-align: center; font-family: \(sans); font-size: 8pt; color: var(--ink2); break-inside: avoid; page-break-inside: avoid; }
        .end .mark { display: block; margin: 0 auto 9pt; opacity: 0.55; }
        .end p { margin: 0; }
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

    func pdf(html: String, title: String, ink2: UIColor) async throws -> (Data, Int) {
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

        let renderer = PageRenderer(paper: paper, margins: m, footer: ChatPDF.footer, title: title, ink2: ink2)
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let pages = renderer.numberOfPages
        guard pages > 0 else { throw Failure.empty }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Quire"]
        let data = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: paper), format: format).pdfData { ctx in
            renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
            for i in 0..<pages {
                ctx.beginPage()
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

/// Pages of a fixed size and margin, with the chat's title and the folio at the foot of each.
private final class PageRenderer: UIPrintPageRenderer {
    private let paper: CGRect
    private let printable: CGRect
    private let title: String
    private let ink2: UIColor

    init(paper: CGSize, margins: UIEdgeInsets, footer: CGFloat, title: String, ink2: UIColor) {
        self.paper = CGRect(origin: .zero, size: paper)
        self.printable = self.paper.inset(by: margins)
        self.title = title
        self.ink2 = ink2
        super.init()
        headerHeight = 0
        footerHeight = footer
    }

    override var paperRect: CGRect { paper }
    override var printableRect: CGRect { printable }

    override func drawFooterForPage(at pageIndex: Int, in footerRect: CGRect) {
        let folio = NSAttributedString(string: "\(pageIndex + 1) of \(numberOfPages)", attributes: [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .medium),
            .foregroundColor: ink2,
        ])
        let size = folio.size()
        let y = footerRect.maxY - size.height
        folio.draw(at: CGPoint(x: footerRect.maxX - size.width, y: y))

        var font = UIFont.systemFont(ofSize: 8)
        if let serif = font.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitItalic) {
            font = UIFont(descriptor: serif, size: 8)
        }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let head = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: ink2, .paragraphStyle: style])
        let width = max(0, footerRect.width - size.width - 28)
        head.draw(with: CGRect(x: footerRect.minX, y: y, width: width, height: size.height + 4),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }
}
