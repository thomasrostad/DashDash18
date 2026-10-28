import Foundation
import GolfgutuCore

/// Hvor «Se tabellen →» skal: Tavla-fanen for klubbens hovedturnering (jakkeracet), ellers
/// turneringens egen side.
nonisolated enum HjemTableLink: Equatable, Sendable {
    case tavla
    case competition(UUID)
}

/// Hva siden bak «Se tabellen →» viser, når turneringen ikke var kjent på Hjem.
nonisolated enum HjemTableScreen: Equatable, Sendable {
    case loading
    /// Klubbens hovedturnering: Tavla-fanen.
    case tavla
    case detail(CompetitionRow)
    /// Hentingen feilet: feilen og «Prøv igjen».
    case failed(String)
    /// Hentet uten feil, men turneringen finnes ikke (slettet, eller du har ikke tilgang).
    case missing
}

/// Det lille Hjem-viewene trenger utover feeden: tekster og valg som ikke hører hjemme i
/// `HomeFeed`. Ren, med tester (HjemVisningTests).
nonisolated enum HjemDisplay {
    static let emptyTitle = "Ingenting her ennå"

    /// Symbolet i tomtilstanden.
    static func emptySymbol(_ filter: HomeFeedFilter) -> String {
        filter == .loose ? "figure.golf" : "sparkles"
    }

    /// Den vennlige linja under «Ingenting her ennå», etter filteret.
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

    /// Runden som pågår (i feeden på iOS 26.0) står under Alt og turneringene, men ikke under
    /// «Løse runder» når det er en klubbrunde (og omvendt).
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

    /// Hvor tabellkortet går. Klubbens hovedturnering står på Tavla i klubben du har valgt.
    static func tableLink(competitionID: UUID, competition: CompetitionRow?, currentClub: UUID?) -> HjemTableLink {
        if let competition, let currentClub, competition.clubID == currentClub,
           competition.isMain || competition.kind == .season {
            return .tavla
        }
        return .competition(competitionID)
    }

    /// Siden bak «Se tabellen →»: turneringen fra lista eller hentet rett (`fetched`). Det som er funnet,
    /// vinner over en feil; jakkeracet i klubben går til Tavla som `tableLink`.
    static func tableScreen(listed: CompetitionRow?, fetched: CompetitionRow?, isLoading: Bool, error: String?,
                            currentClub: UUID?) -> HjemTableScreen {
        if let competition = listed ?? fetched {
            return tableLink(competitionID: competition.id, competition: competition, currentClub: currentClub) == .tavla
                ? .tavla : .detail(competition)
        }
        if isLoading { return .loading }
        if let error { return .failed(error) }
        return .missing
    }

    /// Opp er grønt, ned er blush.
    static func isUp(_ move: Int) -> Bool { move > 0 }

    /// Det VoiceOver leser for «Din runde».
    static func myRoundLabel(_ card: HomeMyRoundCard) -> String {
        var parts = ["Din runde", card.title]
        if let subtitle = card.subtitle { parts.append(subtitle) }
        parts.append(card.points.map { "\($0) \(card.unit)" } ?? card.value)
        if let place = card.placeText { parts.append("\(place) \(card.ofText)") }
        if !card.marks.isEmpty { parts.append(card.marks.map(\.label).joined(separator: ", ")) }
        if let winner = card.winner { parts.append(winner) }
        return parts.joined(separator: ". ")
    }

    /// «Anders Berg slo eagle», «Du fikk hole in one» (planen 4.1).
    static func featTitle(_ card: HomeFeatCard) -> String {
        (card.isMe ? "Du" : card.name) + " " + HomeFeedText.featVerb(card.kind)
    }

    /// Fargen på slagtallet: eagle for eagle og bedre, birdie, og blowup for shank.
    static func featScoreName(_ kind: HomeFeatKind) -> ScoreName {
        switch kind {
        case .holeInOne, .albatross, .eagle: .eagle
        case .birdie: .birdie
        case .shank: .blowup
        }
    }

    /// «Hull 5, par 5 · Losby · runde 4».
    static func featLine(_ card: HomeFeatCard) -> String {
        ["Hull \(card.hole), par \(card.par)", card.roundPlace].compactMap { $0 }.joined(separator: " · ")
    }

    /// Det VoiceOver leser for en bragd.
    static func featLabel(_ card: HomeFeatCard, time: String) -> String {
        "\(featTitle(card)). \(card.strokes) slag. \(featLine(card)). \(time)"
    }
}

/// Linja under svaret på «Neste kveld» (utbedringsplanen V2): fristen for å endre svaret i stedet
/// for «Angre». Fristene følger `SignupDeadline`: avmeldingsfristen når du kommer, ellers
/// påmeldingsfristen.
nonisolated enum HomeAnswerNote {
    static func text(answer: SignupStatus?, signupDeadline: Date?, withdrawDeadline: Date?, now: Date) -> String {
        let deadline = answer == .yes ? withdrawDeadline : signupDeadline
        guard let deadline else {
            return answer == nil ? "Svar, så vet arrangøren hvem som kommer." : "Du kan endre svaret når som helst."
        }
        guard now < deadline else {
            return answer == .yes ? "Fristen for å melde av er ute." : "Påmeldingen er stengt."
        }
        let when = EveningDates.longText(EveningDates.dateString(from: deadline)) + " kl. "
            + EveningDates.timeString(from: deadline).prefix(5)
        return answer == nil ? "Svar innen \(when)." : "Du kan endre svaret fram til \(when)."
    }
}
