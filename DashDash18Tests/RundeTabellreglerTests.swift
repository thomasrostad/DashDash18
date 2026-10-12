import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Steg 6 i appen med sql/047: tabellreglene på runden, «skjul de tre siste hullene» og playoff-runden.
private enum P {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(990)
    static let courseID = id(991)
    static let competition = id(992)
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

    static func base(_ row: RoundRow, date: String, bays: [Int: Int]) -> RoundSnapshot {
        var s = RoundSnapshot(round: row)
        s.eventDate = date
        s.players = bays.keys.sorted().map { p in
            RoundPlayerRow(roundID: row.id, memberID: id(p), clubID: club, handicapIndex: 0, seedGroup: nil,
                           playingHandicap: 0, bayNo: bays[p], isMarker: false, teamNo: nil)
        }
        s.course = CourseRow(id: courseID, clubID: club, name: "Testbanen", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map {
            CourseHoleRecord(courseID: courseID, holeNumber: $0 + 1, par: par[$0], strokeIndex: $0 + 1, lengthM: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: four.map { ($0.id, $0.displayName) })
        return s
    }

    /// En runde der spilleren går `over` slag over par på alle hullene.
    static func round(_ n: Int, date: String, over: [Int: Int], status: RoundStatus = .locked,
                      bays: [Int: Int]? = nil, hide: Int? = nil) -> RoundSnapshot {
        var row = roundRow(n, status: status)
        row.hideLastHoles = hide
        var s = base(row, date: date, bays: bays ?? over.mapValues { _ in 1 })
        s.scores = over.flatMap { p, extra in
            par.enumerated().map { h, par in score(row.id, p, h, par + extra) }
        }
        return s
    }

    static func score(_ round: UUID, _ p: Int, _ hole: Int, _ strokes: Int) -> HoleScoreRow {
        HoleScoreRow(roundID: round, memberID: id(p), holeIndex: hole, strokes: strokes, recordedAt: nil,
                     updatedBy: nil, updatedAt: nil)
    }

    /// Playoff-runden: hullene [18, 1, 18], scorene per posisjon.
    static func playoff(_ scores: [Int: [Int]], holes: [Int] = [17, 0, 17], status: RoundStatus = .active,
                        players: [Int] = [anders, bjorn]) -> RoundSnapshot {
        var row = roundRow(9, status: status)
        row.kind = "playoff"
        row.playoffFor = competition
        row.playoffHoles = holes
        row.counts = false
        row.name = "Playoff"
        var s = base(row, date: "2026-05-08", bays: Dictionary(uniqueKeysWithValues: players.map { ($0, 1) }))
        s.scores = scores.flatMap { p, list in list.enumerated().map { score(row.id, p, $0, $1) } }
        return s
    }

    static func rules(tieRule: Ruleset.TieRule = .playoff) -> Ruleset {
        var r = Ruleset.golfgutu
        r.table.pointsSource = .stableford
        r.table.counting = Ruleset.Counting(unit: .round, best: nil)
        r.table.tiebreaks = [.stableford]
        r.table.tieRule = tieRule
        r.sidePrizes.longestDrive.enabled = false
        r.sidePrizes.closestToPin.enabled = false
        return r
    }

    /// Anders og Bjørn står likt øverst, Cato bak.
    static func standings(extra: [RoundSnapshot] = [], viewer: Viewer? = nil) -> TavlaStandings {
        let rounds = [round(1, date: "2026-05-01", over: [anders: 0, bjorn: 0, cato: 1]),
                      round(2, date: "2026-05-08", over: [anders: 1, bjorn: 1])] + extra
        let season = SeasonRow(id: id(882), clubID: club, name: "Vår 2026", status: .active, rules: rules())
        return TavlaStandings(TavlaInput(season: season, members: four, rounds: rounds), me: id(anders), viewer: viewer)
    }
}

struct RundeTabellreglerLesingTests {
    @Test func utenKolonneneGjelderStandardverdiene() throws {
        let json = """
        {"id":"\(P.id(1))","club_id":"\(P.club)","event_id":null,"course_id":null,"round_no":1,"name":null,
         "status":"active","hole_count":18,"first_hole":1,"tee_time":null,"format":"stableford",
         "handicap_allowance":1,"external_handicap":false,"weight":1,"ld_enabled":true,"ld_hole_index":null,
         "kp_enabled":true,"kp_hole_index":null,"cut_rule":null,"cut_after":null,"par_confirmed_by":null,
         "par_confirmed_at":null,"started_at":null,"locked_at":null}
        """
        let row = try JSONDecoder().decode(RoundRow.self, from: Data(json.utf8))
        #expect(row.countsInTable && row.pointsTable == nil && row.hiddenLastHoles == 0 && !row.isPlayoff)
        let round = RoundGame.makeRound(RoundSnapshot(round: row))
        #expect(round.counts && round.pointsTable == nil && round.hideLastHoles == 0)
    }

    @Test func kolonneneLesesInnIRunden() throws {
        let json = """
        {"id":"\(P.id(1))","club_id":"\(P.club)","event_id":null,"course_id":null,"round_no":1,"name":null,
         "status":"active","hole_count":18,"first_hole":1,"tee_time":null,"format":"stableford",
         "handicap_allowance":1,"external_handicap":false,"weight":1,"ld_enabled":true,"ld_hole_index":null,
         "kp_enabled":true,"kp_hole_index":null,"cut_rule":null,"cut_after":null,"par_confirmed_by":null,
         "par_confirmed_at":null,"started_at":null,"locked_at":null,
         "counts":false,"points_table":"finale","hide_last_holes":3,"kind":"playoff",
         "playoff_for":"\(P.competition)","playoff_holes":[17,0,17]}
        """
        let row = try JSONDecoder().decode(RoundRow.self, from: Data(json.utf8))
        #expect(!row.countsInTable && row.pointsTable == "finale" && row.hiddenLastHoles == 3)
        #expect(row.isPlayoff && row.playoffFor == P.competition && row.playoffHoles == [17, 0, 17])
        let round = RoundGame.makeRound(RoundSnapshot(round: row))
        #expect(!round.counts && round.pointsTable == "finale" && round.hideLastHoles == 3)
    }

    @Test func enPlayoffTellerAldri() {
        var row = P.roundRow(1)
        row.kind = "playoff"
        row.counts = true
        #expect(!RoundGame.makeRound(RoundSnapshot(round: row)).counts)
    }

    @Test func kolonneneSendesBareMed047() throws {
        var draft = RoundDraft.new(eventID: P.id(5), roundNo: 1, teeTime: nil, participants: [], source: .signups,
                                   rules: .golfgutu)
        draft.counts = false
        draft.pointsTable = "finale"
        draft.hidesLastHoles = true
        let with = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            RoundWrite(draft: draft, clubID: P.club, course: nil, includeRules: true))) as! [String: Any]
        #expect(with["counts"] as? Bool == false)
        #expect(with["points_table"] as? String == "finale")
        #expect(with["hide_last_holes"] as? Int == 3)
        let without = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            RoundWrite(draft: draft, clubID: P.club, course: nil, includeRules: false))) as! [String: Any]
        #expect(without["counts"] == nil && without["points_table"] == nil && without["hide_last_holes"] == nil)

        // «Vanlig» sendes som null, så en tabell tømmes.
        draft.pointsTable = nil
        draft.hidesLastHoles = false
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            RoundWrite(draft: draft, clubID: P.club, course: nil, includeRules: true))) as! [String: Any]
        #expect(plain["points_table"] is NSNull)
        #expect(plain["hide_last_holes"] as? Int == 0)
    }

    @Test func lagretOppsettLesesTilbake() {
        var row = P.roundRow(1, status: .draft)
        row.counts = false
        row.pointsTable = "finale"
        row.hideLastHoles = 3
        let draft = RoundDraft.saved(row, players: [], matches: [], participants: [], source: .signups)
        #expect(!draft.counts && draft.pointsTable == "finale" && draft.hidesLastHoles)
    }

    @Test func poengtabellValgene() {
        var rules = Ruleset.golfgutu
        rules.table.pointsTables = ["finale": .init(multiplier: 2), "dobbel": .init(multiplier: 1.5)]
        #expect(RoundTableRules.tableNames(rules) == ["dobbel", "finale"])
        #expect(RoundTableRules.title("finale", rules: rules) == "Finale (× 2)")
        #expect(RoundTableRules.title("dobbel", rules: rules) == "Dobbel (× 1,5)")
        #expect(RoundTableRules.choices(["finale"], current: "borte") == ["finale", "borte"])
    }
}

