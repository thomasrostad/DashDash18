import Foundation
import GolfgutuCore

// Ren logikk for konkurransene (fase 15): hvem som ser og styrer, påmelding, «Teller også i …»,
// morrokvelder på Kveld og tekstene. Ingen nettverk og ingen SwiftUI. Reglene speiler RLS og
// RPC-ene i sql/017 og sql/022, så appen viser bare det databasen vil godta.

/// Deg, sett fra konkurransene: profilen og klubbmedlemskapene dine.
nonisolated struct CompetitionAccess: Equatable, Sendable {
    /// Medlemskapet ditt i én klubb.
    struct Membership: Equatable, Sendable {
        let clubID: UUID
        let memberID: UUID
        let isOrganizer: Bool
        let isActive: Bool
    }

    let profileID: UUID?
    let memberships: [Membership]

    init(profileID: UUID?, memberships: [Membership]) {
        self.profileID = profileID
        self.memberships = memberships
    }

    private func membership(in club: UUID?) -> Membership? {
        guard let club else { return nil }
        return memberships.first { $0.clubID == club && $0.isActive }
    }

    var memberIDs: Set<UUID> { Set(memberships.filter(\.isActive).map(\.memberID)) }

    /// Er påmeldingen din? Profilen din, eller et av medlemskapene dine.
    func isMine(_ p: CompetitionParticipantRow) -> Bool {
        (p.profileID != nil && p.profileID == profileID) || p.memberID.map(memberIDs.contains) == true
    }

    /// Din aktive påmelding i konkurransen.
    func myParticipation(_ c: CompetitionRow, _ participants: [CompetitionParticipantRow]) -> CompetitionParticipantRow? {
        participants.first { $0.competitionID == c.id && isMine($0) && $0.status == .active }
    }

    /// `can_read_competition`: klubbens (aktivt medlem), din egen, eller en du er påmeldt.
    func canSee(_ c: CompetitionRow, _ participants: [CompetitionParticipantRow]) -> Bool {
        if c.clubID != nil, membership(in: c.clubID) != nil { return true }
        if c.clubID == nil, c.ownerID != nil, c.ownerID == profileID { return true }
        return myParticipation(c, participants) != nil
    }

    /// `is_competition_admin`: arrangør i klubben, eller eieren av en privat.
    func isAdmin(_ c: CompetitionRow) -> Bool {
        if let club = c.clubID { return membership(in: club)?.isOrganizer == true }
        return c.ownerID != nil && c.ownerID == profileID
    }

    /// Kan du lage en konkurranse i klubben (arrangør), eller en privat (alle med profil)?
    func canCreate(inClub club: UUID?) -> Bool {
        guard let club else { return profileID != nil }
        return membership(in: club)?.isOrganizer == true
    }

    /// Personene du er i tabellene, for å markere «deg».
    var myEntrants: Set<Entrant> {
        var out = Set(memberIDs.map(Entrant.member))
        if let profileID { out.insert(.profile(profileID)) }
        return out
    }

    /// Påmeldingen sett fra deg (`join_competition`).
    enum Signup: Equatable, Sendable {
        /// Du er med («Meld meg av»).
        case entered
        /// «Meld meg på».
        case open
        /// Ikke åpen, ferdig, eller cupen er trukket.
        case closed
        /// Tabellen teller troppen eller alle som spiller: ingen påmelding.
        case notNeeded
    }

    func signup(_ c: CompetitionRow, _ participants: [CompetitionParticipantRow], isDrawn: Bool) -> Signup {
        guard c.entry == .listed, c.kind != .season, c.kind != .game else { return .notNeeded }
        if myParticipation(c, participants) != nil { return .entered }
        guard canSee(c, participants), c.isSignupOpen, c.status != .finished,
              !(c.kind == .cup && isDrawn) else { return .closed }
        // En klubbkonkurranse melder på medlemmet: du må være aktivt medlem.
        if c.clubID != nil, membership(in: c.clubID) == nil { return .closed }
        return .open
    }

    /// «Inviter» (`competition_invite`): bare private liga-, cup- og morroturneringer som ikke er
    /// ferdige, og ikke en trukket cup. Eieren og de påmeldte deler koden.
    func canInvite(_ c: CompetitionRow, _ participants: [CompetitionParticipantRow], isDrawn: Bool) -> Bool {
        guard c.clubID == nil, [.league, .cup, .fun].contains(c.kind), c.status != .finished,
              !(c.kind == .cup && isDrawn) else { return false }
        return isAdmin(c) || myParticipation(c, participants) != nil
    }
}

// MARK: - Resultat i en cupkamp

