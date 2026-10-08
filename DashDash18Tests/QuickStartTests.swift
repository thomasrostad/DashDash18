import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 11: hurtigstarten, simulator / ekte bane og arrangørsidens «I kveld».

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)
private let season = id(800)

private func member(_ n: Int, _ name: String) -> ClubMemberRow {
    ClubMemberRow(id: id(n), clubID: club, userID: UUID(), displayName: name, handicapIndex: 10, seedGroup: nil,
                  isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
}

private let names = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode", "Gunnar", "Halvor", "Ivar", "Jon", "Kåre", "Lars"]
private let roster = names.enumerated().map { member($0.offset + 1, $0.element) }

private func course(_ n: Int, holes: Int = 18, ready: Bool = true) -> CourseListItem {
    let row = CourseRow(id: id(n), clubID: club, name: "Bane \(n)", externalName: nil, courseRating: 72,
                        slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
    let records = (1...holes).map { h in
        CourseHoleRecord(courseID: id(n), holeNumber: h, par: 4, strokeIndex: h, lengthM: nil)
    }
    return CourseListItem(course: row, holes: ready ? records : [])
}

private func event(_ n: Int, _ date: String) -> EventRow {
    EventRow(id: id(n), clubID: club, seasonID: season, eventDate: date, startTime: "18:00:00", venue: nil, note: nil)
}

private func round(_ n: Int, event: Int, no: Int = 1, status: RoundStatus = .locked, course: Int? = 701,
                   holes: Int = 18, first: Int = 1, ld: Int? = 6, kp: Int? = 2, weight: Double = 1,
                   cutAfter: Int? = nil, venue: String? = nil) -> RoundRow {
    RoundRow(id: id(n), clubID: club, eventID: id(event), courseID: course.map(id), roundNo: no, name: nil,
             status: status, holeCount: holes, firstHole: first, teeTime: nil, format: "stableford",
             handicapAllowance: 1, externalHandicap: false, weight: weight, ldEnabled: true, ldHoleIndex: ld,
             kpEnabled: true, kpHoleIndex: kp, cutRule: cutAfter == nil ? nil : "common", cutAfter: cutAfter,
             parConfirmedBy: nil, parConfirmedAt: nil, startedAt: nil, lockedAt: nil, venue: venue)
}

private func newDraft(_ count: Int = 12, rules: Ruleset = .golfgutu) -> RoundDraft {
    var draft = RoundDraft.new(eventID: id(503), roundNo: 1, teeTime: "18:00:00",
                               participants: roster.prefix(count).map(\.id), source: .signups, rules: rules)
    draft.courseID = id(701)
    return draft
}

// MARK: - Bås og flight

struct GroupTermTests {
    @Test func basIsimulatorenFlightPaaEkteBane() {
        let bay = GroupTerm.for(.simulator)
        #expect(bay.numbered(2) == "Bås 2")
        #expect(bay.numberedLower(2) == "bås 2")
        #expect(bay.count(1) == "1 bås")
        #expect(bay.count(3) == "3 båser")
        #expect(bay.definiteTitle == "Båsen")
        #expect(bay.definitePlural == "båsene")
        #expect(bay.marker == "markør")

        let flight = GroupTerm.for(.course)
        #expect(flight.numbered(2) == "Flight 2")
        #expect(flight.count(1) == "1 flight")
        #expect(flight.count(3) == "3 flighter")
        #expect(flight.definiteTitle == "Flighten")
        #expect(flight.pluralTitle == "Flighter")
        #expect(flight.marker == "markør")
    }

    @Test func ukjentEllerTomtStedErSimulator() {
        #expect(Venue(stored: nil) == .simulator)
        #expect(Venue(stored: "månen") == .simulator)
        #expect(Venue(stored: "course") == .course)
        #expect(GroupTerm.for(stored: nil) == .bay)
        #expect(GroupTerm.for(stored: "course") == .flight)
    }

    @Test func meldingenOmMarkoerBrukerRundensOrd() {
        #expect(RoundSetupIssue.bayWithoutMarker([1, 3]).message(.bay) == "Bås 1 og 3 har ingen markør.")
        #expect(RoundSetupIssue.bayWithoutMarker([2]).message(.flight) == "Flight 2 har ingen markør.")
    }

    @Test func trackmanBareISimulatoren() {
        var rules = Ruleset.golfgutu
        rules.handicap.externalHandicap = true
        var draft = newDraft(rules: rules)
        #expect(draft.externalHandicap)
        draft.setVenue(.course, rules: rules)
        #expect(draft.venue == .course)
        #expect(!draft.externalHandicap)
        #expect(draft.groupTerm == .flight)
        draft.setVenue(.simulator, rules: rules)
        #expect(draft.externalHandicap)
    }

    @Test func stedetSendesBareMedFlagget() throws {
        var draft = newDraft()
        draft.setVenue(.course, rules: .golfgutu)
        let off = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RoundWrite(draft: draft, clubID: club, course: nil, includeVenue: false))) as? [String: Any]
        #expect(off?["venue"] == nil)
        let on = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(RoundWrite(draft: draft, clubID: club, course: nil, includeVenue: true))) as? [String: Any]
        #expect(on?["venue"] as? String == "course")
        // Uten flagget er standarden av.
        #expect(RoundWrite(draft: draft, clubID: club, course: nil).venue == (VenueFeature.isEnabled ? "course" : nil))
    }

    @Test func lagretKladdHuskerStedet() {
        let saved = RoundDraft.saved(round(1, event: 503, status: .draft, venue: "course"), players: [], matches: [],
                                     participants: [], source: .signups)
        #expect(saved.venue == .course)
        let old = RoundDraft.saved(round(2, event: 503, status: .draft), players: [], matches: [],
                                   participants: [], source: .signups)
        #expect(old.venue == .simulator)
    }
}

