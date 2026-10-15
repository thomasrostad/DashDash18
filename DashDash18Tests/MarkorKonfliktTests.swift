import Foundation
import Testing
@testable import DashDash18

/// K6/6.3: to markører fører ulikt for samme spiller og hull (sql/055).
struct MarkorKonfliktTests {
    let round = UUID()
    let kare = UUID()
    let ola = UUID()
    let me = UUID()
    let base = Date(timeIntervalSince1970: 1_792_000_000)

    func row(member: UUID? = nil, hole: Int = 4, kept: Int = 5, other: Int = 6, created: TimeInterval = 0,
             resolved: Bool = false, round: UUID? = nil) -> HoleConflictRow {
        HoleConflictRow(id: UUID(), roundID: round ?? self.round, memberID: member ?? kare, holeIndex: hole,
                        keptStrokes: kept, keptBy: me, keptAt: base.addingTimeInterval(created),
                        otherStrokes: other, otherBy: ola, otherAt: base.addingTimeInterval(created - 60),
                        createdAt: base.addingTimeInterval(created), resolvedAt: resolved ? base : nil)
    }

    @Test func dekoderRadenFraServeren() throws {
        let json = """
        {"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","round_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
         "member_id":"2c3d4e5f-6071-4829-9b0c-1d2e3f4a5b6c","hole_index":4,
         "kept_strokes":5,"kept_by":"3d4e5f60-7182-4930-8c1d-2e3f4a5b6c7d","kept_at":"2026-10-15T16:42:00Z",
         "other_strokes":6,"other_by":null,"other_at":"2026-10-15T16:40:00Z",
         "created_at":"2026-10-15T16:42:00Z","resolved_at":null}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let c = try decoder.decode(HoleConflictRow.self, from: Data(json.utf8))
        #expect(c.holeIndex == 4)
        #expect(c.keptStrokes == 5)
        #expect(c.otherStrokes == 6)
        #expect(c.otherBy == nil)
        #expect(c.isOpen)
        #expect(HoleConflictRow.columns.contains("resolved_at"))
    }

    @Test func viserBareAapneOgNyesteForHullet() {
        let open = row()
        let resolved = row(hole: 7, resolved: true)
        let otherRound = row(round: UUID())
        let shown = MarkerConflicts.open([open, resolved, otherRound], roundID: round)
        #expect(shown == [open])
    }

    @Test func eldreRadErUtdatertNaarEnNyereFinnes() {
        // En tredje føring lager en ny rad. Den gamle står åpen, men vises ikke.
        let old = row(kept: 5, other: 6, created: 0)
        let newer = row(kept: 4, other: 5, created: 120)
        #expect(MarkerConflicts.open([old, newer]) == [newer])
        // Er den nyeste løst, er hullet ferdig, selv om den gamle står åpen.
        let newerResolved = row(kept: 4, other: 5, created: 120, resolved: true)
        #expect(MarkerConflicts.open([old, newerResolved]).isEmpty)
    }

    @Test func sortertPaaHull() {
        let late = row(hole: 9)
        let early = row(member: ola, hole: 2)
        #expect(MarkerConflicts.open([late, early]).map(\.holeIndex) == [2, 9])
    }

    @Test func spillerneMedKonfliktPaaHullet() {
        let list = [row(hole: 4), row(member: ola, hole: 4), row(member: me, hole: 5)]
        #expect(MarkerConflicts.members(onHole: 4, in: list) == [kare, ola])
        #expect(MarkerConflicts.members(onHole: 6, in: list).isEmpty)
        #expect(MarkerConflicts.first(list, preferring: 5)?.memberID == me)
        #expect(MarkerConflicts.first(list, preferring: 8)?.holeIndex == 4)
    }

    @Test func valgeneViserBeggeTallHvemOgNaar() {
        let names = [ola: "Ola", me: "Thomas"]
        let options = MarkerConflicts.options(row(), current: 5, me: me, name: { names[$0] })
        #expect(options.map(\.strokes) == [6, 5])
        #expect(options.map(\.isCurrent) == [false, true])
        let clock = MarkerConflicts.clock(base)
        #expect(options[1].byline == "Ført av deg kl. \(clock)")
        #expect(options[0].byline.hasPrefix("Ført av Ola kl. "))
        // Ukjent markør (slettet medlem).
        #expect(MarkerConflicts.byline(by: nil, at: base, me: me, name: { _ in nil }).hasPrefix("Ført av ukjent markør"))
    }

    @Test func klokkaErOsloTid() {
        // 16:42 UTC i oktober (sommertid) er 18:42 i Oslo.
        let date = ISO8601DateFormatter().date(from: "2026-10-15T16:42:00Z")!
        #expect(MarkerConflicts.clock(date) == "18:42")
    }

    @Test func bareDeToTalleneKanVelges() {
        let c = row(kept: 5, other: 6)
        #expect(MarkerConflicts.isValidChoice(5, for: c))
        #expect(MarkerConflicts.isValidChoice(6, for: c))
        #expect(!MarkerConflicts.isValidChoice(4, for: c))
    }

    @Test func tekstene() {
        let name: (UUID) -> String = { [kare: "Kåre", ola: "Ola"][$0] ?? "Ukjent" }
        let number: (Int) -> Int = { $0 + 1 }
        #expect(MarkerConflicts.stripeText([], holeNumber: number, name: name) == nil)
        #expect(MarkerConflicts.stripeText([row()], holeNumber: number, name: name)
            == "Hull 5: to markører førte ulikt for Kåre.")
        #expect(MarkerConflicts.stripeText([row(), row(member: ola)], holeNumber: number, name: name)
            == "Hull 5: to markører førte ulikt for 2 spillere.")
        #expect(MarkerConflicts.stripeText([row(), row(hole: 8)], holeNumber: number, name: name)
            == "2 hull har ulike tall fra to markører.")
        #expect(MarkerConflicts.organizerText([]) == nil)
        #expect(MarkerConflicts.organizerText([row()]) == "1 hull har ulike tall fra to markører")
        // To spillere på samme hull er ett hull.
        #expect(MarkerConflicts.organizerText([row(), row(member: ola), row(hole: 8)]) == "2 hull har ulike tall fra to markører")
    }
}
