import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)
private let eventID = id(500)

private func member(_ n: Int, _ name: String, hcp: Double? = nil, seed: Int? = nil) -> ClubMemberRow {
    ClubMemberRow(id: id(n), clubID: club, userID: UUID(), displayName: name, handicapIndex: hcp, seedGroup: seed,
                  isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
}

/// Troppen fra markor-test.js: a–h.
private let roster = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode", "Gunnar", "Halvor"]
    .enumerated().map { member($0.offset + 1, $0.element) }
private let a = id(1), b = id(2), c = id(3), d = id(4), e = id(5), f = id(6), g = id(7), h = id(8)

private func course(holes: Int = 18, par: Int? = 4, rating: Double? = 72, slope: Int? = 113, name: String = "Testbanen") -> CourseListItem {
    let row = CourseRow(id: id(700), clubID: club, name: name, externalName: nil, courseRating: rating,
                        slopeRating: slope, inUse: true, confirmedBy: nil, confirmedAt: nil)
    let records = (1...holes).map { n in
        CourseHoleRecord(courseID: id(700), holeNumber: n, par: par ?? 0, strokeIndex: n, lengthM: nil)
    }
    return CourseListItem(course: row, holes: par == nil ? [] : records)
}

private func perBay(_ plan: BayPlan) -> [Int: Int] { plan.counts }

// MARK: - Båser (markor-test.js, paamelding-test.js)

struct BayPlanTests {
    @Test func aatteMannPaaTreBaaserMedEnMarkoerHver() {
        let plan = BayPlan.suggested(participants: [a, b, c, d, e, f, g, h], bays: 3)
        #expect(perBay(plan) == [1: 3, 2: 3, 3: 2])
        for bay in 1...3 {
            #expect(plan.seats.filter { $0.bay == bay && $0.isMarker }.count == 1)
        }
        // Markør = den første i en tom bås.
        #expect(plan.marker(in: 1) == a && plan.marker(in: 2) == b && plan.marker(in: 3) == c)
    }

    @Test func tolvBlirFireFireFire() {
        let twelve = (1...12).map(id)
        let count = BayPlan.defaultBayCount(players: 12, maxPerBay: Ruleset.golfgutu.formats.maxPerBay)
        #expect(count == 3)
        let plan = BayPlan.suggested(participants: twelve, bays: count)
        #expect(perBay(plan) == [1: 4, 2: 4, 3: 4])
        #expect(plan.baysWithoutMarker.isEmpty)
        #expect(plan.seats.filter(\.isMarker).count == 3)
    }

    @Test func antallBaaserFoelgerRegelsettet() {
        #expect(BayPlan.defaultBayCount(players: 0, maxPerBay: 4) == 1)
        #expect(BayPlan.defaultBayCount(players: 4, maxPerBay: 4) == 1)
        #expect(BayPlan.defaultBayCount(players: 5, maxPerBay: 4) == 2)
        #expect(BayPlan.defaultBayCount(players: 12, maxPerBay: 6) == 2)
    }

    @Test func duellpartnereSitterISammeBaas() {
        // Kvelden fra markor-test.js: a–h, c–f, e–b. Dag og Gunnar er ikke med.
        let groups = [[a, h], [c, f], [e, b]]
        let plan = BayPlan.suggested(participants: [a, b, c, e, f, h], matchGroups: groups, bays: 2)
        #expect(plan.seat(for: d) == nil && plan.seat(for: g) == nil)
        #expect(plan.seat(for: a)?.bay == plan.seat(for: h)?.bay)
        #expect(plan.seat(for: c)?.bay == plan.seat(for: f)?.bay)
        #expect(plan.seat(for: e)?.bay == plan.seat(for: b)?.bay)
        #expect(plan.baysWithoutMarker.isEmpty)
    }

    @Test func spillereUtenforRundenIMatchHoppesOver() {
        let plan = BayPlan.suggested(participants: [a, b], matchGroups: [[a, d], [b, a]], bays: 1)
        #expect(plan.seats.map(\.memberID) == [a, b])
    }

    @Test func markoerSomFlyttesLarIngenBaasStaaUten() {
        let twelve = (1...12).map(id)
        var plan = BayPlan.suggested(participants: twelve, bays: 3)
        let m1 = plan.marker(in: 1)!
        let m2 = plan.marker(in: 2)!
        plan.move(m1, to: 2)
        #expect(plan.marker(in: 2) == m2)
        #expect(plan.marker(in: 1) != nil && plan.marker(in: 1) != m1)
        #expect(plan.seat(for: m1)?.isMarker == false)

        plan.makeMarker(m1)
        #expect(plan.marker(in: 2) == m1)
        #expect(plan.seats.filter { $0.bay == 2 && $0.isMarker }.count == 1)
    }

    @Test func markoerTilTomBaasTarRollenMed() {
        var plan = BayPlan.suggested(participants: [a, b, c], bays: 1)
        plan.move(a, to: 2)
        #expect(plan.marker(in: 2) == a)
        #expect(plan.marker(in: 1) == b)
    }

    @Test func utAvBaaseneOgInnIgjen() {
        var plan = BayPlan.suggested(participants: [a, b, c, d, e], bays: 2)
        plan.move(a, to: nil)
        #expect(plan.seat(for: a) == nil)
        #expect(plan.marker(in: 1) == c)
        // Inn i båsen med færrest: bås 1 har c, e; bås 2 har b, d. Likt → laveste nummer.
        plan.add(a)
        #expect(plan.seat(for: a)?.bay == 1 && plan.seat(for: a)?.isMarker == false)

        var empty = BayPlan()
        empty.add(a)
        #expect(empty.seat(for: a) == BaySeat(memberID: a, bay: 1, isMarker: true))
    }
}

// MARK: - Deltakere (paamelding-test.js, rediger-kladd-test.js)

struct RoundParticipantsTests {
    private func signup(_ m: UUID, _ status: SignupStatus) -> SignupRow {
        SignupRow(eventID: eventID, memberID: m, clubID: club, status: status, comment: nil)
    }

    @Test func dePaameldteITroppensRekkefoelge() {
        let signups = [signup(e, .yes), signup(a, .yes), signup(b, .maybe), signup(c, .no), signup(h, .yes)]
        let result = RoundParticipants.initial(roster: roster, signups: signups)
        #expect(result.ids == [a, e, h])
        #expect(result.source == .signups)
    }

    @Test func ingenKommerGirAlle() {
        let result = RoundParticipants.initial(roster: roster, signups: [signup(b, .maybe)])
        #expect(result.ids == roster.map(\.id))
        #expect(result.source == .everyone)
    }

    @Test func kladdenBrukerDeSomErSattOpp() {
        let saved = [b, f, a].map {
            RoundPlayerRow(roundID: id(600), memberID: $0, clubID: club, handicapIndex: nil, seedGroup: nil,
                           playingHandicap: nil, bayNo: 1, isMarker: false, teamNo: nil)
        }
        let result = RoundParticipants.forDraft(roster: roster, saved: saved, signups: [signup(c, .yes)])
        #expect(result.ids == [a, b, f])
        #expect(result.source == .saved)
        let none = RoundParticipants.forDraft(roster: roster, saved: [], signups: [signup(c, .yes)])
        #expect(none.ids == [c] && none.source == .signups)
    }
}

// MARK: - Lag og matcher

struct TeamAndMatchTests {
    @Test func elleveIToerscrambleBlirTreTreTreTo() {
        let eleven = (1...11).map(id)
        let teams = TeamPlanner.suggested(participants: eleven, form: CompetitionForm.form(id: "scramble-2"), maxPerBay: 4)
        let sizes = Dictionary(grouping: teams.values, by: { $0 }).mapValues(\.count)
        #expect(sizes == [1: 3, 2: 3, 3: 3, 4: 2])
        #expect(TeamPlanner.problem(teams: teams, participants: eleven, form: CompetitionForm.form(id: "scramble-2"), maxPerBay: 4) == nil)
    }

    @Test func foursomeMedElleveGaarIkkeOpp() {
        let eleven = (1...11).map(id)
        #expect(TeamPlanner.suggested(participants: eleven, form: CompetitionForm.form(id: "foursome"), maxPerBay: 4).isEmpty)
    }

    @Test func lagSomIkkeGaarOpp() {
        let foursome = CompetitionForm.form(id: "foursome")
        let four = [a, b, c, d]
        #expect(TeamPlanner.problem(teams: [:], participants: four, form: foursome, maxPerBay: 4) == "Sett opp lagene før du starter runden.")
        #expect(TeamPlanner.problem(teams: [a: 1, b: 1, c: 1, d: 1], participants: four, form: foursome, maxPerBay: 4) == "Det må være minst to lag.")
        #expect(TeamPlanner.problem(teams: [a: 1, b: 1, c: 1, d: 2], participants: four, form: foursome, maxPerBay: 4) == "Lag 1 og 2 har ikke 2 spillere.")
        #expect(TeamPlanner.problem(teams: [a: 1, b: 1, c: 2], participants: four, form: foursome, maxPerBay: 4) == "Én av deltakerne har ikke lag.")
        let scramble = CompetitionForm.form(id: "scramble-2")
        let six = [a, b, c, d, e, f]
        #expect(TeamPlanner.problem(teams: [a: 1, b: 1, c: 1, d: 1, e: 1, f: 2], participants: six, form: scramble, maxPerBay: 4)
                == "Lag 1 har flere enn 4. Et lag får ikke plass i en bås da.")
    }

    @Test func lagMotLagEnMotToTreMotFire() {
        let matches = MatchPlanner.teamMatches([a: 1, b: 1, c: 2, d: 2, e: 3, f: 3, g: 4, h: 4])
        #expect(matches == [.teams(1, 2), .teams(3, 4)])
    }

    @Test func trekningenGirDuellerOgEnTrekantVedOddetall() {
        let five = Array(roster.prefix(5))
        let matches = MatchPlanner.drawIndividual(five)
        // Uten stilling: navnerekkefølge, de tre siste blir trekant.
        #expect(matches == [.players(a, b), .players(c, d, e)])
        #expect(MatchPlanner.drawIndividual([roster[0]]).isEmpty)
    }

    @Test func lagredeMatcherStaarNaarDeSammeErMed() {
        let matches: [MatchDraft] = [.players(a, b), .players(c, d)]
        #expect(MatchPlanner.canKeep(matches, participants: [a, b, c, d], teams: [:], isTeamForm: false))
        #expect(!MatchPlanner.canKeep(matches, participants: [a, b, c, d, e], teams: [:], isTeamForm: false))
        #expect(!MatchPlanner.canKeep([], participants: [a, b], teams: [:], isTeamForm: false))
        #expect(MatchPlanner.canKeep([.teams(1, 2)], participants: [a, b], teams: [a: 1, b: 2], isTeamForm: true))
        #expect(!MatchPlanner.canKeep([.teams(1, 3)], participants: [a, b], teams: [a: 1, b: 2], isTeamForm: true))
    }

    @Test func feilIMatchene() {
        let names = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0.displayName) })
        let problems = MatchPlanner.problems([.players(a, b), .players(b, g), MatchDraft(playerA: c)],
                                             participants: [a, b, c], teams: [:], names: names)
        #expect(problems == ["Bjørn står i både match 1 og 2.", "Gunnar i match 2 er ikke med i runden.",
                             "Match 3 mangler to forskjellige spillere."])
    }
}

