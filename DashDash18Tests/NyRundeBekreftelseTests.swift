import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 18: «Ny runde» som én bekreftelse. Hva som vises, og oppsummeringstekstene.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)

private func course(_ n: Int, kind: CourseKind? = nil, holes: Int = 18, ready: Bool = true,
                    external: String? = nil) -> CourseListItem {
    let row = CourseRow(id: id(n), clubID: club, name: "Bane \(n)", externalName: external, courseRating: 72,
                        slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
    let records = (1...holes).map { h in
        CourseHoleRecord(courseID: id(n), holeNumber: h, par: h % 5 == 0 ? 3 : 4, strokeIndex: h, lengthM: nil)
    }
    return CourseListItem(course: row, holes: ready ? records : [], storedKind: kind)
}

private func member(_ n: Int) -> ClubMemberRow {
    ClubMemberRow(id: id(n), clubID: club, userID: UUID(), displayName: "Spiller \(n)", handicapIndex: 10,
                  seedGroup: nil, isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
}

private let roster = (1...12).map(member)

private func draft(players: Int = 12, form: String? = nil) -> RoundDraft {
    var draft = RoundDraft.new(eventID: id(500), roundNo: 1, teeTime: "18:00:00",
                               participants: roster.prefix(players).map(\.id), source: .signups, rules: .golfgutu)
    if let form { draft.setForm(form, rules: .golfgutu, roster: roster) }
    draft.prepareSetup(rules: .golfgutu, roster: roster)
    return draft
}

struct NyRundeStedTests {
    @Test func hvorSpillerDereBareNaarKlubbenHarBeggeTyper() {
        #expect(!RoundConfirm.showsVenueChoice([]))
        #expect(!RoundConfirm.showsVenueChoice([course(1), course(2, kind: .simulator)]))
        #expect(!RoundConfirm.showsVenueChoice([course(1, kind: .course), course(2, kind: .course)]))
        #expect(RoundConfirm.showsVenueChoice([course(1), course(2, kind: .course)]))
        // En ekte bane som ikke er klar, gir ikke noe valg.
        #expect(!RoundConfirm.showsVenueChoice([course(1), course(2, kind: .course, ready: false)]))
    }

    @Test func stedetFoelgerBanen() {
        #expect(RoundConfirm.venue(for: course(1)) == .simulator)
        #expect(RoundConfirm.venue(for: course(1, kind: .course)) == .course)

        var d = draft()
        d.ldHoleIndex = 4
        RoundConfirm.selectCourse(course(7, kind: .course), on: &d, rules: .golfgutu)
        #expect(d.courseID == id(7))
        #expect(d.venue == .course)
        #expect(d.groupTerm == .flight)
        #expect(d.ldHoleIndex == nil)
        #expect(!d.externalHandicap)

        RoundConfirm.selectCourse(course(8), on: &d, rules: .golfgutu)
        #expect(d.venue == .simulator)
        #expect(d.externalHandicap == Ruleset.golfgutu.handicap.externalHandicap)
    }

    @Test func banevelgerenViserStedetsBaner() {
        let sim = course(1), ute = course(2, kind: .course), ikkeKlar = course(3, ready: false)
        #expect(RoundConfirm.courseChoices([sim, ute], selected: nil, venue: .simulator, showsVenue: true).map(\.id) == [sim.id])
        #expect(RoundConfirm.courseChoices([sim, ute], selected: nil, venue: .course, showsVenue: true).map(\.id) == [ute.id])
        #expect(RoundConfirm.courseChoices([sim, ute], selected: sim, venue: .course, showsVenue: true).map(\.id) == [sim.id, ute.id])
        #expect(RoundConfirm.courseChoices([sim], selected: nil, venue: .course, showsVenue: false).map(\.id) == [sim.id])
        #expect(RoundConfirm.courseChoices([sim], selected: ikkeKlar, venue: .simulator, showsVenue: false).map(\.id)
                == [ikkeKlar.id, sim.id])
    }

    @Test func banelinjaStaarIVelgeren() {
        #expect(RoundConfirm.courseDetail(course(1)) == "18 hull · par 69 · CR 72 · slope 113 · med indeks")
        #expect(RoundConfirm.courseDetail(course(1, external: "Pebble"))
                == "18 hull · par 69 · CR 72 · slope 113 · med indeks. Heter «Pebble» i simulatoren.")
        #expect(RoundConfirm.courseDetail(course(1, kind: .course, external: "Pebble"))
                == "18 hull · par 69 · CR 72 · slope 113 · med indeks")
    }
}

