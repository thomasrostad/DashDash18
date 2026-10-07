import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Fase 15: flere konkurranser samtidig. Tabellen for liga og morro via `CompetitionScope`, cuptreet
/// fra radene i 022, hvem som ser og kan melde seg på, «Teller også i …», morrokvelder og «Ny
/// konkurranse». Motoren selv er testet i GolfgutuCore (CompetitionsTests, konkurranser.json).
@MainActor private enum F {
    static func id(_ n: Int) -> UUID { TavlaSamples.id(n) }

    static let club = TavlaSamples.club
    static let otherClub = id(9100)
    static let me = id(800)
    static let friend = id(801)
    static let stranger = id(802)

    static func competition(_ n: Int, kind: CompetitionKind, club: UUID? = F.club, owner: UUID? = nil,
                            entry: CompetitionEntry = .listed, status: SeasonStatus = .active, signup: Bool? = true,
                            starts: String? = nil, ends: String? = nil, rules: Ruleset = .golfgutu,
                            name: String? = nil) -> CompetitionRow {
        CompetitionRow(id: id(n), kind: kind, name: name ?? "K\(n)", clubID: club, ownerID: owner, seasonID: nil,
                       status: status, entry: entry, rules: rules, startsOn: starts, endsOn: ends, isMain: false,
                       requiresPurchase: false, entitlementID: nil, signupOpen: signup)
    }

    static func participant(_ n: Int, _ c: CompetitionRow, member: UUID? = nil, profile: UUID? = nil,
                            status: CompetitionParticipantRow.Status = .active) -> CompetitionParticipantRow {
        CompetitionParticipantRow(id: id(n), competitionID: c.id, memberID: member, profileID: profile, status: status)
    }

    /// Spiller i klubben (medlem 1 = deg, arrangør).
    static func access(organizer: Bool = false) -> CompetitionAccess {
        CompetitionAccess(profileID: me, memberships: [.init(clubID: club, memberID: id(1), isOrganizer: organizer,
                                                             isActive: true)])
    }

    /// Medlemmene i TavlaSamples, med innlogging for de to første.
    static var members: [ClubMemberRow] {
        var m = TavlaSamples.members
        m[0].userID = me
        m[1].userID = friend
        return m
    }
}

// MARK: - Liga og morroturnering

@MainActor struct KonkurranseLigaTests {
    static func input(kind: CompetitionKind, rules: Ruleset = .golfgutu, rounds: [RoundSnapshot],
                      entrants: [Int] = [1, 2, 3, 4]) -> CompetitionInput {
        let c = F.competition(7200, kind: kind, rules: rules)
        let participants = entrants.map { F.participant(7300 + $0, c, member: F.id($0)) }
        let links = rounds.map { CompetitionRoundRow(competitionID: c.id, roundID: $0.round.id, source: .manual) }
        let scope = CompetitionScope(competition: c, links: links, participants: participants)
        return scope.input(candidates: rounds, directory: PersonDirectory(members: TavlaSamples.members))
    }

    static let rounds = (1...3).map { TavlaSamples.round($0, date: "2026-10-0\($0)") }

    /// Morromalen teller stablefordpoengene rett fram: summen er den samme som jakkeracetets
    /// stablefordsum over de samme rundene (Golfgutu teller beste 5, og her er det 3).
    @Test func morroErStablefordsummen() {
        let input = Self.input(kind: .fun, rounds: Self.rounds)
        let league = LeagueStandings(input, me: [.member(F.id(1))])
        let season = CompetitionBoard.season(input)
        #expect(league.rows.count == 4)
        for row in league.rows {
            #expect(row.total == Double(season.stablefordTotal(for: row.entrant.key)), "\(row.name)")
            #expect(row.played == 3)
            #expect(row.results.map(\.roundID) == Self.rounds.map(\.round.id.uuidString))
        }
        #expect(league.rows.first { $0.isMe }?.entrant == .member(F.id(1)))
        // Synkende poeng.
        #expect(league.rows.map(\.total) == league.rows.map(\.total).sorted(by: >))
        #expect(league.roundTitles[Self.rounds[0].round.id.uuidString] == "1. okt · Marco Simone")
    }

    /// Ligamalen: plasseringspoeng blant de påmeldte, med stablefordpoengene fra regelmotoren.
    @Test func ligaGirPlasseringspoeng() {
        let input = Self.input(kind: .league, rounds: Self.rounds)
        let league = LeagueStandings(input, me: [])
        let season = CompetitionBoard.season(input)
        for (i, _) in Self.rounds.enumerated() {
            let points = season.roundPoints(i).filter { key, _ in input.roster.contains { $0.id == key } }
            let expected = League.placings(.init(id: "", stableford: points), entrants: Set(points.keys), rules: .league)
            for row in league.rows {
                let result = row.results[i]
                #expect(result.points == expected[row.entrant.key]?.points)
                #expect(result.stableford == points[row.entrant.key])
            }
        }
        // 4 påmeldte i 3 runder: hver runde deler ut 10 + 8 + 6 + 5 og 1 for å spille.
        #expect(league.rows.reduce(0) { $0 + $1.total } == 3 * (29 + 4))
        #expect(league.rulesSummary == "Plassering 10–8–6 … · + 1 for å spille · alle runder teller")
    }

