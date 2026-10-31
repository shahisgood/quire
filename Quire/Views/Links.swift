import SwiftUI
import UIKit
import SafariServices

// Links a reply cites, the way a well-made answer engine shows them: in the text, a small pill
// with the site's icon and name in place of the bare address; under the reply, a Sources button
// with the icons stacked, opening the list. Every link opens in Safari inside Quire, so you come
// straight back to the conversation.

// MARK: - Sites

nonisolated enum Site {
    /// "https://www.nytimes.com/…" → "nytimes.com".
    static func host(_ url: URL) -> String? {
        guard let h = url.host()?.lowercased(), !h.isEmpty else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// The name a pill shows: the site's own part of the address. "en.wikipedia.org" is
    /// "wikipedia", "bbc.co.uk" is "bbc".
    static func name(_ host: String) -> String {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return host }
        let shared: Set<String> = ["co", "com", "org", "net", "ac", "gov", "edu", "ne", "or", "go", "gob", "nic"]
        if parts.count >= 3, let last = parts.last, last.count == 2, shared.contains(parts[parts.count - 2]) {
            return parts[parts.count - 3]
        }
        return parts[parts.count - 2]
    }

    /// Whether a link is a citation rather than words in a sentence: its text is the site's name,
    /// its address, or a reference number. A link whose text is prose ("the official guide")
    /// stays as it is, so nothing the model wrote goes missing.
    static func isCitation(_ text: String, host: String) -> Bool {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return true }
        if t.allSatisfy({ $0.isNumber || $0 == "[" || $0 == "]" || $0 == "^" }), t.count <= 4 { return true }
        for prefix in ["https://", "http://", "www."] where t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
        while t.hasSuffix("/") { t.removeLast() }
        if t == host || t.hasPrefix(host + "/") || host.hasSuffix("." + t) { return true }
        if t.hasPrefix("http") || t.contains("/") && t.contains(".") && !t.contains(" ") { return true }
        let site = name(host)
        return t == site || t.replacingOccurrences(of: " ", with: "") == site
    }

    /// The citation-style links in a piece of Markdown, in order, each once.
    static func citedLinks(in markdown: String) -> [URL] {
        guard markdown.contains("](http"), let re = try? NSRegularExpression(pattern: #"\[([^\]\n]{0,80})\]\((https?://[^)\s]+)\)"#) else { return [] }
        let ns = markdown as NSString
        var out: [URL] = []
        for m in re.matches(in: markdown, range: NSRange(location: 0, length: ns.length)) {
            let label = ns.substring(with: m.range(at: 1))
            guard let url = URL(string: ns.substring(with: m.range(at: 2))), let host = host(url),
                  isCitation(label, host: host), !out.contains(url) else { continue }
            out.append(url)
        }
        return out
    }
}

/// A reply's sources: what web search returned, or failing that the citation links in its text.
nonisolated struct Source: Identifiable, Hashable, Sendable {
    let url: URL
    let host: String
    var title: String?
    var snippet: String?
    var id: String { url.absoluteString }

    static func of(_ message: Message) -> [Source] {
        var out: [Source] = []
        for c in message.citations ?? [] {
            guard let url = URL(string: c.url), let host = Site.host(url), !out.contains(where: { $0.url == url }) else { continue }
            out.append(Source(url: url, host: host, title: c.title, snippet: c.snippet))
        }
        if out.isEmpty {
            for url in Site.citedLinks(in: message.content) {
                guard let host = Site.host(url) else { continue }
                out.append(Source(url: url, host: host))
            }
        }
        return out
    }
}

// MARK: - Icons

/// Each site's icon, fetched once from DuckDuckGo's icon service (which is told the site's name
/// and nothing else), kept on disk, and drawn small with softened corners. Off in Settings, no
/// icon is ever asked for.
@Observable
final class Favicons {
    static let shared = Favicons()

    /// Settings → Appearance → Site icons.
    var enabled = true
    private(set) var icons: [String: UIImage] = [:]
    @ObservationIgnored private var asked: Set<String> = []

    /// The icon if it's here; otherwise asks for it, and whoever read this redraws when it comes.
    func icon(_ host: String) -> UIImage? {
        guard enabled else { return nil }
        if let i = icons[host] { return i }
        if !asked.contains(host) {
            asked.insert(host)
            Task { await load(host) }
        }
        return nil
    }

