import Foundation

/// En linje i Varsler (bjella): teksten, tiden, om den er ulest, og reaksjonene.
nonisolated struct HomeBellItem: Identifiable, Equatable, Sendable {
    let row: ActivityRow
    let display: ActivityDisplay
    let time: String
    let isUnread: Bool
    let chips: [ReactionChip]
    /// Hvor et trykk på en reaksjon skal.
    let target: HomeReactions
    /// Kommentarene linja handler om (`comment_added`, `mentioned`).
    var opens: SocialTarget? = nil
    /// Klubben der noen venter på godkjenning (`member_pending`, sql/067): «Åpne Troppen».
    var opensRoster: UUID? = nil
    var id: UUID { row.id }
}

nonisolated struct HomeBellSection: Identifiable, Equatable, Sendable {
    let title: String
    let items: [HomeBellItem]
    var id: String { title }
}

/// Varsler-skjermen bak bjella (fase 19): bare det som angår deg (`HomeBell`), på tvers av klubbene,
/// i «I dag» og «Tidligere» som før. Ren.
nonisolated enum HomeBellList {
    static func sections(_ rows: [ActivityRow], reactions: [ActivityReactionRow], social: [UUID: ActivitySocial] = [:],
                         names: [UUID: String], viewer: HomeViewer, lastSeen: Date?, now: Date) -> [HomeBellSection] {
        ActivityFeed.sections(rows, now: now).map { section in
            HomeBellSection(title: section.title, items: section.rows.compactMap { row -> HomeBellItem? in
                // Reaksjoner krever klubb: hendelser uten klubb (sql/034) står ikke her.
                guard let club = row.clubID else { return nil }
                let me = row.clubMember(of: viewer)
                let social = social[row.id]
                let chips = social?.summary.chips()
                    ?? ActivityReactions.chips(for: row.id, in: reactions, me: me, name: { names[$0] })
                var opens: SocialTarget?
                if case let .commentAdded(c) = row.event { opens = c.target(clubID: club) }
                if case let .mentioned(c) = row.event { opens = c.target(clubID: club) }
                var roster: UUID?
                if case .memberPending = row.event { roster = club }
                return HomeBellItem(row: row,
                                    display: ActivityText.display(row, name: { names[$0] }),
                                    time: ActivityFeed.relativeTime(row.createdAt, now: now),
                                    isUnread: isUnread(row, lastSeen: lastSeen, viewer: viewer),
                                    chips: chips,
                                    target: HomeReactions(activityID: row.id, clubID: club, chips: chips,
                                                          commentCount: social?.commentCount),
                                    opens: opens,
                                    opensRoster: roster)
            })
        }
    }

    /// Nyere enn sist bjella ble åpnet, og ikke noe du gjorde selv (i noen av klubbene).
    static func isUnread(_ row: ActivityRow, lastSeen: Date?, viewer: HomeViewer) -> Bool {
        if let actor = row.actorMemberID, viewer.memberIDs.contains(actor) { return false }
        guard let lastSeen else { return true }
        return row.createdAt > lastSeen
    }
}