    @Test func besteNRunderFraRegelsettet() {
        var rules = Ruleset.golfgutu
        rules.competition = CompetitionRules(league: LeagueRules(scoring: .placement, placementPoints: [3, 2, 1],
                                                                 participationPoints: 0, bestRounds: 2, tiebreaks: [.wins]))
        let league = LeagueStandings(Self.input(kind: .league, rules: rules, rounds: Self.rounds), me: [])
        for row in league.rows {
            #expect(row.results.filter(\.counted).count == 2)
            #expect(row.total == row.results.filter(\.counted).reduce(0) { $0 + $1.points })
        }
        #expect(league.detail(league.rows[0]).contains("beste 2 teller"))
    }

    @Test func forForsteRunde() {
        let league = LeagueStandings(Self.input(kind: .league, rounds: []), me: [])
        #expect(!league.hasResults)
        #expect(league.rows.map(\.name) == ["Bjørn", "Knut", "Kåre", "Lars"])
        #expect(league.placeText(league.rows[0]) == "–")
        #expect(league.detail(league.rows[0]) == "Ingen runder ennå")
    }

    @Test func poengtekst() {
        #expect(LeagueStandings.points(11) == "11")
        #expect(LeagueStandings.points(6.5) == "6,5")
        #expect(LeagueStandings.points(19.0 / 3) == "6,33")
    }
}

// MARK: - Cup

@MainActor struct KonkurranseCupTests {
    static let cup = F.competition(7400, kind: .cup)
    /// Fem påmeldte: p1–p5.
    static let participants = (1...5).map { F.participant(7400 + $0, cup, member: F.id($0)) }
    static var names: [UUID: String] {
        Dictionary(uniqueKeysWithValues: participants.enumerated().map { ($1.id, TavlaSamples.names[$0]) })
    }

    static func p(_ n: Int) -> UUID { F.id(7400 + n) }

    static func match(_ round: Int, _ slot: Int, _ a: Int?, _ b: Int?, winner: Int? = nil, walkover: Bool = false,
                      result: String? = nil) -> CompetitionMatchRow {
        CompetitionMatchRow(id: F.id(7500 + round * 10 + slot), competitionID: cup.id, roundNo: round, slot: slot,
                            playerA: a.map(p), playerB: b.map(p), winner: winner.map(p), walkover: walkover,
                            result: result, roundID: nil)
    }

    /// Trekningen slik draw_cup lagrer den: seed 1–5 = p1–p5, byes til 1, 2 og 3.
    static let drawn = [match(1, 0, 1, nil, winner: 1), match(1, 1, 4, 5), match(1, 2, 2, nil, winner: 2),
                        match(1, 3, 3, nil, winner: 3)]

    @Test func treetFraRadene() {
        let drawn = CupStandings(participants: Self.participants, matches: Self.drawn, names: Self.names, me: [Self.p(1)])
        #expect(drawn.rounds.count == 3)
        #expect(drawn.roundTitles == ["Kvartfinale", "Semifinale", "Finale"])
        #expect(drawn.rounds[0].map { $0.a?.name } == ["Bjørn", "Knut", "Lars", "Kåre"])
        #expect(drawn.rounds[0].map(\.isBye) == [true, false, true, true])
        // Seedene følger plassene: 1, 4/5, 2, 3.
        #expect(drawn.rounds[0][1].a?.seed == 4 && drawn.rounds[0][1].b?.seed == 5)
        // Du (seed 1) har bye og venter på vinneren av 4 mot 5.
        #expect(drawn.rounds[1][0].a?.name == "Bjørn" && drawn.rounds[1][0].b == nil)
        #expect(drawn.rounds[1][0].state == .waiting)
        #expect(drawn.myNext?.id == "2:0")

        var rows = Self.drawn
        rows[1] = Self.match(1, 1, 4, 5, winner: 5, result: "2&1")
        let cup = CupStandings(participants: Self.participants, matches: rows, names: Self.names, me: [Self.p(1)])
        #expect(cup.rounds[0][1].result == "2&1" && cup.rounds[0][1].winnerSide?.name == "Ola")
        #expect(cup.rounds[1][0].b?.name == "Ola" && cup.rounds[1][0].state == .ready)
        #expect(cup.myNext?.id == "2:0" && cup.myNext?.b?.name == "Ola")
        #expect(cup.champion == nil)
    }

    @Test func mesterOgWalkover() {
        var rows = Self.drawn
        rows[1] = Self.match(1, 1, 4, 5, winner: 4, result: "1 opp")
        rows += [
            Self.match(2, 0, 1, 4, winner: 4, walkover: true),
            Self.match(2, 1, 2, 3, winner: 2, result: "3&2"),
            Self.match(3, 0, 4, 2, winner: 2, result: "19. hull"),
        ]
        let cup = CupStandings(participants: Self.participants, matches: rows, names: Self.names, me: [Self.p(1)])
        #expect(cup.champion?.name == "Lars")
        #expect(cup.rounds[1][0].walkover)
        #expect(cup.rounds[2][0].result == "19. hull")
        // Du (p1) tapte på walkover: ingen neste kamp.
        #expect(cup.myNext == nil)
        #expect(cup.bracket.isEliminated(Self.p(1).uuidString))
    }

    @Test func ikkeTrukket() {
        let cup = CupStandings(participants: Self.participants, matches: [], names: Self.names, me: [])
        #expect(!cup.isDrawn)
        #expect(cup.myNext == nil)
    }

