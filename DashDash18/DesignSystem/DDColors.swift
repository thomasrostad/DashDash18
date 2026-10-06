import SwiftUI
import UIKit

extension DDRGBA {
    nonisolated var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

extension DDToken {
    /// Følger lys og mørk modus.
    nonisolated var uiColor: UIColor {
        let (light, dark) = values
        let lightColor = light.uiColor
        let darkColor = dark.uiColor
        return UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        }
    }

    nonisolated var color: Color { Color(uiColor: uiColor) }
}

/// Fargene i appen. Bruk disse, ikke `.green`/`.orange`, så lys og mørk modus stemmer med PWA-en.
extension Color {
    // Flater
    static let ddBackground = DDToken.background.color
    static let ddCard = DDToken.card.color
    static let ddHeroCard = DDToken.heroCard.color
    static let ddEarth = DDToken.earth.color
    static let ddEarthDeep = DDToken.earthDeep.color
    static let ddForest = DDToken.forest.color
    static let ddForestDeep = DDToken.forestDeep.color
    static let ddTabBar = DDToken.tabBar.color
    static let ddDriveBox = DDToken.driveBox.color
    static let ddYouRow = DDToken.youRow.color
    // Tekst og strek
    static let ddForestInk = DDToken.forestInk.color
    static let ddInk = DDToken.ink.color
    static let ddInkSecondary = DDToken.inkSecondary.color
    static let ddOnDark = DDToken.onDark.color
    static let ddHairline = DDToken.hairline.color
    static let ddRule = DDToken.rule.color
    static let ddRuleCream = DDToken.ruleCream.color
    static let ddCardBorder = DDToken.cardBorder.color
    // Aksent
    static let ddRust = DDToken.rust.color
    static let ddRustText = DDToken.rustText.color
    static let ddRustDark = DDToken.rustDark.color
    static let ddGold = DDToken.gold.color
    static let ddGoldInk = DDToken.goldInk.color
    // Status
    static let ddLimeBackground = DDToken.limeBackground.color
    static let ddLimeInk = DDToken.limeInk.color
    static let ddSunBackground = DDToken.sunBackground.color
    static let ddSunInk = DDToken.sunInk.color
    static let ddBlushBackground = DDToken.blushBackground.color
    static let ddBlushDeep = DDToken.blushDeep.color
    static let ddBlushInk = DDToken.blushInk.color
    // Aksenter fra golfee
    static let ddLime = DDToken.accentLime.color
    static let ddLimeOnAccent = DDToken.accentLimeInk.color
    static let ddYellow = DDToken.accentYellow.color
    static let ddYellowInk = DDToken.accentYellowInk.color
    static let ddYellowText = DDToken.yellowText.color
    static let ddStatCard = DDToken.statCard.color
    static let ddStatText = DDToken.statText.color
    static let ddStatSecondary = DDToken.statSecondary.color
    static let ddStatRust = DDToken.statRust.color
    /// Feilmeldinger: mørk rust på lys flate, lys rust i mørk modus.
    static let ddError = DDToken.rustDark.color
}
