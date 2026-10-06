import CoreText
import SwiftUI
import UIKit

/// Skriftene (begge SIL Open Font License, se `Resources/Fonts/OFL-*.txt`).
/// 42dot Sans for overskrifter, brødtekst og tall (føringen fra konseptappen «golfee»),
/// Sometype Mono fra PWA-en bare for små etiketter i versaler.
nonisolated enum DDFontFamily: String, CaseIterable, Sendable {
    case sans   // 42dot Sans
    case mono   // Sometype Mono

    /// Fila i appbunten (variabel skrift, alle vekter i én fil).
    var fileName: String {
        switch self {
        case .sans: "42dotSans-Variable"
        case .mono: "SometypeMono-Variable"
        }
    }

    /// PostScript-navnet til den navngitte vekten i den variable fila.
    func postScriptName(_ weight: DDFontWeight) -> String {
        switch self {
        case .sans:
            switch weight {
            case .light: "42dotSans-Light"
            case .regular: "42dotSans-Light_Regular"
            case .medium: "42dotSans-Light_Medium"
            case .semibold: "42dotSans-Light_SemiBold"
            case .bold: "42dotSans-Light_Bold"
            }
        case .mono:
            switch weight {
            // Sometype Mono har ingen lett vekt; 400 er det letteste.
            case .light, .regular: "SometypeMono-Regular"
            case .medium: "SometypeMono-Regular_Medium"
            case .semibold: "SometypeMono-Regular_SemiBold"
            case .bold: "SometypeMono-Regular_Bold"
            }
        }
    }

    var systemDesign: Font.Design {
        switch self {
        case .sans: .default
        case .mono: .monospaced
        }
    }
}

nonisolated enum DDFontWeight: CaseIterable, Sendable {
    case light, regular, medium, semibold, bold

    var system: Font.Weight {
        switch self {
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }
}

/// Registrerer skriftene fra bunten ved oppstart, uten Info.plist (`UIAppFonts`).
nonisolated enum DDFonts {
    /// Familiene som er registrert og kan brukes. Registreringen skjer første gang denne leses.
    static let available: Set<DDFontFamily> = registerAll(in: .main)

    /// Kalles fra `DashDash18App.init` så skriftene er klare før første skjerm.
    static func register() {
        _ = available
    }

    /// Registrerer hver fil og svarer med familiene som faktisk finnes etterpå.
    /// Er en fil allerede registrert (feil `alreadyRegistered`), regnes den som klar.
    static func registerAll(in bundle: Bundle) -> Set<DDFontFamily> {
        var result = Set<DDFontFamily>()
        for family in DDFontFamily.allCases {
            if let url = bundle.url(forResource: family.fileName, withExtension: "ttf") {
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
                error?.release()
            }
            if UIFont(name: family.postScriptName(.regular), size: 12) != nil {
                result.insert(family)
            }
        }
        return result
    }
}

extension Font {
    /// Skrift fra designsystemet som skalerer med Dynamic Type (`relativeTo`).
    /// Mangler skriften, brukes systemskrift med samme vekt og design.
    nonisolated static func dd(_ family: DDFontFamily, size: CGFloat, weight: DDFontWeight = .regular,
                               relativeTo style: Font.TextStyle = .body) -> Font {
        if DDFonts.available.contains(family) {
            return .custom(family.postScriptName(weight), size: size, relativeTo: style)
        }
        return .system(style, design: family.systemDesign, weight: weight.system)
    }

    // Typografiskala. Store tall og navn i 42dot Sans (lett/medium), som i golfee;
    // størrelsene følger PWA-en på en 402 pt bred iPhone.

    /// Stor tittel på innlogging (lett 44).
    static let ddDisplay = dd(.sans, size: 44, weight: .light, relativeTo: .largeTitle)
    /// Overskrift på skjerm og ark (medium 24).
    static let ddTitle = dd(.sans, size: 24, weight: .medium, relativeTo: .title2)
    /// Kortoverskrift (medium 20), f.eks. «Ingen runde på gang» og datoen for kvelden.
    static let ddTitleSmall = dd(.sans, size: 20, weight: .medium, relativeTo: .title3)
    /// Spillernavn (regular 21 på hullkortet).
    static let ddName = dd(.sans, size: 21, weight: .regular, relativeTo: .title3)
    /// Navn i lister (medium 17).
    static let ddNameSmall = dd(.sans, size: 17, weight: .medium, relativeTo: .headline)
    /// Hullnummer og store plasstall (lett 64).
    static let ddHoleNumber = dd(.sans, size: 64, weight: .light, relativeTo: .largeTitle)
    /// Feiring (lett 54).
    static let ddCelebration = dd(.sans, size: 54, weight: .light, relativeTo: .largeTitle)

    /// Brødtekst (regular 16, «Body 16px» i golfee).
    static let ddBody = dd(.sans, size: 16, relativeTo: .body)
    /// Uthevet brødtekst og radtitler (medium 16).
    static let ddBodyEmphasis = dd(.sans, size: 16, weight: .medium, relativeTo: .body)
    /// Knappetekst (semibold 16).
    static let ddButton = dd(.sans, size: 16, weight: .semibold, relativeTo: .body)
    /// Stor knapp (semibold 17).
    static let ddButtonLarge = dd(.sans, size: 17, weight: .semibold, relativeTo: .headline)
    /// Sekundærtekst (14).
    static let ddCallout = dd(.sans, size: 14, relativeTo: .callout)
    /// Små linjer under en rad (13).
    static let ddCaption = dd(.sans, size: 13, relativeTo: .caption)
    /// Score-merke (semibold 13).
    static let ddChip = dd(.sans, size: 13, weight: .semibold, relativeTo: .footnote)

    /// Seksjonsetikett og «eyebrow» (mono 10, versaler med sporing).
    static let ddEyebrow = dd(.mono, size: 10, relativeTo: .caption2)
    /// Pille i versaler (mono 9.5).
    static let ddPill = dd(.mono, size: 9.5, relativeTo: .caption2)
    /// Små tall og linjer (sans 13, tabelltall).
    static let ddMonoSmall = dd(.sans, size: 13, relativeTo: .caption)
    /// Tall i rader (medium 17).
    static let ddNumber = dd(.sans, size: 17, weight: .medium, relativeTo: .body)
    /// Totalsum (medium 20).
    static let ddNumberLarge = dd(.sans, size: 20, weight: .medium, relativeTo: .title3)
    /// Slag på hullkortet (medium 32).
    static let ddStrokes = dd(.sans, size: 32, weight: .medium, relativeTo: .title)
    /// Stort tall i hero- og statistikk-kort (lett 52).
    static let ddHeroNumber = dd(.sans, size: 52, weight: .light, relativeTo: .largeTitle)
}

extension UIFont {
    /// Samme skrift for UIKit-flater (navigasjonslinja), skalert med Dynamic Type.
    nonisolated static func dd(_ family: DDFontFamily, size: CGFloat, weight: DDFontWeight = .regular,
                               relativeTo style: UIFont.TextStyle = .body) -> UIFont {
        let base = UIFont(name: family.postScriptName(weight), size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .regular)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}
