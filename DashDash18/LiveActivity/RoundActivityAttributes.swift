import ActivityKit
import Foundation

// DELT FIL: må være medlem av både DashDash18 og DashDash18Widgets (se docs/widgets-oppsett.md).
// Bare Foundation og ActivityKit her, ingen typer fra appen.

/// Live Activity under runden: hvor båsen er, egen score, stilling i båsen og matchen.
nonisolated struct RoundActivityAttributes: ActivityAttributes, Sendable {
    /// Det som endrer seg mens runden går.
    struct ContentState: Codable, Hashable, Sendable {
        /// Matchens farge: opp (grønn), ned (rust) eller nøytral.
        enum MatchTone: String, Codable, Hashable, Sendable {
            case neutral, up, down
        }

        /// Banens hullnummer båsen står på (10–18 når runden går på de siste ni).
        var holeNumber: Int
        /// Antall hull i runden (9 eller 18).
        var holeCount: Int
        /// Hull jeg har ført.
        var holesPlayed: Int
        /// Brutto slag så langt.
        var strokes: Int
        /// Stablefordpoeng så langt.
        var points: Int
        /// Plassen min i båsen (eller i runden uten båser), etter poeng. Nil når jeg ikke står der.
        var bayPlace: Int?
        /// Antall spillere i båsen (eller i runden uten båser).
        var bayCount: Int?
        /// Bås-nummeret, når runden har båser.
        var bayNumber: Int?
        /// «2 opp etter 5», «Delt», «Vunnet 3&2». Nil uten match.
        var matchText: String?
        var matchTone: MatchTone
        /// Når dataene ble regnet.
        var updatedAt: Date

        /// Samme innhold, uansett tidspunkt. Brukes for å slippe oppdateringer som ikke endrer noe.
        func sameContent(as other: ContentState) -> Bool {
            var a = self, b = other
            a.updatedAt = .distantPast
            b.updatedAt = .distantPast
            return a == b
        }
    }

    /// Runden aktiviteten følger.
    var roundID: UUID
    /// Banen, til overskriften.
    var courseName: String
    /// Spilleren som eier telefonen.
    var playerName: String
}
