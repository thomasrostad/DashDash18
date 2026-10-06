import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Tavla bygd av rader, slik de kommer fra databasen. Tall fra seier-test.js og sesong-test.js
/// (regnet av db-nytt.js), pluss ett regelsett som ikke er Golfgutu.
private enum T {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(990)
    static let courseID = id(991)
    static let seasonID = id(992)
    static let anders = 1, bjorn = 2, cato = 3, dag = 4

    /// PAR fra seier-test.js.
    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    static func member(_ n: Int, _ name: String, hcp: Double? = 0, status: MemberStatus = .active) -> ClubMemberRow {
        ClubMemberRow(id: id(n), clubID: club, userID: nil, displayName: name, handicapIndex: hcp, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: status, avatarPath: nil)
    }

    static let four = [member(anders, "Anders"), member(bjorn, "Bjørn"), member(cato, "Cato"), member(dag, "Dag")]

    static func season(_ rules: Ruleset = .golfgutu, status: SeasonStatus = .active) -> SeasonRow {
        SeasonRow(id: seasonID, clubID: club, name: "Sesong 2026", status: status, rules: rules)
    }

    struct Match {
        var a: Int?
        var b: Int?
        var teamA: Int?
        var teamB: Int?
    }

    /// En runde der `strokes[spiller][hull]` er brutto. Lag: `teams[spiller] = lagnummer`.
    static func round(_ n: Int, date: String, roundNo: Int = 1, format: String = "stableford",
                      status: RoundStatus = .locked, weight: Double = 1,
                      strokes: [Int: [Int]], teams: [Int: Int] = [:], matches: [Match] = [],
                      claims: [(Int, SideClaimKind, Double)] = [], members: [ClubMemberRow] = four) -> RoundSnapshot {
        let rid = id(100 + n)
        let row = RoundRow(id: rid, clubID: club, eventID: id(200 + n), courseID: courseID, roundNo: roundNo, name: nil,
                           status: status, holeCount: 18, firstHole: 1, teeTime: nil, format: format,
                           handicapAllowance: 1, externalHandicap: false, weight: weight,
                           ldEnabled: true, ldHoleIndex: 6, kpEnabled: true, kpHoleIndex: 2,
                           cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil,
                           startedAt: nil, lockedAt: nil)
        var s = RoundSnapshot(round: row)
        s.eventDate = date
        s.players = strokes.keys.sorted().map { p in
            let m = members.first { $0.id == id(p) }
            return RoundPlayerRow(roundID: rid, memberID: id(p), clubID: club, handicapIndex: m?.handicapIndex,
                                  seedGroup: nil, playingHandicap: nil, bayNo: 1, isMarker: false, teamNo: teams[p])
        }
        s.scores = strokes.flatMap { p, holes in
            holes.enumerated().map { h, g in
                HoleScoreRow(roundID: rid, memberID: id(p), holeIndex: h, strokes: g, recordedAt: nil, updatedBy: nil, updatedAt: nil)
            }
        }
        s.matches = matches.enumerated().map { i, m in
            RoundMatchRow(roundID: rid, matchNo: i + 1, playerA: m.a.map(id), playerB: m.b.map(id), playerC: nil,
                          teamA: m.teamA, teamB: m.teamB, result: nil)
        }
        s.sideClaims = claims.enumerated().map { i, c in
            SideClaimRow(id: id(300 + n * 10 + i), roundID: rid, memberID: id(c.0), kind: c.1, meters: c.2,
                         holeIndex: c.1 == .drive ? 6 : 2)
        }
        s.course = CourseRow(id: courseID, clubID: club, name: "Testbanen", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map {
            CourseHoleRecord(courseID: courseID, holeNumber: $0 + 1, par: par[$0], strokeIndex: $0 + 1, lengthM: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.displayName) })
        return s
    }

    /// `over` slag over par på hvert hull.
    static func over(_ n: Int) -> [Int] { par.map { $0 + n } }

    /// `lagrunde` i seier-test.js: lag 1 (a+b) går ett over par per hull, lag 2 (c+d) to.
    static func teamRound(_ n: Int, date: String, claims: [(Int, SideClaimKind, Double)] = []) -> RoundSnapshot {
        round(n, date: date, format: "scramble-2",
              strokes: [anders: over(1), bjorn: over(1), cato: over(2), dag: over(2)],
              teams: [anders: 1, bjorn: 1, cato: 2, dag: 2],
              matches: [Match(teamA: 1, teamB: 2)], claims: claims)
    }