struct NyRundeOppsummeringTests {
    @Test func baneraden() {
        #expect(RoundConfirm.courseValue(name: "Pebble Beach", venue: .simulator, showsVenue: false) == "Pebble Beach")
        #expect(RoundConfirm.courseValue(name: "Pebble Beach", venue: .simulator, showsVenue: true)
                == "Pebble Beach · Simulator")
        #expect(RoundConfirm.courseValue(name: "Bærum", venue: .course, showsVenue: true) == "Bærum · Ekte bane")
        #expect(RoundConfirm.courseValue(name: nil, venue: .simulator, showsVenue: true) == "Velg")
    }

    @Test func startradenHarHullAntallOgTid() {
        #expect(RoundConfirm.startValue(firstHole: 1, holeCount: 18, teeTime: "18:00:00") == "Hull 1 · 18 hull · 18:00")
        #expect(RoundConfirm.startValue(firstHole: 10, holeCount: 9, teeTime: "17:30:00") == "Hull 10 · 9 hull · 17:30")
        #expect(RoundConfirm.startValue(firstHole: 1, holeCount: 9, teeTime: nil) == "Hull 1 · 9 hull")
    }

    @Test func spillerradenHarAntallOgGrupper() {
        var d = draft()
        d.reshuffleBays(count: 3)
        #expect(QuickStart.playersSummary(d) == "12 påmeldt · 3 båser")
        d.setVenue(.course, rules: .golfgutu)
        #expect(QuickStart.playersSummary(d) == "12 påmeldt · 3 flighter")
    }

    @Test func flereValgOppsummerer() {
        let c = course(1).coreCourse
        var d = draft()
        d.ldEnabled = true
        d.kpEnabled = true
        d.ldHoleIndex = 17
        d.kpHoleIndex = 4
        d.externalHandicap = false
        #expect(RoundConfirm.moreSummary(d, course: c, showsMatches: true)
                == "Stableford (netto) · 6 matcher · LD hull 18 · KP hull 5")
        // Når matchene ikke vises, nevnes de ikke.
        #expect(RoundConfirm.moreSummary(d, course: c, showsMatches: false) == "Stableford (netto) · LD hull 18 · KP hull 5")

        d.ldEnabled = false
        d.kpEnabled = false
        d.weight = 2
        d.externalHandicap = true
        d.matches = []
        #expect(RoundConfirm.moreSummary(d, course: c, showsMatches: true)
                == "Stableford (netto) · ingen matcher · dobbelt · avsluttende runde · Trackman gir slagene")
    }
}

struct NyRundeFlereValgTests {
    @Test func lagBareILagform() {
        #expect(!RoundSetupOptions(draft: draft(), rules: .golfgutu).showsTeams)
        #expect(RoundSetupOptions(draft: draft(form: "fourball"), rules: .golfgutu).showsTeams)
    }

    /// Koblingspunktet for regelen om at tabellen teller stableford i stedet for matcher (fase 18).
    /// I dag gir alle former matcher: dueller og trekant individuelt, lag mot lag i lagform.
    @Test func matcherVisesNaarRundenGirMatcher() {
        #expect(RoundSetupOptions(draft: draft(), rules: .golfgutu).showsMatches)
        #expect(RoundSetupOptions(draft: draft(players: 11), rules: .golfgutu).showsMatches)
        #expect(RoundSetupOptions(draft: draft(form: "match"), rules: .golfgutu).showsMatches)
        #expect(RoundSetupOptions(draft: draft(form: "fourball"), rules: .golfgutu).showsMatches)
        // Stableford-serien (fase 18): tabellen teller stableford, så matchene verken vises eller trekkes.
        let series = RulesetTemplate.stablefordSeries.rules
        #expect(!RoundSetupOptions(draft: draft(), rules: series).showsMatches)
        var d = draft()
        d.prepareSetup(rules: series, roster: [])
        #expect(d.matches.isEmpty)
    }

    @Test func trackmanBareISimulatoren() {
        var d = draft()
        #expect(RoundSetupOptions(draft: d, rules: .golfgutu).showsTrackmanToggle)
        d.setVenue(.course, rules: .golfgutu)
        #expect(!RoundSetupOptions(draft: d, rules: .golfgutu).showsTrackmanToggle)
    }

    @Test func handicapandelBareNaarAppenGirSlagene() {
        var d = draft()
        d.externalHandicap = true
        #expect(!RoundSetupOptions(draft: d, rules: .golfgutu).showsAllowance)
        d.externalHandicap = false
        #expect(RoundSetupOptions(draft: d, rules: .golfgutu).showsAllowance)
    }

    @Test func avansertAapnesNaarNoeErEndret() {
        var d = draft()
        d.externalHandicap = false
        let standard = Ruleset.golfgutu.allowance(for: d.form)
        let options = RoundSetupOptions(draft: d, rules: .golfgutu)
        #expect(!options.advancedIsChanged(weight: 1, allowance: standard))
        #expect(options.advancedIsChanged(weight: 2, allowance: standard))
        #expect(options.advancedIsChanged(weight: 1, allowance: standard - 0.05))
        // Andelen teller ikke når Trackman gir slagene.
        d.externalHandicap = true
        #expect(!RoundSetupOptions(draft: d, rules: .golfgutu).advancedIsChanged(weight: 1, allowance: 0.5))
    }

    @Test func sidepremieSomEnRad() {
        #expect(RoundSetupOptions.sidePrizeChoice(enabled: false, holeIndex: 3, suggestion: 6) == nil)
        #expect(RoundSetupOptions.sidePrizeChoice(enabled: true, holeIndex: nil, suggestion: 6) == 6)
        #expect(RoundSetupOptions.sidePrizeChoice(enabled: true, holeIndex: 3, suggestion: 6) == 3)

        var enabled = true
        var hole: Int? = 3
        RoundSetupOptions.applySidePrize(nil, enabled: &enabled, holeIndex: &hole, suggestion: 6)
        #expect(!enabled)
        #expect(hole == 3)
        RoundSetupOptions.applySidePrize(6, enabled: &enabled, holeIndex: &hole, suggestion: 6)
        #expect(enabled)
        #expect(hole == nil)
        RoundSetupOptions.applySidePrize(9, enabled: &enabled, holeIndex: &hole, suggestion: 6)
        #expect(hole == 9)
    }
}
