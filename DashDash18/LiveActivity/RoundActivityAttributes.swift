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
        /// Summen i formen når runden ikke er netto stableford: «72 slag», «+2», «28 p» (stableford brutto).
        /// Nil: `points` som poeng. Valgfri, så eldre tilstander og push-innhold uten feltet virker.
        var valueText: String? = nil
        /// Matchen avgjør runden (formen er matchspill): plassen i båsen (som regnes på poeng) er borte,
        /// og slagene står under matchen i stedet for poengene. Nil: som før. Valgfri, som `valueText`.
        var isMatchPlay: Bool? = nil

        /// Matchen står i stedet for poengene når det finnes en match (12.11.2026: også i scramble og
        /// fourball, der lagene møtes). Utenom matchspill står poengene under matchen.
        var leadsWithMatch: Bool { matchText != nil }

        /// Linja under matchen: resten av matchteksten og summen. «2 opp etter 5» → «etter 5 · 13 p».
        /// I matchspill teller ikke poengene, så der står slagene («etter 5 · 27 slag»). Uten «etter»:
        /// bare summen.
        var matchDetail: String {
            let sum = isMatchPlay == true ? "\(strokes) slag" : (valueText ?? "\(points) p")
            let parts = (matchText ?? "").components(separatedBy: " etter ")
            return parts.count > 1 ? "etter \(parts[1]) · \(sum)" : sum
        }

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
