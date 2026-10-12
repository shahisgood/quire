import SwiftUI
import UIKit

// MARK: - Palette

/// The PWA's palette (DECISIONS.md §3), as dynamic colours that follow light and dark mode.
/// Quire is a reading object: near-neutral paper and ink, with one periwinkle accent used sparingly
/// for the things that are alive (the cursor, the send button, the current selection).
extension Color {
    static let qBase = Color(light: 0xF6F6F3, dark: 0x0E1013)
    static let qRaised = Color(light: 0xFFFFFF, dark: 0x171A1F)
    static let qSunken = Color(light: 0xEDEDE8, dark: 0x0A0B0E)
    static let qInk = Color(light: 0x1B1D21, dark: 0xE8E6E1)
    static let qInk2 = Color(light: 0x5F646C, dark: 0x8E9299)
    static let qRule = Color(light: 0xDCDCD6, dark: 0x262A31)
    static let qAccent = Color(light: 0x3450C8, dark: 0x9AA8FF)
    static let qAccentSoft = Color(light: 0xE4E8FA, dark: 0x22273D)
    static let qOnAccent = Color(light: 0xFFFFFF, dark: 0x0E1013)
    static let qDanger = Color(light: 0xB3261E, dark: 0xF2B8B5)
    static let qWarn = Color(light: 0x8A5A00, dark: 0xE8C27A)

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

extension ReadingFace {
    var design: Font.Design { self == .serif ? .serif : .default }
    var label: String { self == .serif ? "Serif" : "Sans" }
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

/// Large titles in New York, the system serif, so every screen reads as part of the same book.
enum NavigationTypography {
    static func apply() {
        let appearance = UINavigationBar.appearance()
        if let large = serifFont(.largeTitle, weight: .bold) {
            appearance.largeTitleTextAttributes = [.font: large]
        }
        if let inline = serifFont(.headline, weight: .semibold) {
            appearance.titleTextAttributes = [.font: inline]
        }
    }

    private static func serifFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont? {
        let base = UIFont.preferredFont(forTextStyle: style)
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return nil }
        let weighted = serif.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
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
