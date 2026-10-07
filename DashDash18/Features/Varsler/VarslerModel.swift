import Foundation
import Observation
import Supabase

/// Varsler: aktivitetsloggen som innboks, med uleste, reaksjoner og «Melding til alle».
/// Realtime på `activity` og `activity_reactions` for klubben; i tillegg hentes alt på nytt
/// når appen blir aktiv, fordi realtime ikke sender det som kom mens den var borte.
@Observable
final class VarslerModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    struct Item: Identifiable, Equatable {
        let row: ActivityRow
        let display: ActivityDisplay
        let time: String
        let isUnread: Bool
        let chips: [ReactionChip]
        var id: UUID { row.id }
    }

    struct Section: Identifiable, Equatable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    private(set) var state: LoadState = .loading
    private(set) var rows: [ActivityRow] = []
    private(set) var reactions: [ActivityReactionRow] = []
    private(set) var names: [UUID: String] = [:]
    private(set) var isLive = false
    private(set) var isSending = false
    var errorMessage: String?

    let me: UUID
    let isOrganizer: Bool
    /// Bjella i verktøylinjen, om RootView har gitt en.
    var badge: UnreadBadge?

    private let context: ClubContext?
    private let log: ActivityLog?
    private let seen: ActivitySeenStore
    /// Sist sett da skjermen ble åpnet. Prikkene viser det som var nytt da, selv om alt
    /// markeres som sett med en gang.
    private var seenAtOpen: Date?
    private var hasOpened = false
    private var isLoading = false
    private var reloadAgain = false
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []

    init(context: ClubContext, badge: UnreadBadge? = nil) {
        self.context = context
        me = context.memberID
        isOrganizer = context.isOrganizer
        log = ActivityLog(client: context.client, clubID: context.clubID)
        seen = ActivitySeenStore(clubID: context.clubID)
        self.badge = badge
    }

    /// Forhåndsvisning: faste rader, ingen nettverk.
    init(preview rows: [ActivityRow], reactions: [ActivityReactionRow], names: [UUID: String], me: UUID,
         isOrganizer: Bool, seenAt: Date?) {
        context = nil
        log = nil
        self.me = me
        self.isOrganizer = isOrganizer
        seen = ActivitySeenStore(clubID: rows.first?.clubID ?? UUID())
        self.rows = rows
        self.reactions = reactions
        self.names = names
        seenAtOpen = seenAt
        hasOpened = true
        state = .loaded
    }

    // MARK: Visning

    func name(_ id: UUID) -> String? { names[id] }

    func sections(now: Date = .now) -> [Section] {
        ActivityFeed.sections(rows, now: now).map { s in
            Section(title: s.title, items: s.rows.map { item($0, now: now) })
        }
    }

    private func item(_ row: ActivityRow, now: Date) -> Item {
        Item(row: row,
             display: ActivityText.display(row, name: name),
             time: ActivityFeed.relativeTime(row.createdAt, now: now),
             isUnread: ActivityFeed.isUnread(row, lastSeen: seenAtOpen, me: me),
             chips: ActivityReactions.chips(for: row.id, in: reactions, me: me, name: name))
    }

    func hasReacted(_ reaction: ActivityReaction, on id: UUID) -> Bool {
        ActivityReactions.has(reaction, on: id, by: me, in: reactions)
    }

    // MARK: Henting

    func load() async {
        if isLoading { reloadAgain = true; return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadAgain = false
            await fetch()
        } while reloadAgain
    }

    private func fetch() async {
        guard let log, let context else { return }
        do {
            async let fetchedRows = log.recent()
            async let members: [ClubMemberRow] = context.client.from("club_members")
                .select(KveldQueries.memberColumns)
                .eq("club_id", value: context.clubID)
                .execute().value
            let newRows = try await fetchedRows
            let newReactions = try await log.reactions(for: newRows.map(\.id))
            let memberRows = (try? await members) ?? []
            if !memberRows.isEmpty {
                names = Dictionary(memberRows.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
            }
            rows = newRows
            reactions = newReactions
            state = .loaded
            if !hasOpened {
                hasOpened = true
                seenAtOpen = seen.lastSeen
            }
            // Skjermen er åpen: det som vises, er sett.
            seen.markSeen(newRows)
            badge?.markSeen(newRows)
            await startRealtime()
        } catch {
            if state == .loaded { return }  // behold det som vises
            state = .failed(DataError.from(error).message)
        }
    }

    // MARK: Realtime

    private func startRealtime() async {
        guard channel == nil, let context else { return }
        let channel = context.client.channel("varsler-\(context.clubID.uuidString)")
        let activity = channel.postgresChange(InsertAction.self, schema: "public", table: "activity",
                                              filter: .eq("club_id", value: context.clubID))
        let reactionChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "activity_reactions",
                                                     filter: .eq("club_id", value: context.clubID))
        let statuses = channel.statusChange
        self.channel = channel
        listenTasks = [
            Task { [weak self] in
                // Oppe igjen etter brudd i nettet: hent det som kom mens kanalen var nede.
                for await status in statuses {
                    if self?.setLive(status == .subscribed) == true { await self?.load() }
                }
            },
            Task { [weak self] in
                for await _ in activity { await self?.load() }
            },
            Task { [weak self] in
                for await _ in reactionChanges { await self?.load() }
            },
            Task { try? await channel.subscribeWithError() },
        ]
    }

    /// Gir true når kanalen nettopp kom opp.
    private func setLive(_ live: Bool) -> Bool {
        defer { isLive = live }
        return live && !isLive
    }

    func stopRealtime() async {
        listenTasks.forEach { $0.cancel() }
        listenTasks = []
        if let channel, let context { await context.client.removeChannel(channel) }
        channel = nil
        isLive = false
    }

    // MARK: Reaksjoner

    /// Vises med en gang og rulles tilbake hvis basen sier nei (`handleReaksjon`).
    func toggle(_ reaction: ActivityReaction, on id: UUID) async {
        guard let log, let context else {
            reactions = ActivityReactions.toggled(reaction, on: id, by: me, club: UUID(), in: reactions)
            return
        }
        let had = hasReacted(reaction, on: id)
        let before = reactions
        reactions = ActivityReactions.toggled(reaction, on: id, by: me, club: context.clubID, in: reactions)
        do {
            try await log.toggle(reaction, on: id, as: me, currently: had)
        } catch {
            reactions = before
            errorMessage = "Klarte ikke å lagre reaksjonen: " + error.message
        }
    }

    // MARK: Melding til alle

    /// Bare arrangøren. Gir true når meldingen er sendt.
    func sendAnnouncement(_ text: String) async -> Bool {
        guard isOrganizer, let log, !isSending else { return false }
        isSending = true
        defer { isSending = false }
        do {
            let row = try await log.announce(text)
            if !rows.contains(where: { $0.id == row.id }) { rows.insert(row, at: 0) }
            seen.markSeen(rows)
            return true
        } catch {
            errorMessage = "Klarte ikke å sende: " + error.message
            return false
        }
    }
}
