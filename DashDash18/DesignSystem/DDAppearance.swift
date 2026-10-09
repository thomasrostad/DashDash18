import SwiftUI
import UIKit

/// Oppsett ved oppstart: skrifter og UIKit-flatene SwiftUI ikke styrer selv
/// (titlene i navigasjonslinja).
enum DDAppearance {
    @MainActor
    static func configure() {
        DDFonts.register()
        let large = UIFont.dd(.sans, size: 34, weight: .medium, relativeTo: .largeTitle)
        let inline = UIFont.dd(.sans, size: 20, weight: .medium, relativeTo: .headline)
        let appearance = UINavigationBar.appearance()
        // Alle skjermer har grønn linje (`ddNavigationChrome()`), så titlene er krem.
        let cream = DDToken.onDark.uiColor
        appearance.largeTitleTextAttributes = [.font: large, .foregroundColor: cream]
        appearance.titleTextAttributes = [.font: inline, .foregroundColor: cream]
    }
}

extension View {
    /// Rotoppsett for appen: brødskrift, grønn tint for knapper og lenker.
    func ddAppStyle() -> some View {
        font(.ddBody)
            .tint(Color.ddForestInk)
            // Datoer, «for 3 dager siden», datovelgere og grafer på norsk også når telefonen står på
            // engelsk (skjermsjekken 09.10.2026 fant «3 days ago», «May 26» og «1 Sep 2026»).
            .environment(\.locale, Locale(identifier: "nb_NO"))
    }
}
