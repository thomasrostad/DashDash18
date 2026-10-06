import Foundation
import Observation

/// «Sist sett» for Varsler, per klubb på denne telefonen (PWA: `gg_varsler_sett`).
/// Tiden er serverens tid på den nyeste linja som ble vist, ikke telefonens klokke,
/// så en klokke som går feil ikke skjuler eller gjenoppliver linjer.
nonisolated struct ActivitySeenStore: Sendable {
    let clubID: UUID
    var defaults: UserDefaults { suite.map { UserDefaults(suiteName: $0) ?? .standard } ?? .standard }
    /// Egen suite i tester.
    var suite: String?

    init(clubID: UUID, suite: String? = nil) {
        self.clubID = clubID
        self.suite = suite
    }

    var key: String { "varsler.sistSett.\(clubID.uuidString)" }

    var lastSeen: Date? {
        let t = defaults.double(forKey: key)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// Flytter bare fram, aldri tilbake.
    func markSeen(upTo date: Date) {
        if let lastSeen, lastSeen >= date { return }
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    /// Alt som er vist, er sett: den nyeste linja.
    func markSeen(_ rows: [ActivityRow]) {
        guard let newest = rows.map(\.createdAt).max() else { return }
        markSeen(upTo: newest)
    }
}

/// Antall uleste til bjella i verktøylinjen. RootView eier én, og Varsler oppdaterer den.
@Observable
final class UnreadBadge {
    private(set) var count = 0
    private let seen: ActivitySeenStore
    private let me: UUID
    private let log: ActivityLog?

    init(context: ClubContext) {
        seen = ActivitySeenStore(clubID: context.clubID)
        me = context.memberID
        log = ActivityLog(client: context.client, clubID: context.clubID)
    }

    /// For forhåndsvisning og tester.
    init(clubID: UUID, me: UUID, count: Int = 0) {
        seen = ActivitySeenStore(clubID: clubID)
        self.me = me
        log = nil
        self.count = count
    }

    /// Henter linjene nyere enn sist sett og teller dem. Feil beholder tallet som står.
    func refresh() async {
        guard let log else { return }
        guard let rows = try? await log.newer(than: seen.lastSeen) else { return }
        update(from: rows)
    }

    /// Fra linjer som allerede er hentet (Varsler gjør dette etter hver henting).
    func update(from rows: [ActivityRow]) {
        count = ActivityFeed.unreadCount(rows, lastSeen: seen.lastSeen, me: me)
    }

    /// Varsler er åpnet: alt som vises, er lest.
    func markSeen(_ rows: [ActivityRow]) {
        seen.markSeen(rows)
        count = 0
    }

    /// «9+» når det er mange.
    var label: String? {
        switch count {
        case 0: nil
        case 1...9: "\(count)"
        default: "9+"
        }
    }
}
