import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 7: avkorting, avslutt kvelden, rett en score og Rundene-tabellen.
// Tallene er fra avkorting-test.js og rundene-test.js.

private enum Fixture {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(800)
    static let roundID = id(801)
    static let courseID = id(802)
    static let eventID = id(803)
    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    static func row(status: RoundStatus = .active, holeCount: Int = 18, firstHole: Int = 1,
                    external: Bool = false, cutRule: String? = nil, cutAfter: Int? = nil) -> RoundRow {
        RoundRow(id: roundID, clubID: club, eventID: eventID, courseID: courseID, roundNo: 1, name: nil,
                 status: status, holeCount: holeCount, firstHole: firstHole, teeTime: nil, format: "stableford",
                 handicapAllowance: 1, externalHandicap: external, weight: 1,
                 ldEnabled: true, ldHoleIndex: nil, kpEnabled: true, kpHoleIndex: nil,
                 cutRule: cutRule, cutAfter: cutAfter, parConfirmedBy: nil, parConfirmedAt: nil,
                 startedAt: nil, lockedAt: nil)
    }

    /// Spillere (nummer, navn, handicap) og scorer (nummer → hull → brutto).
    static func game(_ players: [(Int, String, Double?)], scores: [Int: [Int: Int]],
                     round: RoundRow = row()) -> RoundGame {
        var s = RoundSnapshot(round: round)
        s.players = players.map { n, _, hcp in
            RoundPlayerRow(roundID: roundID, memberID: id(n), clubID: club, handicapIndex: hcp, seedGroup: nil,
                           playingHandicap: nil, bayNo: nil, isMarker: false, teamNo: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: players.map { (id($0.0), $0.1) })
        s.course = CourseRow(id: courseID, clubID: club, name: "Testbanen", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map { i in
            CourseHoleRecord(courseID: courseID, holeNumber: i + 1, par: par[i], strokeIndex: i + 1, lengthM: nil)
        }
        s.scores = scores.flatMap { member, holes in
            holes.map { hole, strokes in
                HoleScoreRow(roundID: roundID, memberID: id(member), holeIndex: hole, strokes: strokes,
                             recordedAt: nil, updatedBy: nil, updatedAt: nil)
            }
        }
        return RoundGame(s)
    }

    /// Par på hull 1…n: 2 poeng per hull.
    static func parScores(_ n: Int) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: (0..<n).map { ($0, par[$0]) })
    }

    // avkorting-test.js: Anders rakk 18, Bjørn 14, Cato 16. Dag møtte ikke opp.
    static let a = 1, b = 2, c = 3, d = 4
    static let avkortPlayers: [(Int, String, Double?)] = [(a, "Anders", 0), (b, "Bjørn", 0), (c, "Cato", 0), (d, "Dag", 0)]
    static func avkorting(round: RoundRow = row()) -> RoundGame {
        game(avkortPlayers, scores: [a: parScores(18), b: parScores(14), c: parScores(16)], round: round)
    }
}

private typealias F = Fixture

// MARK: - Avkorting (avkorting-test.js)

struct AvkortingTests {
    @Test func lavesteFellesHullErFjorten() {
        #expect(F.avkorting().lowestCommonHole == 14)
    }

    @Test func etHoppetHullStopperOpptellingen() {
        let g = F.game([(F.a, "Anders", 0), (F.b, "Bjørn", 0)],
                       scores: [F.a: [0: 4, 1: 5, 2: 3, 6: 5], F.b: F.parScores(10)])
        #expect(g.lowestCommonHole == 3)
    }

    @Test func forslagetErFellesEtterLavesteFellesHull() {
        #expect(F.avkorting().defaultCutChoice == CutChoice(rule: .common, after: 14))
    }

    @Test func ingenScoreForeslaarHeleRunden() {
        let g = F.game(F.avkortPlayers, scores: [:])
        #expect(g.defaultCutChoice == CutChoice(rule: .common, after: 18))
        #expect(g.cutHint(for: .common) == "Ingen har ført noe ennå.")
    }

    @Test func lagretAvkortingErForslaget() {
        let g = F.avkorting(round: F.row(cutRule: "net_par", cutAfter: 12))
        #expect(g.defaultCutChoice == CutChoice(rule: .netPar, after: 12))
        #expect(g.cutSummary == "Avkortet etter hull 12 · uspilte hull gir netto par")
    }

