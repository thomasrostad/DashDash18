import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

private let me = UUID(uuidString: "11111111-0000-0000-0000-000000000001")!
private let guestMe = UUID(uuidString: "33333333-0000-0000-0000-000000000001")!
private let clubID = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
private let courseID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000001")!
private let eventID = UUID(uuidString: "EEEEEEEE-0000-0000-0000-000000000001")!
private let clubRound = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000001")!
private let looseRound = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000002")!
private let draftRound = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000003")!
private let backNine = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!

private func round(_ id: UUID, club: UUID? = clubID, event: UUID? = eventID, status: RoundStatus = .locked,
                   holes: Int = 18, first: Int = 1, external: Bool = false, started: Date? = nil) -> StatsRoundRow {
    StatsRoundRow(id: id, clubID: club, eventID: event, courseID: courseID, name: nil, status: status,
                  holeCount: holes, firstHole: first, format: "stableford", handicapAllowance: 1,
                  externalHandicap: external, startedAt: started)
}

/// Banen: par 4 på alle hull unntatt 3, 6, 9 … (par 3), indeks = hullnummer.
private func input() -> StatsInput {
    var i = StatsInput()
    // 2026-06-10 21:30 UTC = 23:30 i Oslo (samme dag).
    let started = Date(timeIntervalSince1970: 1_781_127_000)
    i.rounds = [round(clubRound), round(looseRound, club: nil, event: nil, external: true, started: started),
                round(draftRound, status: .draft), round(backNine, holes: 9, first: 10)]
    i.players = [
        StatsPlayerRow(roundID: clubRound, memberID: me, handicapIndex: 14.2, seedGroup: nil, playingHandicap: 15),
        StatsPlayerRow(roundID: looseRound, memberID: guestMe, handicapIndex: 14.0, seedGroup: nil, playingHandicap: 14),
        StatsPlayerRow(roundID: draftRound, memberID: me, handicapIndex: 14.2, seedGroup: nil, playingHandicap: 15),
        StatsPlayerRow(roundID: backNine, memberID: me, handicapIndex: 14.2, seedGroup: nil, playingHandicap: nil),
    ]
    i.courses = [StatsCourseRow(id: courseID, name: "Bjaavann", courseRating: 71.2, slopeRating: 125)]
    i.courseHoles = (1...18).map { CourseHoleRecord(courseID: courseID, holeNumber: $0, par: $0 % 3 == 0 ? 3 : 4,
                                                   strokeIndex: $0, lengthM: nil) }
    i.roundHoles = [RoundHoleRow(roundID: clubRound, holeIndex: 0, par: 5, strokeIndex: nil, lengthM: nil)]
    i.scores = [HoleScoreRow(roundID: clubRound, memberID: me, holeIndex: 0, strokes: 6),
                HoleScoreRow(roundID: looseRound, memberID: guestMe, holeIndex: 1, strokes: 3),
                HoleScoreRow(roundID: clubRound, memberID: UUID(), holeIndex: 1, strokes: 9)]
    i.details = [HoleStatRow(roundID: clubRound, memberID: me, holeIndex: 0,
                             detail: HoleDetail(fairway: .left, putts: 2))]
    i.eventDates = [eventID: "2026-09-03"]
    var rules = Ruleset.golfgutu
    rules.scoring = .init(netParPoints: 3, minimumPoints: 0)
    i.eventRules = [eventID: rules]
    i.clubNames = [clubID: "Golfgutu"]
    return i
}

struct StatistikkInputTests {
    let rounds = input().statsRounds()

    @Test func kladderErIkkeMed() {
        #expect(Set(rounds.map(\.id)) == Set([clubRound, looseRound, backNine].map(\.uuidString)))
    }

    @Test func klubbrunde() throws {
        let r = try #require(rounds.first { $0.id == clubRound.uuidString })
        #expect(r.kind == .club)
        #expect(r.date == "2026-09-03")
        #expect(r.clubName == "Golfgutu")
        #expect(r.courseName == "Bjaavann")
        #expect(r.playingHandicap == 15)
        #expect(r.handicapIndex == 14.2)
        #expect(r.courseRating == 71.2 && r.slopeRating == 125)
        #expect(r.holes.count == 18)
        #expect(r.holes[0].par == 5, "rundens eget par vinner over banen")
        #expect(r.holes[2].par == 3)
        #expect(r.scores == [0: 6], "bare spillerens egne slag")
        #expect(r.details[0]?.fairway == .left)
        #expect(r.scoring?.netParPoints == 3, "stablefordregelen fra sesongen")
    }

    @Test func loesRundeMedEksternHandicap() throws {
        let r = try #require(rounds.first { $0.id == looseRound.uuidString })
        #expect(r.kind == .loose)
        #expect(r.date == "2026-06-10", "dagen runden startet, norsk tid")
        #expect(r.clubName == nil)
        #expect(r.playingHandicap == 0, "simulatoren deler ut slagene")
        #expect(r.scores == [1: 3])
        #expect(r.scoring?.netParPoints == Ruleset.golfgutu.scoring.netParPoints)
    }

    @Test func sisteNiHarHullnummer10Til18() throws {
        let r = try #require(rounds.first { $0.id == backNine.uuidString })
        #expect(r.holes.map(\.number) == Array(10...18))
        #expect(r.layoutKey == "10-18")
        // Uten frosset tall: effectiveHandicap (WHS-banehandicap · 9/18).
        let expected = JS.round(Handicap.courseHandicap(index: 14.2, courseRating: 71.2, slopeRating: 125, par: 66) / 2)
        #expect(r.playingHandicap == expected)
    }