    static func standings(_ rounds: [RoundSnapshot], members: [ClubMemberRow] = four, rules: Ruleset = .golfgutu,
                          status: SeasonStatus = .active, me: Int? = anders) -> TavlaStandings {
        TavlaStandings(TavlaInput(season: season(rules, status: status), members: members, rounds: rounds),
                       me: me.map(id))
    }

    static func row(_ s: TavlaStandings, _ n: Int) -> TavlaStandings.Row { s.row(id(n))! }
}

// MARK: - Tabellen (seier-test.js)

struct TavlaTableTests {
    @Test func lagseierOgLongestDriveGirHverSine() {
        // seier-test.js 2–3: Anders tar longest drive, laget vinner duellen.
        let s = T.standings([T.teamRound(1, date: "2026-09-01",
                                         claims: [(T.anders, .drive, 250), (T.cato, .drive, 230)])])
        #expect(s.rows.map(\.memberID) == [T.anders, T.bjorn, T.cato, T.dag].map(T.id))
        let a = T.row(s, T.anders)
        #expect(a.total == 2 && a.duel == 1 && a.side == 1)
        #expect(T.row(s, T.bjorn).total == 1)
        #expect(T.row(s, T.cato).total == 0 && T.row(s, T.dag).total == 0)
        #expect(a.holes == 18 && T.row(s, T.cato).holes == -18)
        #expect(a.place == 1 && a.isMe && !T.row(s, T.bjorn).isMe)
        #expect(a.evenings == 1 && s.eveningsPlayed == 1 && s.eveningsTotal == 7)
    }

    @Test func naermestPinnenStablesOppaa() {
        let s = T.standings([T.teamRound(1, date: "2026-09-01",
                                         claims: [(T.anders, .drive, 250), (T.cato, .drive, 230), (T.anders, .kp, 2.4)])])
        #expect(T.row(s, T.anders).total == 3)
    }

    @Test func likLengdeDelerPoenget() {
        let s = T.standings([T.teamRound(1, date: "2026-09-01",
                                         claims: [(T.anders, .drive, 250), (T.cato, .drive, 250)])])
        #expect(T.row(s, T.anders).side == 0.5 && T.row(s, T.cato).side == 0.5)
        #expect(s.points(T.row(s, T.anders).total) == "1,5")
    }

    @Test func syvSeireGirSyvPoeng() {
        let rounds = (1...7).map { T.teamRound($0, date: "2026-09-0\($0)") }
        let s = T.standings(rounds)
        #expect(T.row(s, T.anders).total == 7 && T.row(s, T.anders).matches == 7)
        #expect(T.row(s, T.cato).total == 0)
        #expect(s.eveningsPlayed == 7)
    }

    @Test func alleStaarITabellenVedSesongstart() {
        let s = T.standings([])
        #expect(s.rows.count == 4 && s.rows.allSatisfy { $0.total == 0 && $0.evenings == 0 })
        #expect(s.eveningsPlayed == 0)
        #expect(s.summary == nil)
    }

    /// seier-test.js 8: Anders vinner duellen (ti hull mot åtte), Bjørn vinner stablefordet (26 mot 20).
    static func duel() -> RoundSnapshot {
        let a = T.par.indices.map { $0 < 10 ? T.par[$0] : T.par[$0] + 3 }
        let b = T.par.indices.map { $0 < 10 ? T.par[$0] + 1 : T.par[$0] }
        return T.round(1, date: "2026-09-01", strokes: [T.anders: a, T.bjorn: b], matches: [T.Match(a: T.anders, b: T.bjorn)])
    }

    @Test func tabellenRangererPaaDuellenIkkeStablefordet() {
        let s = T.standings([Self.duel()], members: Array(T.four.prefix(2)))
        #expect(s.rows.map(\.name) == ["Anders", "Bjørn"])
        let a = T.row(s, T.anders), b = T.row(s, T.bjorn)
        #expect(a.total == 1 && a.holes == 2 && a.stableford == 20)
        #expect(b.total == 0 && b.holes == -2 && b.stableford == 26)
        // Oppsummeringen kårer samme mester som tabellen.
        #expect(s.summary?.champion.memberID == T.id(T.anders))
    }