// MARK: - Sjekk før start

struct RoundSetupCheckTests {
    private func draft(_ participants: [UUID], rules: Ruleset = .golfgutu) -> RoundDraft {
        var draft = RoundDraft.new(eventID: eventID, roundNo: 1, teeTime: "17:00:00", participants: participants,
                                   source: .signups, rules: rules)
        draft.courseID = id(700)
        draft.redrawMatches(roster: roster)
        return draft
    }

    @Test func gyldigRundeHarIngenHindringer() {
        let issues = RoundSetupCheck.issues(draft([a, b, c, d]), course: course(), rules: .golfgutu, roster: roster, forStart: true)
        #expect(issues.isEmpty)
    }

    @Test func banenMaaVaereKlar() {
        let setup = draft([a, b])
        #expect(RoundSetupCheck.issues(setup, course: nil, rules: .golfgutu, roster: roster, forStart: false) == [.noCourse])
        #expect(RoundSetupCheck.issues(setup, course: course(par: nil), rules: .golfgutu, roster: roster, forStart: false)
                == [.courseNotReady("Testbanen")])
    }

    @Test func startKreverToSpillereOgMarkoerIHverBaas() {
        #expect(RoundSetupCheck.issues(draft([a]), course: course(), rules: .golfgutu, roster: roster, forStart: true)
                .contains(.tooFewPlayers))
        // En kladd kan lagres med én.
        #expect(RoundSetupCheck.issues(draft([a]), course: course(), rules: .golfgutu, roster: roster, forStart: false).isEmpty)

        var setup = draft([a, b, c, d, e, f])
        setup.bays = BayPlan(seats: [BaySeat(memberID: a, bay: 1, isMarker: true), BaySeat(memberID: b, bay: 1, isMarker: false),
                                 BaySeat(memberID: c, bay: 2, isMarker: false), BaySeat(memberID: d, bay: 2, isMarker: false),
                                 BaySeat(memberID: e, bay: 3, isMarker: false), BaySeat(memberID: f, bay: 3, isMarker: false)])
        #expect(RoundSetupCheck.issues(setup, course: course(), rules: .golfgutu, roster: roster, forStart: true)
                == [.bayWithoutMarker([2, 3])])
        #expect(RoundSetupIssue.bayWithoutMarker([2, 3]).message == "Bås 2 og 3 har ingen markør.")
    }

    @Test func formenMaaVaereTillattIRegelsettet() {
        var rules = Ruleset.golfgutu
        rules.formats.allowedFormIDs = ["stableford"]
        var setup = draft([a, b])
        setup.setForm("match", rules: rules, roster: roster)
        #expect(RoundSetupCheck.issues(setup, course: course(), rules: rules, roster: roster, forStart: false)
                == [.formNotAllowed("Matchspill (individuelt)")])
        setup.setForm("skins", rules: .golfgutu, roster: roster)
        #expect(RoundSetupCheck.issues(setup, course: course(), rules: .golfgutu, roster: roster, forStart: false)
                == [.formNotSupported("Skins")])
    }

    @Test func lagformKreverLagSomGaarOpp() {
        var setup = draft([a, b, c, d])
        setup.setForm("foursome", rules: .golfgutu, roster: roster)
        #expect(setup.teams == [a: 1, b: 1, c: 2, d: 2])
        #expect(setup.matches == [.teams(1, 2)])
        #expect(RoundSetupCheck.issues(setup, course: course(), rules: .golfgutu, roster: roster, forStart: true).isEmpty)
        setup.teams[d] = 1
        #expect(RoundSetupCheck.issues(setup, course: course(), rules: .golfgutu, roster: roster, forStart: true)
                .contains(.teams("Lag 1 og 2 har ikke 2 spillere.")))
    }

    @Test func nyRundeFaarRegelsettetsStandarder() {
        var rules = Ruleset.golfgutu
        rules.formats.defaultFormID = "match"
        rules.handicap.externalHandicap = true
        rules.sidePrizes.closestToPin.enabled = false
        let d = RoundDraft.new(eventID: eventID, roundNo: 2, teeTime: nil, participants: [a, b], source: .signups, rules: rules)
        #expect(d.formID == "match")
        #expect(d.allowance == 1.0)
        #expect(d.externalHandicap)
        #expect(d.ldEnabled && !d.kpEnabled)
        // Golfgutu: stableford, 95 %, appen deler ut slagene.
        let g = RoundDraft.new(eventID: eventID, roundNo: 1, teeTime: nil, participants: [a, b], source: .signups, rules: .golfgutu)
        #expect(g.formID == "stableford" && g.allowance == 0.95 && !g.externalHandicap)
    }

    @Test func sisteNiBareFor9HullPaa18Hullsbane() {
        #expect(RoundDraft.canStartAtTen(holeCount: 9, courseHoles: 18))
        #expect(!RoundDraft.canStartAtTen(holeCount: 18, courseHoles: 18))
        #expect(!RoundDraft.canStartAtTen(holeCount: 9, courseHoles: 9))
    }
}

