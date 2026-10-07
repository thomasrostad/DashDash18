import SwiftUI
import UIKit

/// Fargene fra designsystemet (DashDash18/DesignSystem/DDPalette.swift, `DDToken`), kopiert hit
/// så extension-targetet ikke trenger hele designsystemet. Endres en farge der, endres den her.
nonisolated enum WidgetPalette {
    /// --sun-pale / mørk: `DDToken.background`.
    static let background = dynamic(light: 0xFFF9DF, dark: 0x0C1F18)
    /// `DDToken.card`.
    static let card = dynamic(light: 0xFFFFFF, dark: 0x132B23)
    /// --forest: `DDToken.forest`.
    static let forest = dynamic(light: 0x1C483A, dark: 0x123026)
    /// `DDToken.forestInk`: grønt som tekst.
    static let forestInk = dynamic(light: 0x1C483A, dark: 0xCFE3D6)
    /// `DDToken.ink`.
    static let ink = dynamic(light: 0x21292B, dark: 0xE8EFE7)
    /// `DDToken.inkSecondary`.
    static let inkSecondary = dynamic(light: 0x727065, dark: 0x8FA398)
    /// `DDToken.onDark`: tekst på grønn flate.
    static let onDark = fixed(0xFFF9DF)
    /// `DDToken.onDark` dempet, for sekundærtekst på grønn flate.
    static let onDarkSecondary = fixed(0xFFF9DF, alpha: 0.72)
    /// `DDToken.gold`.
    static let gold = fixed(0xE4C767)
    /// `DDToken.accentYellow` og `accentYellowInk`.
    static let yellow = fixed(0xF5C842)
    static let yellowInk = fixed(0x1E1A05)
    /// `DDToken.yellowText`: gul som tekst (mørk oker i lys modus).
    static let yellowText = dynamic(light: 0x7A5C00, dark: 0xF5C842)
    /// `DDToken.accentLime`: «opp» i matchen på mørk flate.
    static let lime = fixed(0x6BE07A)
    /// `DDToken.statRust`: «ned» i matchen på mørk flate.
    static let rustOnDark = fixed(0xE4762F)
    /// `DDToken.rustText`: rust som tekst på lys flate.
    static let rustText = dynamic(light: 0xA84A10, dark: 0xE4762F)
    /// `DDToken.limeInk`: «opp» som tekst på lys flate.
    static let limeInk = dynamic(light: 0x21451F, dark: 0xD9EBD0)
    /// `DDToken.youRow`: raden min.
    static let youRow = fixed(0xE4C767, alpha: 0.13)
    /// `DDToken.hairline`.
    static let hairline = dynamic(light: 0xD5D5D5, dark: 0x24443A)

    private static func uiColor(_ hex: UInt32, alpha: Double = 1) -> UIColor {
        UIColor(red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255,
                alpha: alpha)
    }

    private static func fixed(_ hex: UInt32, alpha: Double = 1) -> Color {
        Color(uiColor: uiColor(hex, alpha: alpha))
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        let lightColor = uiColor(light), darkColor = uiColor(dark)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkColor : lightColor })
    }
}

/// Små tekstbiter som både widgetene og Live Activity bruker.
nonisolated enum WidgetText {
    static var osloCalendar: Calendar { WidgetSnapshot.osloCalendar }

    /// Hele dager fra `now` til `date`, i Oslo (som `EveningDates.daysBetween`).
    static func days(from now: Date, to date: Date) -> Int {
        let a = osloCalendar.startOfDay(for: now), b = osloCalendar.startOfDay(for: date)
        return osloCalendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// «I dag», «I morgen», «Om 5 dager» (som `EveningDates.countdownText`).
    static func countdown(days: Int) -> String {
        switch days {
        case ...0: "I dag"
        case 1: "I morgen"
        default: "Om \(days) dager"
        }
    }

    /// «1.», «2.», «3.».
    static func place(_ n: Int) -> String { "\(n)." }
}
