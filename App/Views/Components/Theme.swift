import OutfitEngine
import SwiftUI
import UIKit

enum Theme {
    /// Deep navy accent (lighter in dark mode), defined in the asset catalog.
    static let accent = Color("AccentColor")
    /// Light neutral background garments are shown on.
    static let canvas = Color("Canvas")
    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 16
    static let spacing: CGFloat = 16
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    func darker(by amount: CGFloat = 0.2) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return UIColor(hue: hue, saturation: saturation, brightness: max(brightness - amount, 0), alpha: alpha)
    }
}

extension Color {
    /// Swatch color for a palette name.
    static func garment(_ name: String) -> Color {
        Color(uiColor: UIColor(hex: ColorPalette.color(named: name)?.hex ?? "#8E8E93"))
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

extension Double {
    func currency(_ code: String) -> String {
        formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }
}