    /// Seeding på handicap (lavest først) til påmeldings-id-er, med bye til de beste.
    @Test func trekningPaHandicap() {
        let handicaps = Dictionary(uniqueKeysWithValues: Self.participants.enumerated().map {
            ($1.id, TavlaSamples.members[$0].handicapIndex ?? 0)
        })
        var participants = Self.participants
        participants.append(F.participant(7409, Self.cup, member: F.id(6), status: .withdrawn))
        let pairings = CupStandings.pairings(participants: participants, names: Self.names, handicaps: handicaps,
                                             ranks: [:], rules: CupRules(seeding: .handicap, tie: .suddenDeath), seed: 1)
        // Handicap 8, 10, 12, 14, 16 = p1 … p5. Den som har meldt seg av, er ikke med.
        #expect(pairings == [CupPairingParam(slot: 0, a: Self.p(1), b: nil),
                             CupPairingParam(slot: 1, a: Self.p(4), b: Self.p(5)),
                             CupPairingParam(slot: 2, a: Self.p(2), b: nil),
                             CupPairingParam(slot: 3, a: Self.p(3), b: nil)])
        // Rangering går foran handicap.
        let ranked = CupStandings.pairings(participants: Self.participants, names: Self.names, handicaps: handicaps,
                                           ranks: [Self.p(5): 1], rules: CupRules(seeding: .ranking, tie: .suddenDeath),
                                           seed: 1)
        #expect(ranked.first == CupPairingParam(slot: 0, a: Self.p(5), b: nil))
    }

    /// Forslaget fra runden er det samme som matchspillet i regelmotoren for de to.
    @Test func forslagFraRunden() throws {
        let round = TavlaSamples.round(1, date: "2026-10-01")
        let c = Self.cup
        let links = [CompetitionRoundRow(competitionID: c.id, roundID: round.round.id, source: .manual)]
        let scope = CompetitionScope(competition: c, links: links, participants: Self.participants)
        let directory = PersonDirectory(members: TavlaSamples.members)
        let input = scope.input(candidates: [round], directory: directory)
        let cup = CupStandings(participants: Self.participants, matches: Self.drawn, names: Self.names, me: [])
        let game = cup.rounds[0][1]  // p4 mot p5
        let byID = Dictionary(uniqueKeysWithValues: Self.participants.map { ($0.id, $0) })
        let s = try #require(CupStandings.suggestion(for: game, input: input) { id in
            byID[id].flatMap { scope.entrant(for: $0, directory: directory) }
        })
        #expect(s.roundID == round.round.id)
        let g = RoundGame(round)
        let a = F.id(4).uuidString, b = F.id(5).uuidString
        let st = try #require(MatchPlay.standing(Match(playerA: a, playerB: b), from: a, in: g.round, roster: g.roster,
                                                 rules: .golfgutu))
        switch s.decision {
        case .won(let w, let up, _, nil):
            #expect(st.up != 0 && w == (st.up > 0 ? a : b) && up == abs(st.up))
        case .tied:
            #expect(st.up == 0)
        default:
            Issue.record("Uventet: \(s.decision)")
        }
        // De har ikke spilt sammen: ingen forslag.
        let other = CupStandings.suggestion(for: game, input: scope.input(candidates: [], directory: directory)) { _ in nil }
        #expect(other == nil)
    }

    @Test func resultattekst() {
        #expect(CompetitionText.cupResult(.won(winner: "a", up: 3, remaining: 2, tie: nil)) == "3&2")
        #expect(CompetitionText.cupResult(.won(winner: "a", up: 1, remaining: 0, tie: nil)) == "1 opp")
        #expect(CompetitionText.cupResult(.won(winner: "a", up: 0, remaining: 0, tie: .countback))
                == "Likt, avgjort: siste hull som ikke var delt")
        #expect(CompetitionText.cupResult(.inProgress(up: -2, played: 7, remaining: 11)) == "2 ned etter 7")
        #expect(CompetitionText.cupResult(.notStarted) == nil)
        #expect(CompetitionText.cupRound(1, of: 4) == "1. runde")
    }
}

// MARK: - Hvem ser, styrer og kan melde seg på

@MainActor struct KonkurranseTilgangTests {
    @Test func klubbensKonkurranse() {
        let c = F.competition(7600, kind: .league)
        let player = F.access(), organizer = F.access(organizer: true)
        #expect(player.canSee(c, []))
        #expect(!player.isAdmin(c) && organizer.isAdmin(c))
        #expect(player.signup(c, [], isDrawn: false) == .open)
        let entered = [F.participant(7601, c, member: F.id(1))]
        #expect(player.signup(c, entered, isDrawn: false) == .entered)
        // Meldt av: kan melde seg på igjen.
        let withdrawn = [F.participant(7601, c, member: F.id(1), status: .withdrawn)]
        #expect(player.signup(c, withdrawn, isDrawn: false) == .open)
        // Påmeldt som profil teller også.
        #expect(player.signup(c, [F.participant(7602, c, profile: F.me)], isDrawn: false) == .entered)
    }

    @Test func stengtPamelding() {
        let a = F.access()
        #expect(a.signup(F.competition(7610, kind: .fun, signup: false), [], isDrawn: false) == .closed)
        #expect(a.signup(F.competition(7611, kind: .fun, signup: nil), [], isDrawn: false) == .closed)
        #expect(a.signup(F.competition(7612, kind: .fun, status: .finished), [], isDrawn: false) == .closed)
        #expect(a.signup(F.competition(7613, kind: .cup), [], isDrawn: true) == .closed)
        #expect(a.signup(F.competition(7614, kind: .cup), [], isDrawn: false) == .open)
        #expect(a.signup(F.competition(7615, kind: .fun, entry: .club), [], isDrawn: false) == .notNeeded)
        #expect(a.signup(F.competition(7616, kind: .fun, entry: .open), [], isDrawn: false) == .notNeeded)
        // En annen klubbs konkurranse ser du ikke.
        let other = F.competition(7617, kind: .fun, club: F.otherClub)
        #expect(!a.canSee(other, []) && a.signup(other, [], isDrawn: false) == .closed)
        // Ventende medlem ser ikke klubbens konkurranser.
        let pending = CompetitionAccess(profileID: F.me, memberships: [.init(clubID: F.club, memberID: F.id(1),
                                                                              isOrganizer: true, isActive: false)])
        let c = F.competition(7618, kind: .fun)
        #expect(!pending.canSee(c, []) && !pending.isAdmin(c) && !pending.canCreate(inClub: F.club))
    }

