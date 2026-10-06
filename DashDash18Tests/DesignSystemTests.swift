import Foundation
import Testing
import UIKit
@testable import DashDash18

struct DesignFontTests {
    @Test("Alle tre skriftfamiliene ligger i bunten og er registrert")
    func familiesRegistered() {
        #expect(DDFonts.available == Set(DDFontFamily.allCases))
    }

    @Test("Registrering på nytt er trygg og gir samme svar", arguments: [1, 2])
    func registerIsIdempotent(_ run: Int) {
        #expect(DDFonts.registerAll(in: .main) == Set(DDFontFamily.allCases))
    }

    @Test("Hver vekt finnes som navngitt instans", arguments: DDFontFamily.allCases)
    func weightsResolve(_ family: DDFontFamily) throws {
        for weight in DDFontWeight.allCases {
            let name = family.postScriptName(weight)
            let font = try #require(UIFont(name: name, size: 17), "Fant ikke \(name)")
            #expect(font.familyName == expectedFamily(family))
        }
    }

    @Test("Ulike vekter gir ulike skrifter")
    func weightsDiffer() throws {
        let regular = try #require(UIFont(name: DDFontFamily.grotesk.postScriptName(.regular), size: 17))
        let semibold = try #require(UIFont(name: DDFontFamily.grotesk.postScriptName(.semibold), size: 17))
        #expect(regular.fontName != semibold.fontName)
    }

    @Test("Skriften for navigasjonslinja skalerer med Dynamic Type")
    func uiFontScales() {
        let small = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: UIFont(name: DDFontFamily.serif.postScriptName(.regular), size: 17)!,
                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraSmall))
        let large = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: UIFont(name: DDFontFamily.serif.postScriptName(.regular), size: 17)!,
                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityLarge))
        #expect(large.pointSize > small.pointSize)
    }

    private func expectedFamily(_ family: DDFontFamily) -> String {
        switch family {
        case .grotesk: "Hanken Grotesk"
        case .serif: "Source Serif 4"
        case .mono: "Sometype Mono"
        }
    }
}

struct DesignColorTests {
    @Test("Hex leses riktig")
    func hex() {
        let rust = DDRGBA(0xBF5412)
        #expect(abs(rust.red - 191.0 / 255) < 1e-9)
        #expect(abs(rust.green - 84.0 / 255) < 1e-9)
        #expect(abs(rust.blue - 18.0 / 255) < 1e-9)
    }

    @Test("Kontrast: svart på hvitt er 21:1, lik farge er 1:1")
    func contrastExtremes() {
        #expect(abs(DDContrast.ratio(DDRGBA(0x000000), on: DDRGBA(0xFFFFFF)) - 21) < 0.01)
        #expect(abs(DDContrast.ratio(DDRGBA(0x1C483A), on: DDRGBA(0x1C483A)) - 1) < 1e-9)
    }

    @Test("Rust #BF5412 er under 4,5:1 på krem, derfor egen tekstfarge")
    func rustNeedsDarkerText() {
        let cream = DDToken.background.values.light
        #expect(DDContrast.ratio(DDToken.rust.values.light, on: cream) < 4.5)
        #expect(DDContrast.ratio(DDToken.rustText.values.light, on: cream) >= 4.5)
    }

    @Test("Gjennomsiktig farge legges over bakgrunnen før kontrasten regnes")
    func compositing() {
        let mixed = DDRGBA(0xFFFFFF, alpha: 0.5).composited(over: DDRGBA(0x000000))
        #expect(abs(mixed.red - 0.5) < 1e-9)
        #expect(mixed.alpha == 1)
    }

    @Test("Tekstparene holder 4,5:1 i lys modus", arguments: DDContrastPairs.text.map(\.name))
    func lightContrast(_ name: String) throws {
        let pair = try #require(DDContrastPairs.text.first { $0.name == name })
        let ratio = DDContrastPairs.ratio(pair, dark: false)
        #expect(ratio >= 4.5, "\(name): \(ratio)")
    }

    @Test("Tekstparene holder 4,5:1 i mørk modus", arguments: DDContrastPairs.text.map(\.name))
    func darkContrast(_ name: String) throws {
        let pair = try #require(DDContrastPairs.text.first { $0.name == name })
        let ratio = DDContrastPairs.ratio(pair, dark: true)
        #expect(ratio >= 4.5, "\(name): \(ratio)")
    }

    @Test("Dynamiske farger bytter med mørk modus")
    func dynamicColors() {
        let color = DDToken.background.uiColor
        let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r1: CGFloat = 0, r2: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        light.getRed(&r1, green: &g, blue: &b, alpha: &a)
        dark.getRed(&r2, green: &g, blue: &b, alpha: &a)
        #expect(abs(r1 - 1) < 0.01)          // #FFF9DF
        #expect(abs(r2 - 12.0 / 255) < 0.01)  // #0C1F18
    }

    @Test("Initialer til avatar")
    func initials() {
        #expect(DDAvatar.initials("Thomas Rostad") == "TR")
        #expect(DDAvatar.initials("kåre") == "K")
        #expect(DDAvatar.initials("") == "")
    }
}