/// Hvem fører resultatet i en cupkamp (`record_cup_result`, sql/022, besluttet 07.10.2026): de to
/// spillerne fører selv, og første førte resultat gjelder. Arrangøren eller eieren kan føre og rette.
nonisolated enum CupRecording {
    enum Right: Equatable, Sendable {
        /// Ingen knapp.
        case none
        /// «Før»: spilleren fører kampen sin én gang, uten å kunne fjerne resultatet.
        case record
        /// «Før» / «Endre»: arrangøren eller eieren, også «Ikke avgjort».
        case edit
    }

    static func right(_ game: CupStandings.Game, isAdmin: Bool) -> Right {
        guard !game.isBye, game.state != .waiting else { return .none }
        if isAdmin { return .edit }
        let mine = game.a?.isMe == true || game.b?.isMe == true
        return mine && game.winner == nil ? .record : .none
    }
}

extension ClubContext {
    /// Deg sett fra konkurransene, fra klubben som er valgt i appen.
    var competitionAccess: CompetitionAccess {
        CompetitionAccess(profileID: user.id,
                          memberships: [.init(clubID: clubID, memberID: memberID, isOrganizer: isOrganizer,
                                              isActive: membership.status == .active)])
    }
}

// MARK: - «Teller også i …»

/// Hvilke konkurranser en runde kan telle i i tillegg (`set_round_competitions`, sql/022).
nonisolated enum CompetitionLinking {
    /// En spiller i runden, som `round_roster`: id-en i runden, klubben (klubbrunde) og profilen.
    struct Player: Equatable, Sendable {
        let playerID: UUID
        let clubID: UUID?
        let profileID: UUID?
    }

    /// En konkurranse runden kan legges i, og hvor mange av spillerne som er med i den.
    struct Candidate: Identifiable, Equatable, Sendable {
        let competition: CompetitionRow
        let entrants: Int
        let players: Int
        var id: UUID { competition.id }

        /// «3 av 8 er med», «Alle er med».
        var coverage: String {
            entrants == players ? "Alle er med" : "\(entrants) av \(players) er med"
        }
    }

    /// Konkurransene du styrer, som runden kan telle i: liga, cup eller morroturnering som ikke er
    /// ferdig, der minst én av spillerne er med. Sortert på navn.
    static func candidates(competitions: [CompetitionRow], participants: [CompetitionParticipantRow],
                           members: [ClubMemberRow], access: CompetitionAccess, players: [Player]) -> [Candidate] {
        competitions
            .filter { [.league, .cup, .fun].contains($0.kind) && $0.status != .finished && access.isAdmin($0) }
            .map { c in
                Candidate(competition: c,
                          entrants: entrantCount(c, participants: participants, members: members, players: players),
                          players: players.count)
            }
            .filter { $0.entrants > 0 }
            .sorted { NorwegianSort.areInIncreasingOrder($0.competition.name, $1.competition.name) }
    }

    /// `competition_round_entrants`: hvor mange av spillerne er med i konkurransen.
    static func entrantCount(_ c: CompetitionRow, participants: [CompetitionParticipantRow],
                             members: [ClubMemberRow], players: [Player]) -> Int {
        let active = participants.filter { $0.competitionID == c.id && $0.status == .active }
        let memberUser = Dictionary(members.map { ($0.id, $0.userID) }, uniquingKeysWith: { first, _ in first })
        return players.filter { p in
            switch c.entry {
            case .open:
                return true
            case .club:
                if let club = p.clubID, club == c.clubID { return true }
                guard let profile = p.profileID else { return false }
                return members.contains { $0.clubID == c.clubID && $0.status == .active && $0.userID == profile }
            case .listed:
                return active.contains { cp in
                    if let m = cp.memberID, p.clubID != nil, m == p.playerID { return true }
                    guard let profile = p.profileID else { return false }
                    if cp.profileID == profile { return true }
                    if let m = cp.memberID, memberUser[m] ?? nil == profile { return true }
                    return false
                }
            }
        }.count
    }

    /// Lista til `set_round_competitions`: de valgte blant kandidatene. Koblinger du ikke styrer,
    /// røres ikke av databasen.
    static func selection(_ selected: Set<UUID>, among candidates: [Candidate]) -> [UUID] {
        candidates.map(\.id).filter(selected.contains)
    }
}

// MARK: - Kveld