// MARK: - set_round_setup

struct RoundSetupParamsTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private let players = [member(1, "Anders", hcp: 10), member(2, "Bjørn", hcp: 20.4), member(3, "Cato", hcp: 30, seed: 2),
                           member(4, "Dag", hcp: nil)]

    private func draft() -> RoundDraft {
        var d = RoundDraft.new(eventID: eventID, roundNo: 1, teeTime: nil, participants: players.map(\.id),
                               source: .signups, rules: .golfgutu)
        d.courseID = id(700)
        d.redrawMatches(roster: players)
        return d
    }

    @Test func kladdSenderOppsettetUtenSpillehandicap() throws {
        let params = RoundSetupParams.make(roundID: id(600), draft: draft(), roster: players, course: course().coreCourse,
                                           rules: .golfgutu, withPlayingHandicap: false)
        let object = try json(params)
        #expect(object["p_round_id"] as? String == id(600).uuidString)
        let entries = object["p_players"] as! [[String: Any]]
        #expect(entries.count == 4)
        #expect(entries[0]["member_id"] as? String == id(1).uuidString)
        #expect(entries[0]["bay_no"] as? Int == 1)
        #expect(entries[0]["is_marker"] as? Bool == true)
        #expect(entries[1]["is_marker"] as? Bool == false)
        #expect(entries[0]["team_no"] is NSNull)
        #expect(entries[0]["playing_handicap"] is NSNull)

        let matches = object["p_matches"] as! [[String: Any]]
        #expect(matches.count == 2)
        #expect(matches[0]["match_no"] as? Int == 1)
        #expect(matches[0]["player_a"] as? String == id(1).uuidString)
        #expect(matches[0]["player_b"] as? String == id(2).uuidString)
        #expect(matches[0]["player_c"] is NSNull)
        #expect(matches[0]["team_a"] is NSNull)
        #expect(matches[1]["match_no"] as? Int == 2)
    }

    @Test func startRegnerSpillehandicapMedEffectiveHandicap() {
        // CR 72, slope 113, par 72: banehandicap = indeksen. 95 % på 18 hull, avrundet som JS.
        let params = RoundSetupParams.make(roundID: id(600), draft: draft(), roster: players, course: course().coreCourse,
                                           rules: .golfgutu, withPlayingHandicap: true)
        let hcp = params.players.map(\.playingHandicap)
        // 10 · 0,95 = 9,5 → 10. 20,4 → 20 · 0,95 = 19. Seedet gruppe 2 → 5. Uten indeks → 0.
        #expect(hcp == [10, 19, 5, 0])
    }

    @Test func trackmanFordelerGirNull() {
        var d = draft()
        d.externalHandicap = true
        let params = RoundSetupParams.make(roundID: id(600), draft: d, roster: players, course: course().coreCourse,
                                           rules: .golfgutu, withPlayingHandicap: true)
        #expect(params.players.map(\.playingHandicap) == [0, 0, 0, 0])
    }

    @Test func lagformSenderLagOgLagmatcher() throws {
        var d = draft()
        d.setForm("fourball", rules: .golfgutu, roster: players)
        let params = RoundSetupParams.make(roundID: id(600), draft: d, roster: players, course: course().coreCourse,
                                           rules: .golfgutu, withPlayingHandicap: true)
        #expect(params.players.map(\.teamNo) == [1, 1, 2, 2])
        #expect(params.matches == [RoundSetupParams.MatchEntry(matchNo: 1, playerA: nil, playerB: nil, playerC: nil,
                                                               teamA: 1, teamB: 2, result: nil)])
        // Fourball: laget har ett handicap, snittet av grunnlagene (banehandicap 10 og 20): 15; (5 + 0) / 2 = 2,5 → 3.
        #expect(params.players.map(\.playingHandicap) == [15, 15, 3, 3])
    }

    @Test func spillereUtenforTroppenOgBaaseneTasUt() {
        var d = draft()
        d.participants.append(id(77))
        d.bays.move(id(1), to: nil)
        let params = RoundSetupParams.make(roundID: id(600), draft: d, roster: players, course: nil,
                                           rules: .golfgutu, withPlayingHandicap: false)
        #expect(params.players.map(\.memberID) == players.map(\.id))
        #expect(params.players[0].bayNo == nil && params.players[0].isMarker == false)
    }

    @Test func raden() throws {
        var d = draft()
        d.holeCount = 9
        d.firstHole = 10
        d.ldEnabled = false
        let object = try json(RoundWrite(draft: d, clubID: club, course: course().coreCourse))
        #expect(object["hole_count"] as? Int == 9)
        #expect(object["first_hole"] as? Int == 10)
        #expect(object["format"] as? String == "stableford")
        #expect(object["handicap_allowance"] as? Double == 0.95)
        #expect(object["ld_enabled"] as? Bool == false)
        // Forslaget lagres også når premien er av. Alle par 4: første par 4 (hull 1) for LD, KP hull 3.
        #expect(object["ld_hole_index"] as? Int == 0)
        #expect(object["kp_hole_index"] as? Int == 2)
        #expect(object["tee_time"] is NSNull)
        #expect(object["status"] == nil)

        d.holeCount = 18
        #expect(RoundWrite(draft: d, clubID: club, course: nil).firstHole == 1)
    }
}