// MARK: - Forslag fra forrige runde

struct QuickStartSuggestionTests {
    private let events = [event(501, "2026-09-03"), event(502, "2026-09-17"), event(503, "2026-10-01"),
                          event(504, "2026-10-15")]

    @Test func forrigeStartedeRundeISesongen() {
        let rounds = [
            round(1, event: 501),
            round(2, event: 502, no: 1),
            round(3, event: 502, no: 2),
            round(4, event: 503, status: .draft),        // kladd teller ikke
            round(5, event: 504),                        // senere kveld teller ikke
            round(6, event: 999),                        // annen sesong (kvelden er ikke med)
        ]
        let previous = QuickStart.previousRound(rounds: rounds, events: events, upTo: events[2])
        #expect(previous?.id == id(3))
    }

    @Test func tidligereRundeSammeKveldTeller() {
        let rounds = [round(2, event: 502), round(7, event: 503, no: 1, status: .active)]
        #expect(QuickStart.previousRound(rounds: rounds, events: events, upTo: events[2])?.id == id(7))
        #expect(QuickStart.previousRound(rounds: [], events: events, upTo: events[2]) == nil)
    }

    @Test func fyllerInnBaneStartSidepremierOgVekt() {
        var draft = newDraft()
        draft.courseID = id(701)
        let previous = round(3, event: 502, course: 702, holes: 9, first: 10, ld: 4, kp: 1, weight: 2, venue: "course")
        QuickStart.applySuggestion(from: previous, to: &draft, courses: [course(701), course(702)], rules: .golfgutu)
        #expect(draft.courseID == id(702))
        #expect(draft.holeCount == 9)
        #expect(draft.firstHole == 10)
        #expect(draft.ldHoleIndex == 4)
        #expect(draft.kpHoleIndex == 1)
        #expect(draft.weight == 2)
        #expect(draft.venue == .course)
    }

    @Test func banenSomIkkeErKlarGirStandard() {
        var draft = newDraft()
        let previous = round(3, event: 502, course: 702, holes: 9, ld: 4, weight: 1.5)
        QuickStart.applySuggestion(from: previous, to: &draft, courses: [course(701), course(702, ready: false)],
                                   rules: .golfgutu)
        #expect(draft.courseID == id(701))
        #expect(draft.holeCount == 18)
        #expect(draft.ldHoleIndex == nil)
        #expect(draft.weight == 1.5)
    }

    @Test func utenForrigeRundeGjelderRegelsettet() {
        var draft = newDraft()
        let before = draft
        QuickStart.applySuggestion(from: nil, to: &draft, courses: [course(701)], rules: .golfgutu)
        #expect(draft == before)
        #expect(draft.formID == Ruleset.golfgutu.formats.defaultFormID)
        #expect(draft.weight == 1)
    }

