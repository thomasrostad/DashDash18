import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Fase 12: konkurranser som eget lag over rundene (sql/017, docs/datamodell-v2.md). Viktigst:
/// jakkeracet regnet via konkurransen gir nøyaktig samme tabell som Tavla regner fra sesongen i dag.
/// Fixtures: `TavlaSamples` og rundene fra `TavlaTests` (seier-test.js og sesong-test.js).
@MainActor private enum K {
    static func id(_ n: Int) -> UUID { TavlaSamples.id(n) }

    /// Klubben og spillerne i `TavlaTests` (`T`): Anders, Bjørn, Cato, Dag i klubb 990, handicap 0.
    static let tClub = id(990)
    static let tMembers = [(1, "Anders"), (2, "Bjørn"), (3, "Cato"), (4, "Dag")].map { n, name in
        ClubMemberRow(id: id(n), clubID: tClub, userID: nil, displayName: name, handicapIndex: 0, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }

    /// Sesongens konkurranse slik 017 lager den: type season, hovedturnering, klubbens tropp.
    static func seasonCompetition(_ season: SeasonRow) -> CompetitionRow {
        CompetitionRow(id: id(7000), kind: .season, name: season.name, clubID: season.clubID, ownerID: nil,
                       seasonID: season.id, status: season.status, entry: .club, rules: season.rules,
                       startsOn: nil, endsOn: nil, isMain: true, requiresPurchase: false, entitlementID: nil)
    }

    static func links(_ competition: CompetitionRow, _ rounds: [RoundSnapshot]) -> [CompetitionRoundRow] {
        rounds.map { CompetitionRoundRow(competitionID: competition.id, roundID: $0.round.id, source: .season) }
    }

    /// Runder som IKKE skal telle i jakkeracet: en fra en annen sesong (ikke koblet), en kladd som er
    /// koblet (sesongens kladder kobles av triggeren), og en som er koblet til en annen konkurranse.
    static func noise(club: UUID) -> (rounds: [RoundSnapshot], links: [CompetitionRoundRow]) {
        var otherSeason = TavlaSamples.round(11, date: "2025-09-04")
        otherSeason.round = with(otherSeason.round, id: id(911), club: club)
        var draft = TavlaSamples.round(12, date: "2026-10-01", status: .draft)
        draft.round = with(draft.round, id: id(912), club: club)
        var elsewhere = TavlaSamples.round(13, date: "2026-10-02")
        elsewhere.round = with(elsewhere.round, id: id(913), club: club)
        return ([otherSeason, draft, elsewhere],
                [CompetitionRoundRow(competitionID: id(7000), roundID: id(912), source: .season),
                 CompetitionRoundRow(competitionID: id(7999), roundID: id(913), source: .manual)])
    }

    static func with(_ row: RoundRow, id: UUID, club: UUID) -> RoundRow {
        RoundRow(id: id, clubID: club, eventID: row.eventID, courseID: row.courseID, roundNo: row.roundNo, name: row.name,
                 status: row.status, holeCount: row.holeCount, firstHole: row.firstHole, teeTime: row.teeTime,
                 format: row.format, handicapAllowance: row.handicapAllowance, externalHandicap: row.externalHandicap,
                 weight: row.weight, ldEnabled: row.ldEnabled, ldHoleIndex: row.ldHoleIndex, kpEnabled: row.kpEnabled,
                 kpHoleIndex: row.kpHoleIndex, cutRule: row.cutRule, cutAfter: row.cutAfter,
                 parConfirmedBy: row.parConfirmedBy, parConfirmedAt: row.parConfirmedAt, startedAt: row.startedAt,
                 lockedAt: row.lockedAt, venue: row.venue)
    }

    /// Tavla i dag (sesongen) og Tavla via konkurransen, regnet av de samme radene pluss støy.
    static func bothWays(season: SeasonRow, members: [ClubMemberRow], rounds: [RoundSnapshot],
                         me: UUID?) -> (today: TavlaStandings, viaCompetition: TavlaStandings, scope: CompetitionScope) {
        let today = TavlaStandings(TavlaInput(season: season, members: members, rounds: rounds), me: me)
        let competition = seasonCompetition(season)
        let extra = noise(club: season.clubID)
        let scope = CompetitionScope(competition: competition, links: links(competition, rounds) + extra.links)
        // Rundene kommer i en annen rekkefølge enn sesongen hentet dem, med støy innimellom.
        let candidates = extra.rounds + rounds.reversed()
        let input = scope.tavlaInput(members: members, candidates: candidates)!
        return (today, TavlaStandings(input, me: me), scope)
    }

    /// Tabellen som sammenlignbare tall.
    static func table(_ s: TavlaStandings) -> [String] {
        s.rows.map { r in
            "\(r.place) \(r.name) \(r.memberID) \(r.total) \(r.duel) \(r.side) \(r.matches) \(r.holes) \(r.stableford) \(r.evenings) \(r.isMe)"
        }
    }

    static func board(_ rows: [Season.JacketRow]) -> [String] {
        rows.map { "\($0.player.id) \($0.total) \($0.duel) \($0.side) \($0.matches) \($0.holes) \($0.stableford)" }
    }

    static func board(_ s: TavlaStandings) -> [String] {
        s.rows.map { "\($0.memberID.uuidString) \($0.total) \($0.duel) \($0.side) \($0.matches) \($0.holes) \($0.stableford)" }
    }
}

// MARK: - Paritet: jakkeracet via konkurransen

@MainActor struct KonkurranseJakkeracetTests {
    static func expectSame(season: SeasonRow, members: [ClubMemberRow], rounds: [RoundSnapshot], me: UUID?) {
        let (today, via, scope) = K.bothWays(season: season, members: members, rounds: rounds, me: me)
        #expect(!today.rows.isEmpty)
        #expect(K.table(via) == K.table(today))
        #expect(via.rows == today.rows)
        #expect(via.snapshots.map(\.round.id) == today.snapshots.map(\.round.id))
        #expect(via.eveningsPlayed == today.eveningsPlayed && via.eveningsTotal == today.eveningsTotal)
        #expect(via.seasonName == today.seasonName && via.status == today.status && via.rules == today.rules)
        // Oppsummeringen (mester, pall, sesongens tall) og rundenavnene er de samme.
        #expect(String(describing: via.summary) == String(describing: today.summary))
        #expect(via.snapshots.indices.map(via.roundTitle) == today.snapshots.indices.map(today.roundTitle))
        // Den generelle veien (CompetitionBoard) gir samme tall som Tavla for klubbens konkurranse.
        let generic = CompetitionBoard.rows(scope.input(candidates: K.noise(club: season.clubID).rounds + rounds,
                                                        directory: PersonDirectory(members: members)))
        #expect(K.board(generic) == K.board(today))
    }