    @Test func vektNullTellerIkke() {
        // seier-test.js 8b: «teller ikke sammenlagt» teller ikke, heller ikke i hulldifferansen.
        let r = T.round(1, date: "2026-09-01", weight: 0, strokes: [T.anders: T.over(5), T.bjorn: T.over(1)],
                        matches: [T.Match(a: T.anders, b: T.bjorn)])
        let s = T.standings([r], members: Array(T.four.prefix(2)))
        #expect(s.rows.allSatisfy { $0.total == 0 && $0.holes == 0 })
        #expect(s.rows.map(\.name) == ["Anders", "Bjørn"])
    }

    @Test func kladderTellerIkkeOgToRunderSammeKveldErEnKveld() {
        let draft = T.round(3, date: "2026-09-08", status: .draft, strokes: [T.anders: T.over(0)])
        let first = T.teamRound(1, date: "2026-09-01")
        var second = T.teamRound(2, date: "2026-09-01")
        second.round.roundNo = 2
        let ongoing = T.round(4, date: "2026-09-15", status: .active, strokes: [T.anders: T.over(0)])
        let s = T.standings([ongoing, second, draft, first])
        #expect(s.snapshots.map(\.round.id) == [T.id(101), T.id(102), T.id(104)])
        #expect(s.eveningsPlayed == 2)
        #expect(T.row(s, T.anders).total == 2)
        #expect(T.row(s, T.anders).evenings == 2 && T.row(s, T.bjorn).evenings == 1)
        #expect(s.roundTitle(0) == "Kveld 1 · runde 1" && s.roundTitle(2) == "Kveld 2")
    }

    @Test func troppenErAktiveOgDeSomHarSpilt() {
        let members = [T.member(T.anders, "Anders"), T.member(T.bjorn, "Bjørn", status: .archived),
                       T.member(T.cato, "Cato", status: .archived), T.member(T.dag, "Dag", status: .pending)]
        let r = T.round(1, date: "2026-09-01", strokes: [T.anders: T.over(0), T.bjorn: T.over(1)], members: members)
        let s = T.standings([r], members: members)
        #expect(Set(s.rows.map(\.memberID)) == [T.id(T.anders), T.id(T.bjorn)])
    }
}

// MARK: - Regelsettet styrer (ikke Golfgutu)

struct TavlaRulesetTests {
    /// Anders slår Bjørn de tre første kveldene, Bjørn vinner den fjerde. LD til Bjørn den fjerde.
    static func fourEvenings() -> [RoundSnapshot] {
        (1...4).map { n in
            let anders = n < 4 ? T.over(0) : T.over(1)
            let bjorn = n < 4 ? T.over(1) : T.over(0)
            return T.round(n, date: "2026-09-0\(n)", strokes: [T.anders: anders, T.bjorn: bjorn],
                           matches: [T.Match(a: T.anders, b: T.bjorn)],
                           claims: n == 4 ? [(T.bjorn, .drive, 260)] : [])
        }
    }

    @Test func golfgutuTellerAlt() {
        let s = T.standings(Self.fourEvenings(), members: Array(T.four.prefix(2)))
        #expect(T.row(s, T.anders).total == 3)
        #expect(T.row(s, T.bjorn).total == 2) // én seier + longest drive
    }

    @Test func beste2KvelderStrykerResten() {
        var rules = Ruleset.golfgutu
        rules.evenings = 5
        rules.table.counting = .init(unit: .evening, best: 2)
        let s = T.standings(Self.fourEvenings(), members: Array(T.four.prefix(2)), rules: rules)
        let a = T.row(s, T.anders), b = T.row(s, T.bjorn)
        #expect(a.total == 2 && a.matches == 2 && a.holes == 36)
        // Bjørns beste kveld er den fjerde (seier + LD = 2), så en tapt kveld (0) med −18.
        #expect(b.total == 2 && b.duel == 1 && b.side == 1 && b.holes == 0)
        // Likt på 2: hulldifferansen skiller.
        #expect(s.rows.map(\.name) == ["Anders", "Bjørn"])
        #expect(s.eveningsPlayed == 4 && s.eveningsTotal == 5)
        #expect(s.summary?.championLine == nil)
    }

