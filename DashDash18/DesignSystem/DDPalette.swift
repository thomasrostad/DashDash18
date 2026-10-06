import Foundation

/// En farge som tall (0–1), uten SwiftUI, så den kan testes og regnes kontrast på.
nonisolated struct DDRGBA: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    /// `0xRRGGBB`, med valgfri gjennomsiktighet (som `rgba(…, .16)` i style.css).
    init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Fargen lagt over en ugjennomsiktig bakgrunn.
    func composited(over background: DDRGBA) -> DDRGBA {
        DDRGBA(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha)
        )
    }

    /// Relativ luminans etter WCAG 2.x.
    var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

/// Kontrastforhold etter WCAG (1–21). Tekst skal ha minst 4,5:1.
nonisolated enum DDContrast {
    static func ratio(_ foreground: DDRGBA, on background: DDRGBA) -> Double {
        let fg = foreground.composited(over: background).relativeLuminance
        let bg = background.relativeLuminance
        return (max(fg, bg) + 0.05) / (min(fg, bg) + 0.05)
    }
}

/// Fargetokens fra PWA-ens style.css (`:root` og mørk modus, handoff 1k).
/// Én kilde: `Color.dd…` bygges herfra, og testene regner kontrast herfra.
nonisolated enum DDToken: String, CaseIterable, Sendable {
    // Flater
    case background          // --sun-pale
    case card                // --white
    case heroCard            // .gg-green (forest i lys, --card-raised i mørk)
    case earth               // --earth
    case earthDeep           // --earth-deep
    case forest              // --forest (header, flater)
    case forestDeep          // --forest-deep (feiring)
    case tabBar              // tabbar (#0F241D i mørk)
    case driveBox            // .gg-drivebox
    case youRow              // .gg-hullrad.deg
    // Tekst og strek
    case forestInk           // --forest-ink: grønt som tekst og strek
    case ink                 // --ink
    case inkSecondary        // --gray-600
    case onDark              // --ondark: tekst på grønn flate
    case hairline            // --gray-300
    case rule                // --rule
    case ruleCream           // --rule-cream
    case cardBorder          // --hair-card
    // Aksent
    case rust                // --rust: prikker, strek, stiplet boks, aktiv fane
    case rustText            // rust som tekst (mørkere enn --rust i lys modus, se under)
    case rustDark            // --rust-dark: tekst på earth/blush
    case gold                // --gold
    case goldInk             // --gold-ink
    // Status
    case limeBackground, limeInk
    case sunBackground, sunInk
    case blushBackground, blushDeep
    /// Tekst på blush (bogey og verre). I mørk modus lysere enn --rust-dark: #F0B48F ga 4,2:1 på Dobbel.
    case blushInk
    // Knapper (handoff «knappelogikken», 01.10.2026)
    case buttonPrimary, buttonPrimaryText, buttonPrimaryPressed
    case buttonMoney, buttonMoneyText, buttonMoneyPressed
    case buttonLine
    case buttonDanger, buttonDangerText, buttonDangerPressed
    case buttonGold, buttonGoldText, buttonGoldPressed
    case buttonDisabled, buttonDisabledText
    case buttonOK, buttonOKText
    case focus

    /// Lys og mørk variant.
    var values: (light: DDRGBA, dark: DDRGBA) {
        switch self {
        case .background: (DDRGBA(0xFFF9DF), DDRGBA(0x0C1F18))
        case .card: (DDRGBA(0xFFFFFF), DDRGBA(0x132B23))
        case .heroCard: (DDRGBA(0x1C483A), DDRGBA(0x16332A))
        case .earth: (DDRGBA(0xF3E9DD), DDRGBA(0xF3E9DD, alpha: 0.08))
        case .earthDeep: (DDRGBA(0xEADBCA), DDRGBA(0xF3E9DD, alpha: 0.16))
        case .forest: (DDRGBA(0x1C483A), DDRGBA(0x123026))
        case .forestDeep: (DDRGBA(0x123026), DDRGBA(0x0B1F18))
        case .tabBar: (DDRGBA(0xFFF9DF), DDRGBA(0x0F241D))
        case .driveBox: (DDRGBA(0xFBF5DF), DDRGBA(0xE4C767, alpha: 0.08))
        case .youRow: (DDRGBA(0xE4C767, alpha: 0.13), DDRGBA(0xE4C767, alpha: 0.13))
        case .forestInk: (DDRGBA(0x1C483A), DDRGBA(0xCFE3D6))
        case .ink: (DDRGBA(0x21292B), DDRGBA(0xE8EFE7))
        case .inkSecondary: (DDRGBA(0x727065), DDRGBA(0x8FA398))
        case .onDark: (DDRGBA(0xFFF9DF), DDRGBA(0xFFF9DF))
        case .hairline: (DDRGBA(0xD5D5D5), DDRGBA(0x24443A))
        case .rule: (DDRGBA(0xF0EADB), DDRGBA(0x1F3B31))
        case .ruleCream: (DDRGBA(0xE4DBBB), DDRGBA(0x24443A))
        case .cardBorder: (DDRGBA(0x1C483A, alpha: 0.07), DDRGBA(0x24443A))
        case .rust: (DDRGBA(0xBF5412), DDRGBA(0xE4762F))
        // #BF5412 gir 4,46:1 på krem, under kravet på 4,5:1. Som tekst bruker vi
        // --knapp-penger (#A84A10), som gir 5,5:1 på krem og 5,9:1 på hvitt.
        case .rustText: (DDRGBA(0xA84A10), DDRGBA(0xE4762F))
        case .rustDark: (DDRGBA(0x612807), DDRGBA(0xF0B48F))
        case .gold: (DDRGBA(0xE4C767), DDRGBA(0xE4C767))
        case .goldInk: (DDRGBA(0x4B3A0B), DDRGBA(0x4B3A0B))
        case .limeBackground: (DDRGBA(0xD9EBD0), DDRGBA(0xD9EBD0, alpha: 0.16))
        case .limeInk: (DDRGBA(0x21451F), DDRGBA(0xD9EBD0))
        case .sunBackground: (DDRGBA(0xEFE3B0), DDRGBA(0xEFE3B0, alpha: 0.16))
        case .sunInk: (DDRGBA(0x4B4A35), DDRGBA(0xEFE3B0))
        case .blushBackground: (DDRGBA(0xFCE5DB), DDRGBA(0xFCE5DB, alpha: 0.14))
        case .blushDeep: (DDRGBA(0xF7D4C6), DDRGBA(0xFCE5DB, alpha: 0.24))
        case .blushInk: (DDRGBA(0x612807), DDRGBA(0xFCE5DB))
        case .buttonPrimary: (DDRGBA(0x1C483A), DDRGBA(0xD9EBD0))
        case .buttonPrimaryText: (DDRGBA(0xFFF9DF), DDRGBA(0x10231D))
        case .buttonPrimaryPressed: (DDRGBA(0x123528), DDRGBA(0xBAD3B0))
        case .buttonMoney: (DDRGBA(0xA84A10), DDRGBA(0xB4501A))
        case .buttonMoneyText: (DDRGBA(0xFFF9DF), DDRGBA(0xFFF9DF))
        case .buttonMoneyPressed: (DDRGBA(0x8E3E0D), DDRGBA(0x9A4416))
        case .buttonLine: (DDRGBA(0x1C483A), DDRGBA(0xD9EBD0))
        case .buttonDanger: (DDRGBA(0xFCE5DB), DDRGBA(0x3A2219))
        case .buttonDangerText: (DDRGBA(0x612807), DDRGBA(0xF2B39A))
        case .buttonDangerPressed: (DDRGBA(0xF7D4C6), DDRGBA(0x4A2B1F))
        case .buttonGold: (DDRGBA(0xE2C76A), DDRGBA(0xE2C76A))
        case .buttonGoldText: (DDRGBA(0x2E2A12), DDRGBA(0x2E2A12))
        case .buttonGoldPressed: (DDRGBA(0xD3B455), DDRGBA(0xD3B455))
        case .buttonDisabled: (DDRGBA(0xECE5CF), DDRGBA(0x1E3530))
        case .buttonDisabledText: (DDRGBA(0x8A8470), DDRGBA(0x7E8F86))
        case .buttonOK: (DDRGBA(0xD9EBD0), DDRGBA(0x2C4A3A))
        case .buttonOKText: (DDRGBA(0x21451F), DDRGBA(0xCFE6C3))
        case .focus: (DDRGBA(0x0014EB), DDRGBA(0x9DB0FF))
        }
    }
}