    @Test func tavlaSamplesGolfgutu() {
        let season = SeasonRow(id: TavlaSamples.id(9002), clubID: TavlaSamples.club, name: "Sesongen 2026",
                               status: .active, rules: .golfgutu)
        let rounds = (1...5).map { TavlaSamples.round($0, date: "2026-0\($0 + 4)-14") }
        Self.expectSame(season: season, members: TavlaSamples.members, rounds: rounds, me: TavlaSamples.me)
    }

    @Test func tavlaSamplesFerdigSesong() {
        let season = SeasonRow(id: TavlaSamples.id(9002), clubID: TavlaSamples.club, name: "Sesongen 2025",
                               status: .finished, rules: .golfgutu)
        let rounds = (1...3).map { TavlaSamples.round($0, date: "2025-0\($0 + 4)-14") }
        Self.expectSame(season: season, members: TavlaSamples.members, rounds: rounds, me: nil)
    }

    @Test func seierTestFireKvelder() {
        let season = SeasonRow(id: K.id(992), clubID: K.tClub, name: "Sesong 2026", status: .active, rules: .golfgutu)
        Self.expectSame(season: season, members: Array(K.tMembers.prefix(2)), rounds: TavlaRulesetTests.fourEvenings(),
                        me: K.id(1))
    }

    @Test func annetRegelsettBeste2Kvelder() {
        var rules = Ruleset.golfgutu
        rules.evenings = 5
        rules.table.counting = .init(unit: .evening, best: 2)
        let season = SeasonRow(id: K.id(992), clubID: K.tClub, name: "Sesong 2026", status: .active, rules: rules)
        Self.expectSame(season: season, members: Array(K.tMembers.prefix(2)), rounds: TavlaRulesetTests.fourEvenings(),
                        me: K.id(1))
    }