struct SkjulteHullTests {
    /// Anders og Bjørn i bås 1, Cato i bås 2, runden går med de tre siste hullene skjult.
    static let active = P.round(3, date: "2026-05-15", over: [P.anders: 0, P.bjorn: 0, P.cato: 0], status: .active,
                                bays: [P.anders: 1, P.bjorn: 1, P.cato: 2], hide: 3)

    static func holes(_ s: RoundSnapshot, _ p: Int) -> Set<Int> {
        Set(s.scores.filter { $0.memberID == P.id(p) }.map(\.holeIndex))
    }

    @Test func baasenDinSerAltDeAndreIkkeDeSisteHullene() {
        let s = HiddenHoles.apply(Self.active, viewer: Viewer(memberID: P.id(P.anders), isOrganizer: false))
        #expect(Self.holes(s, P.anders).count == 18 && Self.holes(s, P.bjorn).count == 18)
        #expect(Self.holes(s, P.cato) == Set(0..<15))
        #expect(HiddenHoles.isHiding(Self.active, viewer: Viewer(memberID: P.id(P.anders), isOrganizer: false)))
    }

    @Test func enAnnenBaasSerIkkeDinBaas() {
        let s = HiddenHoles.apply(Self.active, viewer: Viewer(memberID: P.id(P.cato), isOrganizer: false))
        #expect(Self.holes(s, P.cato).count == 18)
        #expect(Self.holes(s, P.anders) == Set(0..<15) && Self.holes(s, P.bjorn) == Set(0..<15))
    }