    @Test func hull10BareNaarBanenHar18() {
        var draft = newDraft()
        let previous = round(3, event: 502, course: 703, holes: 9, first: 10)
        QuickStart.applySuggestion(from: previous, to: &draft, courses: [course(703, holes: 9)], rules: .golfgutu)
        #expect(draft.firstHole == 1)
    }
}

// MARK: - Automatisk fordeling og start

struct QuickStartArrangeTests {
    @Test func tolvPaameldtePaaTreBaaserMedMarkoer() {
        var draft = newDraft(12)
        QuickStart.autoArrange(&draft, rules: .golfgutu, roster: roster)
        #expect(draft.bays.bayNumbers == [1, 2, 3])
        #expect(draft.bays.counts.values.allSatisfy { $0 == 4 })
        #expect(draft.bays.baysWithoutMarker.isEmpty)
        #expect(draft.matches.count == 6)
        // Duellpartnerne står i samme bås.
        for match in draft.matches {
            let bays = Set(match.members().compactMap { draft.bays.seat(for: $0)?.bay })
            #expect(bays.count == 1)
        }
        #expect(QuickStart.playersSummary(draft) == "12 påmeldt · 3 båser")
        #expect(RoundSetupCheck.issues(draft, course: course(701), rules: .golfgutu, roster: roster, forStart: true).isEmpty)
    }

    @Test func flighterPaaEkteBane() {
        var draft = newDraft(5)
        draft.setVenue(.course, rules: .golfgutu)
        QuickStart.autoArrange(&draft, rules: .golfgutu, roster: roster)
        #expect(QuickStart.playersSummary(draft) == "5 påmeldt · 2 flighter")
        let lines = QuickStart.groupLines(draft) { id in roster.first { $0.id == id }?.displayName ?? "?" }
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("Flight 1: "))
        #expect(lines[0].contains("(markør)"))
    }

    @Test func maksPerBaasFraRegelsettet() {
        var rules = Ruleset.golfgutu
        rules.formats.maxPerBay = 6
        var draft = newDraft(12, rules: rules)
        QuickStart.autoArrange(&draft, rules: rules, roster: roster)
        #expect(draft.bays.bayNumbers == [1, 2])
    }

    @Test func startvalgOgHullSomFaller() {
        #expect(QuickStart.startOptions(courseHoles: 18).map(\.title) == ["Hull 1 · 18 hull", "Hull 1 · 9 hull", "Hull 10 · 9 hull"])
        #expect(QuickStart.startOptions(courseHoles: 9).map(\.title) == ["Hull 1 · 18 hull", "Hull 1 · 9 hull"])

        var draft = newDraft()
        draft.ldHoleIndex = 14
        draft.kpHoleIndex = 3
        QuickStart.setStart(QuickStartStart(firstHole: 10, holeCount: 9), on: &draft, courseHoles: 18)
        #expect(draft.holeCount == 9 && draft.firstHole == 10)
        #expect(draft.ldHoleIndex == nil)
        #expect(draft.kpHoleIndex == 3)
        QuickStart.setStart(QuickStartStart(firstHole: 10, holeCount: 9), on: &draft, courseHoles: 9)
        #expect(draft.firstHole == 1)
    }

    @Test func nyBaneGirNyttForslagTilSidepremier() {
        var draft = newDraft()
        draft.holeCount = 9
        draft.firstHole = 10
        draft.ldHoleIndex = 4
        draft.kpHoleIndex = 2
        QuickStart.setCourse(id(703), on: &draft, courseHoles: 9)
        #expect(draft.courseID == id(703))
        #expect(draft.ldHoleIndex == nil && draft.kpHoleIndex == nil)
        #expect(draft.firstHole == 1)
    }
}

// MARK: - Mangler med snarvei

struct QuickStartProblemTests {
    @Test func hverManglerHarSnarvei() {
        let problems = QuickStart.problems([.noCourse, .bayWithoutMarker([2]), .matches(["Match 1 mangler to forskjellige spillere."])],
                                           term: .flight, blockingTitle: nil)
        #expect(problems.map(\.target) == [.course, .players, .moreOptions])
        #expect(problems[1].message == "Flight 2 har ingen markør.")
        #expect(problems.map { $0.target?.shortcutTitle } == ["Velg bane", "Endre spillere", "Flere valg"])
    }