    @Test func fellesKosterAndersAatteOgCatoFire() {
        let preview = F.avkorting().cutPreview(CutChoice(rule: .common, after: 14))
        #expect(preview.countingHoles == 14)
        #expect(preview.holes == 18)
        #expect(preview.lines.map(\.text) == ["Anders 36 → 28 (−8)", "Cato 32 → 28 (−4)"])
        #expect(preview.losers == 2)
    }

    @Test func nettoparGirBjornOgCatoTilbakeHullene() {
        let preview = F.avkorting().cutPreview(CutChoice(rule: .netPar, after: 14))
        #expect(preview.countingHoles == 18)
        #expect(preview.lines.map(\.text) == ["Cato 32 → 36 (+4)", "Bjørn 28 → 36 (+8)"])
        #expect(preview.lines.allSatisfy { $0.diff >= 0 })
        #expect(preview.losers == 0)
    }

    @Test func nullEndrerIngenSum() {
        let preview = F.avkorting().cutPreview(CutChoice(rule: .zero, after: 14))
        #expect(preview.countingHoles == 18)
        #expect(preview.lines.isEmpty)
    }

    /// Samme svar som regelmotorens `avkortingenKoster` når handicapet ikke er lagret.
    @Test func forhaandsvisningenErLikAvkortingenKoster() {
        let g = F.avkorting()
        for rule in Truncation.Rule.allCases {
            let mine = g.cutPreview(CutChoice(rule: rule, after: 14))
            let core = Truncation.cost(of: g.round, after: 14, rule: rule, roster: g.roster, rules: g.rules)
            #expect(mine.countingHoles == core.countingHoles)
            #expect(Set(mine.lines.map { "\($0.memberID.uuidString):\($0.before):\($0.after)" })
                    == Set(core.changes.map { "\($0.playerID):\($0.before):\($0.after)" }))
        }
    }

    @Test func hjelpetekstenSierOmTalletKutterEllerOpplyser() {
        let g = F.avkorting()
        #expect(g.cutHint(for: .common)
                == "Alle som har begynt har ført til og med hull 14. Med denne regelen er det tallet du vil ha.")
        #expect(g.cutHint(for: .zero).hasSuffix("Regelen over fyller hullene i stedet for å kutte dem."))
        #expect(g.cutOptionTitle(14) == "Hull 14 · laveste felles")
        #expect(g.cutOptionTitle(15) == "Hull 15")
    }

    @Test func sisteNiHeterTiTilAtten() {
        let g = F.game([(F.a, "Anders", 0)], scores: [F.a: F.parScores(3)],
                       round: F.row(holeCount: 9, firstHole: 10))
        #expect(g.cutOptionTitle(5) == "Hull 14")
        #expect(g.cutOptionTitle(3) == "Hull 12 · laveste felles")
    }

    @Test func regelenLagresMedSkjemaetsNavn() {
        for rule in Truncation.Rule.allCases {
            #expect(RoundGame.cutRule(rule.databaseValue) == rule)
        }
        #expect(Truncation.Rule.zero.databaseValue == "zero")
    }

    @Test func lagringenSkriverAlleFireFelt() throws {
        let me = F.id(42)
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let set = try json(CutPatch.set(CutChoice(rule: .common, after: 14), by: me, at: at))
        #expect(set["cut_rule"] as? String == "common")
        #expect(set["cut_after"] as? Int == 14)
        #expect(set["cut_by"] as? String == me.uuidString)
        #expect(set["cut_at"] != nil && !(set["cut_at"] is NSNull))

        // Fjern avkorting: eksplisitt null, ellers står den gamle verdien (rounds_cut_whole).
        let removed = try json(CutPatch.remove)
        #expect(Set(removed.keys) == ["cut_rule", "cut_after", "cut_by", "cut_at"])
        #expect(removed.values.allSatisfy { $0 is NSNull })
    }

    @Test func radenSjekkesTilbake() {
        let patch = CutPatch.set(CutChoice(rule: .netPar, after: 14), by: F.id(1), at: Date())
        #expect(patch.matches(F.row(cutRule: "net_par", cutAfter: 14)))
        #expect(!patch.matches(F.row()))
        #expect(CutPatch.remove.matches(F.row()))
    }

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - Avslutt kvelden