    @Test func arrangorenSerAlt() {
        let viewer = Viewer(memberID: P.id(P.dag), isOrganizer: true)
        #expect(HiddenHoles.apply(Self.active, viewer: viewer) == Self.active)
        #expect(!HiddenHoles.isHiding(Self.active, viewer: viewer))
    }

    @Test func denSomIkkeSpillerSerIngenAvDeSisteHullene() {
        let s = HiddenHoles.apply(Self.active, viewer: Viewer(memberID: P.id(P.dag), isOrganizer: false))
        for p in [P.anders, P.bjorn, P.cato] { #expect(Self.holes(s, p) == Set(0..<15)) }
    }

    @Test func utenBaasSerDuBareDegSelv() {
        var round = Self.active
        round.players = round.players.map { var p = $0; p.bayNo = nil; return p }
        let s = HiddenHoles.apply(round, viewer: Viewer(memberID: P.id(P.anders), isOrganizer: false))
        #expect(Self.holes(s, P.anders).count == 18 && Self.holes(s, P.bjorn) == Set(0..<15))
    }

    @Test func laastRundeOgAvSlaattViserAlt() {
        var locked = Self.active
        locked.round.status = .locked
        let viewer = Viewer(memberID: P.id(P.dag), isOrganizer: false)
        #expect(HiddenHoles.apply(locked, viewer: viewer) == locked)
        #expect(!HiddenHoles.isHiding(locked, viewer: viewer))
        var off = Self.active
        off.round.hideLastHoles = 0
        #expect(HiddenHoles.apply(off, viewer: viewer) == off)
    }

    @Test func tavlaRegnerUtenDeSkjulteHulleneForAndre() {
        let viewer = Viewer(memberID: P.id(P.dag), isOrganizer: false)
        let hidden = P.standings(extra: [Self.active], viewer: viewer)
        let all = P.standings(extra: [Self.active], viewer: Viewer(memberID: P.id(P.dag), isOrganizer: true))
        #expect(hidden.hidesLastHoles && !all.hidesLastHoles)
        let anders = hidden.row(P.id(P.anders))!, andersAll = all.row(P.id(P.anders))!
        #expect(anders.roundPoints < andersAll.roundPoints)
    }

    @Test func ingenStorScoreEllerLedelsePaaSkjultHull() {
        let game = RoundGame(Self.active)
        #expect(game.bigScoreEventsAfterSaving(hole: 16, fresh: [(P.id(P.anders), 1)]).isEmpty)
        #expect(!game.bigScoreEventsAfterSaving(hole: 2, fresh: [(P.id(P.anders), 1)]).isEmpty)
        #expect(!game.shouldCheckLead(afterSaving: 17, fresh: [(P.id(P.anders), 4)]))
    }
}

struct PlayoffRundeTests {
    @Test func playoffenErIngenVanligRunde() {
        let playoff = P.playoff([:])
        let t = P.standings(extra: [playoff])
        #expect(!t.snapshots.contains { $0.round.isPlayoff })
        #expect(t.snapshots.count == 2)
        #expect(t.playoff?.snapshot.round.id == playoff.round.id)
        // Kveld og «Gå til runden» velger aldri playoffen.
        #expect(ActiveRounds.pick([playoff.round], mine: [playoff.round.id], preferred: playoff.round.id) == nil)
        let normal = P.roundRow(3, status: .active)
        #expect(ActiveRounds.pick([playoff.round, normal], mine: [], preferred: nil)?.id == normal.id)
        #expect(ActiveRounds.blocking([playoff.round], roundID: normal.id, eventID: playoff.round.eventID!, waves: [:]) == nil)
    }

