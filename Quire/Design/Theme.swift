import SwiftUI
import UIKit

// MARK: - Palette

/// The colours of the app, by theme. Every view reads them through `Color.qBase` and the rest,
/// which look the current theme up in `ThemeStore`; because that store is observable, changing the
/// theme re-colours exactly the views that use a colour, live, without rebuilding anything.
/// Each colour still follows light and dark mode on its own.
struct Palette {
    let base, raised, sunken: Color
    let ink, inkBody, inkStrong, ink2, rule: Color
    let accent, accentSoft, onAccent: Color
    let danger, warn: Color
    /// The theme's signature, dark to light, for its swatch.
    let swatch: [Color]
}

extension AppTheme {
    var palette: Palette {
        switch self {
        case .quire: Self.quirePalette
        case .velvet: Self.velvetPalette
        case .amethyst: Self.amethystPalette
        case .pitch: Self.pitchPalette
        }
    }

    var name: String {
        switch self {
        case .quire: "Quire"
        case .velvet: "Velvet"
        case .amethyst: "Amethyst"
        case .pitch: "Pitch"
        }
    }

    /// What it's made of, in a few words.
    var detail: String {
        switch self {
        case .quire: "Ink, paper and periwinkle"
        case .velvet: "Obsidian, velvet and almond"
        case .amethyst: "Noir, amethyst and steel"
        case .pitch: "True black and white"
        }
    }

    /// Quire is a reading object: near-neutral paper and ink, with one periwinkle accent used
    /// sparingly for the things that are alive (the cursor, the send button, the selection).
    private static let quirePalette = Palette(
        base: Color(light: 0xF6F6F3, dark: 0x0E1013), raised: Color(light: 0xFFFFFF, dark: 0x171A1F),
        sunken: Color(light: 0xEDEDE8, dark: 0x0A0B0E),
        ink: Color(light: 0x1B1D21, dark: 0xE8E6E1), inkBody: Color(light: 0x34373D, dark: 0xC9C6BF),
        inkStrong: Color(light: 0x07080A, dark: 0xFFFDF8), ink2: Color(light: 0x5F646C, dark: 0x8E9299),
        rule: Color(light: 0xDCDCD6, dark: 0x262A31),
        accent: Color(light: 0x3450C8, dark: 0x9AA8FF), accentSoft: Color(light: 0xE4E8FA, dark: 0x22273D),
        onAccent: Color(light: 0xFFFFFF, dark: 0x0E1013),
        danger: Color(light: 0xB3261E, dark: 0xF2B8B5), warn: Color(light: 0x8A5A00, dark: 0xE8C27A),
        swatch: [Color(hex: 0x0E1013), Color(hex: 0x3F55C9), Color(hex: 0xE9ECF8)])

    /// Obsidian ink, velvet curfew and almond hearth. In the dark, almond is the live colour on a
    /// velvet wash; in the light, velvet on almond paper.
    private static let velvetPalette = Palette(
        base: Color(light: 0xF7EEE5, dark: 0x151311), raised: Color(light: 0xFFFAF5, dark: 0x211A1B),
        sunken: Color(light: 0xEFE0D2, dark: 0x0E0C0B),
        ink: Color(light: 0x151311, dark: 0xF2E6DA), inkBody: Color(light: 0x3B302D, dark: 0xD8C8BA),
        inkStrong: Color(light: 0x0A0807, dark: 0xFFF5EA), ink2: Color(light: 0x7A6762, dark: 0x9E8B83),
        rule: Color(light: 0xE6D5C6, dark: 0x2F2627),
        accent: Color(light: 0x4B262F, dark: 0xEED3BA), accentSoft: Color(light: 0xEED3BA, dark: 0x4B262F),
        onAccent: Color(light: 0xF7EEE5, dark: 0x151311),
        danger: Color(light: 0xA3262E, dark: 0xF2B8B5), warn: Color(light: 0x8A5A00, dark: 0xE8C27A),
        swatch: [Color(hex: 0x151311), Color(hex: 0x4B262F), Color(hex: 0xEED3BA)])

