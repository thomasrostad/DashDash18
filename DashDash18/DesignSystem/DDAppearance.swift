import SwiftUI
import UIKit

/// Oppsett ved oppstart: skrifter og UIKit-flatene SwiftUI ikke styrer selv
/// (titlene i navigasjonslinja).
enum DDAppearance {
    @MainActor
    static func configure() {
        DDFonts.register()
        let large = UIFont.dd(.serif, size: 34, weight: .light, relativeTo: .largeTitle)
        let inline = UIFont.dd(.serif, size: 21, relativeTo: .headline)
        let appearance = UINavigationBar.appearance()
        // Fargen kommer fra `ddNavigationChrome()` (krem på grønt) eller systemet; her bare skriften.
        appearance.largeTitleTextAttributes = [.font: large]
        appearance.titleTextAttributes = [.font: inline]
    }
}

extension View {
    /// Rotoppsett for appen: brødskrift, grønn tint for knapper og lenker.
    func ddAppStyle() -> some View {
        font(.ddBody)
            .tint(Color.ddForestInk)
    }
}
