import Foundation
import GolfgutuCore

// Rene beslutninger om NÅR noe skal logges, så innkoblingen i Runde, Admin og Kveld blir én
// linje. Ingen nettverk og ingen SwiftUI.

// MARK: - Store scorer

/// `loggStorScore`: brutto, ikke netto. Hole in one går foran (1 slag på par 4 er også albatross).
nonisolated enum BigScore {
    static func detect(gross: Int, par: Int) -> BigScoreName? {
        if gross == 1 { return .holeInOne }
        let diff = gross - par
        if diff <= -3 { return .albatross }
        if diff == -2 { return .eagle }
        return nil
    }
}

// MARK: - Ledelsen underveis

/// `loggLedelseHvisEndret`: hvem leder etter de n FØRSTE hullene, ved sjekkpunktene.
nonisolated enum LeadTracker {
    /// Golfgutu: hull 3, 6, 9, 12, 15 og 18 (PWA: `LEDELSE_SJEKKPUNKT`). Andre regelsett setter
    /// sine egne (`Ruleset.leadCheckpoints`).
    static let golfgutuCheckpoints = Ruleset.golfgutu.leadCheckpoints

    struct Entry: Equatable, Sendable {
        let member: UUID
        /// Stablefordpoeng per ført hull: rundens 0-baserte hull → poeng.
        let points: [Int: Int]
    }

    struct Leaders: Equatable, Sendable {
        /// Alle som deler førsteplassen, i rekkefølgen de kom inn (navnesortert av den som kaller).
        let ids: [UUID]
        let points: Int
    }

    struct Change: Equatable, Sendable {
        let afterHole: Int
        let leaders: Leaders
        let outcome: LeadOutcome
    }

    /// `poengGjennomHull`: summen over hull 0..<n, eller nil når et av dem mangler.
    static func total(_ entry: Entry, through n: Int) -> Int? {
        var sum = 0
        for i in 0..<n {
            guard let p = entry.points[i] else { return nil }
            sum += p
        }
        return sum
    }

    /// `lederEtter`: alle med flest poeng over de n første hullene. Under to med hullene ført: nil.
    static func leaders(_ entries: [Entry], through n: Int) -> Leaders? {
        let totals = entries.compactMap { e in total(e, through: n).map { (e.member, $0) } }
        guard totals.count >= 2, let top = totals.map(\.1).max() else { return nil }
        return Leaders(ids: totals.filter { $0.1 == top }.map(\.0), points: top)
    }

    /// `sammeLedelse`: samme personer, uansett rekkefølge.
    static func same(_ a: Leaders?, _ b: Leaders?) -> Bool {
        guard let a, let b, a.ids.count == b.ids.count else { return false }
        return Set(a.ids) == Set(b.ids)
    }

    /// Skal noe meldes etter at hull n (antall hull fra start) er ført?
    /// Venter til alle som har ført noe, har ført de n første. Samme ledelse som ved forrige
    /// sjekkpunkt meldes ikke, bortsett fra på siste hull (slik endte runden).
    static func change(_ entries: [Entry], afterHoles n: Int, holeCount: Int,
                       checkpoints: [Int] = golfgutuCheckpoints) -> Change? {
        guard checkpoints.contains(n), n <= holeCount else { return nil }
        let participants = entries.filter { !$0.points.isEmpty }
        guard participants.count >= 2,
              participants.allSatisfy({ total($0, through: n) != nil }),
              let now = leaders(participants, through: n) else { return nil }
        let previous = checkpoints.filter { $0 < n }.max().flatMap { leaders(participants, through: $0) }
        let isLast = n == holeCount
        let unchanged = same(now, previous)
        if unchanged && !isLast { return nil }

        let outcome: LeadOutcome
        if now.ids.count > 1 {
            outcome = isLast ? .tiedFinish : .shares
        } else if isLast {
            outcome = unchanged ? .won : .snatched
        } else {
            outcome = previous == nil ? .leads : .tookLead
        }
        return Change(afterHole: n, leaders: now, outcome: outcome)
    }
}

// MARK: - Påmelding