    @Test func privatKonkurranse() {
        let mine = F.competition(7620, kind: .fun, club: nil, owner: F.me)
        let theirs = F.competition(7621, kind: .fun, club: nil, owner: F.friend)
        let a = F.access()
        #expect(a.canSee(mine, []) && a.isAdmin(mine))
        #expect(!a.canSee(theirs, []) && !a.isAdmin(theirs))
        // Påmeldt i en annens: du ser den, men styrer den ikke.
        let entered = [F.participant(7622, theirs, profile: F.me)]
        #expect(a.canSee(theirs, entered) && !a.isAdmin(theirs))
        #expect(a.signup(theirs, entered, isDrawn: false) == .entered)
        #expect(a.canCreate(inClub: nil) && !a.canCreate(inClub: F.club) && F.access(organizer: true).canCreate(inClub: F.club))
        #expect(a.myEntrants == [.member(F.id(1)), .profile(F.me)])
    }
}

// MARK: - «Teller også i …»

@MainActor struct KonkurranseTellerOgsaTests {
    static let clubPlayers = [1, 2, 3].map {
        CompetitionLinking.Player(playerID: F.id($0), clubID: F.club, profileID: F.members[$0 - 1].userID)
    }

    @Test func hvemErMed() {
        let listed = F.competition(7700, kind: .fun)
        let parts = [F.participant(7701, listed, member: F.id(2)), F.participant(7702, listed, profile: F.me),
                     F.participant(7703, listed, member: F.id(3), status: .withdrawn)]
        // Medlem 2 (medlem), medlem 1 (profilen hans er påmeldt), ikke 3 (meldt av).
        #expect(CompetitionLinking.entrantCount(listed, participants: parts, members: F.members,
                                                players: Self.clubPlayers) == 2)
        #expect(CompetitionLinking.entrantCount(F.competition(7704, kind: .fun, entry: .open), participants: [],
                                                members: F.members, players: Self.clubPlayers) == 3)
        #expect(CompetitionLinking.entrantCount(F.competition(7705, kind: .fun, entry: .club), participants: [],
                                                members: F.members, players: Self.clubPlayers) == 3)
        // En løs runde: deg og vennen (profiler) og en gjest. Klubbkonkurransen kjenner profilene i troppen.
        let loose = [CompetitionLinking.Player(playerID: F.id(900), clubID: nil, profileID: F.me),
                     CompetitionLinking.Player(playerID: F.id(901), clubID: nil, profileID: F.friend),
                     CompetitionLinking.Player(playerID: F.id(902), clubID: nil, profileID: nil)]
        #expect(CompetitionLinking.entrantCount(F.competition(7706, kind: .fun, entry: .club), participants: [],
                                                members: F.members, players: loose) == 2)
        #expect(CompetitionLinking.entrantCount(listed, participants: parts, members: F.members, players: loose) == 2)
        // Medlem 2 er påmeldt som medlem; i en løs runde er han profilen sin (friend).
        let onlyMember2 = [F.participant(7707, listed, member: F.id(2))]
        #expect(CompetitionLinking.entrantCount(listed, participants: onlyMember2, members: F.members, players: loose) == 1)
    }

    @Test func kandidaterBareDuStyrerOgSomPasser() {
        let organizer = F.access(organizer: true)
        let comps = [
            F.competition(7710, kind: .league, name: "Torsdagsligaen"),
            F.competition(7711, kind: .fun, club: F.otherClub, name: "Andre klubbs"),
            F.competition(7712, kind: .cup, status: .finished, name: "Ferdig cup"),
            F.competition(7713, kind: .fun, entry: .open, name: "Åpen morro"),
            F.competition(7714, kind: .season, entry: .club, name: "Jakkeracet"),
            F.competition(7715, kind: .fun, name: "Tom morro"),
            F.competition(7716, kind: .fun, club: nil, owner: F.me, entry: .open, name: "Min private"),
        ]
        let parts = [F.participant(7720, comps[0], member: F.id(1)), F.participant(7721, comps[1], member: F.id(1))]
        let candidates = CompetitionLinking.candidates(competitions: comps, participants: parts, members: F.members,
                                                       access: organizer, players: Self.clubPlayers)
        #expect(candidates.map(\.competition.name) == ["Min private", "Torsdagsligaen", "Åpen morro"])
        #expect(candidates.map(\.coverage) == ["Alle er med", "1 av 3 er med", "Alle er med"])
        // En spiller (ikke arrangør) styrer bare sin private.
        let player = CompetitionLinking.candidates(competitions: comps, participants: parts, members: F.members,
                                                   access: F.access(), players: Self.clubPlayers)
        #expect(player.map(\.competition.name) == ["Min private"])
        // Lista til databasen: bare de valgte blant kandidatene.
        #expect(CompetitionLinking.selection([F.id(7710), F.id(7712), F.id(7713)], among: candidates)
                == [F.id(7710), F.id(7713)])
    }
}

// MARK: - Morrokvelder på Kveld

