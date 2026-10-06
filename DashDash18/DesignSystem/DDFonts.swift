import CoreText
import SwiftUI
import UIKit

/// De tre skriftene fra PWA-en (alle SIL Open Font License, se `Resources/Fonts/OFL-*.txt`).
/// Regel: serif for navn og drama, mono for tall og etiketter, grotesk for resten.
nonisolated enum DDFontFamily: String, CaseIterable, Sendable {
    case grotesk   // Hanken Grotesk
    case serif     // Source Serif 4
    case mono      // Sometype Mono

    /// Fila i appbunten (variabel skrift, alle vekter i én fil).
    var fileName: String {
        switch self {
        case .grotesk: "HankenGrotesk-Variable"
        case .serif: "SourceSerif4-Variable"
        case .mono: "SometypeMono-Variable"
        }
    }

    /// PostScript-navnet til den navngitte vekten i den variable fila.
    func postScriptName(_ weight: DDFontWeight) -> String {
        switch self {
        case .grotesk:
            switch weight {
            case .light: "HankenGrotesk-Regular_Light"
            case .regular: "HankenGrotesk-Regular"
            case .medium: "HankenGrotesk-Regular_Medium"
            case .semibold: "HankenGrotesk-Regular_SemiBold"
            case .bold: "HankenGrotesk-Regular_Bold"
            }
        case .serif:
            switch weight {
            case .light: "SourceSerif4Roman-Light"
            case .regular: "SourceSerif4Roman-Regular"
            case .medium: "SourceSerif4Roman-Medium"
            case .semibold: "SourceSerif4Roman-SemiBold"
            case .bold: "SourceSerif4Roman-Bold"
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
        case .grotesk: .default
        case .serif: .serif
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

    // Typografiskala (style.css). Størrelsene er PWA-ens px på en 402 pt bred iPhone.

    /// «GolfGutu» på innlogging og velkomst (serif light 40).
    static let ddDisplay = dd(.serif, size: 40, weight: .light, relativeTo: .largeTitle)
    /// Overskrift på skjerm og ark (serif 24).
    static let ddTitle = dd(.serif, size: 24, relativeTo: .title2)
    /// Kortoverskrift (serif 21), f.eks. «Ingen runde på gang» og datoen for kvelden.
    static let ddTitleSmall = dd(.serif, size: 21, relativeTo: .title3)
    /// Spillernavn (serif 21 på hullkortet og Tavla).
    static let ddName = dd(.serif, size: 21, relativeTo: .title3)
    /// Navn i lister (serif 18).
    static let ddNameSmall = dd(.serif, size: 18, relativeTo: .headline)
    /// Hullnummer og store plasstall (serif light 64).
    static let ddHoleNumber = dd(.serif, size: 64, weight: .light, relativeTo: .largeTitle)
    /// Feiring (serif light 54).
    static let ddCelebration = dd(.serif, size: 54, weight: .light, relativeTo: .largeTitle)

    /// Brødtekst (grotesk 15).
    static let ddBody = dd(.grotesk, size: 15, relativeTo: .body)
    /// Uthevet brødtekst og radtitler (grotesk 500 15).
    static let ddBodyEmphasis = dd(.grotesk, size: 15, weight: .medium, relativeTo: .body)
    /// Knappetekst (grotesk 600 16).
    static let ddButton = dd(.grotesk, size: 16, weight: .semibold, relativeTo: .body)
    /// Stor knapp (grotesk 600 17).
    static let ddButtonLarge = dd(.grotesk, size: 17, weight: .semibold, relativeTo: .headline)
    /// Sekundærtekst (grotesk 13.5).
    static let ddCallout = dd(.grotesk, size: 13.5, relativeTo: .callout)
    /// Små linjer under en rad (grotesk 12.5).
    static let ddCaption = dd(.grotesk, size: 12.5, relativeTo: .caption)
    /// Score-merke (grotesk 600 13).
    static let ddChip = dd(.grotesk, size: 13, weight: .semibold, relativeTo: .footnote)

    /// Seksjonsetikett og «eyebrow» (mono 10, versaler med sporing).
    static let ddEyebrow = dd(.mono, size: 10, relativeTo: .caption2)
    /// Pille (mono 9.5).
    static let ddPill = dd(.mono, size: 9.5, relativeTo: .caption2)
    /// Små tall og linjer i mono (11–12).
    static let ddMonoSmall = dd(.mono, size: 12, relativeTo: .caption)
    /// Tall i rader (mono 500 17).
    static let ddNumber = dd(.mono, size: 17, weight: .medium, relativeTo: .body)
    /// Totalsum (mono 500 20).
    static let ddNumberLarge = dd(.mono, size: 20, weight: .medium, relativeTo: .title3)
    /// Slag på hullkortet (mono 500 32).
    static let ddStrokes = dd(.mono, size: 32, weight: .medium, relativeTo: .title)
    /// Stort tall i hero-kort (mono 500 52).
    static let ddHeroNumber = dd(.mono, size: 52, weight: .medium, relativeTo: .largeTitle)
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
