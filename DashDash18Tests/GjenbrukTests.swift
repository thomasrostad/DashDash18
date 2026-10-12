import Foundation
import GolfgutuCore
import Supabase
import Testing
@testable import DashDash18

// Steg 8 (sql/049): serie av spilledager, egne maler og «Samme som sist».

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)

private func member(_ n: Int, _ name: String) -> ClubMemberRow {
    ClubMemberRow(id: id(n), clubID: club, userID: UUID(), displayName: name, handicapIndex: 10, seedGroup: nil,
                  isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
}

private let roster = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode"].enumerated()
    .map { member($0.offset + 1, $0.element) }

private func course(_ n: Int, holes: Int = 18, ready: Bool = true) -> CourseListItem {
    let row = CourseRow(id: id(n), clubID: club, name: "Bane \(n)", externalName: nil, courseRating: 72,
                        slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
    let records = (1...holes).map { h in
        CourseHoleRecord(courseID: id(n), holeNumber: h, par: 4, strokeIndex: h, lengthM: nil)
    }
    return CourseListItem(course: row, holes: ready ? records : [])
}

private func newDraft(rules: Ruleset = .golfgutu) -> RoundDraft {
    var draft = RoundDraft.new(eventID: id(503), roundNo: 1, teeTime: "18:00:00",
                               participants: roster.map(\.id), source: .signups, rules: rules)
    draft.courseID = id(702)
    return draft
}

private func json(_ value: some Encodable) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
}

// MARK: - Serie av spilledager

struct SerieDatoerTests {
    @Test func isoUkedag() {
        #expect(EventSeriesDates.isoWeekday("2026-10-12") == 1)  // mandag
        #expect(EventSeriesDates.isoWeekday("2026-10-15") == 4)  // torsdag
        #expect(EventSeriesDates.isoWeekday("2026-10-18") == 7)  // søndag
        #expect(EventSeriesDates.isoWeekday("2026-02-30") == nil)
    }

    @Test func startdatoenErRiktigUkedag() {
        #expect(EventSeriesDates.dates(start: "2026-10-15", weekday: 4, count: 3, everyWeeks: 1)
                == ["2026-10-15", "2026-10-22", "2026-10-29"])
    }

    @Test func startEtterUkedagenGaarTilNesteUke() {
        // Fredag 16. oktober, torsdag ønsket: første er torsdag 22.
        #expect(EventSeriesDates.firstDate(onOrAfter: "2026-10-16", weekday: 4) == "2026-10-22")
        // Søndag 18., mandag ønsket: dagen etter.
        #expect(EventSeriesDates.firstDate(onOrAfter: "2026-10-18", weekday: 1) == "2026-10-19")
        // Mandag 12., søndag ønsket: samme uke.
        #expect(EventSeriesDates.firstDate(onOrAfter: "2026-10-12", weekday: 7) == "2026-10-18")
    }

    @Test func annenhverUke() {
        #expect(EventSeriesDates.dates(start: "2026-10-12", weekday: 2, count: 3, everyWeeks: 2)
                == ["2026-10-13", "2026-10-27", "2026-11-10"])
    }

    @Test func overNyttaarOgSommertid() {
        #expect(EventSeriesDates.dates(start: "2026-12-24", weekday: 4, count: 3, everyWeeks: 1)
                == ["2026-12-24", "2026-12-31", "2027-01-07"])
        // Sommertiden slutter 25. oktober 2026: datoene flytter seg ikke.
        #expect(EventSeriesDates.dates(start: "2026-10-20", weekday: 2, count: 2, everyWeeks: 1)
                == ["2026-10-20", "2026-10-27"])
    }

    @Test func ugyldigGirIngenDatoer() {
        #expect(EventSeriesDates.dates(start: "2026-10-12", weekday: 8, count: 3, everyWeeks: 1).isEmpty)
        #expect(EventSeriesDates.dates(start: "2026-10-12", weekday: 1, count: 0, everyWeeks: 1).isEmpty)
        #expect(EventSeriesDates.dates(start: "tull", weekday: 1, count: 3, everyWeeks: 1).isEmpty)
    }

    @Test func datoerSomFinnesHoppesOver() {
        let plan = SeriesPlan(weekday: 4, count: 4)
        let preview = EventSeriesDates.preview(start: "2026-10-15", plan: plan, existing: ["2026-10-22", "2026-11-26"])
        #expect(preview.created == ["2026-10-15", "2026-10-29", "2026-11-05"])
        #expect(preview.skipped == ["2026-10-22"])
    }

    @Test func tekstene() {
        #expect(SeriesText.summary(weekday: 4, everyWeeks: 1, startTime: "18:00:00") == "Hver torsdag kl. 18:00")
        #expect(SeriesText.summary(weekday: 2, everyWeeks: 2, startTime: nil) == "Annenhver tirsdag")
        #expect(SeriesText.summary(weekday: 1, everyWeeks: 3, startTime: "17:30") == "Hver 3. uke på mandag kl. 17:30")
        #expect(SeriesText.every(1) == "Hver uke")
        #expect(SeriesText.skippedDates([]) == nil)
        let result = CreateSeriesResult(seriesID: id(1), eventIDs: [id(2)], dates: ["2026-10-15"], skipped: ["2026-10-22"])
        #expect(SeriesText.created(result) == "1 dato er lagt inn. Hoppet over 22. oktober, som alt var i bruk.")
        let updated = UpdateSeriesResult(updated: [id(2), id(3)], skipped: [id(4)], shiftedDays: 0)
        #expect(SeriesText.updated(updated, dates: [id(4): "2026-10-08"])
                == "2 endret. Ikke endret: 8. oktober (passert eller startet).")
        #expect(SeriesText.updated(UpdateSeriesResult(updated: [id(2)], skipped: [], shiftedDays: 7), dates: [:]) == nil)
    }

    @Test func planenSomSendesOgLagres() throws {
        let plan = SeriesPlan(weekday: 4, everyWeeks: 2, count: 8, startTime: "18:00:00", venue: "  Holtsmark ")
        let object = try json(plan)
        #expect(object["weekday"] as? Int == 4)
        #expect(object["every_weeks"] as? Int == 2)
        #expect(object["count"] as? Int == 8)
        #expect(object["start_time"] as? String == "18:00")
        #expect(object["venue"] as? String == "Holtsmark")
        // Mangler noe, gjelder standarden; verdier utenfor grensene trekkes inn.
        let loose = try JSONDecoder().decode(SeriesPlan.self, from: Data(#"{"weekday": 9, "count": 80}"#.utf8))
        #expect(loose == SeriesPlan(weekday: 7, everyWeeks: 1, count: 52))
    }

    @Test func svaretFraRPCene() throws {
        let created = try JSONDecoder().decode(CreateSeriesResult.self, from: Data("""
            {"series_id": null, "event_ids": [], "dates": [], "skipped": ["2026-10-15"]}
            """.utf8))
        #expect(created.seriesID == nil)
        #expect(created.skipped == ["2026-10-15"])
        let updated = try JSONDecoder().decode(UpdateSeriesResult.self, from: Data("""
            {"updated": ["\(id(1).uuidString)"], "skipped": [], "shifted_days": -7}
            """.utf8))
        #expect(updated.updated == [id(1)])
        #expect(updated.shiftedDays == -7)
    }
}

// MARK: - Maler

struct MalTests {
    @Test func rundemalTurOgRetur() throws {
        var draft = newDraft()
        draft.courseID = id(701)
        draft.teeID = id(55)
        draft.holeCount = 9
        draft.firstHole = 10
        draft.allowance = 0.85
        draft.weight = 2
        draft.counts = false
        draft.pointsTable = "finale"
        draft.hidesLastHoles = true
        draft.ldHoleIndex = 3
        draft.venue = .course
        var payload = RoundTemplatePayload(draft: draft)
        payload.games = [TemplateGame(kind: "skins", settings: .object(["stake": .integer(10)]))]

        let data = try JSONEncoder().encode(payload)
        #expect(try JSONDecoder().decode(RoundTemplatePayload.self, from: data) == payload)

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["version", "course_id", "tee_id", "hole_count", "first_hole", "format",
                                     "handicap_allowance", "external_handicap", "venue", "ld_enabled",
                                     "ld_hole_index", "kp_enabled", "kp_hole_index", "weight", "counts",
                                     "points_table", "hide_last_holes", "games"])
        #expect(object["hole_count"] as? Int == 9)
        #expect(object["first_hole"] as? Int == 10)
        #expect(object["hide_last_holes"] as? Int == 3)
        #expect(object["venue"] as? String == "course")
        #expect(object["kp_hole_index"] is NSNull)
        // Spillerne er aldri med i en mal.
        #expect(object["players"] == nil)
    }

    @Test func rundemalTaalerManglendeOgUkjenteNokler() throws {
        let empty = try JSONDecoder().decode(RoundTemplatePayload.self, from: Data("{}".utf8))
        #expect(empty == RoundTemplatePayload())
        #expect(empty.holeCount == 18 && empty.weight == 1 && empty.counts && empty.games.isEmpty)
        let odd = try JSONDecoder().decode(RoundTemplatePayload.self, from: Data("""
            {"hole_count": 9, "weight": "tung", "framtidig": true, "games": [{"kind": "wolf"}]}
            """.utf8))
        #expect(odd.holeCount == 9)
        #expect(odd.weight == 1)
        #expect(odd.games == [TemplateGame(kind: "wolf")])
    }

    @Test func turneringsmalTurOgRetur() throws {
        var draft = TournamentDraft(template: .matchSeries, clubID: club, name: "Høst 2026", today: "2026-10-12")
        draft.dayTerm = .evening
        draft.rules.evenings = 9
        draft.schedule = SeriesPlan(weekday: 4, count: 9, startTime: "18:00", venue: "Holtsmark")
        let payload = TournamentTemplatePayload(draft: draft)
        #expect(payload.template == .matchSeries)
        #expect(payload.kind == .season)
        #expect(payload.rules.dayTerm == .evening)

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(TournamentTemplatePayload.self, from: data)
        #expect(decoded == payload)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["version", "template", "kind", "rules", "schedule", "venue", "entry",
                                     "signup_open", "max_entrants"])
        let schedule = try #require(object["schedule"] as? [String: Any])
        #expect(Set(schedule.keys) == ["weekday", "every_weeks", "count", "start_time", "venue"])

        // Brukt igjen: reglene, ordet for dagen og planen kommer tilbake.
        let again = decoded.draft(name: "Vår 2027", clubID: club, today: "2027-03-01")
        #expect(again.template == .matchSeries)
        #expect(again.rules.evenings == 9)
        #expect(again.dayTerm == .evening)
        #expect(again.schedule == draft.schedule)
        #expect(again.target == .season)
        // Uten klubb blir det ingen serie.
        #expect(decoded.draft(name: "x", clubID: nil, today: "2027-03-01").schedule == nil)
    }

    @Test func cupmalHuskerCupreglene() throws {
        var draft = TournamentDraft(template: .cup, clubID: club, name: "Høstcupen", today: "2026-10-12")
        draft.competition.cup.seeding = CupRules.Seeding.allCases.last!
        let payload = TournamentTemplatePayload(draft: draft)
        #expect(payload.kind == .cup)
        let decoded = try JSONDecoder().decode(TournamentTemplatePayload.self, from: JSONEncoder().encode(payload))
        let again = decoded.draft(name: "Vårcupen", clubID: club, today: "2027-03-01")
        #expect(again.competition.cup.seeding == CupRules.Seeding.allCases.last!)
        #expect(again.competition.entry == draft.competition.entry)
    }

    @Test func turneringsmalUtenOppsettBrukerTypen() throws {
        // Fra web-admin eller en eldre mal: bare typen.
        let decoded = try JSONDecoder().decode(TournamentTemplatePayload.self, from: Data(#"{"kind": "cup"}"#.utf8))
        #expect(decoded.template == .cup)
        #expect(decoded.kind == .cup)
        #expect(decoded.schedule == nil)
        let fun = try JSONDecoder().decode(TournamentTemplatePayload.self, from: Data(#"{"template": "fun"}"#.utf8))
        #expect(fun.kind == .fun)
    }

    @Test func malnavn() throws {
        #expect(try TemplateName.clean("  Torsdag  ").get() == "Torsdag")
        #expect((try? TemplateName.clean("   ").get()) == nil)
        #expect((try? TemplateName.clean(String(repeating: "a", count: 61)).get()) == nil)
    }
}

// MARK: - Samme som sist

struct SammeSomSistTests {
    private func previousJSON(players: String, matches: String) -> Data {
        Data("""
        {"round_id": "\(id(1).uuidString)", "event_id": "\(id(502).uuidString)", "event_date": "2026-10-08",
         "round_no": 2, "name": null, "status": "locked", "course_id": "\(id(701).uuidString)", "tee_id": null,
         "hole_count": 9, "first_hole": 10, "format": "\(Ruleset.golfgutu.formats.defaultFormID)",
         "handicap_allowance": 0.85, "external_handicap": false, "venue": "course",
         "ld_enabled": false, "ld_hole_index": 3, "kp_enabled": true, "kp_hole_index": 12,
         "weight": 2, "counts": false, "points_table": "finale", "hide_last_holes": 3, "wave_no": 1,
         "players": \(players), "matches": \(matches),
         "games": [{"kind": "skins", "settings": {"stake": 10}}]}
        """.utf8)
    }

    private func player(_ n: Int, bay: Int, marker: Bool = false, team: Int? = nil) -> String {
        """
        {"member_id": "\(id(n).uuidString)", "bay_no": \(bay), "is_marker": \(marker), \
        "team_no": \(team.map(String.init) ?? "null"), "seed_group": null}
        """
    }

    private var standard: Data {
        previousJSON(players: "[\(player(1, bay: 1, marker: true)), \(player(2, bay: 1)), "
                     + "\(player(3, bay: 2, marker: true)), \(player(4, bay: 2)), \(player(77, bay: 2))]",
                     matches: """
                     [{"match_no": 2, "player_a": "\(id(3).uuidString)", "player_b": "\(id(77).uuidString)",
                       "player_c": null, "team_a": null, "team_b": null},
                      {"match_no": 1, "player_a": "\(id(1).uuidString)", "player_b": "\(id(2).uuidString)",
                       "player_c": null, "team_a": null, "team_b": null}]
                     """)
    }

    @Test func lesesFraRPCen() throws {
        let previous = try JSONDecoder().decode(PreviousRoundSetup.self, from: standard)
        #expect(previous.roundNo == 2)
        #expect(previous.eventDate == "2026-10-08")
        #expect(previous.players.count == 5)
        #expect(previous.matches.count == 2)
        #expect(previous.setup.holeCount == 9)
        #expect(previous.setup.games == [TemplateGame(kind: "skins", settings: .object(["stake": .integer(10)]))])
        #expect(previous.sourceText == "Fra torsdag 8. oktober, runde 2 · 5 spillere")
        // Ingen runde: null.
        let none = try JSONDecoder().decode(PreviousRoundSetup?.self, from: Data("null".utf8))
        #expect(none == nil)
    }

    @Test func oppsettetFyllesInn() throws {
        var rules = Ruleset.golfgutu
        rules.table.pointsTables["finale"] = Ruleset.PointsTable(multiplier: 2)
        let previous = try JSONDecoder().decode(PreviousRoundSetup.self, from: standard)
        var draft = newDraft(rules: rules)
        previous.setup.apply(to: &draft, courses: [course(701), course(702)], rules: rules, roster: roster)
        #expect(draft.courseID == id(701))
        #expect(draft.holeCount == 9)
        #expect(draft.firstHole == 10)
        #expect(draft.venue == .course)
        #expect(draft.allowance == 0.85)
        #expect(draft.weight == 2)
        #expect(!draft.counts)
        #expect(draft.pointsTable == "finale")
        #expect(draft.hidesLastHoles)
        #expect(!draft.ldEnabled)
        #expect(draft.kpEnabled)
        #expect(draft.ldHoleIndex == 3)
        #expect(draft.kpHoleIndex == nil)  // hull 13 finnes ikke i en 9-hullsrunde
        // Spillerne står til arrangøren velger «Samme spillere».
        #expect(draft.participants == roster.map(\.id))
    }

    @Test func banenSomIkkeErKlarOgUkjentTabellHoppesOver() throws {
        let previous = try JSONDecoder().decode(PreviousRoundSetup.self, from: standard)
        var draft = newDraft()
        previous.setup.apply(to: &draft, courses: [course(701, ready: false), course(702)], rules: .golfgutu,
                             roster: roster)
        #expect(draft.courseID == id(702))
        #expect(draft.holeCount == 18)
        #expect(draft.pointsTable == nil)  // «finale» finnes ikke i regelsettet
        #expect(draft.weight == 2)
    }

    @Test func sammeSpillereOgBaaser() throws {
        let previous = try JSONDecoder().decode(PreviousRoundSetup.self, from: standard)
        var draft = newDraft()
        previous.applyPlayers(to: &draft, roster: roster)
        // Nr. 77 har sluttet: står ikke med, og matchen hans er borte.
        #expect(draft.participants == [id(1), id(2), id(3), id(4)])
        #expect(draft.participantSource == .saved)
        #expect(draft.bays.marker(in: 1) == id(1))
        #expect(draft.bays.marker(in: 2) == id(3))
        #expect(draft.bays.members(in: 2) == [id(3), id(4)])
        #expect(draft.matches == [MatchDraft(playerA: id(1), playerB: id(2))])
        #expect(draft.teams.isEmpty)
    }
}
