import Foundation

/// Hvor «Se tabellen →» skal: Tavla-fanen for klubbens hovedturnering (jakkeracet), ellers
/// turneringens egen side.
nonisolated enum HjemTableLink: Equatable, Sendable {
    case tavla
    case competition(UUID)
}

/// Det lille Hjem-viewene trenger utover feeden: tekster og valg som ikke hører hjemme i
/// `HomeFeed`. Ren, med tester (HjemVisningTests).
nonisolated enum HjemDisplay {
    static let emptyTitle = "Ingenting her ennå."

    /// Den vennlige linja under «Ingenting her ennå.», etter filteret.
    static func emptyLine(_ filter: HomeFeedFilter) -> String {
        switch filter {
        case .all:
            "Når noen slår eagle, tar ledelsen eller runden din er ferdig, dukker det opp her."
        case .competition:
            "Bragder, tabellendringer og runder i turneringen dukker opp her."
        case .club:
            "Meldinger og påmeldinger i klubben dukker opp her."
        case .loose:
            "Løse runder du spiller med venner, dukker opp her."
        }
    }

    /// «Pågår nå» står under Alt og turneringene, men ikke under «Løse runder» når det er en
    /// klubbrunde (og omvendt).
    static func showsLive(_ live: HomeLive, filter: HomeFeedFilter) -> Bool {
        switch filter {
        case .all: true
        case .loose: live.isLoose
        case .competition, .club: !live.isLoose
        }
    }

    /// «Neste kveld» hører til klubben: ikke under «Løse runder».
    static func showsEvening(filter: HomeFeedFilter) -> Bool {
        filter != .loose
    }

    /// Radene i «Pågår nå»: topp 3, og deg under når du er lenger ned.
    static func liveRows(_ live: HomeLive) -> [HomeLive.Row] {
        live.top + (live.me.map { [$0] } ?? [])
    }

    /// Navnet i «Pågår nå»: «Thomas (deg)» for deg, som i designet.
    static func liveName(_ row: HomeLive.Row) -> String {
        row.isMe ? "\(row.name) (deg)" : row.name
    }

    /// Hvor tabellkortet går. Klubbens hovedturnering står på Tavla i klubben du har valgt.
    static func tableLink(competitionID: UUID, competition: CompetitionRow?, currentClub: UUID?) -> HjemTableLink {
        if let competition, let currentClub, competition.clubID == currentClub,
           competition.isMain || competition.kind == .season {
            return .tavla
        }
        return .competition(competitionID)
    }

    /// Opp er grønt, ned er blush.
    static func isUp(_ move: Int) -> Bool { move > 0 }

    /// Det VoiceOver leser for «Din runde».
    static func myRoundLabel(_ card: HomeMyRoundCard) -> String {
        var parts = ["Din runde", card.title]
        if let subtitle = card.subtitle { parts.append(subtitle) }
        parts.append(card.points.map { "\($0) poeng" } ?? card.value)
        if let place = card.placeText { parts.append("\(place) \(card.ofText)") }
        if !card.marks.isEmpty { parts.append(card.marks.map(\.label).joined(separator: ", ")) }
        if let winner = card.winner { parts.append(winner) }
        return parts.joined(separator: ". ")
    }

    /// Det VoiceOver leser for en bragd.
    static func featLabel(_ card: HomeFeatCard, time: String) -> String {
        "\(card.name): \(card.headline). \(card.detail). \(time)"
    }
}