    @Test func skilletegnFolgerRegelsettet() {
        // Beste kveld teller, ingen longest drive: begge står på 1 poeng og +18 hull.
        var rules = Ruleset.golfgutu
        rules.table.counting = .init(unit: .evening, best: 1)
        rules.sidePrizes.longestDrive.enabled = false
        let members = [T.member(T.anders, "Øystein"), T.member(T.bjorn, "Bjørn")]
        let s = T.standings(Self.fourEvenings(), members: members, rules: rules)
        #expect(T.row(s, T.anders).total == 1 && T.row(s, T.bjorn).total == 1)
        #expect(T.row(s, T.anders).holes == 18 && T.row(s, T.bjorn).holes == 18)
        // Golfgutu-skillene: stablefordsummen (36 · 3 + 18 mot 18 · 3 + 36) setter Øystein først.
        #expect(T.row(s, T.anders).stableford == 126 && T.row(s, T.bjorn).stableford == 90)
        #expect(s.rows.map(\.name) == ["Øystein", "Bjørn"])
        // Uten skilletegn avgjør navnet, norsk: Ø etter B.
        rules.table.tiebreaks = []
        let t = T.standings(Self.fourEvenings(), members: members, rules: rules)
        #expect(t.rows.map(\.name) == ["Bjørn", "Øystein"])
    }

    @Test func poengmodellenFolgerRegelsettet() {
        var rules = Ruleset.golfgutu
        rules.table.matchPoints = .init(win: 2, draw: 1, loss: 0)
        rules.sidePrizes.longestDrive.points = 3
        let s = T.standings(Self.fourEvenings(), members: Array(T.four.prefix(2)), rules: rules)
        #expect(T.row(s, T.anders).total == 6)
        #expect(T.row(s, T.bjorn).total == 5 && T.row(s, T.bjorn).side == 3)
        #expect(s.rows.map(\.name) == ["Anders", "Bjørn"])
    }
}

// MARK: - Profil og oppsummering (sesong-test.js, seier-test.js)

struct TavlaProfileTests {
    /// sesong-test.js 1: Anders spiller sju runder med 30, 28, 26, 24, 22, 20, 18 poeng
    /// (36 − antall bogeyer med handicap 0). De fem beste er 130.
    static func sevenRounds(withBjorn: Bool = false) -> [RoundSnapshot] {
        [30, 28, 26, 24, 22, 20, 18].enumerated().map { i, p in
            let bogeys = 36 - p
            let anders = T.par.indices.map { T.par[$0] + ($0 < bogeys ? 1 : 0) }
            var strokes = [T.anders: anders]
            // Bjørn: ett slag til på de to første hullene, to poeng mindre.
            if withBjorn { strokes[T.bjorn] = anders.indices.map { anders[$0] + ($0 < 2 ? 1 : 0) } }
            return T.round(i + 1, date: "2026-0\(i + 1)-01", strokes: strokes)
        }
    }

    @Test func stablefordsummenErDeFemBeste() {
        let s = T.standings(Self.sevenRounds())
        let p = s.profile(T.id(T.anders))!
        #expect(p.stablefordTotal == 130 && T.row(s, T.anders).stableford == 130)
        #expect(p.roundsPlayed == 7 && p.best == 30 && p.average == 24)
        #expect(p.rounds.map(\.stableford) == [18, 20, 22, 24, 26, 28, 30])
        #expect(p.rounds.first?.title == "Kveld 7")
        #expect(p.rounds.allSatisfy { $0.duel == nil && $0.place == 1 })
        #expect(p.headToHead == nil)
    }

    @Test func innbyrdesOgPlassIRunden() {
        // Bjørn har to poeng mindre hver runde (sesong-test.js 5).
        let s = T.standings(Self.sevenRounds(withBjorn: true))
        let bjorn = s.profile(T.id(T.bjorn))!
        #expect(bjorn.headToHead == .init(them: 0, me: 7))
        #expect(bjorn.headToHeadText(name: "Bjørn") == "7–0 til deg")
        #expect(bjorn.rounds.allSatisfy { $0.place == 2 })
        #expect(s.profile(T.id(T.anders))!.headToHead == nil)
    }

    @Test func duellPoengPerRundeOgSnittMedDesimal() {
        let s = T.standings([TavlaTableTests.duel()], members: Array(T.four.prefix(2)), me: T.anders)
        let b = s.profile(T.id(T.bjorn))!
        #expect(b.rounds.map(\.duel) == [0] && b.rounds.map(\.stableford) == [26])
        #expect(b.headToHeadText(name: "Bjørn") == "1–0 til Bjørn")
        let a = s.profile(T.id(T.anders))!
        #expect(a.rounds.map(\.duel) == [1] && a.basis(s) == "1 fra én duell · +2 hull")
    }