@MainActor struct KonkurranseKveldTests {
    @Test func morroturneringerPaKvelden() {
        let comps = [
            F.competition(7800, kind: .fun, starts: "2026-10-01", ends: "2026-10-31", name: "Oktobermorro"),
            F.competition(7801, kind: .fun, starts: "2026-11-01", name: "Novembermorro"),
            F.competition(7802, kind: .fun, status: .finished, starts: "2026-10-01", name: "Ferdig"),
            F.competition(7803, kind: .league, starts: "2026-10-01", name: "Liga"),
            F.competition(7804, kind: .fun, club: nil, owner: F.me, starts: "2026-10-01", name: "Privat"),
            F.competition(7805, kind: .fun, club: nil, owner: F.me, name: "Privat med runde"),
        ]
        let links = [CompetitionRoundRow(competitionID: F.id(7805), roundID: F.id(50), source: .manual)]
        #expect(CompetitionCalendar.funNames(eventDate: "2026-10-15", eventClubID: F.club, roundIDs: [F.id(50)],
                                             competitions: comps, links: links) == ["Oktobermorro", "Privat med runde"])
        #expect(CompetitionCalendar.funNames(eventDate: "2026-11-05", eventClubID: F.club, roundIDs: [],
                                             competitions: comps, links: links) == ["Novembermorro"])
        #expect(CompetitionCalendar.funNames(eventDate: "2026-10-31", eventClubID: F.otherClub, roundIDs: [],
                                             competitions: comps, links: links).isEmpty)
    }
}

// MARK: - Ny konkurranse

@MainActor struct KonkurranseNyTests {
    @Test func manglerOgRettOpp() {
        var d = CompetitionDraft(clubID: F.club, today: "2026-10-07")
        #expect(d.issues() == ["Gi konkurransen et navn."])
        d.name = "  Høstcupen "
        #expect(d.issues().isEmpty)
        d.hasPeriod = true
        d.endsOn = "2026-10-01"
        #expect(d.issues() == ["Perioden slutter før den starter."])
        d.endsOn = "2026-10-31"
        // Cup: bare påmeldte, og «hele troppen» rettes opp.
        d.entry = .club
        d.kind = .cup
        d.normalize()
        #expect(d.entry == .listed && d.entryOptions == [.listed])
        d.signupOpen = false
        #expect(d.issues() == ["En cup trenger minst to påmeldte, eller åpen påmelding."])
        d.memberIDs = [F.id(1), F.id(2)]
        #expect(d.issues().isEmpty)
        // Privat: ingen medlemmer, ingen «hele troppen», ingen kopi av hovedturneringen.
        d.kind = .fun
        d.entry = .club
        d.rulesSource = .copyMain
        d.clubID = nil
        d.normalize()
        #expect(d.memberIDs.isEmpty && d.entry == .listed && d.rulesSource == .template)
        #expect(d.entryOptions == [.listed, .open])
        d.entry = .open
        d.normalize()
        #expect(!d.signupOpen)
    }

    @Test func regelsettOgParametre() throws {
        var main = Ruleset.golfgutu
        main.evenings = 5
        main.table.counting = .init(unit: .evening, best: 3)
        var d = CompetitionDraft(clubID: F.club, today: "2026-10-07")
        d.name = "Torsdagsligaen"
        d.kind = .league
        d.leagueRules.bestRounds = 4
        d.leagueRules.scoring = .stableford
        d.rulesSource = .copyMain
        d.memberIDs = [F.id(2), F.id(1)]
        d.profileIDs = [F.friend]
        let rules = d.rules(main: main)
        #expect(rules.evenings == 5 && rules.table.counting == main.table.counting)
        #expect(rules.competitionRules.league.bestRounds == 4 && rules.competitionRules.league.scoring == .stableford)
        #expect(rules.competitionRules.fun == .fun && rules.competitionRules.cup == .standard)
        // Malen er Golfgutu-oppsettet, med konkurransereglene i tillegg.
        d.rulesSource = .template
        var template = d.rules(main: main)
        #expect(template.competition != nil)
        template.competition = nil
        #expect(template == .golfgutu)

        let p = d.params(main: main)
        #expect(p.p_kind == "league" && p.p_name == "Torsdagsligaen" && p.p_club_id == F.club && p.p_entry == "listed")
        #expect(p.p_starts_on == nil && p.p_signup_open)
        #expect(p.p_member_ids == [F.id(1), F.id(2)] && p.p_profile_ids == [F.friend])
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        #expect(json["p_club_id"] as? String == F.club.uuidString)
        #expect((json["p_rules"] as? [String: Any])?["competition"] != nil)
        // Privat og «alle som spiller»: ingen medlemmer, ingen påmelding.
        d.clubID = nil
        d.entry = .open
        d.hasPeriod = true
        let q = d.params(main: nil)
        #expect(q.p_club_id == nil && q.p_member_ids.isEmpty && !q.p_signup_open && q.p_starts_on == "2026-10-07")
    }

    @Test func flaggeneErAv() {
        #expect(!CompetitionsFeature.isEnabled)
        #expect(!PurchaseFeature.isEnabled)
        // Med kjøp av er alt låst opp, som før.
        #expect(CompetitionPurchase.isUnlocked(kind: .cup, clubID: nil, userID: F.me, entitlements: []))
    }
}

// MARK: - Kjøp: bare liga og cup (besluttet 07.10.2026)