    /// Nox noir, royal amethyst and steel mist. The amethyst is lifted in the dark so it reads as
    /// text as well as a fill.
    private static let amethystPalette = Palette(
        base: Color(light: 0xF4F4F6, dark: 0x141414), raised: Color(light: 0xFFFFFF, dark: 0x1E1D21),
        sunken: Color(light: 0xE7E6EB, dark: 0x0D0D0E),
        ink: Color(light: 0x141414, dark: 0xECEAF0), inkBody: Color(light: 0x2F2D35, dark: 0xCFCFCF),
        inkStrong: Color(light: 0x0A0A0A, dark: 0xFFFFFF), ink2: Color(light: 0x63606B, dark: 0x918D99),
        rule: Color(light: 0xDCDAE2, dark: 0x2B2930),
        accent: Color(light: 0x7E49B3, dark: 0xA275D8), accentSoft: Color(light: 0xEEE5F8, dark: 0x2D2140),
        onAccent: Color(light: 0xFFFFFF, dark: 0x141414),
        danger: Color(light: 0xB3261E, dark: 0xF2B8B5), warn: Color(light: 0x8A5A00, dark: 0xE8C27A),
        swatch: [Color(hex: 0x141414), Color(hex: 0x7E49B3), Color(hex: 0xCFCFCF)])

    /// Black and white and nothing else: true black in the dark, for OLED screens, where unlit
    /// pixels are off. The accent is the ink itself.
    private static let pitchPalette = Palette(
        base: Color(light: 0xFFFFFF, dark: 0x000000), raised: Color(light: 0xF7F7F7, dark: 0x0F0F0F),
        sunken: Color(light: 0xEFEFEF, dark: 0x161616),
        ink: Color(light: 0x000000, dark: 0xFFFFFF), inkBody: Color(light: 0x1C1C1C, dark: 0xE8E8E8),
        inkStrong: Color(light: 0x000000, dark: 0xFFFFFF), ink2: Color(light: 0x6B6B6B, dark: 0x8F8F8F),
        rule: Color(light: 0xE3E3E3, dark: 0x222222),
        accent: Color(light: 0x000000, dark: 0xFFFFFF), accentSoft: Color(light: 0xEBEBEB, dark: 0x262626),
        onAccent: Color(light: 0xFFFFFF, dark: 0x000000),
        danger: Color(light: 0xC4241D, dark: 0xFF6B60), warn: Color(light: 0x8A5A00, dark: 0xE8C27A),
        swatch: [Color(hex: 0x000000), Color(hex: 0x474747), Color(hex: 0xFFFFFF)])
}

/// The theme in use. Set from settings at launch and whenever it changes.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    private(set) var theme: AppTheme = .quire

    func use(_ theme: AppTheme) {
        if theme != self.theme { self.theme = theme }
    }

    var palette: Palette { theme.palette }
}

extension Color {
    static var qBase: Color { ThemeStore.shared.palette.base }
    static var qRaised: Color { ThemeStore.shared.palette.raised }
    static var qSunken: Color { ThemeStore.shared.palette.sunken }
    static var qInk: Color { ThemeStore.shared.palette.ink }
    /// Running text in a reply: a step softer than `qInk`, so bold (in `qInkStrong`) stands out by
    /// colour as well as weight. In dark mode especially, weight alone barely shows.
    static var qInkBody: Color { ThemeStore.shared.palette.inkBody }
    static var qInkStrong: Color { ThemeStore.shared.palette.inkStrong }
    static var qInk2: Color { ThemeStore.shared.palette.ink2 }
    static var qRule: Color { ThemeStore.shared.palette.rule }
    static var qAccent: Color { ThemeStore.shared.palette.accent }
    static var qAccentSoft: Color { ThemeStore.shared.palette.accentSoft }
    static var qOnAccent: Color { ThemeStore.shared.palette.onAccent }
    static var qDanger: Color { ThemeStore.shared.palette.danger }
    static var qWarn: Color { ThemeStore.shared.palette.warn }

