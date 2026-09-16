import SwiftUI
import UIKit

/// Central palette for the redesign: a cool neutral base with a single blue
/// accent, plus semantic green/red. All colors adapt to light and dark mode.
enum Palette {
    static let background = dynamic(light: 0xF1F2F4, dark: 0x0E0F12)
    static let card       = dynamic(light: 0xFFFFFF, dark: 0x191B1F)
    static let cardBorder = dynamic(light: 0xE9EBEF, dark: 0x2A2D33)
    static let ink        = dynamic(light: 0x1B1D21, dark: 0xF2F3F5)
    static let muted      = dynamic(light: 0x868C95, dark: 0x9298A2)
    static let accent     = dynamic(light: 0x2C5FE0, dark: 0x5B84F0)
    static let hero       = dynamic(light: 0x20242C, dark: 0x24272F)
    static let positive   = dynamic(light: 0x1F9D57, dark: 0x35C97A)
    static let negative   = dynamic(light: 0xDC5A4B, dark: 0xF07567)
    static let hairline   = dynamic(light: 0xEEF0F3, dark: 0x24272D)

    /// Muted avatar hues, indexed by `Person.colorIndex` (wraps for big groups).
    static let avatars: [Color] = [
        Color(rgb: 0x3B6FE0), // blue
        Color(rgb: 0x667085), // slate
        Color(rgb: 0x2E9C8E), // teal
        Color(rgb: 0x7A6FE0), // violet
        Color(rgb: 0xC96A8E), // rose
        Color(rgb: 0x5A6AD0), // indigo
        Color(rgb: 0x6E8B5B), // olive
        Color(rgb: 0x8A7A66), // taupe
    ]

    static func avatar(_ colorIndex: Int) -> Color {
        avatars[((colorIndex % avatars.count) + avatars.count) % avatars.count]
    }

    private static func dynamic(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension Color {
    init(rgb: UInt) {
        self.init(uiColor: UIColor(rgb: rgb))
    }
}

extension UIColor {
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Reusable pieces

/// Round initials avatar in the person's muted color.
struct Avatar: View {
    let name: String
    let colorIndex: Int
    var size: CGFloat = 38
    var ringColor: Color? = nil

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let joined = parts.map { String($0.prefix(1)).uppercased() }.joined()
        return joined.isEmpty ? "?" : joined
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.36, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.avatar(colorIndex), in: Circle())
            .overlay(
                Circle().strokeBorder(ringColor ?? .clear, lineWidth: ringColor == nil ? 0 : 2)
            )
    }
}

/// Soft card container matching the mockups.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var radius: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.cardBorder, lineWidth: 1)
            )
    }
}

/// Full-width solid accent button used for the primary action on each screen.
struct PrimaryButtonLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Palette.accent)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    /// Hides a List/ScrollView's default chrome and paints the app background.
    func appBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
    }
}