    @Test func birdiesErNettoOgLengsteDrive() {
        // Handicap 18 og brutto par på alle hull: netto birdie på hvert hull, 3 poeng hvert = 54.
        let members = [T.member(T.anders, "Anders", hcp: 18), T.member(T.bjorn, "Bjørn")]
        let r = T.round(1, date: "2026-09-01", strokes: [T.anders: T.par, T.bjorn: T.over(0)],
                        claims: [(T.anders, .drive, 241.5), (T.bjorn, .drive, 250)], members: members)
        let r2 = T.round(2, date: "2026-09-08", strokes: [T.anders: T.over(1)],
                         claims: [(T.anders, .drive, 255)], members: members)
        let s = T.standings([r, r2], members: members)
        let a = s.profile(T.id(T.anders))!
        #expect(a.birdies == 18 && a.best == 54)
        #expect(a.longestDrive == 255)
        #expect(s.profile(T.id(T.bjorn))!.birdies == 0)
        let sum = s.summary!
        #expect(sum.mostBirdies?.name == "Anders" && sum.mostBirdies?.value == "18")
        #expect(sum.longestDrive?.name == "Anders" && sum.longestDrive?.value == "255 m")
        #expect(sum.bestRound?.name == "Anders" && sum.bestRound?.value == "54 p" && sum.bestRound?.detail == "Kveld 1")
    }

    @Test func oppsummeringenMedGolfgutuOppsettet() {
        let s = T.standings([T.teamRound(1, date: "2026-09-01", claims: [(T.anders, .drive, 250)])], status: .finished)
        let sum = s.summary!
        #expect(sum.champion.name == "Anders")
        #expect(sum.championLine == "bærer den grønne jakka")
        #expect(sum.championBasis == "1 fra én duell · 1 fra sidepremier")
        #expect(sum.podium.map(\.name) == ["Anders", "Bjørn", "Cato"] && sum.rest.map(\.name) == ["Dag"])
        #expect(sum.eveningsPlayed == 1 && sum.eveningsTotal == 7)
    }
}

// MARK: - Rundens frosne handicap (én sannhet med Kveld)

struct TavlaFrozenHandicapTests {
    /// Bjørn hadde 18 i kveld 1 og 0 i kveld 2; i troppen står han nå med 9. Anders har 0.
    /// Anders går par, Bjørn ett over på hvert hull (banehandicap = indeks: CR 72, slope 113, SI 1–18).
    /// Samme scenario som GolfgutuCore-fixturen frosset-handicap.json.
    static func changedHandicap() -> (members: [ClubMemberRow], rounds: [RoundSnapshot]) {
        let members = [T.member(T.anders, "Anders"), T.member(T.bjorn, "Bjørn", hcp: 9)]
        let rounds = [(1, "2026-05-01", 18.0), (2, "2026-05-08", 0.0)].map { n, date, frozen in
            var r = T.round(n, date: date, strokes: [T.anders: T.over(0), T.bjorn: T.over(1)],
                            matches: [T.Match(a: T.anders, b: T.bjorn)], members: members)
            r.players = r.players.map { p in
                var p = p
                if p.memberID == T.id(T.bjorn) { p.handicapIndex = frozen }
                return p
            }
            return r
        }
        return (members, rounds)
    }

    @Test func hverRundeRegnesMedHandicapetDaDenBleSpilt() {
        let (members, rounds) = Self.changedHandicap()
        let s = T.standings(rounds, members: members)
        let a = T.id(T.anders).uuidString, b = T.id(T.bjorn).uuidString
        // Kveld 1: ett slag per hull gir Bjørn netto par, 36 mot 36 og delt match.
        #expect(s.season.roundPoints(0) == [a: 36, b: 36])
        // Kveld 2: scratch, 18 poeng, og Anders vinner alle hull.
        #expect(s.season.roundPoints(1) == [a: 36, b: 18])
        let anders = T.row(s, T.anders), bjorn = T.row(s, T.bjorn)
        #expect(anders.total == 1.5 && anders.holes == 18 && anders.stableford == 72)
        #expect(bjorn.total == 0.5 && bjorn.holes == -18 && bjorn.stableford == 54)
    }