    @Test func sesongTestSyvRunderOgDuell() {
        let season = SeasonRow(id: K.id(992), clubID: K.tClub, name: "Sesong 2026", status: .active, rules: .golfgutu)
        Self.expectSame(season: season, members: K.tMembers, rounds: TavlaProfileTests.sevenRounds(withBjorn: true),
                        me: K.id(2))
        Self.expectSame(season: season, members: Array(K.tMembers.prefix(2)), rounds: [TavlaTableTests.duel()],
                        me: K.id(1))
    }

    @Test func troppenMedArkivertSomHarSpilt() {
        // Arkivert spiller som har spilt står i tabellen; ventende som ikke har spilt, gjør ikke.
        var members = TavlaSamples.members
        members[1].status = .archived
        members[2].status = .pending
        var rounds = [TavlaSamples.round(1, date: "2026-05-14")]
        rounds[0].players.removeAll { $0.memberID == members[2].id }
        rounds[0].scores.removeAll { $0.memberID == members[2].id }
        rounds[0].matches.removeAll { $0.playerA == members[2].id || $0.playerB == members[2].id }
        let season = SeasonRow(id: TavlaSamples.id(9002), clubID: TavlaSamples.club, name: "Sesongen 2026",
                               status: .active, rules: .golfgutu)
        Self.expectSame(season: season, members: members, rounds: rounds, me: TavlaSamples.me)
    }
}

// MARK: - Hvilke runder teller

@MainActor struct KonkurranseRunderTests {
    static let competition = K.seasonCompetition(SeasonRow(id: K.id(992), clubID: K.tClub, name: "S", status: .active,
                                                            rules: .golfgutu))

    @Test func baretKobledeOgStartedeRunderTeller() {
        let scope = CompetitionScope(competition: Self.competition, links: [
            CompetitionRoundRow(competitionID: K.id(7000), roundID: K.id(1), source: .season),
            CompetitionRoundRow(competitionID: K.id(7000), roundID: K.id(2), source: .season),
            CompetitionRoundRow(competitionID: K.id(7000), roundID: K.id(3), source: .manual),
            CompetitionRoundRow(competitionID: K.id(7001), roundID: K.id(4), source: .manual),
        ])
        #expect(scope.counts(RoundOriginRow(id: K.id(1), clubID: K.tClub, eventID: K.id(50), ownerID: nil, status: .locked)))
        #expect(scope.counts(RoundOriginRow(id: K.id(3), clubID: nil, eventID: nil, ownerID: K.id(60), status: .active)))
        // Kladd teller ikke, heller ikke når den er koblet.
        #expect(!scope.counts(RoundOriginRow(id: K.id(2), clubID: K.tClub, eventID: K.id(50), ownerID: nil, status: .draft)))
        // Koblet til en annen konkurranse, eller ikke koblet.
        #expect(!scope.counts(RoundOriginRow(id: K.id(4), clubID: K.tClub, eventID: K.id(50), ownerID: nil, status: .locked)))
        #expect(!scope.counts(RoundOriginRow(id: K.id(5), clubID: K.tClub, eventID: K.id(50), ownerID: nil, status: .locked)))
    }

    @Test func hjemmetTilRunden() {
        #expect(RoundOriginRow(id: K.id(1), clubID: K.tClub, eventID: K.id(50), ownerID: nil, status: .active).home
                == .club(clubID: K.tClub, eventID: K.id(50)))
        #expect(RoundOriginRow(id: K.id(1), clubID: nil, eventID: nil, ownerID: K.id(60), status: .active).home
                == .loose(ownerID: K.id(60)))
    }

    @Test func tellendeRunderITavlasRekkefolge() {
        let rounds = TavlaRulesetTests.fourEvenings()
        let scope = CompetitionScope(competition: Self.competition, links: K.links(Self.competition, rounds))
        #expect(scope.countedRounds(rounds.reversed()).map(\.round.id) == rounds.map(\.round.id))
    }
}

// MARK: - Hvem teller: samme person på tvers av runder

@MainActor struct KonkurranseDeltakereTests {
    static let golfgutu = K.id(9000), andre = K.id(9100)
    static let anders = K.id(1), andersAndre = K.id(101), carl = K.id(3), carlAndre = K.id(103)
    static let andersProfil = K.id(801)