    private static var folder: URL? {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let dir = base?.appendingPathComponent("Favicons", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ host: String) -> URL? {
        let safe = host.filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return safe.isEmpty ? nil : folder?.appendingPathComponent(safe + ".png")
    }

    private func load(_ host: String) async {
        if let f = Self.file(host), let data = try? Data(contentsOf: f), let img = UIImage(data: data) {
            icons[host] = img
            return
        }
        guard let url = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") else { return }
        guard let fetched = try? await URLSession.shared.data(from: url),
              (fetched.1 as? HTTPURLResponse)?.statusCode == 200,
              let raw = UIImage(data: fetched.0), let icon = Self.prepare(raw) else { return }
        icons[host] = icon
        if let f = Self.file(host), let png = icon.pngData() { try? png.write(to: f, options: .atomic) }
    }

    /// Small and square, its corners softened, at the screen's scale.
    private static func prepare(_ image: UIImage) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let side: CGFloat = 32
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            UIBezierPath(roundedRect: rect, cornerRadius: side * 0.24).addClip()
            let scale = min(side / image.size.width, side / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
    }
}

/// A site's icon as a view: the fetched icon, or a quiet globe while it comes (or if it can't).
struct SiteIcon: View {
    let host: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let icon = Favicons.shared.icon(host) {
                Image(uiImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .foregroundStyle(Color.qInk2)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Pills in the text

/// Marks the stretch of a paragraph that is a citation pill.
nonisolated struct LinkPill: TextAttribute {
    let host: String
}

/// Draws each pill's capsule, and its site icon in the room left for it, under the text.
nonisolated struct PillRenderer: TextRenderer {
    let fill: Color
    let tint: Color
    let icons: [String: Image]
    let showIcons: Bool

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let pill = run[LinkPill.self] else {
                    ctx.draw(run)
                    continue
                }
                let bounds = run.typographicBounds.rect
                let capsule = bounds.insetBy(dx: 0, dy: -1.5)
                ctx.fill(Path(roundedRect: capsule, cornerRadius: capsule.height / 2), with: .color(fill))
                if showIcons {
                    // The two figure spaces after the opening space are the icon's room.
                    let slices = Array(run)
                    let slot = slices.count > 3
                        ? slices[1].typographicBounds.rect.union(slices[2].typographicBounds.rect)
                        : CGRect(x: bounds.minX, y: bounds.minY, width: bounds.height, height: bounds.height)
                    let side = min(slot.width, capsule.height - 5)
                    let rect = CGRect(x: slot.midX - side / 2, y: capsule.midY - side / 2, width: side, height: side)
                    if let icon = icons[pill.host] {
                        ctx.draw(icon, in: rect)
                    } else {
                        var globe = ctx.resolve(Image(systemName: "globe"))
                        globe.shading = .color(tint)
                        ctx.draw(globe, in: rect.insetBy(dx: side * 0.06, dy: side * 0.06))
                    }
                }
                ctx.draw(run)
            }
        }
    }
}

/// Turns the citation links in a paragraph into pills. Nil when there are none, so ordinary
/// paragraphs stay a single plain text.
enum LinkPills {
    struct Composed {
        let text: Text
        let hosts: [String]
    }

    static func compose(_ a: AttributedString, icons: Bool) -> Composed? {
        let runs = Array(a.runs)
        guard runs.contains(where: { $0.link != nil }) else { return nil }
        var out: Text? = nil
        var hosts: [String] = []
        var plain = AttributedString()
        var k = 0
        while k < runs.count {
            guard let url = runs[k].link else {
                plain.append(a[runs[k].range])
                k += 1
                continue
            }
            // The whole link: bold or code inside it splits it into several runs.
            var end = k
            var label = String(a[runs[k].range].characters)
            while end + 1 < runs.count, runs[end + 1].link == url {
                end += 1
                label += String(a[runs[end].range].characters)
            }
            if let host = Site.host(url), Site.isCitation(label, host: host) {
                if !plain.characters.isEmpty { out = join(out, Text(plain)) }
                plain = AttributedString()
                out = join(out, pill(host: host, url: url, icons: icons))
                if !hosts.contains(host) { hosts.append(host) }
            } else {
                for j in k...end { plain.append(a[runs[j].range]) }
            }
            k = end + 1
        }
        guard !hosts.isEmpty else { return nil }
        if !plain.characters.isEmpty { out = join(out, Text(plain)) }
        return out.map { Composed(text: $0, hosts: hosts) }
    }

    private static func join(_ a: Text?, _ b: Text) -> Text {
        guard let a else { return b }
        return Text("\(a)\(b)")
    }