/// Tekst-/bakgrunnspar som brukes i appen og skal holde 4,5:1 i begge moduser.
nonisolated enum DDContrastPairs {
    struct Pair: Sendable {
        let name: String
        let foreground: DDToken
        let background: DDToken
        /// Ligger bakgrunnen selv oppå en annen flate (gjennomsiktig i mørk modus)?
        let base: DDToken?
    }

    static let text: [Pair] = [
        Pair(name: "Brødtekst på bakgrunn", foreground: .ink, background: .background, base: nil),
        Pair(name: "Brødtekst på kort", foreground: .ink, background: .card, base: nil),
        Pair(name: "Sekundær på bakgrunn", foreground: .inkSecondary, background: .background, base: nil),
        Pair(name: "Sekundær på kort", foreground: .inkSecondary, background: .card, base: nil),
        Pair(name: "Grønn tekst på bakgrunn", foreground: .forestInk, background: .background, base: nil),
        Pair(name: "Grønn tekst på kort", foreground: .forestInk, background: .card, base: nil),
        Pair(name: "Rust-tekst på bakgrunn", foreground: .rustText, background: .background, base: nil),
        Pair(name: "Rust-tekst på kort", foreground: .rustText, background: .card, base: nil),
        Pair(name: "Krem på grønn flate", foreground: .onDark, background: .forest, base: nil),
        Pair(name: "Krem på hero-kort", foreground: .onDark, background: .heroCard, base: nil),
        Pair(name: "Info-stripe", foreground: .rustDark, background: .earth, base: .background),
        Pair(name: "Birdie", foreground: .limeInk, background: .limeBackground, base: .card),
        Pair(name: "Eagle", foreground: .sunInk, background: .sunBackground, base: .card),
        Pair(name: "Par", foreground: .rustDark, background: .earth, base: .card),
        Pair(name: "Bogey", foreground: .blushInk, background: .blushBackground, base: .card),
        Pair(name: "Dobbel", foreground: .blushInk, background: .blushDeep, base: .card),
        Pair(name: "Gull-merke", foreground: .goldInk, background: .gold, base: nil),
        Pair(name: "Primærknapp", foreground: .buttonPrimaryText, background: .buttonPrimary, base: nil),
        Pair(name: "Pengeknapp", foreground: .buttonMoneyText, background: .buttonMoney, base: nil),
        Pair(name: "Sekundærknapp", foreground: .buttonLine, background: .card, base: nil),
        Pair(name: "Fareknapp", foreground: .buttonDangerText, background: .buttonDanger, base: nil),
        Pair(name: "Gullknapp", foreground: .buttonGoldText, background: .buttonGold, base: nil),
        Pair(name: "Ferdig-knapp", foreground: .buttonOKText, background: .buttonOK, base: nil),
    ]

    /// Kontrast for paret i lys (`dark == false`) eller mørk modus.
    static func ratio(_ pair: Pair, dark: Bool) -> Double {
        func value(_ token: DDToken) -> DDRGBA { dark ? token.values.dark : token.values.light }
        var background = value(pair.background)
        if let base = pair.base {
            background = background.composited(over: value(base))
        }
        return DDContrast.ratio(value(pair.foreground), on: background)
    }
}
