import SwiftUI

/// Fargene fra designsystemet (DashDash18/DesignSystem/DDPalette.swift, `DDToken`), kopiert hit
/// så klokkemålet ikke trenger hele designsystemet. Klokka er alltid mørk, så det er de mørke
/// verdiene. Endres en farge der, endres den her (som WidgetPalette).
nonisolated enum WatchPalette {
    /// `DDToken.forest`, mørk.
    static let forest = color(0x123026)
    /// `DDToken.accentYellow` og `accentYellowInk`: lagre-knappen.
    static let yellow = color(0xF5C842)
    static let yellowInk = color(0x21292B)
    /// `DDToken.inkSecondary`, mørk.
    static let secondary = color(0xA3B5AB)
    /// `DDToken.youRow`, mørk: raden min.
    static let youRow = color(0xE4C767, alpha: 0.14)
    /// `DDToken.rustText`, mørk: hull som venter.
    static let rust = color(0xF08A4B)

    /// Scorefargen (`ScoreName.tone`, mørk): teksten under tallet.
    static func tone(_ name: String?) -> Color {
        switch name {
        case "eagle": color(0xF2E3A6)
        case "birdie": color(0xCFEAC4)
        case "par": color(0xD9DCD2)
        case "bogey": color(0xF6C9B5)
        case "dobbel": color(0xFBD3C2)
        case "blowup": color(0xC9CEC9)
        default: secondary
        }
    }

    private static func color(_ hex: UInt32, alpha: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255,
              green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255,
              opacity: alpha)
    }
}
