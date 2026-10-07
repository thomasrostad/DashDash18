import Foundation
import GolfgutuCore

/// Personen bak en spiller i en runde, slik en konkurranse teller hen (fase 12).
///
/// I en klubbrunde er spilleren et klubbmedlem (`round_players.member_id` = `club_members.id`). I en
/// løs runde er spilleren en deltaker (`round_participants.id`) som er en profil eller en gjest. En
/// konkurranse som teller runder fra flere steder, må kjenne igjen samme person på tvers.
nonisolated enum Entrant: Hashable, Sendable {
    /// Klubbmedlem i konkurransens klubb. Samme id som Tavla bruker i dag.
    case member(UUID)
    /// En profil (innlogging).
    case profile(UUID)
    /// Kjent bare i én runde: en gjest, eller et medlem uten innlogging i en annen klubb.
    case guest(UUID)

    var id: UUID {
        switch self {
        case .member(let id), .profile(let id), .guest(let id): id
        }
    }

    /// Spiller-id-en i regelmotoren.
    var key: String { id.uuidString }
}

/// Oppslag fra spiller-id-en i en runde til personen bak: klubbmedlemmer (med innlogging) og deltakere
/// i løse runder (med profil). Bygges av radene som er hentet; ingen nettverk.
nonisolated struct PersonDirectory: Sendable {
    /// `club_members.id` → medlemmet.
    let members: [UUID: ClubMemberRow]
    /// `round_participants.id` → deltakeren.
    let participants: [UUID: RoundParticipantRow]
    /// `profiles.id` → profilen.
    let profiles: [UUID: ProfileRow]

    init(members: [ClubMemberRow] = [], participants: [RoundParticipantRow] = [], profiles: [ProfileRow] = []) {
        self.members = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.participants = Dictionary(participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.profiles = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Medlemmet i klubben for en innlogging, om det finnes.
    func member(in clubID: UUID, profile: UUID) -> ClubMemberRow? {
        members.values
            .filter { $0.clubID == clubID && $0.userID == profile }
            .min { $0.id.uuidString < $1.id.uuidString }
    }

    /// Personen bak spilleren, sett fra en konkurranse som eies av `clubID` (eller ingen klubb).
    /// Regelen: i klubbens egen konkurranse er et medlem alltid medlemmet (som Tavla), også når hen
    /// spiller en løs runde med profilen sin. Ellers er det profilen når den er kjent, og ellers bare
    /// spilleren i den runden.
    func entrant(_ playerID: UUID, competitionClub clubID: UUID?) -> Entrant {
        if let member = members[playerID] {
            if member.clubID == clubID { return .member(member.id) }
            if let user = member.userID { return .profile(user) }
            return .guest(member.id)
        }
        if let participant = participants[playerID] {
            guard let profile = participant.profileID else { return .guest(participant.id) }
            if let clubID, let member = member(in: clubID, profile: profile) { return .member(member.id) }
            return .profile(profile)
        }
        // Ukjent: hører til konkurransens klubb (klubbrunder hentet uten tropp), ellers bare runden.
        return clubID == nil ? .guest(playerID) : .member(playerID)
    }

    /// Navnet å vise: troppen, profilen, deltakeren, ellers navnet runden hadde.
    func name(_ entrant: Entrant, fallback: String?) -> String {
        switch entrant {
        case .member(let id):
            return members[id]?.displayName ?? fallback ?? ""
        case .profile(let id):
            return profiles[id]?.displayName ?? fallback ?? ""
        case .guest(let id):
            return participants[id]?.displayName ?? members[id]?.displayName ?? fallback ?? ""
        }
    }
}

/// Hvilke runder og hvem en konkurranse teller. Ren logikk, uten nettverk og SwiftUI.
///
/// - Runder: de som står i `competition_rounds` for konkurransen, og som er startet (ikke kladd),
///   i tidsrekkefølge (dato, så rundenummer), som Tavla.
/// - Deltakere: etter `entry` — klubbens tropp (aktive + de som har spilt, som Tavla), de påmeldte,
///   eller alle som har spilt.
///
/// For sesongens konkurranse (jakkeracet) gir `tavlaInput` nøyaktig samme grunnlag som Tavla bygger
/// fra sesongen i dag, så tabellen blir den samme.
nonisolated struct CompetitionScope: Sendable {
    let competition: CompetitionRow
    /// Rundene som teller (`competition_rounds.round_id` for konkurransen).
    let roundIDs: Set<UUID>
    /// Aktive påmeldte (`entry = listed`).
    let participants: [CompetitionParticipantRow]

    init(competition: CompetitionRow, links: [CompetitionRoundRow], participants: [CompetitionParticipantRow] = []) {
        self.competition = competition
        roundIDs = Set(links.filter { $0.competitionID == competition.id }.map(\.roundID))
        self.participants = participants.filter { $0.competitionID == competition.id && $0.status == .active }
    }

    // MARK: Runder

    /// Teller runden? Den må være koblet til konkurransen og startet.
    func counts(_ round: RoundOriginRow) -> Bool {
        roundIDs.contains(round.id) && round.status != .draft
    }

    /// Rundene som teller blant de hentede, i Tavlas rekkefølge: dato, så rundenummer.
    func countedRounds(_ candidates: [RoundSnapshot]) -> [RoundSnapshot] {
        candidates
            .filter { counts(RoundOriginRow($0.round)) }
            .sorted { a, b in
                let da = a.eventDate ?? "", db = b.eventDate ?? ""
                return da != db ? da < db : a.round.roundNo < b.round.roundNo
            }
    }

    // MARK: Deltakere

    /// Hvem som står i tabellen, i norsk navnerekkefølge.
    func entrants(counted: [RoundSnapshot], directory: PersonDirectory) -> [Entrant] {
        let club = competition.clubID
        let played = counted.flatMap { s in s.players.map { directory.entrant($0.memberID, competitionClub: club) } }
        var chosen: [Entrant]
        switch competition.entry {
        case .club:
            let active = directory.members.values
                .filter { $0.clubID == club && $0.status == .active }
                .map { Entrant.member($0.id) }
            chosen = active + played
        case .listed:
            chosen = participants.compactMap { p in
                if let member = p.memberID { return .member(member) }
                guard let profile = p.profileID else { return nil }
                if let club, let member = directory.member(in: club, profile: profile) { return .member(member.id) }
                return .profile(profile)
            }
        case .open:
            chosen = played
        }
        var seen = Set<Entrant>()
        let unique = chosen.filter { seen.insert($0).inserted }
        let names = Dictionary(counted.flatMap { s in
            s.players.map { (directory.entrant($0.memberID, competitionClub: club), s.names[$0.memberID]) }
        }, uniquingKeysWith: { first, _ in first })
        return unique.sorted {
            NorwegianSort.areInIncreasingOrder(directory.name($0, fallback: names[$0] ?? nil),
                                               directory.name($1, fallback: names[$1] ?? nil))
        }
    }

    /// Runden med spillerne gitt nytt navn etter personen bak (`Entrant.id`), så samme person har samme
    /// id i alle runder. Klubbmedlemmer i klubbens egen konkurranse beholder id-en sin.
    func rekeyed(_ snapshot: RoundSnapshot, directory: PersonDirectory) -> RoundSnapshot {
        let club = competition.clubID
        func key(_ id: UUID) -> UUID { directory.entrant(id, competitionClub: club).id }
        var s = snapshot
        s.players = snapshot.players.map { p in
            RoundPlayerRow(roundID: p.roundID, memberID: key(p.memberID), clubID: p.clubID,
                           handicapIndex: p.handicapIndex, seedGroup: p.seedGroup, playingHandicap: p.playingHandicap,
                           bayNo: p.bayNo, isMarker: p.isMarker, teamNo: p.teamNo)
        }
        s.scores = snapshot.scores.map { h in
            HoleScoreRow(roundID: h.roundID, memberID: key(h.memberID), holeIndex: h.holeIndex, strokes: h.strokes,
                         recordedAt: h.recordedAt, updatedBy: h.updatedBy, updatedAt: h.updatedAt)
        }
        s.matches = snapshot.matches.map { m in
            var m = m
            m.playerA = m.playerA.map(key)
            m.playerB = m.playerB.map(key)
            m.playerC = m.playerC.map(key)
            return m
        }
        s.sideClaims = snapshot.sideClaims.map { c in
            SideClaimRow(id: c.id, roundID: c.roundID, memberID: key(c.memberID), kind: c.kind, meters: c.meters,
                         holeIndex: c.holeIndex, createdAt: c.createdAt)
        }
        s.names = Dictionary(snapshot.players.map { p in
            let entrant = directory.entrant(p.memberID, competitionClub: club)
            return (entrant.id, directory.name(entrant, fallback: snapshot.names[p.memberID]))
        }, uniquingKeysWith: { first, _ in first })
        s.rules = competition.rules
        return s
    }

    // MARK: Grunnlaget for tabellen

    /// Grunnlaget for Tavla når konkurransen eies av en klubb og teller klubbens tropp, som jakkeracet:
    /// sesongens navn, status og regler fra konkurransen, hele troppen, og rundene som teller.
    /// Nil for andre konkurranser (de har ikke en tropp å vise); bruk `input` og `CompetitionBoard`.
    func tavlaInput(members: [ClubMemberRow], candidates: [RoundSnapshot]) -> TavlaInput? {
        guard let club = competition.clubID, competition.entry == .club else { return nil }
        let season = SeasonRow(id: competition.seasonID ?? competition.id, clubID: club, name: competition.name,
                               status: competition.status, rules: competition.rules)
        let rounds = countedRounds(candidates).map { snapshot -> RoundSnapshot in
            var s = snapshot
            s.rules = competition.rules
            return s
        }
        return TavlaInput(season: season, members: members.filter { $0.clubID == club }, rounds: rounds)
    }

    /// Grunnlaget for en hvilken som helst konkurranse: tellende runder med spillerne gitt id etter
    /// personen bak, og hvem som står i tabellen.
    func input(candidates: [RoundSnapshot], directory: PersonDirectory) -> CompetitionInput {
        let counted = countedRounds(candidates)
        let entrants = entrants(counted: counted, directory: directory)
        let rounds = counted.map { rekeyed($0, directory: directory) }
        let names = Dictionary(rounds.flatMap { $0.names.map { ($0.key, $0.value) } }, uniquingKeysWith: { first, _ in first })
        let roster = entrants.map { e in
            Player(id: e.key, name: directory.name(e, fallback: names[e.id]),
                   handicap: handicap(e, directory: directory), seedGroup: seedGroup(e, directory: directory))
        }
        return CompetitionInput(competition: competition, entrants: entrants, roster: roster, rounds: rounds)
    }

    private func handicap(_ e: Entrant, directory: PersonDirectory) -> Double? {
        switch e {
        case .member(let id): directory.members[id]?.handicapIndex
        case .profile(let id): directory.profiles[id]?.handicapIndex
        case .guest(let id): directory.participants[id]?.handicapIndex ?? directory.members[id]?.handicapIndex
        }
    }

    private func seedGroup(_ e: Entrant, directory: PersonDirectory) -> Int? {
        if case .member(let id) = e { return directory.members[id]?.seedGroup }
        return nil
    }
}

/// Det en konkurranses tabell regnes av.
nonisolated struct CompetitionInput: Sendable {
    let competition: CompetitionRow
    let entrants: [Entrant]
    /// Spillerne i tabellen, i norsk navnerekkefølge. `Player.id` = `Entrant.key`.
    let roster: [Player]
    /// Tellende runder i tidsrekkefølge, med spiller-id-er etter personen bak.
    let rounds: [RoundSnapshot]
}

/// Tabellen for en konkurranse, regnet av GolfgutuCore etter konkurransens regelsett, på samme måte
/// som Tavla: hver runde med handicapet som ble frosset i den.
nonisolated enum CompetitionBoard {
    static func season(_ input: CompetitionInput) -> Season {
        Season(players: input.roster,
               rounds: input.rounds.map(RoundGame.makeRound),
               claims: input.rounds.flatMap(\.sideClaims).map(TavlaStandings.claim),
               ruleset: input.competition.rules,
               playingHandicaps: TavlaStandings.playingHandicaps(input.rounds))
    }

    static func rows(_ input: CompetitionInput) -> [Season.JacketRow] {
        season(input).jacketBoard()
    }
}