// MARK: - Liste og sletting (slett-runde-test.js)

struct RoundListingTests {
    @Test func tittelOgStatus() {
        #expect(RoundListing.title(roundNo: 2, courseName: "Pebble Beach") == "Runde 2 – Pebble Beach")
        #expect(RoundListing.title(roundNo: 1, courseName: nil) == "Runde 1")
        #expect(RoundListing.statusText(.draft) == "Kladd")
        #expect(RoundListing.statusText(.active) == "Pågår")
        #expect(RoundListing.statusText(.locked) == "Låst")
    }

    @Test func regelsettetForKvelden() {
        var other = Ruleset.golfgutu
        other.formats.maxPerBay = 6
        let season = SeasonRow(id: id(800), clubID: club, name: "2027", status: .planned, rules: other)
        let active = SeasonRow(id: id(801), clubID: club, name: "2026", status: .active, rules: .golfgutu)
        let event = EventRow(id: eventID, clubID: club, seasonID: id(800), eventDate: "2026-10-08",
                             startTime: nil, venue: nil, note: nil)
        #expect(RoundListing.rules(for: event, seasons: [season, active]).formats.maxPerBay == 6)
        #expect(RoundListing.rules(for: nil, seasons: [season, active]) == .golfgutu)
        #expect(RoundListing.rules(for: nil, seasons: []) == .golfgutu)
    }

