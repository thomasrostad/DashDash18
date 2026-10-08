import Foundation

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
