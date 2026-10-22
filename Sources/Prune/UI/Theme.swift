import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Identidade do Prune: uma folha escura sobre marfim, como o ícone. Monocromática (tinta e marfim),
/// com um só acento natural, o verde-salva da folha, para estados e controlos do sistema.
/// Cores adaptativas (modo claro e escuro) e uma só família tipográfica, com a largura como variável.
enum Theme {
    static let background = adaptive(light: 0xF5F4EE, dark: 0x1C1C19)
    static let panel = adaptive(light: 0xFBFAF6, dark: 0x252521)
    static let stone = adaptive(light: 0xE8E6DC, dark: 0x2D2D28)
    /// Tinta no modo claro, marfim no escuro: ações principais, anéis, seleção.
    static let accent = adaptive(light: 0x1F1F1C, dark: 0xF5F4EE)
    /// Texto sobre `accent`.
    static let onAccent = adaptive(light: 0xF5F4EE, dark: 0x1F1F1C)
    static let leaf = adaptive(light: 0x5E7A4F, dark: 0x9DBB88)
    static let amber = adaptive(light: 0xA86A14, dark: 0xD9A04A)
    static let hairline = Color.primary.opacity(0.08)
    static let inset = Color.primary.opacity(0.045)
    static let selection = Color.primary.opacity(0.09)

    /// Títulos e números: SF Pro Expanded.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}