/// Morroturneringer på Kveld: kvelden er med når datoen er innenfor perioden, eller en av rundene
/// teller i turneringen.
nonisolated enum CompetitionCalendar {
    /// Navnene på morroturneringene kvelden hører til, i navnerekkefølge.
    static func funNames(eventDate: String, eventClubID: UUID, roundIDs: Set<UUID>,
                         competitions: [CompetitionRow], links: [CompetitionRoundRow]) -> [String] {
        competitions
            .filter { c in
                guard c.kind == .fun, c.status != .finished else { return false }
                if links.contains(where: { $0.competitionID == c.id && roundIDs.contains($0.roundID) }) { return true }
                // Perioden gjelder bare klubbens egne turneringer, så en privat morro ikke merker kvelder.
                guard c.clubID == eventClubID, let start = c.startsOn else { return false }
                return start <= eventDate && (c.endsOn.map { eventDate <= $0 } ?? true)
            }
            .map(\.name)
            .sorted(by: NorwegianSort.areInIncreasingOrder)
    }
}

// MARK: - Tekst

nonisolated enum CompetitionText {
    static func kind(_ kind: CompetitionKind) -> String {
        switch kind {
        case .season: "Sesong"
        case .league: "Liga"
        case .cup: "Cup"
        case .fun: "Morroturnering"
        case .game: "Spill"
        }
    }

    static func kindHelp(_ kind: CompetitionKind) -> String {
        switch kind {
        case .season: "Sesongen med terminliste og tabell, som jakkeracet."
        case .league: "Poeng for hver runde etter plassering eller stableford. Beste runder teller."
        case .cup: "Utslag i matchspill. Trekning, tre og en vinner."
        case .fun: "Kort periode og egne deltakere. Tabell som en liga."
        case .game: "Spill på runden."
        }
    }

    static func entry(_ entry: CompetitionEntry) -> String {
        switch entry {
        case .club: "Hele troppen"
        case .listed: "De påmeldte"
        case .open: "Alle som spiller en runde som teller"
        }
    }

    static func scoring(_ s: LeagueRules.Scoring) -> String {
        switch s {
        case .placement: "Plassering"
        case .stableford: "Stableford"
        }
    }

    static func seeding(_ s: CupRules.Seeding) -> String {
        switch s {
        case .random: "Trekning"
        case .handicap: "Lavest handicap først"
        case .ranking: "Plassen i hovedturneringen"
        }
    }

    static func tie(_ t: CupRules.Tie) -> String {
        switch t {
        case .suddenDeath: "Sudden death"
        case .countback: "Siste hull som ikke var delt"
        case .higherSeed: "Beste seed går videre"
        case .lowerHandicap: "Lavest handicap går videre"
        }
    }

    /// «1. runde», «Kvartfinale», «Semifinale», «Finale».
    static func cupRound(_ round: Int, of count: Int) -> String {
        switch count - round {
        case 0: "Finale"
        case 1: "Semifinale"
        case 2: "Kvartfinale"
        default: "\(round). runde"
        }
    }

    /// «3&2», «2 opp», «Likt, countback».
    static func cupResult(_ d: Cup.Decision) -> String? {
        switch d {
        case .won(_, let up, let remaining, let tie):
            if let tie { return "Likt, avgjort: \(self.tie(tie).lowercased())" }
            return remaining > 0 ? "\(up)&\(remaining)" : "\(up) opp"
        case .tied: return "Likt etter siste hull"
        case .inProgress(let up, let played, _):
            return up == 0 ? "Likt etter \(played)" : "\(abs(up)) \(up > 0 ? "opp" : "ned") etter \(played)"
        case .notStarted: return nil
        }
    }

    /// «1.–31. okt», «fra 1. okt», eller nil.
    static func period(_ c: CompetitionRow) -> String? {
        switch (c.startsOn, c.endsOn) {
        case let (s?, e?): "\(shortDate(s)) – \(shortDate(e))"
        case let (s?, nil): "fra \(shortDate(s))"
        case let (nil, e?): "til \(shortDate(e))"
        default: nil
        }
    }

    /// «2026-10-01» → «1. okt».
    static func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        let months = ["jan", "feb", "mar", "apr", "mai", "jun", "jul", "aug", "sep", "okt", "nov", "des"]
        guard parts.count == 3, (1...12).contains(parts[1]) else { return date }
        return "\(parts[2]). \(months[parts[1] - 1])"
    }

    /// Linja under navnet i lista: type, eier og periode.
    static func subtitle(_ c: CompetitionRow, clubName: String?) -> String {
        var parts = [kind(c.kind)]
        if c.isMain { parts.append("hovedturnering") }
        parts.append(c.clubID == nil ? "privat" : (clubName ?? "klubb"))
        if let p = period(c) { parts.append(p) }
        if c.status == .finished { parts.append("ferdig") }
        return parts.joined(separator: " · ")
    }
}