/// Kjøpene fra serveren uten nett, for `PurchaseService`.
nonisolated private struct FakePurchaseBackend: PurchaseBackend {
    let rows: [EntitlementRow]
    func verify(transactionID: UInt64, competitionID: UUID?, clubID: UUID?) async throws -> EntitlementRow {
        throw PurchaseError.offline
    }
    func entitlements() async throws -> [EntitlementRow] { rows }
    func assign(entitlementID: UUID, competitionID: UUID) async throws {}
    func isUnlocked(competitionID: UUID) async throws -> Bool { false }
}

@MainActor struct KonkurranseKjopTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func entitlement(kind: String = "consumable", competition: UUID? = nil, club: UUID? = nil,
                     expires: Date? = nil, status: EntitlementRow.Status = .active) -> EntitlementRow {
        EntitlementRow(id: UUID(), profileID: F.me, clubID: club, competitionID: competition,
                       productID: kind == "consumable" ? PurchaseProduct.tournament.rawValue : PurchaseProduct.yearly.rawValue,
                       productKind: kind, status: status, expiresAt: expires)
    }

    func unlocked(_ kind: CompetitionKind, club: UUID? = nil, _ e: [EntitlementRow]) -> Bool {
        CompetitionPurchase.isUnlocked(kind: kind, clubID: club, userID: F.me, entitlements: e, enabled: true, now: now)
    }

    /// Samme liste som triggeren i sql/023.
    @Test func bareLigaOgCupKreverKjop() {
        #expect(CompetitionPurchase.requiresPurchase(.league))
        #expect(CompetitionPurchase.requiresPurchase(.cup))
        #expect(!CompetitionPurchase.requiresPurchase(.fun))
        #expect(!CompetitionPurchase.requiresPurchase(.season))
        #expect(!CompetitionPurchase.requiresPurchase(.game))
    }

    @Test func morroErGratisLigaOgCupLaast() {
        #expect(unlocked(.fun, []))
        #expect(!unlocked(.league, []))
        #expect(!unlocked(.cup, club: F.club, []))
        // Med kjøp av: alt låst opp.
        #expect(CompetitionPurchase.isUnlocked(kind: .cup, clubID: nil, userID: F.me, entitlements: [], enabled: false))
    }

    @Test func abonnementEllerKredittLaserOpp() {
        let later = now.addingTimeInterval(3600)
        let personal = entitlement(kind: "subscription", expires: later)
        let forClub = entitlement(kind: "subscription", club: F.club, expires: later)
        let expired = entitlement(kind: "subscription", expires: now.addingTimeInterval(-1))
        #expect(unlocked(.cup, [personal]))
        #expect(!unlocked(.cup, club: F.club, [personal]))
        #expect(unlocked(.league, club: F.club, [forClub]))
        #expect(!unlocked(.league, [forClub]))
        #expect(!unlocked(.league, [expired]))
        // Et kjøp som ikke er koblet (kreditt), låser opp den neste. Et brukt eller refundert gjør ikke.
        #expect(unlocked(.cup, [entitlement()]))
        #expect(!unlocked(.cup, [entitlement(competition: UUID())]))
        #expect(!unlocked(.cup, [entitlement(status: .refunded)]))
    }

    @Test func kredittenKoblesBareNarDenTrengs() {
        let credit = entitlement()
        let sub = entitlement(kind: "subscription", expires: now.addingTimeInterval(3600))
        func needs(_ kind: CompetitionKind, _ e: [EntitlementRow], enabled: Bool = true) -> Bool {
            CompetitionPurchase.needsCredit(kind: kind, clubID: nil, userID: F.me, entitlements: e, enabled: enabled, now: now)
        }
        #expect(needs(.cup, [credit]))
        #expect(!needs(.cup, [credit, sub]))
        #expect(!needs(.fun, [credit]))
        #expect(!needs(.cup, []))
        #expect(!needs(.cup, [credit], enabled: false))
    }

    @Test func tekstenINyKonkurranse() {
        #expect(CompetitionPurchase.note(.cup, enabled: false) == nil)
        #expect(CompetitionPurchase.note(.league, enabled: true)?.contains("krever kjøp") == true)
        #expect(CompetitionPurchase.note(.fun, enabled: true) == "Gratis å lage og kjøre.")
    }

    /// Koblingen til fase 17: kjøpene som `PurchaseService` har hentet.
    @Test func brukerKjopenePurchaseServiceHarHentet() async {
        let service = PurchaseService(backend: FakePurchaseBackend(rows: [entitlement()]), profileID: F.me)
        #expect(!CompetitionPurchase.isUnlocked(kind: .cup, clubID: nil, userID: F.me, purchases: service, enabled: true))
        await service.refreshEntitlements()
        #expect(CompetitionPurchase.isUnlocked(kind: .cup, clubID: nil, userID: F.me, purchases: service, enabled: true))
        #expect(!CompetitionPurchase.isUnlocked(kind: .cup, clubID: nil, userID: F.me, purchases: nil, enabled: true))
        #expect(CompetitionPurchase.isUnlocked(kind: .fun, clubID: nil, userID: F.me, purchases: nil, enabled: true))
    }

    /// «Ny konkurranse» viser betalingsveggen bare når typen er låst.
    @Test func nyKonkurranseTrengerKjop() {
        let list = CompetitionsModel(preview: .init(), access: F.access(organizer: true), clubID: F.club, clubName: "Golfgutu")
        var d = CompetitionDraft(clubID: F.club, today: "2026-10-07")
        d.kind = .fun
        #expect(!list.needsPurchase(d, purchases: nil))
        d.kind = .cup
        // Med PurchaseFeature av: ingen betalingsvegg.
        #expect(list.needsPurchase(d, purchases: nil) == PurchaseFeature.isEnabled)
    }
}

