import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Steg 6 i appen: Tavla med delt plass, uten plass og playoff, de nye reglene i «Tilpass reglene», og
/// trekningen og lagene i rundeoppsettet.
private enum S {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(880)
    static let courseID = id(881)
    static let anders = 1, bjorn = 2, cato = 3, dag = 4
    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    static func member(_ n: Int, _ name: String) -> ClubMemberRow {
        ClubMemberRow(id: id(n), clubID: club, userID: nil, displayName: name, handicapIndex: 0, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }

    static let four = [member(anders, "Anders"), member(bjorn, "Bjørn"), member(cato, "Cato"), member(dag, "Dag")]

    static func roundRow(_ n: Int, status: RoundStatus = .locked) -> RoundRow {
        RoundRow(id: id(100 + n), clubID: club, eventID: id(200 + n), courseID: courseID, roundNo: 1, name: nil,
                 status: status, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                 handicapAllowance: 1, externalHandicap: false, weight: 1,
                 ldEnabled: false, ldHoleIndex: 6, kpEnabled: false, kpHoleIndex: 2,
                 cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil, startedAt: nil, lockedAt: nil)
    }

    /// En låst runde der `strokes[spiller]` er slag over par på hvert hull.
    static func round(_ n: Int, date: String, over: [Int: Int]) -> RoundSnapshot {
        let row = roundRow(n)
        var s = RoundSnapshot(round: row)
        s.eventDate = date
        s.players = over.keys.sorted().map { p in
            RoundPlayerRow(roundID: row.id, memberID: id(p), clubID: club, handicapIndex: 0, seedGroup: nil,
                           playingHandicap: nil, bayNo: 1, isMarker: false, teamNo: nil)
        }
        s.scores = over.flatMap { p, extra in
            par.enumerated().map { h, par in
                HoleScoreRow(roundID: row.id, memberID: id(p), holeIndex: h, strokes: par + extra, recordedAt: nil,
                             updatedBy: nil, updatedAt: nil)
            }
        }
        s.course = CourseRow(id: courseID, clubID: club, name: "Testbanen", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map {
            CourseHoleRecord(courseID: courseID, holeNumber: $0 + 1, par: par[$0], strokeIndex: $0 + 1, lengthM: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: four.map { ($0.id, $0.displayName) })
        return s
    }

    /// Stableford som tabellpoeng, uten sidepremier. Anders og Bjørn spiller likt to kvelder, Cato én, Dag ingen.
    static func rules(tieRule: Ruleset.TieRule = .tiebreaks, minEvenings: Int? = nil) -> Ruleset {
        var r = Ruleset.golfgutu
        r.table.pointsSource = .stableford
        r.table.counting = Ruleset.Counting(unit: .round, best: nil)
        r.table.tiebreaks = [.stableford]
        r.table.tieRule = tieRule
        r.table.minEvenings = minEvenings
        r.sidePrizes.longestDrive.enabled = false
        r.sidePrizes.closestToPin.enabled = false
        return r
    }

    static func standings(_ rules: Ruleset) -> TavlaStandings {
        let rounds = [round(1, date: "2026-05-01", over: [anders: 0, bjorn: 0, cato: 1]),
                      round(2, date: "2026-05-08", over: [anders: 1, bjorn: 1])]
        let season = SeasonRow(id: id(882), clubID: club, name: "Vår 2026", status: .active, rules: rules)
        return TavlaStandings(TavlaInput(season: season, members: four, rounds: rounds), me: id(anders))
    }

    static func row(_ t: TavlaStandings, _ n: Int) -> TavlaStandings.Row { t.row(id(n))! }
}

struct TavlaTabellreglerTests {
    @Test func deltPlassVedLiktPaAlleSkillene() {
        let t = S.standings(S.rules())
        #expect(t.rows.map(\.name) == ["Anders", "Bjørn", "Cato", "Dag"])
        #expect(t.rows.map(t.placeText) == ["1.", "1.", "3.", "4."])
        #expect(t.rows.allSatisfy { $0.qualified && !$0.playoffPending })
        #expect(!t.detail(S.row(t, S.anders)).contains("Playoff"))
    }

    @Test func playoffMerkerDeltForsteplass() {
        let t = S.standings(S.rules(tieRule: .playoff))
        let anders = S.row(t, S.anders), bjorn = S.row(t, S.bjorn), cato = S.row(t, S.cato)
        #expect(anders.place == 1 && bjorn.place == 1)
        #expect(anders.playoffPending && bjorn.playoffPending && !cato.playoffPending)
        #expect(t.detail(anders).hasPrefix("Playoff · "))
        #expect(!t.detail(cato).contains("Playoff"))
        #expect(t.placeText(cato) == "3.")
    }

    @Test func utenNokKvelderStaarNederstUtenPlass() {
        let t = S.standings(S.rules(minEvenings: 2))
        #expect(t.rows.map(\.name) == ["Anders", "Bjørn", "Cato", "Dag"])
        let cato = S.row(t, S.cato), dag = S.row(t, S.dag)
        #expect(!cato.qualified && !dag.qualified)
        #expect(t.placeText(cato) == "–")
        #expect(t.detail(cato).hasSuffix(" · minst 2 kvelder for plass"))
        #expect(!t.isOnPodium(cato))
        // Rundeoversikten og widgeten viser heller ikke plass for dem.
        #expect(t.roundGrid.rows.first { $0.playerID == S.id(S.cato) }?.place == "–")
        #expect(WidgetSnapshot.topThree(t).map(\.name) == ["Anders", "Bjørn"])
        // Plassbevegelsene på Hjem regner bare de rangerte.
        #expect(TableBoard(t).standings.map(\.id) == [S.id(S.anders), S.id(S.bjorn)])
    }

    @Test func spilledagISteden() {
        var rules = S.rules(minEvenings: 2)
        rules.dayTerm = .playingDay
        let t = S.standings(rules)
        #expect(t.detail(S.row(t, S.cato)).hasSuffix(" · minst 2 spilledager for plass"))
    }

    @Test func golfgutuUtenMerker() {
        let t = S.standings(.golfgutu)
        #expect(t.rows.allSatisfy { $0.qualified && !$0.playoffPending })
        #expect(t.rows.allSatisfy { !t.detail($0).contains("Playoff") && !t.detail($0).contains("for plass") })
    }
}

struct TilpassReglerSteg6Tests {
    @Test func minsteAntallKvelderErAvTilDetSlaasPaa() throws {
        var draft = RulesetDraft(.golfgutu)
        #expect(!draft.hasMinEvenings)
        draft.hasMinEvenings = true
        #expect(draft.rules.table.minEvenings == 3)  // halvparten av 7
        draft.minEvenings = 5
        draft.hasMinEvenings = false
        #expect(draft.rules.table.minEvenings == nil)
        draft.hasMinEvenings = true
        #expect(draft.rules.table.minEvenings == 5)
        #expect(draft.changedFields == [.minEvenings])
        let json = String(decoding: try RulesetDraft.encoded(draft.rules), as: UTF8.self)
        #expect(json.contains("\"minEvenings\":5"))
    }

    @Test func forMangeKvelderGirMelding() {
        var draft = RulesetDraft(.golfgutu)
        draft.hasMinEvenings = true
        draft.minEvenings = 9
        #expect(!draft.canSave)
        #expect(draft.issues(in: .table).contains { $0.field == "table.minEvenings" })
    }

    @Test func poengtabellerSomListe() throws {
        var draft = RulesetDraft(.golfgutu)
        draft.addPointsTable()
        draft.addPointsTable()
        #expect(draft.pointsTables == [.init(name: "Finale", multiplier: 2), .init(name: "Tabell 2", multiplier: 2)])
        let renamed = draft.renamePointsTable("Tabell 2", to: "  Semifinale ")
        let taken = draft.renamePointsTable("Semifinale", to: "Finale")
        let empty = draft.renamePointsTable("Semifinale", to: " ")
        #expect(renamed && !taken && !empty)
        draft.setPointsTableMultiplier("Semifinale", 1.5)
        #expect(draft.pointsTables.map(\.name) == ["Finale", "Semifinale"])
        #expect(draft.rules.table.pointsTables["Semifinale"]?.multiplier == 1.5)
        draft.removePointsTable("Finale")
        #expect(draft.canSave)
        let decoded = try JSONDecoder().decode(Ruleset.self, from: RulesetDraft.encoded(draft.rules))
        #expect(decoded.table.pointsTables == ["Semifinale": Ruleset.PointsTable(multiplier: 1.5)])
        draft.setPointsTableMultiplier("Semifinale", -1)
        #expect(draft.issues.contains { $0.field == "table.pointsTables.Semifinale" })
    }

    @Test func snittPlayoffOgTrekningLagres() throws {
        var draft = RulesetDraft(.golfgutu)
        draft.rules.table.aggregation = .average
        draft.rules.table.tieRule = .playoff
        draft.rules.formats.drawMethod = .avoidRepeats
        #expect(draft.canSave)
        #expect(Set(draft.changedFields) == [.aggregation, .tieRule, .drawMethod])
        #expect(draft.changeNote(.drawMethod) == "Endret · standard etter tabellen")
        let decoded = try JSONDecoder().decode(Ruleset.self, from: RulesetDraft.encoded(draft.rules))
        #expect(decoded.table.aggregation == .average)
        #expect(decoded.table.tieRule == .playoff)
        #expect(decoded.formats.drawMethod == .avoidRepeats)
    }

    @Test func forklaringenNevnerReglene() {
        #expect(!RulesetExplanation.text(for: .golfgutu).contains("playoff"))
        var r = Ruleset.golfgutu
        r.dayTerm = .playingDay
        r.table.minEvenings = 3
        r.table.aggregation = .average
        r.table.pointsTables = ["Finale": Ruleset.PointsTable(multiplier: 2)]
        r.table.tieRule = .playoff
        r.formats.drawMethod = .manual
        let text = RulesetExplanation.text(for: r)
        #expect(text.contains("Tabellen viser snittet per spilledag som teller."))
        #expect(text.contains("Finale teller 2 ganger."))
        #expect(text.contains("Du må ha spilt minst 3 spilledager for å få plass i tabellen."))
        #expect(text.contains("avgjøres det med playoff"))
        #expect(!text.contains("Ved likt poeng skiller"))
        #expect(text.contains("Arrangøren setter opp matchene."))
    }
}

struct TrekningOgLagTests {
    private let players = S.four

    @Test func etterTabellenErSomFoer() {
        let plan = MatchDrawPlan.standings
        #expect(MatchPlanner.draw(players, plan: plan, seed: 1) == MatchPlanner.drawIndividual(players))
    }

    @Test func manueltGirIngenMatcher() {
        var draft = RoundDraft.new(eventID: S.id(900), roundNo: 1, teeTime: nil, participants: players.map(\.id),
                                   source: .signups, rules: .golfgutu)
        draft.redrawMatches(roster: players, plan: MatchDrawPlan(method: .manual, previous: [:]))
        #expect(draft.matches.isEmpty)
        #expect(MatchDrawText.footer(plan: MatchDrawPlan(method: .manual, previous: [:]), matches: []) == "Du setter opp matchene selv.")
        #expect(MatchDrawText.footer(plan: .standings, matches: []) == nil)
    }

    @Test func moeteneFraLagredeMatcher() {
        let r1 = S.roundRow(1), draftRound = S.roundRow(2, status: .draft), current = S.roundRow(3)
        let matches = [
            RoundMatchRow(roundID: r1.id, matchNo: 1, playerA: S.id(1), playerB: S.id(2), playerC: nil, teamA: nil, teamB: nil, result: nil),
            RoundMatchRow(roundID: r1.id, matchNo: 2, playerA: S.id(3), playerB: S.id(4), playerC: S.id(5), teamA: nil, teamB: nil, result: nil),
            RoundMatchRow(roundID: draftRound.id, matchNo: 1, playerA: S.id(1), playerB: S.id(3), playerC: nil, teamA: nil, teamB: nil, result: nil),
            RoundMatchRow(roundID: current.id, matchNo: 1, playerA: S.id(1), playerB: S.id(4), playerC: nil, teamA: nil, teamB: nil, result: nil),
        ]
        var rules = Ruleset.golfgutu
        rules.formats.drawMethod = .avoidRepeats
        let plan = MatchDrawPlan.make(rules: rules, rounds: [r1, draftRound, current], matches: matches, players: [:],
                                      excluding: current.id)
        #expect(plan.method == .avoidRepeats)
        let key = { (a: Int, b: Int) in Draw.pairKey(S.id(a).uuidString, S.id(b).uuidString) }
        #expect(plan.previous == [key(1, 2): 1, key(3, 4): 1, key(3, 5): 1, key(4, 5): 1])
    }

    @Test func lagmatchSlaarOppLagene() {
        let r = S.roundRow(1)
        let players = [1, 2, 3, 4].map { n in
            RoundPlayerRow(roundID: r.id, memberID: S.id(n), clubID: S.club, handicapIndex: 0, seedGroup: nil,
                           playingHandicap: nil, bayNo: 1, isMarker: false, teamNo: n <= 2 ? 1 : 2)
        }
        let match = RoundMatchRow(roundID: r.id, matchNo: 1, playerA: nil, playerB: nil, playerC: nil, teamA: 1, teamB: 2, result: nil)
        let meetings = MatchDrawPlan.meetings([match], players: [r.id: players])
        #expect(meetings.count == 4)
        #expect(meetings[Draw.pairKey(S.id(1).uuidString, S.id(2).uuidString)] == nil)
    }

    @Test func utenGjentakelserUnngaarGamleMotstandere() {
        let a = S.id(1).uuidString, b = S.id(2).uuidString, c = S.id(3).uuidString, d = S.id(4).uuidString
        let plan = MatchDrawPlan(method: .avoidRepeats, previous: [Draw.pairKey(a, b): 1, Draw.pairKey(c, d): 1])
        for seed: UInt64 in [1, 2, 3, 42] {
            let matches = MatchPlanner.draw(players, plan: plan, seed: seed)
            #expect(matches.count == 2)
            #expect(plan.repeats(in: matches) == 0)
            let core = Draw.avoidingRepeats(players.map { Player(id: $0.id.uuidString, name: $0.displayName) },
                                            previous: plan.previous, seed: seed)
            #expect(matches.map { $0.members().map(\.uuidString) } == core)
        }
        #expect(MatchDrawText.footer(plan: plan, matches: MatchPlanner.draw(players, plan: plan, seed: 1))
                == "Trekkes tilfeldig uten gjentakelser. Ingen har møtt hverandre før.")
    }

    @Test func tilfeldigeLagGaarOppOgKanByttes() {
        let ids = (1...8).map(S.id)
        let form = CompetitionForm.form(id: "fourball")
        let teams = TeamPlanner.random(participants: ids, form: form, maxPerBay: 4, seed: 7)
        #expect(Set(teams.keys) == Set(ids))
        #expect(TeamPlanner.problem(teams: teams, participants: ids, form: form, maxPerBay: 4) == nil)
        #expect(teams == TeamPlanner.random(participants: ids, form: form, maxPerBay: 4, seed: 7))
        // Rekkefølgen er motorens stokking (`Teams.random`), fylt i formens lagstørrelser.
        let order = Teams.random(ids.map(\.uuidString), teamSize: 1, seed: 7)
        let first = ids.sorted { order[$0.uuidString]! < order[$1.uuidString]! }
        #expect(teams == TeamPlanner.suggested(participants: first, form: form, maxPerBay: 4))

        let a = ids.first { teams[$0] == 1 }!, b = ids.first { teams[$0] == 2 }!
        let swapped = TeamPlanner.swap(teams, a, b)
        #expect(swapped[a] == 2 && swapped[b] == 1)
        #expect(TeamPlanner.swap(teams, a, a) == teams)
    }
}