    /// The site's name between narrow no-break spaces, with room at the start for its icon,
    /// so a pill never breaks across a line. Tapping anywhere on it opens the source.
    private static func pill(host: String, url: URL, icons: Bool) -> Text {
        let name = Site.name(host).replacingOccurrences(of: " ", with: "\u{00A0}")
        let open = icons ? "\u{202F}\u{2007}\u{2007}\u{202F}" : "\u{202F}\u{202F}"
        var s = AttributedString(open + name + "\u{202F}\u{202F}")
        s.link = url
        s[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = Font.footnote.weight(.medium)
        s[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.qInk2
        return Text(s).customAttribute(LinkPill(host: host))
    }
}

/// A paragraph with its citations as pills, drawn by `PillRenderer`. Redraws as icons arrive.
struct PilledText: View {
    let composed: LinkPills.Composed

    var body: some View {
        composed.text
            .textRenderer(PillRenderer(fill: Color.qInk.opacity(0.075), tint: Color.qInk2,
                                       icons: icons, showIcons: Favicons.shared.enabled))
    }

    /// The icons that have come so far. Reading them is what redraws the text as more arrive.
    private var icons: [String: Image] {
        var out: [String: Image] = [:]
        for host in composed.hosts {
            if let ui = Favicons.shared.icon(host) { out[host] = Image(uiImage: ui) }
        }
        return out
    }
}

// MARK: - Sources

/// Under a reply that cites the web: its sources' icons, stacked, and a word. Opens the list.
struct SourcesButton: View {
    let sources: [Source]
    @State private var open = false

    var body: some View {
        Button {
            Haptics.tap()
            open = true
        } label: {
            HStack(spacing: 8) {
                if Favicons.shared.enabled {
                    HStack(spacing: -5) {
                        ForEach(Array(sources.prefix(3).enumerated()), id: \.element.id) { i, s in
                            SiteIcon(host: s.host, size: 16)
                                .padding(1.5)
                                .background(Color.qBase, in: .rect(cornerRadius: 5.5, style: .continuous))
                                .zIndex(Double(3 - i))
                        }
                    }
                }
                Text("Sources")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.qInk)
                Text("\(sources.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.qInk2)
            }
            .padding(.leading, Favicons.shared.enabled ? 6 : 12)
            .padding(.trailing, 12)
            .frame(minHeight: 32)
            .background(Color.qInk.opacity(0.06), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Sources, \(sources.count)")
        .accessibilityHint("Lists the pages this reply drew on")
        .sheet(isPresented: $open) { SourcesSheet(sources: sources) }
    }
}

/// Every source a reply drew on: its icon and site, the page's title, and a little of what it
/// said. A row opens the page in Safari, inside Quire.
struct SourcesSheet: View {
    let sources: [Source]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { i, s in
                        if i > 0 {
                            Rectangle().fill(Color.qRule).frame(height: 1 / 3).padding(.leading, 50)
                        }
                        row(s)
                    }
                }
                .padding(.horizontal, 16)
                .card(radius: 22)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.qBase)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ s: Source) -> some View {
        Button {
            Haptics.tap()
            InAppBrowser.open(s.url)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                SiteIcon(host: s.host, size: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.host)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.qInk2)
                        .lineLimit(1)
                    Text(s.title ?? s.url.absoluteString)
                        .displayFont { .system(.subheadline, design: $0).weight(.semibold) }
                        .foregroundStyle(Color.qInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let snippet = s.snippet {
                        Text(snippet)
                            .font(.footnote)
                            .foregroundStyle(Color.qInk2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.qInk2)
                    .padding(.top, 3)
            }
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.row)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the page")
    }
}

// MARK: - Opening links

/// Opens web links in Safari inside Quire, over whatever is on screen, sheets included.
enum InAppBrowser {
    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let top = topController() else { return false }
        let config = SFSafariViewController.Configuration()
        config.barCollapsingEnabled = true
        let safari = SFSafariViewController(url: url, configuration: config)
        safari.dismissButtonStyle = .close
        top.present(safari, animated: true)
        return true
    }

    private static func topController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !($0 is ToastWindow) }
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

extension View {
    /// Links tapped in here open in Safari inside Quire; anything that isn't a web page goes to
    /// the system as before.
    func opensLinksInApp() -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard InAppBrowser.open(url) else { return .systemAction }
            Haptics.tap()
            return .handled
        })
    }
}