// MARK: - Invitasjon til en privat konkurranse (sql/022)

@MainActor struct KonkurranseInvitasjonTests {
    @Test func lenkenTilKonkurransen() throws {
        let code = try #require(InviteCode("ABCDEFGH23"))
        let target = InviteTarget.competition(name: "Vennecupen")
        #expect(target.url(code).absoluteString == "dashdash://konkurranse/ABCDEFGH23")
        #expect(InviteCode(url: target.url(code), host: InviteTarget.competitionHost) == code)
        // En rundelenke er ikke en konkurranselenke, og omvendt.
        #expect(InviteCode(url: target.url(code)) == nil)
        #expect(InviteCode(url: code.url, host: InviteTarget.competitionHost) == nil)
        #expect(InviteCode.parse(" dashdash://Konkurranse/abcde-fgh23 ", host: InviteTarget.competitionHost) == code)
        #expect(InviteCode.parse("abcde-fgh23", host: InviteTarget.competitionHost) == code)
        let text = target.shareText(code)
        #expect(text.contains("Vennecupen") && text.contains("dashdash://konkurranse/ABCDEFGH23") && text.contains("ABCDE-FGH23"))
        #expect(InviteTarget.round(courseName: "Losby").shareText(code) == code.shareText(courseName: "Losby"))
        #expect(InviteTarget.round(courseName: nil).url(code) == code.url)
    }

    @Test func appenTarImotBeggeLenkene() throws {
        let code = try #require(InviteCode("ABCDEFGH23"))
        let round = try #require(URL(string: "dashdash://runde/ABCDEFGH23"))
        let competition = try #require(URL(string: "dashdash://konkurranse/ABCDEFGH23"))
        #expect(AppLink.parse(round, rounds: true, competitions: true) == .round(code))
        #expect(AppLink.parse(competition, rounds: true, competitions: true) == .competition(code))
        // Hver lenke virker bare med flagget sitt.
        #expect(AppLink.parse(round, rounds: false, competitions: true) == nil)
        #expect(AppLink.parse(competition, rounds: true, competitions: false) == nil)
        #expect(AppLink.parse(try #require(URL(string: "dashdash://login-callback")), rounds: true, competitions: true) == nil)
        #expect(AppLink.round(code).id != AppLink.competition(code).id)
    }

    @Test func hvemKanInvitere() {
        let a = F.access()
        let mine = F.competition(7700, kind: .fun, club: nil, owner: F.me)
        let theirs = F.competition(7701, kind: .league, club: nil, owner: F.friend)
        let entered = [F.participant(7702, theirs, profile: F.me)]
        #expect(a.canInvite(mine, [], isDrawn: false))
        #expect(!a.canInvite(theirs, [], isDrawn: false))
        #expect(a.canInvite(theirs, entered, isDrawn: false))
        // Meldt av: ingen kode.
        #expect(!a.canInvite(theirs, [F.participant(7702, theirs, profile: F.me, status: .withdrawn)], isDrawn: false))
        // Klubbens deles i klubben, og ferdige og trukne cuper tar ingen nye.
        #expect(!F.access(organizer: true).canInvite(F.competition(7703, kind: .fun), [], isDrawn: false))
        #expect(!a.canInvite(F.competition(7704, kind: .fun, club: nil, owner: F.me, status: .finished), [], isDrawn: false))
        let cup = F.competition(7705, kind: .cup, club: nil, owner: F.me)
        #expect(a.canInvite(cup, [], isDrawn: false) && !a.canInvite(cup, [], isDrawn: true))
        #expect(!a.canInvite(F.competition(7706, kind: .game, club: nil, owner: F.me), [], isDrawn: false))
    }