nonisolated enum SignupNews {
    /// `svarLinje`: bare det som er nytt for de andre. «Kommer ikke» uten å ha sagt ja er ingen
    /// nyhet, og en kommentar er ingen hendelse.
    static func event(member: UUID, from old: SignupStatus?, to new: SignupStatus, eventDate: String?) -> ActivityEvent? {
        if new == .yes && old != .yes { return .signup(member: member, status: .yes, eventDate: eventDate) }
        if old == .yes && new == .no { return .signup(member: member, status: .no, eventDate: eventDate) }
        if old == .yes && new == .maybe { return .signup(member: member, status: .maybe, eventDate: eventDate) }
        return nil
    }
}

// MARK: - Runden

nonisolated extension RoundGame {
    /// «Ny runde» når runden startes.
    var startedEvent: ActivityEvent {
        .roundStarted(roundNo: snapshot.round.roundNo, courseName: snapshot.course?.name, holeCount: holeCount,
                      bays: hasBays ? bays.count : nil,
                      ldHole: longestDriveHole.map(holeNumber), kpHole: closestToPinHole.map(holeNumber))
    }

    /// Store scorer blant hullene som nettopp ble lagret for første gang (ikke rettinger).
    func bigScoreEvents(hole index: Int, saved: [(member: UUID, strokes: Int)]) -> [ActivityEvent] {
        guard holes.indices.contains(index) else { return [] }
        let par = holes[index].par
        return saved.compactMap { s in
            BigScore.detect(gross: s.strokes, par: par).map {
                .bigScore(member: s.member, hole: holeNumber(index), holeIndex: index, name: $0, strokes: s.strokes, par: par)
            }
        }
    }

    /// Spillerne i runden med stablefordpoeng per ført hull, sortert på navn (norsk).
    var leadEntries: [LeadTracker.Entry] {
        snapshot.players
            .map(\.memberID)
            .sorted { NorwegianSort.areInIncreasingOrder(name($0), name($1)) }
            .map { member in
                let hcp = handicap(member)
                var points: [Int: Int] = [:]
                for (i, gross) in scores(member) where holes.indices.contains(i) {
                    let hole = holes[i]
                    points[i] = Scoring.points(par: hole.par, gross: gross, handicap: hcp,
                                               strokeIndex: hole.strokeIndex, holes: holeCount, rules: rules)
                }
                return LeadTracker.Entry(member: member, points: points)
            }
    }

    /// Ledelsen etter at `holeIndex` er lagret, eller nil. Runder som avgjøres hull for hull
    /// (matcher som ikke er trekanter) har ingen poengleder å melde. Sjekkpunktene er
    /// regelsettets (`leadCheckpoints`) når de ikke gis.
    func leadEvent(afterSaving holeIndex: Int, checkpoints: [Int]? = nil) -> ActivityEvent? {
        guard !MatchPlay.isDecidedHoleByHole(round),
              let change = LeadTracker.change(leadEntries, afterHoles: holeIndex + 1, holeCount: holeCount,
                                              checkpoints: checkpoints ?? rules.leadCheckpoints) else { return nil }
        return .leadChanged(afterHole: change.afterHole, leaders: change.leaders.ids, points: change.leaders.points,
                            outcome: change.outcome)
    }

    /// Ny leder på longest drive eller nærmest pinnen etter `member` sin innmelding.
    /// `before` er runden før innmeldingen. Varsel bare når ledelsen skifter til `member`.
    func sidePrizeLeadEvent(_ kind: SideClaimKind, member: UUID, before: RoundGame) -> ActivityEvent? {
        guard let prizeHole = sidePrizeHole(kind) else { return nil }
        let leaderBefore = SidePrizes.claims(kind.core, in: before.round, claims: before.coreSideClaims).first
        guard let leaderNow = SidePrizes.claims(kind.core, in: round, claims: coreSideClaims).first,
              leaderNow.playerId == member.uuidString,
              leaderBefore?.playerId != member.uuidString else { return nil }
        return .sidePrize(kind: kind, member: member, hole: holeNumber(prizeHole), meters: leaderNow.meters,
                          passed: leaderBefore.flatMap { UUID(uuidString: $0.playerId) },
                          passedMeters: leaderBefore?.meters)
    }
}