    @Test func hullOgPosisjoner() {
        let state = PlayoffState(snapshot: P.playoff([P.anders: [4, 5], P.bjorn: [4]]))
        #expect(state.holes.map(\.holeIndex) == [17, 0, 17])
        #expect(state.holes.map(\.number) == [18, 1, 18])
        #expect(state.holes.map(\.par) == [4, 4, 4])
        #expect(state.holes.map(\.position) == [0, 1, 2])
        // Scorene per posisjon, sammenhengende fra første.
        let scores = PlayoffState.scores(state.snapshot)
        #expect(scores[P.id(P.anders).uuidString] == [4, 5] && scores[P.id(P.bjorn).uuidString] == [4])
        #expect(state.nextPosition == 1 && state.winner == nil)
        #expect(state.strokes(P.id(P.anders), at: 1) == 5)
    }

    @Test func avgjortPaaForsteHullMedEnBeste() {
        let state = PlayoffState(snapshot: P.playoff([P.anders: [4, 4], P.bjorn: [4, 5]]),
                                 tied: [P.id(P.anders), P.id(P.bjorn)])
        #expect(state.winner == P.id(P.anders))
        #expect(state.statusText { $0 == P.id(P.anders) ? "Anders" : "Bjørn" } == "Anders vant på playoff-hull 2")
    }

    @Test func fortsattLiktEtterAlleHullene() {
        let state = PlayoffState(snapshot: P.playoff([P.anders: [4], P.bjorn: [4]], holes: [17]))
        #expect(state.needsMoreHoles && state.winner == nil)
        #expect(state.statusText { _ in "" } == "Fortsatt likt")
        #expect(PlayoffState.extended([17], holeCount: 18) == [17, 0])
        #expect(PlayoffState.extended([17, 0], holeCount: 18) == [17, 0, 17])
    }

    @Test func vinnerenGaarInnITabellen() {
        let t = P.standings(extra: [P.playoff([P.anders: [5], P.bjorn: [4]])])
        #expect(t.rows.map(\.name).prefix(2) == ["Bjørn", "Anders"])
        let bjorn = t.row(P.id(P.bjorn))!, anders = t.row(P.id(P.anders))!
        #expect(bjorn.place == 1 && anders.place == 2)
        #expect(!bjorn.playoffPending && !anders.playoffPending)
        #expect(t.tiedForFirst == [P.id(P.anders), P.id(P.bjorn)])
    }

    @Test func ikkeAvgjortStaarSomVentende() {
        let t = P.standings(extra: [P.playoff([P.anders: [4], P.bjorn: [4]])])
        #expect(t.row(P.id(P.anders))!.playoffPending && t.row(P.id(P.bjorn))!.playoffPending)
    }

    @Test func playoffUtenAlleSomStaarLiktTellerIkke() {
        let t = P.standings(extra: [P.playoff([P.anders: [4]], players: [P.anders])])
        #expect(t.row(P.id(P.anders))!.playoffPending)
    }

    @Test func mineRunderViserPlayoff() {
        var loose = P.playoff([P.anders: [5], P.bjorn: [4]], status: .locked)
        loose.round = RoundRow(id: loose.round.id, clubID: nil, eventID: nil, courseID: P.courseID, roundNo: 0,
                               name: "Playoff", status: .locked, holeCount: 18, firstHole: 1, teeTime: nil,
                               format: "stableford", handicapAllowance: 1, externalHandicap: false, weight: 1,
                               ldEnabled: false, ldHoleIndex: nil, kpEnabled: false, kpHoleIndex: nil, cutRule: nil,
                               cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil, startedAt: nil, lockedAt: nil,
                               counts: false, kind: "playoff", playoffFor: P.competition, playoffHoles: [17, 0, 17])
        let item = MyRounds.item(loose, userID: P.id(77))
        #expect(item.isPlayoff && item.title == "Playoff")
        #expect(item.subtitle.contains("3 playoff-hull"))
        #expect(item.leader == "Bjørn vant på playoff-hull 1")
    }

    @Test func ligaenFaarVinnerenForst() {
        let a = Entrant.member(P.id(P.anders)), b = Entrant.member(P.id(P.bjorn)), c = Entrant.member(P.id(P.cato))
        let places = [(entrant: a, place: 1), (entrant: b, place: 1), (entrant: c, place: 3)]
        let decided = LeaguePlayoff.apply(places: places, playoff: P.playoff([P.anders: [5], P.bjorn: [4]]))
        #expect(decided[b] == 1 && decided[a] == 2 && decided[c] == 3)
        let open = LeaguePlayoff.apply(places: places, playoff: P.playoff([P.anders: [4], P.bjorn: [4]]))
        #expect(open[a] == 1 && open[b] == 1)
        #expect(LeaguePlayoff.apply(places: places, playoff: nil)[b] == 1)
    }

    @Test func hvemKanStarte() {
        #expect(PlayoffRules.canStart(rights: ClubRights(rights: [.tournaments])))
        #expect(PlayoffRules.canStart(rights: ClubRights(rights: [.rounds])))
        #expect(!PlayoffRules.canStart(rights: ClubRights(rights: [.money])))
    }
}