struct AvsluttKveldenTests {
    @Test func toManglerHullNaarRundenIkkeErAvkortet() {
        #expect(F.avkorting().playersMissingHoles == 2)
    }

    @Test func avkortetEtterFjortenManglerIngen() {
        #expect(F.avkorting(round: F.row(cutRule: "common", cutAfter: 14)).playersMissingHoles == 0)
    }

    @Test func spoersmaaletForeslaarAvkorting() throws {
        let check = EveningClose.check(F.avkorting(), title: "Runde 1 – Testbanen")
        let prompt = try #require(EveningClose.prompt([check]))
        #expect(prompt.title == "Avslutte Runde 1 – Testbanen?")
        #expect(prompt.suggestCut == F.roundID)
        #expect(prompt.lines.first == "2 spillere har ikke ført alle 18 hullene. Uspilte hull gir 0 poeng slik runden står nå, så den som rakk færrest hull taper på det.")
        #expect(prompt.lines.last == "Runden låses og teller i sesongen.")
    }

    @Test func avkortetRundeSpoerIkkeOmAvkorting() throws {
        let game = F.avkorting(round: F.row(cutRule: "common", cutAfter: 14))
        let prompt = try #require(EveningClose.prompt([EveningClose.check(game, title: "Runde 1")]))
        #expect(prompt.suggestCut == nil)
        #expect(prompt.lines.first == "Avkortet etter hull 14 · tell til laveste felles hull.")
    }

    @Test func nullregelenErValgtSaaDetSpoerresIkke() throws {
        // «null» er valgt, ikke glemt: runden er avkortet, så det spørres ikke på nytt.
        let game = F.avkorting(round: F.row(cutRule: "zero", cutAfter: 14))
        #expect(game.playersMissingHoles == 2)
        let prompt = try #require(EveningClose.prompt([EveningClose.check(game, title: "Runde 1")]))
        #expect(prompt.suggestCut == nil)
    }

    @Test func ingenPaagaaendeRunde() {
        #expect(EveningClose.prompt([]) == nil)
    }

    @Test func meldingenSierHvaSomErLaast() {
        #expect(EveningClose.summary(locked: ["Runde 1"], drafts: [], failed: [])
                == "Runde 1 er låst. Kvelden er ferdig, og neste kveld står øverst.")
        #expect(EveningClose.summary(locked: ["Runde 1", "Runde 2"], drafts: ["Runde 3"], failed: [])
                == "Låst: Runde 1, Runde 2. Kladden Runde 3 er ikke spilt. Kvelden er ikke ferdig før den er startet og låst, eller slettet.")
        #expect(EveningClose.summary(locked: [], drafts: [], failed: ["Runde 1"])
                == "Ble ikke låst: Runde 1. Prøv igjen.")
    }
}

// MARK: - Rundene og retting (rundene-test.js)

struct RundeneTabellTests {
    // GAMMEL: låst, Trackman fordeler (scorene er netto). Thomas og Bjørn har ført, Cato er med uten score.
    static let t = 1, bj = 2, ca = 3
    static func gammel() -> RoundGame {
        F.game([(t, "Thomas", 12), (bj, "Bjørn", 8), (ca, "Cato", 20)],
               scores: [t: [0: 4, 1: 5, 2: 3], bj: [0: 5, 1: 6, 2: 4]],
               round: F.row(status: .locked, external: true))
    }

    @Test func tabellenHarDeSomHarFoertFlestPoengOeverst() {
        let table = Self.gammel().table()
        #expect(table.rows.map(\.name) == ["Thomas", "Bjørn"])
        #expect(table.columns.count == 18)
        #expect(table.columns.last?.number == 18)
        #expect(table.parTotal == 72)
        // Stableford mot par (PWA-testen har lagrede poeng 6 og 4; her regnes de fra scorene).
        #expect(table.rows.map(\.points) == [6, 3])
        #expect(table.rows.map(\.strokes) == [12, 15])
        #expect(table.rows[1].cells[1].strokes == 6)
        #expect(table.rows[1].cells[1].scoreName == .bogey)
        #expect(table.rows[1].cells[5].strokes == nil)
        #expect(!table.hasOutside)
    }