    static func member(_ id: UUID, club: UUID, user: UUID?, name: String) -> ClubMemberRow {
        ClubMemberRow(id: id, clubID: club, userID: user, displayName: name, handicapIndex: 10, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }

    static let directory = PersonDirectory(
        members: [member(anders, club: golfgutu, user: andersProfil, name: "Anders"),
                  member(andersAndre, club: andre, user: andersProfil, name: "Anders A."),
                  member(carlAndre, club: andre, user: nil, name: "Carl")],
        participants: [
            RoundParticipantRow(id: K.id(301), roundID: K.id(30), profileID: andersProfil, displayName: "Anders", handicapIndex: 10),
            RoundParticipantRow(id: K.id(302), roundID: K.id(30), profileID: nil, displayName: "Per", handicapIndex: 12.4),
            RoundParticipantRow(id: K.id(303), roundID: K.id(30), profileID: K.id(802), displayName: "Frida", handicapIndex: 22),
        ],
        profiles: [ProfileRow(id: andersProfil, displayName: "Anders", handicapIndex: 10, avatarPath: nil),
                   ProfileRow(id: K.id(802), displayName: "Frida", handicapIndex: 22, avatarPath: nil)])

    @Test func iKlubbensEgenKonkurranseErMedlemmetMedlemmet() {
        let d = Self.directory
        #expect(d.entrant(Self.anders, competitionClub: Self.golfgutu) == .member(Self.anders))
        // Anders spiller en løs runde med profilen sin: i Golfgutus konkurranse er han fortsatt medlemmet.
        #expect(d.entrant(K.id(301), competitionClub: Self.golfgutu) == .member(Self.anders))
        // Frida er ikke medlem i Golfgutu.
        #expect(d.entrant(K.id(303), competitionClub: Self.golfgutu) == .profile(K.id(802)))
        // Medlem i en annen klubb: profilen, eller bare i runden når det ikke finnes en innlogging.
        #expect(d.entrant(Self.andersAndre, competitionClub: Self.golfgutu) == .profile(Self.andersProfil))
        #expect(d.entrant(Self.carlAndre, competitionClub: Self.golfgutu) == .guest(Self.carlAndre))
    }

    @Test func utenKlubbErDetProfilenEllerGjesten() {
        let d = Self.directory
        #expect(d.entrant(Self.anders, competitionClub: nil) == .profile(Self.andersProfil))
        #expect(d.entrant(Self.andersAndre, competitionClub: nil) == .profile(Self.andersProfil))
        #expect(d.entrant(K.id(301), competitionClub: nil) == .profile(Self.andersProfil))
        #expect(d.entrant(K.id(302), competitionClub: nil) == .guest(K.id(302)))
        #expect(d.name(.guest(K.id(302)), fallback: nil) == "Per")
        #expect(d.name(.profile(K.id(802)), fallback: nil) == "Frida")
        // Ukjent id: hører til runden.
        #expect(d.entrant(K.id(999), competitionClub: nil) == .guest(K.id(999)))
        #expect(d.entrant(K.id(999), competitionClub: Self.golfgutu) == .member(K.id(999)))
    }

    /// En konkurranse uten klubb som teller en runde i Golfgutu og en i en annen klubb, der de samme
    /// åtte spillerne er medlemmer begge steder med samme innlogging. Tabellen per person skal bli
    /// den samme som om begge rundene var spilt i én klubb.
    @Test func runderFraToStederSlaasSammenPerPerson() {
        let profiles = TavlaSamples.members.indices.map { K.id(850 + $0) }
        let golfgutu = TavlaSamples.members.enumerated().map { i, m in
            var m = m
            m.userID = profiles[i]
            return m
        }
        let other = golfgutu.enumerated().map { i, m in
            Self.member(K.id(500 + i), club: Self.andre, user: profiles[i], name: m.displayName)
        }
        let first = TavlaSamples.round(1, date: "2026-05-14")
        let secondHere = TavlaSamples.round(2, date: "2026-06-14")
        // Samme runde, men spilt i den andre klubben: medlems-id-ene byttes til den klubbens.
        let swap = Dictionary(uniqueKeysWithValues: zip(golfgutu.map(\.id), other.map(\.id)))
        let secondThere = Self.moved(secondHere, to: Self.andre, ids: swap)

        let cup = CompetitionRow(id: K.id(7100), kind: .fun, name: "Høstcup", clubID: nil, ownerID: profiles[0],
                                 seasonID: nil, status: .active, entry: .open, rules: .golfgutu, startsOn: nil,
                                 endsOn: nil, isMain: false, requiresPurchase: false, entitlementID: nil)
        let scope = CompetitionScope(competition: cup, links: [
            CompetitionRoundRow(competitionID: cup.id, roundID: first.round.id, source: .manual),
            CompetitionRoundRow(competitionID: cup.id, roundID: secondThere.round.id, source: .manual),
        ])
        let directory = PersonDirectory(members: golfgutu + other)
        let input = scope.input(candidates: [secondThere, first], directory: directory)
        #expect(input.entrants == profiles.sorted { a, b in
            let na = golfgutu[profiles.firstIndex(of: a)!].displayName, nb = golfgutu[profiles.firstIndex(of: b)!].displayName
            return NorwegianSort.areInIncreasingOrder(na, nb)
        }.map(Entrant.profile))
        #expect(input.rounds.map(\.round.id) == [first.round.id, secondThere.round.id])
        #expect(Set(input.rounds.flatMap { $0.players.map(\.memberID) }) == Set(profiles))

