import SwiftUI
import UIKit

/// The PWA's palette (DECISIONS.md §3), as dynamic colours that follow light and dark mode.
extension Color {
    static let qBase = Color(light: 0xF6F6F3, dark: 0x0E1013)
    static let qRaised = Color(light: 0xFFFFFF, dark: 0x171A1F)
    static let qInk = Color(light: 0x1B1D21, dark: 0xE8E6E1)
    static let qInk2 = Color(light: 0x5F646C, dark: 0x8E9299)
    static let qRule = Color(light: 0xDCDCD6, dark: 0x262A31)
    static let qAccent = Color(light: 0x3450C8, dark: 0x9AA8FF)
    static let qOnAccent = Color(light: 0xFFFFFF, dark: 0x0E1013)
    static let qDanger = Color(light: 0xB3261E, dark: 0xF2B8B5)

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

extension ThemeChoice {
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    var label: String { rawValue.capitalized }
}

extension ReadingFace {
    var design: Font.Design { self == .serif ? .serif : .default }
    var label: String { self == .serif ? "Serif" : "Sans" }
}

/// Hairline card used for the user's own messages and for code blocks.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(Color.qRaised, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color.qRule, lineWidth: 1))
    }
}

extension View {
    func card(radius: CGFloat = 16) -> some View { modifier(CardBackground(radius: radius)) }
}
