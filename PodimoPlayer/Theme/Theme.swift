import SwiftUI

extension Color {
    static let podimoInk = Color(light: 0x1B1230, dark: 0xF3EFFF)
    static let podimoPurple = Color(light: 0x6C4DF6, dark: 0x9C86FF)
    static let podimoDeep = Color(light: 0x2E1F73, dark: 0x2E1F73)
    static let podimoCoral = Color(light: 0xFF6B5B, dark: 0xFF8A7B)
    static let podimoMint = Color(light: 0x1FC8A9, dark: 0x3FE0C0)
    static let podimoBackground = Color(light: 0xF6F3FF, dark: 0x0F0B1E)
    static let podimoCard = Color(light: 0xFFFFFF, dark: 0x1A1430)

    init(light: UInt32, dark: UInt32) {
        self = Color(uiColor: UIColor(light: UIColor(rgb: light), dark: UIColor(rgb: dark)))
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255
        let g = CGFloat((rgb >> 8) & 0xFF) / 255
        let b = CGFloat(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    convenience init(light: UIColor, dark: UIColor) {
        self.init { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
    }
}

extension LinearGradient {
    static let podimoBrand = LinearGradient(colors: [.podimoPurple, .podimoDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
}