        // Fasit: de samme to rundene i én klubb, regnet av Tavla i dag.
        let season = SeasonRow(id: K.id(9002), clubID: TavlaSamples.club, name: "Én klubb", status: .active, rules: .golfgutu)
        let oneClub = TavlaStandings(TavlaInput(season: season, members: golfgutu, rounds: [first, secondHere]), me: nil)
        let byProfile = Dictionary(uniqueKeysWithValues: zip(golfgutu.map(\.id.uuidString), profiles.map(\.uuidString)))
        let expected = K.board(oneClub).map { line -> String in
            var parts = line.split(separator: " ").map(String.init)
            parts[0] = byProfile[parts[0]]!
            return parts.joined(separator: " ")
        }
        #expect(K.board(CompetitionBoard.rows(input)) == expected)
    }

    @Test func pameldteBestemmerHvemSomStaarITabellen() {
        let profiles = TavlaSamples.members.indices.map { K.id(850 + $0) }
        let members = TavlaSamples.members.enumerated().map { i, m in
            var m = m
            m.userID = profiles[i]
            return m
        }
        let round = TavlaSamples.round(1, date: "2026-05-14")
        let league = CompetitionRow(id: K.id(7200), kind: .league, name: "Liga", clubID: nil, ownerID: profiles[0],
                                    seasonID: nil, status: .active, entry: .listed, rules: .golfgutu, startsOn: nil,
                                    endsOn: nil, isMain: false, requiresPurchase: false, entitlementID: nil)
        let scope = CompetitionScope(
            competition: league,
            links: [CompetitionRoundRow(competitionID: league.id, roundID: round.round.id, source: .manual)],
            participants: [
                CompetitionParticipantRow(id: K.id(1), competitionID: league.id, memberID: nil, profileID: profiles[0], status: .active),
                CompetitionParticipantRow(id: K.id(2), competitionID: league.id, memberID: nil, profileID: profiles[3], status: .active),
                CompetitionParticipantRow(id: K.id(3), competitionID: league.id, memberID: nil, profileID: profiles[5], status: .withdrawn),
            ])
        let input = scope.input(candidates: [round], directory: PersonDirectory(members: members))
        #expect(Set(input.entrants) == [.profile(profiles[0]), .profile(profiles[3])])
        #expect(input.roster.map(\.name) == ["Bjørn", "Knut"])
    }

    static func moved(_ s: RoundSnapshot, to club: UUID, ids: [UUID: UUID]) -> RoundSnapshot {
        var out = s
        out.round = K.with(s.round, id: K.id(777), club: club)
        let rid = out.round.id
        out.players = s.players.map { p in
            RoundPlayerRow(roundID: rid, memberID: ids[p.memberID]!, clubID: club, handicapIndex: p.handicapIndex,
                           seedGroup: p.seedGroup, playingHandicap: p.playingHandicap, bayNo: p.bayNo,
                           isMarker: p.isMarker, teamNo: p.teamNo)
        }
        out.scores = s.scores.map { h in
            HoleScoreRow(roundID: rid, memberID: ids[h.memberID]!, holeIndex: h.holeIndex, strokes: h.strokes,
                         recordedAt: nil, updatedBy: nil, updatedAt: nil)
        }
        out.matches = s.matches.map { m in
            var m = m
            m.playerA = m.playerA.map { ids[$0]! }
            m.playerB = m.playerB.map { ids[$0]! }
            return RoundMatchRow(roundID: rid, matchNo: m.matchNo, playerA: m.playerA, playerB: m.playerB,
                                 playerC: nil, teamA: m.teamA, teamB: m.teamB, result: m.result)
        }
        out.sideClaims = s.sideClaims.map { c in
            SideClaimRow(id: c.id, roundID: rid, memberID: ids[c.memberID]!, kind: c.kind, meters: c.meters,
                         holeIndex: c.holeIndex)
        }
        out.names = Dictionary(uniqueKeysWithValues: s.names.map { (ids[$0.key]!, $0.value) })
        return out
    }
}