    @Test func forhandsvisningenOgSvaret() throws {
        let json = #"""
        {"competition_id":"0a000000-0000-0000-0000-00000000000a","name":"Vennecupen","kind":"cup",
         "owner_name":"Anders","entrants":4,"entered":false}
        """#
        let p = try JSONDecoder().decode(CompetitionInvitePreview.self, from: Data(json.utf8))
        #expect(p.name == "Vennecupen" && p.kind == .cup && p.ownerName == "Anders" && !p.entered)
        #expect(p.summary == "Cup · 4 påmeldte")
        let one = CompetitionInvitePreview(competitionID: p.competitionID, name: "Morro", kind: .fun, ownerName: nil,
                                           entrants: 1, entered: true)
        #expect(one.summary == "Morroturnering · 1 påmeldt")
        let claim = try JSONDecoder().decode(CompetitionClaimResult.self, from: Data(#"""
        {"competition_id":"0a000000-0000-0000-0000-00000000000a","participant_id":"0b000000-0000-0000-0000-00000000000b","joined":"rejoined"}
        """#.utf8))
        #expect(claim.joined == .rejoined && claim.competitionID == p.competitionID)
    }

    /// Sikkerhetsrevisjonen: bare eieren fornyer og trekker tilbake koden. De påmeldte får bare
    /// koden som gjelder.
    @Test func eierenFornyerOgTrekkerTilbake() async throws {
        let first = try #require(InviteCode("ABCDEFGH23"))
        let second = try #require(InviteCode("ZYXWVTSRQ9"))
        let target = InviteTarget.competition(name: "Vennecupen")
        let participant = InviteModel(target: target) { first }
        await participant.load()
        #expect(participant.code == first && participant.manage == nil)
        await participant.revoke()
        #expect(participant.code == first && !participant.isRevoked)

        let owner = InviteModel(target: target, manage: .init(renew: { second }, revoke: {})) { first }
        await owner.load()
        await owner.revoke()
        #expect(owner.code == nil && owner.isRevoked)
        // Etter tilbaketrekking hentes ingen kode av seg selv.
        await owner.load()
        #expect(owner.code == nil)
        await owner.renew()
        #expect(owner.code == second && !owner.isRevoked)

        let refused = InviteModel(target: target, manage: .init(renew: { throw DataError.notAllowed },
                                                                revoke: { throw DataError.notAllowed })) { first }
        await refused.load()
        await refused.revoke()
        #expect(refused.code == first && !refused.isRevoked && refused.error == DataError.notAllowed.message)
    }

    @Test func kodenSkrevetInnEllerLimtInn() throws {
        let preview = CompetitionInvitePreview(competitionID: F.id(1), name: "Vennecupen", kind: .cup, ownerName: "Anders",
                                               entrants: 2, entered: false)
        let model = JoinCompetitionModel(preview: preview, code: try #require(InviteCode("ABCDEFGH23")))
        model.codeText = "dashdash://runde/ABCDEFGH23"
        #expect(model.typedCode == nil)
        model.codeText = "dashdash://konkurranse/ABCDEFGH23"
        #expect(model.typedCode?.value == "ABCDEFGH23")
        model.codeText = "abcde fgh23"
        #expect(model.typedCode?.value == "ABCDEFGH23")
    }
}

// MARK: - Resultat i cupkampen: spillerne fører selv (besluttet 07.10.2026)

@MainActor struct KonkurranseCupForingTests {
    typealias C = KonkurranseCupTests

    @Test func spillerneForerSinEgenKampEnGang() {
        // Du er p4 (mot p5 i første runde).
        let cup = CupStandings(participants: C.participants, matches: C.drawn, names: C.names, me: [C.p(4)])
        let mine = cup.rounds[0][1], bye = cup.rounds[0][0], later = cup.rounds[1][0]
        #expect(CupRecording.right(mine, isAdmin: false) == .record)
        #expect(CupRecording.right(bye, isAdmin: false) == .none)
        #expect(CupRecording.right(later, isAdmin: false) == .none)
        // Når resultatet står, kan bare arrangøren endre det.
        var rows = C.drawn
        rows[1] = C.match(1, 1, 4, 5, winner: 5, result: "2&1")
        let decided = CupStandings(participants: C.participants, matches: rows, names: C.names, me: [C.p(4)])
        #expect(CupRecording.right(decided.rounds[0][1], isAdmin: false) == .none)
        #expect(CupRecording.right(decided.rounds[0][1], isAdmin: true) == .edit)
    }

    @Test func andresKamperOgArrangoren() {
        // Du er p1 (bye): kampen p4 – p5 er ikke din.
        let cup = CupStandings(participants: C.participants, matches: C.drawn, names: C.names, me: [C.p(1)])
        #expect(CupRecording.right(cup.rounds[0][1], isAdmin: false) == .none)
        #expect(CupRecording.right(cup.rounds[0][1], isAdmin: true) == .edit)
        // Ingen fører en bye eller en kamp som venter, heller ikke arrangøren.
        #expect(CupRecording.right(cup.rounds[0][0], isAdmin: true) == .none)
        #expect(CupRecording.right(cup.rounds[1][0], isAdmin: true) == .none)
    }
}

// MARK: - Golfgutu-paritet

@MainActor struct KonkurranseParitetFase15Tests {
    /// Jakkeracetets regelsett får ingen konkurranseregler, og radene fra 017 dekodes som før.
    @Test func jakkeracetetErUrort() throws {
        let json = #"""
        {"id": "00000000-0000-0000-0000-000000007000", "kind": "season", "name": "Jakkeracet 2026",
         "club_id": "00000000-0000-0000-0000-000000009000", "owner_id": null,
         "season_id": "00000000-0000-0000-0000-000000009002", "status": "active", "entry": "club",
         "rules": {"version": 1}, "starts_on": null, "ends_on": null, "is_main": true,
         "requires_purchase": false, "entitlement_id": null}
        """#
        let row = try JSONDecoder().decode(CompetitionRow.self, from: Data(json.utf8))
        #expect(row.rules == .golfgutu && row.rules.competition == nil)
        #expect(row.signupOpen == nil && !row.isSignupOpen)
        #expect(!CompetitionRow.columns.contains("signup_open"))
        #expect(CompetitionRow.columnsWithSignup.hasSuffix(", signup_open"))
    }

    /// Velgeren på Tavla: hovedturneringen først, ferdige og andre klubbers hovedturneringer skjult.
    @Test func velgerenPaTavla() {
        var main = F.competition(7900, kind: .season, entry: .club, name: "Jakkeracet")
        main.isMain = true
        var oldMain = F.competition(7901, kind: .season, entry: .club, status: .finished, name: "Jakkeracet 2025")
        oldMain.isMain = true
        let comps = [oldMain, F.competition(7902, kind: .fun, name: "Oktobermorro"), main,
                     F.competition(7903, kind: .league, status: .finished, name: "Gammel liga"),
                     F.competition(7904, kind: .cup, status: .planned, name: "Vintercup")]
        let model = CompetitionsModel(preview: .init(competitions: comps), access: F.access(), clubID: F.club,
                                      clubName: "Golfgutu")
        #expect(model.main?.id == main.id)
        #expect(model.all.map(\.name) == ["Jakkeracet", "Oktobermorro", "Vintercup", "Gammel liga", "Jakkeracet 2025"])
        #expect(model.switcher.map(\.name) == ["Jakkeracet", "Oktobermorro", "Vintercup"])
    }
}