    // Code highlighting
    static let qCodeKeyword = Color(light: 0x3450C8, dark: 0x9AA8FF)
    static let qCodeString = Color(light: 0x8A5A1C, dark: 0xD9BC8C)
    static let qCodeNumber = Color(light: 0x2B7A6E, dark: 0x7FC6B8)
    static let qCodeComment = Color(light: 0x7A7F87, dark: 0x6E737B)

    // Settings tiles: muted, distinct, never louder than the accent.
    static let qTileBlue = Color(light: 0x3450C8, dark: 0x5B6CC9)
    static let qTileTeal = Color(light: 0x2B7A6E, dark: 0x3C8F82)
    static let qTileViolet = Color(light: 0x6B4FB8, dark: 0x7D66C4)
    static let qTileAmber = Color(light: 0xA86A12, dark: 0xB07A2A)
    static let qTileSlate = Color(light: 0x5F646C, dark: 0x5C616A)
    static let qTileRose = Color(light: 0xA8455E, dark: 0xB15A70)

    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Type

extension ThemeChoice {
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Auto"
        }
    }
}

extension Typeface {
    /// For titles, names, headings and the big figures.
    var design: Font.Design {
        switch self {
        case .newYork: .serif
        case .sfPro: .default
        case .sfRounded: .rounded
        }
    }

    var systemDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .newYork: .serif
        case .sfPro: .default
        case .sfRounded: .rounded
        }
    }

    /// Everything else (buttons, rows, the message box) is SF Pro, except that Rounded carries
    /// through the whole app: a rounded title over square-ended text looks like a mistake.
    var interfaceDesign: Font.Design? { self == .sfRounded ? .rounded : nil }

    var name: String {
        switch self {
        case .newYork: "New York"
        case .sfPro: "SF Pro"
        case .sfRounded: "SF Pro Rounded"
        }
    }

    var shortName: String { self == .sfRounded ? "Rounded" : name }

    /// The face replies use when they aren't in New York.
    var sansName: String { self == .sfRounded ? "SF Pro Rounded" : "SF Pro" }

    /// One word for its character, on its card.
    var character: String {
        switch self {
        case .newYork: "Bookish"
        case .sfPro: "Crisp"
        case .sfRounded: "Friendly"
        }
    }

    var blurb: String {
        switch self {
        case .newYork: "Apple's serif, cut for reading on screen. Titles read like a book's, and replies like its pages."
        case .sfPro: "The face iOS itself is set in: crisp, neutral and quietly precise, from titles to replies."
        case .sfRounded: "SF Pro with its ends softened, all through the app. Warmer, and still just as easy to read."
        }
    }
}

extension UISettings {
    /// Replies in New York, or in the typeface's own sans.
    var replyDesign: Font.Design {
        readingFace == .serif ? .serif : (typeface == .sfRounded ? .rounded : .default)
    }

    var replyFaceName: String { readingFace == .serif ? "New York" : typeface.sansName }
}

nonisolated private struct DisplayDesignKey: EnvironmentKey {
    static let defaultValue: Font.Design = .serif
}

extension EnvironmentValues {
    /// The design titles, names and headings are set in. Read through `displayFont`.
    nonisolated var displayDesign: Font.Design {
        get { self[DisplayDesignKey.self] }
        set { self[DisplayDesignKey.self] = newValue }
    }
}

/// Sets a title, name, heading or big figure in the chosen typeface; everything else stays in the
/// interface face. `font` builds the font for a design: `.displayFont { .system(.title3, design: $0) }`.
private struct DisplayFont: ViewModifier {
    let font: (Font.Design) -> Font
    @Environment(\.displayDesign) private var design

    func body(content: Content) -> some View {
        content.font(font(design))
    }
}