// MARK: - Radene mot kolonnenavnene i 017

@MainActor struct FundamentRaderTests {
    /// 017 er kjørt på test (07.10.2026, kontrollen 14 av 14).
    @Test func flaggetErPaa() {
        #expect(FoundationFeature.isEnabled)
    }

    @Test func konkurranseDekodesFraDatabasen() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000007000", "kind": "season", "name": "Jakkeracet 2026",
         "club_id": "00000000-0000-0000-0000-000000009000", "owner_id": null,
         "season_id": "00000000-0000-0000-0000-000000009002", "status": "active", "entry": "club",
         "rules": {"version": 1}, "starts_on": null, "ends_on": "2026-12-31", "is_main": true,
         "requires_purchase": false, "entitlement_id": null}
        """
        let row = try JSONDecoder().decode(CompetitionRow.self, from: Data(json.utf8))
        #expect(row.kind == .season && row.entry == .club && row.status == .active && row.isMain)
        #expect(row.rules == .golfgutu)
        #expect(row.endsOn == "2026-12-31" && row.ownerID == nil && !row.requiresPurchase)
        let back = try JSONDecoder().decode(CompetitionRow.self, from: JSONEncoder().encode(row))
        #expect(back == row)
    }

    @Test func lossRundeDeltakerOgRosterDekodes() throws {
        let origin = try JSONDecoder().decode(RoundOriginRow.self, from: Data("""
        {"id": "00000000-0000-0000-0000-000000000030", "club_id": null, "event_id": null,
         "owner_id": "00000000-0000-0000-0000-000000000801", "status": "active"}
        """.utf8))
        #expect(origin.home == .loose(ownerID: K.id(801)))

        let guest = try JSONDecoder().decode(RoundParticipantRow.self, from: Data("""
        {"id": "00000000-0000-0000-0000-000000000302", "round_id": "00000000-0000-0000-0000-000000000030",
         "profile_id": null, "display_name": "Per", "handicap_index": 12.4}
        """.utf8))
        #expect(guest.isGuest && guest.displayName == "Per" && guest.handicapIndex == 12.4)

        let roster = try JSONDecoder().decode([RoundRosterRow].self, from: Data("""
        [{"round_id": "00000000-0000-0000-0000-000000000030", "player_id": "00000000-0000-0000-0000-000000000302",
          "club_id": null, "display_name": "Per", "profile_id": null, "is_guest": true}]
        """.utf8))
        #expect(roster.first?.isGuest == true && roster.first?.clubID == nil)

        let profile = try JSONDecoder().decode(ProfileRow.self, from: Data("""
        {"id": "00000000-0000-0000-0000-000000000801", "display_name": null, "handicap_index": null, "avatar_path": null}
        """.utf8))
        #expect(profile.displayName == nil)

        let link = try JSONDecoder().decode(CompetitionRoundRow.self, from: Data("""
        {"competition_id": "00000000-0000-0000-0000-000000007000", "round_id": "00000000-0000-0000-0000-000000000030",
         "source": "manual"}
        """.utf8))
        #expect(link.source == .manual)

        let participant = try JSONDecoder().decode(CompetitionParticipantRow.self, from: Data("""
        {"id": "00000000-0000-0000-0000-000000000001", "competition_id": "00000000-0000-0000-0000-000000007000",
         "member_id": null, "profile_id": "00000000-0000-0000-0000-000000000801", "status": "withdrawn"}
        """.utf8))
        #expect(participant.status == .withdrawn && participant.profileID == K.id(801))
    }

    @Test func klubbrundeHarKlubbSomHjem() throws {
        let round = TavlaSamples.round(1, date: "2026-05-14").round
        let origin = RoundOriginRow(round)
        let clubID = try #require(round.clubID), eventID = try #require(round.eventID)
        #expect(origin.home == .club(clubID: clubID, eventID: eventID) && origin.status == round.status)
    }
}
