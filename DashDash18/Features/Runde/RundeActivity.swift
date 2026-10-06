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

nonisolated extension RoundGame {
    /// «Ny runde» når runden går. Nil for en kladd (start_round feilet, eller ikke startet ennå).
    var startedEventIfActive: ActivityEvent? {
        status == .active ? startedEvent : nil
    }

    /// Etter at hull `hole` er lagret hos serveren (ikke når det bare ligger i kø): store scorer
    /// blant hullene som ble ført for første gang, så ledelsen ved regelsettets sjekkpunkt.
    /// Kalles på runden slik den er etter lagringen.
    func eventsAfterSaving(hole: Int, fresh: [(member: UUID, strokes: Int)]) -> [ActivityEvent] {
        guard status == .active else { return [] }
        var events = bigScoreEvents(hole: hole, saved: fresh)
        if let lead = leadEvent(afterSaving: hole) { events.append(lead) }
        return events
    }

    /// Ny leder på longest drive eller nærmest pinnen etter innmeldingen. Kalles på runden etter
    /// innmeldingen, med runden før.
    func sidePrizeEventAfterClaim(_ kind: SideClaimKind, member: UUID, before: RoundGame) -> ActivityEvent? {
        guard status == .active else { return nil }
        return sidePrizeLeadEvent(kind, member: member, before: before)
    }
}
