import Foundation
import GolfgutuCore

// Hva runden logger i aktiviteten, og når. Rene beslutninger: modellene sender det som kommer ut
// med `ActivityLog.logQuietly`. Kladder logges aldri (bare arrangøren ser dem).

nonisolated enum RoundActivity {
    /// Bare runder som går eller er låst, logges.
    static func isLoggable(_ status: RoundStatus) -> Bool { status != .draft }

    /// «Runde låst» fra raden slik serveren ga den tilbake. Nil når den ikke ble låst.
    static func locked(_ row: RoundRow, courseName: String?) -> ActivityEvent? {
        guard row.status == .locked else { return nil }
        return .roundLocked(roundNo: row.roundNo, courseName: courseName)
    }
}

// MARK: - Én gang per hendelse

/// Hendelser som bare skal stå én gang per runde: «ny runde», en stor score (spiller og hull) og
/// ledelsen ved et sjekkpunkt. Samme hendelse kan ellers komme to ganger fra samme telefon (hullet
/// lagres og kommer så tilbake fra køen, eller en ny henting etter realtime). Nøkkelen har de samme
/// feltene som de unike indeksene i `sql/011_varsler_en_gang.sql`, som stopper to telefoner samtidig.
nonisolated enum ActivityOnce {
    /// Nøkkelen for hendelsen i runden, eller nil når den kan stå flere ganger.
    static func key(_ event: ActivityEvent, roundID: UUID?) -> String? {
        guard let round = roundID?.uuidString else { return nil }
        switch event {
        case .roundStarted:
            return "round_started:\(round)"
        case let .bigScore(member, hole, holeIndex, _, _, _):
            let spot = holeIndex.map { "i\($0)" } ?? "h\(hole)"
            return "big_score:\(round):\(member.uuidString):\(spot)"
        case let .leadChanged(afterHole, _, _, _):
            return "lead_changed:\(round):\(afterHole)"
        default:
            return nil
        }
    }
}

/// Det denne telefonen allerede har logget. `admit` slipper gjennom det som er nytt og husker det.
nonisolated struct ActivityOnceLog: Equatable, Sendable {
    private var seen: Set<String> = []

    init() {}

    mutating func admit(_ events: [ActivityEvent], roundID: UUID?) -> [ActivityEvent] {
        events.filter { event in
            guard let key = ActivityOnce.key(event, roundID: roundID) else { return true }
            return seen.insert(key).inserted
        }
    }
}

// MARK: - Runden

nonisolated extension RoundGame {
    /// Et hull som er ført for første gang: hvem og hvor mange slag (brutto).
    typealias FreshScore = (member: UUID, strokes: Int)

    /// «Ny runde» når runden går. Nil for en kladd (start_round feilet, eller ikke startet ennå).
    var startedEventIfActive: ActivityEvent? {
        status == .active ? startedEvent : nil
    }

    /// Store scorer blant hullene som ble ført for første gang (`loggStorScore`). En retting
    /// (spilleren er ikke i `fresh`) gir ingen.
    func bigScoreEventsAfterSaving(hole: Int, fresh: [FreshScore]) -> [ActivityEvent] {
        guard status == .active else { return [] }
        return bigScoreEvents(hole: hole, saved: fresh)
    }

    /// Skal ledelsen sjekkes etter at `hole` er lagret? Bare når noen førte hullet for første gang
    /// (en retting melder ikke ledelsen på nytt), på et av regelsettets sjekkpunkter, og ikke i
    /// runder som avgjøres hull for hull. Selve sjekken gjøres på runden slik serveren har den
    /// (PWA-en henter på nytt før `loggLedelseHvisEndret`): ellers kan en bås som ligger foran,
    /// mangle i tallene, og ledelsen blir aldri meldt.
    func shouldCheckLead(afterSaving hole: Int, fresh: [FreshScore]) -> Bool {
        status == .active && !fresh.isEmpty && rules.leadCheckpoints.contains(hole + 1)
            && !MatchPlay.isDecidedHoleByHole(round)
    }

    /// Ledelsen etter `hole` på denne runden, når runden går.
    func leadEventIfActive(afterSaving hole: Int) -> ActivityEvent? {
        guard status == .active else { return nil }
        return leadEvent(afterSaving: hole)
    }

    /// Alt som logges etter at hull `hole` er lagret, regnet på én og samme runde: store scorer,
    /// så ledelsen ved sjekkpunktet. Brukes når hull i kø er bekreftet av serveren.
    func eventsAfterSaving(hole: Int, fresh: [FreshScore]) -> [ActivityEvent] {
        var events = bigScoreEventsAfterSaving(hole: hole, fresh: fresh)
        if shouldCheckLead(afterSaving: hole, fresh: fresh), let lead = leadEvent(afterSaving: hole) {
            events.append(lead)
        }
        return events
    }

    /// Tallene fra et hull i kø som serveren nå har, med de samme slagene. Et hull som ble
    /// avvist, eller som noen har rettet i mellomtiden, logges ikke.
    func confirmed(_ fresh: [FreshScore], hole: Int) -> [FreshScore] {
        fresh.filter { scores($0.member)[hole] == $0.strokes }
    }

    /// Ny leder på longest drive eller nærmest pinnen etter innmeldingen. Kalles på runden etter
    /// innmeldingen, med runden før.
    func sidePrizeEventAfterClaim(_ kind: SideClaimKind, member: UUID, before: RoundGame) -> ActivityEvent? {
        guard status == .active else { return nil }
        return sidePrizeLeadEvent(kind, member: member, before: before)
    }
}