    @Test func utenScoreStaarAlleDeltakerne() {
        let g = F.game([(Self.t, "Thomas", 0), (Self.bj, "Bjørn", 0)], scores: [:])
        #expect(g.table().rows.map(\.name) == ["Bjørn", "Thomas"])
        #expect(g.table().rows.allSatisfy { $0.strokes == nil && $0.points == 0 })
    }

    @Test func hullUtenforAvkortingenErMerket() {
        let table = F.avkorting(round: F.row(cutRule: "common", cutAfter: 14)).table()
        #expect(table.countingHoles == 14)
        #expect(table.columns.filter(\.outside).map(\.number) == [15, 16, 17, 18])
        #expect(table.rows.first?.cells[15].outside == true)
        #expect(table.rows.map(\.points) == [28, 28, 28])
    }

    @Test func rutenAapnerMedTalletSomStaar() {
        let g = Self.gammel()
        var c = ScoreCorrection(game: g, member: F.id(Self.bj), hole: 1)
        #expect(c.original == 6)
        #expect(c.strokes == 6)
        #expect(!c.isChanged)
        #expect(c.buttonTitle(g) == "Lagre rettingen")
        #expect(c.submission(roundID: g.roundID, recordedAt: Date()) == nil)
        #expect(c.currentText == "Står nå: 6 slag.")

        c.step(-1)
        #expect(c.isChanged)
        #expect(c.buttonTitle(g) == "Lagre 5 på hull 2")
        #expect(c.doneText(g) == "Hull 2 for Bjørn er rettet fra 6 til 5.")
    }

    @Test func rettingenSendesSomEttHullForEnSpiller() throws {
        let g = Self.gammel()
        var c = ScoreCorrection(game: g, member: F.id(Self.bj), hole: 1)
        c.step(-1)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let sub = try #require(c.submission(roundID: g.roundID, recordedAt: now))
        #expect(sub == HoleSubmission(roundID: F.roundID, holeIndex: 1,
                                      entries: [.init(memberID: F.id(Self.bj), strokes: 5)], recordedAt: now))
    }

    @Test func tomtHullStarterPaaPar() {
        let g = Self.gammel()
        let c = ScoreCorrection(game: g, member: F.id(Self.ca), hole: 1)
        #expect(c.original == nil)
        #expect(c.strokes == 5)
        #expect(c.isChanged)
        #expect(c.currentText == "Ikke lagret.")
        #expect(c.doneText(g) == "Hull 2 for Cato er rettet til 5.")
    }

    @Test func stepperenHolderSegInnenforGrensene() {
        let g = Self.gammel()
        var c = ScoreCorrection(game: g, member: F.id(Self.t), hole: 2)
        for _ in 0..<10 { c.step(-1) }
        #expect(c.strokes == StrokeInput.range.lowerBound)
        for _ in 0..<30 { c.step(1) }
        #expect(c.strokes == StrokeInput.range.upperBound)
    }

    @Test func poengForDetNyeTallet() {
        // Bjørn 5 på par 5 med netto-føring: par, 2 poeng.
        let g = Self.gammel()
        var c = ScoreCorrection(game: g, member: F.id(Self.bj), hole: 1)
        c.step(-1)
        let outcome = c.outcome(g)
        #expect(outcome.name == .par)
        #expect(outcome.points == 2)
    }

    @Test func laastRundeSierFra() {
        #expect(CorrectionNotice.text(for: .locked) != nil)
        #expect(CorrectionNotice.text(for: .active) == nil)
    }

    @Test func listaErNyesteFoerst() {
        func item(_ no: Int, _ date: String?) -> RundeneItem {
            var r = F.row(status: .locked)
            r.roundNo = no
            return RundeneItem(round: r, eventDate: date, courseName: "Pebble Beach", players: 2)
        }
        let sorted = RundeneList.sorted([item(1, "2026-08-20"), item(1, "2026-09-10"), item(2, "2026-09-10")])
        #expect(sorted.map { "\($0.eventDate!)#\($0.round.roundNo)" } == ["2026-09-10#2", "2026-09-10#1", "2026-08-20#1"])
        #expect(sorted.first?.title == "Runde 2 – Pebble Beach")
    }
}