    @Test func tabellenGirSammeRundepoengOgMatcherSomKveld() {
        let (members, rounds) = Self.changedHandicap()
        let s = T.standings(rounds, members: members)
        for (i, snapshot) in s.snapshots.enumerated() {
            let game = RoundGame(snapshot)
            for p in snapshot.players {
                #expect(s.season.roundPoints(i)[p.memberID.uuidString] == game.total(p.memberID))
            }
            for m in game.round.matches {
                #expect(MatchPlay.outcomeForA(m, in: s.season.rounds[i], roster: s.season.players)
                        == MatchPlay.outcomeForA(m, in: game.round, roster: game.roster))
            }
        }
    }

    @Test func lagretSpillehandicapErFasit() {
        // Frosset indeks 0, men runden startet med 18 lagret: Kveld og Tavla bruker 18.
        var r = T.round(1, date: "2026-05-01", strokes: [T.anders: T.over(0), T.bjorn: T.over(1)],
                        members: Array(T.four.prefix(2)))
        r.players = r.players.map { p in
            var p = p
            if p.memberID == T.id(T.bjorn) { p.playingHandicap = 18 }
            return p
        }
        let s = T.standings([r], members: Array(T.four.prefix(2)))
        let game = RoundGame(r)
        #expect(game.total(T.id(T.bjorn)) == 36)
        #expect(s.season.roundPoints(0)[T.id(T.bjorn).uuidString] == 36)
        // Netto par på alle hull: ingen netto birdie.
        #expect(s.profile(T.id(T.bjorn))!.birdies == 0)
    }
}

// MARK: - Innmeldinger: lik lengde avgjøres av tidspunktet

struct TavlaClaimOrderTests {
    @Test func likLengdeDenSomMeldteFoerstStaarOeverst() {
        var r = T.round(1, date: "2026-09-01", strokes: [T.anders: T.over(0), T.bjorn: T.over(0)],
                        claims: [(T.anders, .drive, 250), (T.bjorn, .drive, 250)], members: Array(T.four.prefix(2)))
        let t0 = Date(timeIntervalSince1970: 1_788_287_400)
        r.sideClaims[0].createdAt = t0.addingTimeInterval(60.5)
        r.sideClaims[1].createdAt = t0
        let game = RoundGame(r)
        let sorted = SidePrizes.claims(.drive, in: game.round, claims: game.coreSideClaims)
        #expect(sorted.map(\.playerId) == [T.id(T.bjorn).uuidString, T.id(T.anders).uuidString])

        let s = T.standings([r], members: Array(T.four.prefix(2)))
        let tavla = SidePrizes.claims(.drive, in: s.season.rounds[0], claims: s.claims)
        #expect(tavla.map(\.playerId) == sorted.map(\.playerId))
        // Delt uansett rekkefølge.
        #expect(T.row(s, T.anders).side == 0.5 && T.row(s, T.bjorn).side == 0.5)
    }

    @Test func utenTidspunktStaarDeINavnerekkefolge() {
        let r = T.round(1, date: "2026-09-01", strokes: [T.anders: T.over(0), T.bjorn: T.over(0)],
                        claims: [(T.bjorn, .drive, 250), (T.anders, .drive, 250)], members: Array(T.four.prefix(2)))
        let game = RoundGame(r)
        let sorted = SidePrizes.claims(.drive, in: game.round, claims: game.coreSideClaims)
        #expect(sorted.map(\.playerId) == [T.id(T.anders).uuidString, T.id(T.bjorn).uuidString])
    }

    @Test func createdAtDekodesOgErValgfri() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let id = UUID().uuidString
        let with = try decoder.decode(SideClaimRow.self, from: Data("""
            {"id":"\(id)","round_id":"\(id)","member_id":"\(id)","kind":"drive","meters":250,"hole_index":6,
             "created_at":"2026-09-01T18:30:00Z"}
            """.utf8))
        #expect(with.createdAt == Date(timeIntervalSince1970: 1_788_287_400))
        #expect(with.timestamp == "2026-09-01T18:30:00.000Z")
        let without = try decoder.decode(SideClaimRow.self, from: Data("""
            {"id":"\(id)","round_id":"\(id)","member_id":"\(id)","kind":"kp","meters":2.4}
            """.utf8))
        #expect(without.createdAt == nil && without.timestamp == nil)
    }
}