    @Test func rundeSomGaarStaarFoerstUtenSnarvei() {
        let problems = QuickStart.problems([.tooFewPlayers], term: .bay, blockingTitle: "Runde 1 – Pebble Beach")
        #expect(problems.count == 2)
        #expect(problems[0].target == nil)
        #expect(problems[0].message.hasPrefix("Runde 1 – Pebble Beach går fortsatt."))
        #expect(problems[1].target == .players)
    }

    @Test func alleManglerFaarMaal() {
        let all: [RoundSetupIssue] = [.noCourse, .courseNotReady("X"), .tooFewPlayers, .bayWithoutMarker([1]),
                                      .formNotAllowed("X"), .formNotSupported("X"), .teams("X"), .matches([]),
                                      .sidePrizeOutsideRound(9)]
        #expect(all.map(QuickStart.target) == [.course, .course, .players, .players,
                                                .moreOptions, .moreOptions, .moreOptions, .moreOptions, .moreOptions])
    }
}

// MARK: - Arrangørsiden: «I kveld» (stegene og neste steg: EveningStepsTests)

struct TonightTests {
    private let tonight = event(503, "2026-10-01")

    @Test func ferdigNaarAlleHullErFoert() {
        let r = round(1, event: 503, status: .active)
        #expect(Tonight.isComplete(scoredHoles: 72, players: 4, round: r))
        #expect(!Tonight.isComplete(scoredHoles: 71, players: 4, round: r))
        #expect(!Tonight.isComplete(scoredHoles: 0, players: 0, round: r))
        // Avkortet etter 12 hull.
        #expect(Tonight.isComplete(scoredHoles: 48, players: 4, round: round(2, event: 503, status: .active, cutAfter: 12)))
    }

    @Test func paameldingOgStatus() {
        func signup(_ n: Int, _ status: SignupStatus) -> SignupRow {
            SignupRow(eventID: id(503), memberID: id(n), clubID: club, status: status, comment: nil)
        }
        #expect(Tonight.signupText([], rosterCount: 12) == "Ingen har svart ennå · 12 i troppen")
        #expect(Tonight.signupText([signup(1, .yes), signup(2, .yes), signup(3, .no)], rosterCount: 12) == "2 av 12 kommer")
        #expect(Tonight.signupText([signup(1, .yes), signup(2, .maybe)], rosterCount: 12) == "1 av 12 kommer · 1 usikker")
        #expect(Tonight.signupText([signup(2, .maybe), signup(3, .maybe)], rosterCount: 12) == "0 av 12 kommer · 2 usikre")

        #expect(Tonight.statusText(action: .setUp, rounds: [], activeTitle: nil) == "Ikke satt opp")
        #expect(Tonight.statusText(action: .goToRound(id(1)), rounds: [], activeTitle: "Runde 1 – Pebble Beach")
                == "Runde 1 – Pebble Beach pågår")
        #expect(Tonight.statusText(action: .continueDraft(id(1)), rounds: [], activeTitle: nil) == "Kladd lagret · ikke startet")
    }
}

// MARK: - Føringen: bås eller flight

struct ForingGroupTermTests {
    @Test func markoerlinjaSierFlightPaaEkteBane() {
        var snapshot = RoundSnapshot(round: round(1, event: 503, status: .active, venue: "course"))
        snapshot.players = [id(1), id(2)].enumerated().map { i, m in
            RoundPlayerRow(roundID: id(1), memberID: m, clubID: club, handicapIndex: 10, seedGroup: nil,
                           playingHandicap: nil, bayNo: 2, isMarker: i == 0, teamNo: nil)
        }
        snapshot.names = [id(1): "Anders", id(2): "Bjørn"]
        let game = RoundGame(snapshot)
        #expect(game.groupTerm == .flight)
        #expect(game.markerLine(for: Viewer(memberID: id(1), isOrganizer: false)) == "Du er markør i flight 2 · Bjørn og deg")
        #expect(game.markerLine(for: Viewer(memberID: id(2), isOrganizer: false)) == "Flight 2 · Anders fører · du ser det live")
    }
}