    @Test func slettingTellerFoerteHull() {
        let summary = RoundDeleteSummary(holeScores: 6, playersWithScores: 2, sideClaims: 2, isDraft: false)
        #expect(summary.lines == ["6 førte hull, fra 2 spillere", "2 innmeldte sidepremier"])
        #expect(summary.buttonTitle == "Slett runden og 6 førte hull")
        #expect(summary.message.hasPrefix("Dette følger med ut, og kan ikke angres:"))

        let empty = RoundDeleteSummary(holeScores: 0, playersWithScores: 0, sideClaims: 0, isDraft: false)
        #expect(empty.message.contains("Runden er tom"))
        #expect(empty.buttonTitle == "Slett runden")
        let draft = RoundDeleteSummary(holeScores: 0, playersWithScores: 0, sideClaims: 0, isDraft: true)
        #expect(draft.buttonTitle == "Slett kladden")
        #expect(RoundDeleteSummary(holeScores: 1, playersWithScores: 1, sideClaims: 1, isDraft: false).lines
                == ["1 ført hull, fra 1 spiller", "1 innmeldt sidepremie"])
    }

    @Test func svaretFraDeleteRound() throws {
        let data = Data(#"{"round_no":3,"name":null,"hole_scores":6,"side_claims":0,"matches":2,"players":4,"round_holes":0}"#.utf8)
        let result = try JSONDecoder().decode(DeleteRoundResult.self, from: data)
        #expect(result.message == "Runde 3 er slettet, med 6 førte hull.")
    }

    @Test func enRundeGaarAllerede() {
        #expect(RoundErrors.startMessage(sqlState: "23505", fallback: .unknown("x")) == "En runde går allerede. Lås den før du starter en ny.")
        #expect(RoundErrors.startMessage(sqlState: "42501", fallback: .notAllowed) == DataError.notAllowed.message)
        #expect(RoundListing.nextRoundNo(existing: []) == 1)
    }
}