    @Test func oppdelingIBiter() {
        let ids = (0..<85).map { _ in UUID() }
        let chunks = StatsQueries.chunked(ids, size: 40)
        #expect(chunks.map(\.count) == [40, 40, 5])
        #expect(chunks.flatMap { $0 } == ids)
    }
}

struct StatistikkForingTests {
    @Test func fairwayVelgesOgTasBort() {
        let d = HoleStatsInput.fairway(HoleDetail(), .hit)
        #expect(d.fairway == .hit)
        #expect(HoleStatsInput.fairway(d, .left).fairway == .left)
        #expect(HoleStatsInput.fairway(d, .hit).fairway == nil)
    }

    @Test func jaNeiIkkeFort() {
        #expect(HoleStatsInput.cycle(nil) == true)
        #expect(HoleStatsInput.cycle(true) == false)
        #expect(HoleStatsInput.cycle(false) == nil)
    }

    @Test func putter() {
        var d = HoleStatsInput.putts(HoleDetail(), 1)
        #expect(d.putts == 2)
        d = HoleStatsInput.putts(d, -1); d = HoleStatsInput.putts(d, -1)
        #expect(d.putts == 0, "null putter (chip-in) er lov")
        #expect(HoleStatsInput.putts(d, -1).putts == nil)
        #expect(HoleStatsInput.putts(HoleDetail(), -1).putts == 1)
        #expect(HoleStatsInput.putts(HoleDetail(putts: 9), 1).putts == 9)
    }

    @Test func straffeslag() {
        let d = HoleStatsInput.penalties(HoleDetail(), 1)
        #expect(d.penalties == 1)
        #expect(HoleStatsInput.penalties(d, -1).penalties == nil)
        #expect(HoleStatsInput.penalties(HoleDetail(), -1).penalties == nil)
    }

    @Test func ingenFairwayPaaPar3() {
        let d = HoleDetail(fairway: .hit, putts: 2)
        #expect(HoleStatsInput.normalized(d, par: 3).fairway == nil)
        #expect(HoleStatsInput.normalized(d, par: 4).fairway == .hit)
    }

    /// Upserten sender også tomme felt, så noe som er tatt bort nullstilles i databasen.
    @Test func radenSenderAlleFelt() throws {
        let row = HoleStatRow(roundID: clubRound, memberID: me, holeIndex: 3, detail: HoleDetail(putts: 2))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        #expect(json?["putts"] as? Int == 2)
        #expect(json?["fairway"] is NSNull)
        #expect(json?["green_in_regulation"] is NSNull)
        #expect(json?["hole_index"] as? Int == 3)
        #expect(Set(json?.keys.map { $0 } ?? []) == Set(HoleStatRow.columns.components(separatedBy: ", ")))
    }

    @Test func innstillingenErAvSomStandardOgPerInnlogging() throws {
        let defaults = try #require(UserDefaults(suiteName: "statistikk-test-\(UUID())"))
        let setting = HoleStatsSetting(defaults: defaults)
        let a = UUID(), b = UUID()
        #expect(!setting.isOn(for: a))
        setting.set(true, for: a)
        #expect(setting.isOn(for: a))
        #expect(!setting.isOn(for: b))
    }
}

struct StatistikkFormatTests {
    @Test func motPar() {
        #expect(StatsFormat.toPar(5) == "+5")
        #expect(StatsFormat.toPar(-2) == "−2")
        #expect(StatsFormat.toPar(0) == "0")
        #expect(StatsFormat.toPar(1.44, digits: 1) == "+1,4")
        #expect(StatsFormat.toPar(-0.04, digits: 1) == "0,0")
    }

    @Test func indeks() {
        #expect(StatsFormat.index(12.4) == "12,4")
        #expect(StatsFormat.index(-1.2) == "+1,2")
        #expect(StatsFormat.percent(0.456) == "46 %")
    }

    @Test func perioder() throws {
        let today = try #require(StatsFormat.date("2026-10-07"))
        #expect(StatsPeriod.all.from(today: today) == nil)
        #expect(StatsPeriod.thisYear.from(today: today) == "2026-01-01")
        #expect(StatsPeriod.last12Months.from(today: today) == "2025-10-07")
        #expect(StatsPeriod.last90Days.from(today: today) == "2026-07-09")
    }
}

@MainActor
struct StatistikkModelTests {
    @Test func filteretRegnerUtvalgetPaaNytt() throws {
        let model = StatsModel(scope: .me(userID: UUID(), memberIDs: [], clubNames: [:]), rounds: StatsSamples.rounds)
        model.today = try #require(StatsFormat.date("2026-10-07"))
        let all = model.summary.rounds.count
        #expect(all == 16)
        #expect(model.hasEnoughData)
        #expect(model.hasBothKinds)
        #expect(model.primaryHoleCount == 18)
        model.kind = .loose
        #expect(model.summary.rounds.count == 4)
        #expect(model.isFiltered)
        model.courseID = "c2"
        #expect(model.summary.rounds.allSatisfy { $0.courseID == "c2" && $0.kind == .loose })
        model.resetFilter()
        #expect(model.summary.rounds.count == all)
        model.period = .last90Days
        #expect(model.summary.rounds.allSatisfy { $0.date >= "2026-07-09" })
    }

    @Test func tomtilstand() {
        let model = StatsModel(scope: .me(userID: UUID(), memberIDs: [], clubNames: [:]), rounds: [])
        #expect(!model.hasEnoughData)
        #expect(!model.isFilteredEmpty)
        #expect(model.primaryHoleCount == nil)
    }
}