extension View {
    func displayFont(_ font: @escaping (Font.Design) -> Font) -> some View {
        modifier(DisplayFont(font: font))
    }
}

/// The reply text size control: steps relative to the system's Dynamic Type size, stored in the
/// PWA's `fontScale` field so backups round-trip.
nonisolated enum ReadingSize: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case smaller = -1, standard = 0, larger = 1, large = 2, largest = 3
    var id: Int { rawValue }

    init(scale: Double) {
        if scale < 0.95 { self = .smaller }
        else if scale < 1.07 { self = .standard }
        else if scale < 1.22 { self = .larger }
        else if scale < 1.35 { self = .large }
        else { self = .largest }
    }

    var scale: Double {
        switch self {
        case .smaller: 0.9
        case .standard: 1
        case .larger: 1.15
        case .large: 1.3
        case .largest: 1.4
        }
    }

    var label: String {
        switch self {
        case .smaller: "Smaller"
        case .standard: "Standard"
        case .larger: "Larger"
        case .large: "Large"
        case .largest: "Largest"
        }
    }

    func apply(to base: DynamicTypeSize) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let i = all.firstIndex(of: base) else { return base }
        let j = min(max(0, i + rawValue), all.count - 1)
        return all[j]
    }
}

/// Navigation bar titles in the chosen typeface, so every screen reads as part of the same book.
/// Changing it restyles the bars already on screen too, so the switch shows at once.
enum NavigationTypography {
    static func apply(_ typeface: Typeface = .newYork) {
        let large = font(.largeTitle, weight: .bold, design: typeface.systemDesign)
        let inline = font(.headline, weight: .semibold, design: typeface.systemDesign)
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: large]
        appearance.titleTextAttributes = [.font: inline]
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                restyle(window, large: large, inline: inline)
            }
        }
    }

    private static func restyle(_ view: UIView, large: UIFont, inline: UIFont) {
        if let bar = view as? UINavigationBar {
            bar.largeTitleTextAttributes = (bar.largeTitleTextAttributes ?? [:]).merging([.font: large]) { $1 }
            bar.titleTextAttributes = (bar.titleTextAttributes ?? [:]).merging([.font: inline]) { $1 }
        }
        for sub in view.subviews { restyle(sub, large: large, inline: inline) }
    }

    private static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight, design: UIFontDescriptor.SystemDesign) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let shaped = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        let weighted = shaped.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: weighted, size: base.pointSize))
    }
}

// MARK: - Motion

/// Motion tokens. Everything in the app animates with one of these, and every one of them collapses
/// to a plain crossfade (or nothing) when Reduce Motion is on.
enum Motion {
    static let press = Animation.snappy(duration: 0.16)
    static let quick = Animation.smooth(duration: 0.2)
    static let standard = Animation.smooth(duration: 0.3)
    static let bouncy = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let sheet = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Full-screen layers sliding across, like a navigation push. No bounce, so it reads as a
    /// screen moving rather than a toy; leaving is a touch quicker than arriving.
    static let drawerIn = Animation.smooth(duration: 0.38)
    static let drawerOut = Animation.smooth(duration: 0.3)
    /// First arrival of a screen's content (the empty chat). Rare, so it can take its time.
    static let entrance = Animation.smooth(duration: 0.55)
}

extension View {
    /// `withAnimation`-style modifier that respects Reduce Motion.
    func motion<V: Equatable>(_ animation: Animation, value: V, reduce: Bool) -> some View {
        self.animation(reduce ? .easeInOut(duration: 0.15) : animation, value: value)
    }
}

// MARK: - Surfaces

/// Hairline card used for the user's own messages, code and tables.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 16
    var fill: Color = .qRaised
    func body(content: Content) -> some View {
        content
            .background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.qRule, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = 16, fill: Color = .qRaised) -> some View { modifier(CardBackground(radius: radius, fill: fill)) }
}

/// Press feedback for custom tappable surfaces: a quick scale and dim on touch-down, like a native control.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
