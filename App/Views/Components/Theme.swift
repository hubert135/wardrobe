import OutfitEngine
import SwiftUI
import UIKit

/// Editorial design system: warm paper background, ink text, terracotta accent, serif headlines.
enum Theme {
    /// Terracotta accent (lighter in dark mode).
    static let accent = Color("AccentColor")
    /// Warm off-white page background.
    static let paper = Color("Paper")
    /// Card background.
    static let surface = Color("Surface")
    /// Primary text and primary buttons.
    static let ink = Color("Ink")
    /// Backdrop garments are shown on.
    static let canvas = Color("Canvas")
    static let hairline = Color.primary.opacity(0.08)

    static let cornerRadius: CGFloat = 24
    static let smallCornerRadius: CGFloat = 16
    static let spacing: CGFloat = 20
    static let pagePadding: CGFloat = 20

    /// Serif display font (New York), scales with Dynamic Type.
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Makes navigation bar titles serif across the app.
    static func applyNavigationAppearance() {
        func serifFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let descriptor = base.fontDescriptor
                .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
                .withDesign(.serif) ?? base.fontDescriptor
            return UIFont(descriptor: descriptor, size: base.pointSize)
        }
        let ink = UIColor(named: "Ink") ?? .label
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(named: "Paper")
        appearance.largeTitleTextAttributes = [.font: serifFont(.largeTitle, weight: .bold), .foregroundColor: ink]
        appearance.titleTextAttributes = [.font: serifFont(.headline, weight: .semibold), .foregroundColor: ink]
        let scrolled = UINavigationBarAppearance()
        scrolled.configureWithDefaultBackground()
        scrolled.largeTitleTextAttributes = appearance.largeTitleTextAttributes
        scrolled.titleTextAttributes = appearance.titleTextAttributes
        UINavigationBar.appearance().standardAppearance = scrolled
        UINavigationBar.appearance().compactAppearance = scrolled
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).stroke(Theme.hairline))
            .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    }
}

/// Small uppercase label above headlines ("THURSDAY, 9 OCTOBER", "LOOK 01").
struct EyebrowText: View {
    var text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

/// Serif page header used instead of a plain navigation title.
struct PageHeader: View {
    var eyebrow: String?
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { EyebrowText(eyebrow) }
            Text(title)
                .font(Theme.serif(.largeTitle, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Solid ink capsule: the main action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ink.opacity(isEnabled ? 1 : 0.35), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// Outlined capsule for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Capsule().stroke(Theme.ink.opacity(0.18), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Round icon button (favorite, swap).
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(width: 46, height: 46)
            .background(Circle().stroke(Theme.ink.opacity(0.15), lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Warm paper page background for scroll views, lists and forms.
    func paperBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.paper.ignoresSafeArea())
    }
}

extension Double {
    func currency(_ code: String) -> String {
        formatted(.currency(code: code).precision(.fractionLength(0...2)))
    }
}
