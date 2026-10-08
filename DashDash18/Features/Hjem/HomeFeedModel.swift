import Foundation
import Observation
import Supabase

/// Hjem-feeden (fase 19): henter alt fra klubbene, turneringene og rundene dine, bygger `HomeFeed`,
/// og holder den oppdatert. Realtime på `activity` og `activity_reactions` i alle klubbene dine;
/// i tillegg hentes alt på nytt når appen blir aktiv (`load()` fra viewet), fordi realtime ikke sender
/// det som kom mens den var borte (som Varsler).
///
/// «Pågår nå» og «Neste kveld» kommer fra modellene som allerede holder dem levende (`RundeModel`,
/// `KveldModel`): viewet setter `live` og `evening`. Uten `live` vises en løs runde som pågår, om
/// du har en.
@Observable
final class HomeFeedModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var feed: HomeFeed
    /// Tallet på bjella: det som angår deg (`HomeBell`), nyere enn sist bjella ble åpnet.
    private(set) var bellCount = 0
    private(set) var isLive = false
    var errorMessage: String?

    var filter: HomeFeedFilter = .all { didSet { if filter != oldValue { rebuild() } } }
    var live: HomeLiveInput? { didSet { if live != oldValue { rebuild() } } }
    var evening: HomeEveningInput? { didSet { if evening != oldValue { rebuild() } } }

    let viewer: HomeViewer
    let clubs: [HomeClub]
    private let client: SupabaseClient?
    private let seen: HomeSeenStore?
    private let bellSeen: HomeSeenStore?
    private let clock: @Sendable () -> Date
    private var raw = HomeFeedQueries.Raw()
    /// Sist sett da Hjem ble åpnet: oppsummeringen og «ulest» viser det som var nytt da, også etter
    /// at alt er merket som sett.
    private var seenAtOpen: Date?
    private var hasOpened = false
    private var isLoading = false
    private var reloadAgain = false
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []

    /// - Parameters:
    ///   - userID: innloggingen (= `profiles.id`).
    ///   - memberships: medlemskapene (`ClubModel.memberships`). Bare de aktive teller.
    init(client: SupabaseClient, userID: UUID, memberships: [Membership]) {
        let active = memberships.filter { $0.status == .active }
        viewer = HomeViewer(profileID: userID,
                            memberships: Dictionary(active.map { ($0.clubID, $0.id) }, uniquingKeysWith: { a, _ in a }))
        clubs = active.map { HomeClub(id: $0.clubID, name: $0.club.name) }
        self.client = client
        seen = HomeSeenStore(userID: userID, clock: .feed)
        bellSeen = HomeSeenStore(userID: userID, clock: .bell)
        clock = { .now }
        feed = HomeFeed.build(HomeFeedInput(viewer: viewer))
    }

    /// Skjermprøve og tester: fast råmateriale, ingen nettverk og ingen lagring.
    init(preview raw: HomeFeedQueries.Raw, viewer: HomeViewer, clubs: [HomeClub], lastSeen: Date?,
         now: @escaping @Sendable () -> Date = { .now }) {
        self.viewer = viewer
        self.clubs = clubs
        client = nil
        seen = nil
        bellSeen = nil
        clock = now
        self.raw = raw
        seenAtOpen = lastSeen
        hasOpened = true
        state = .loaded
        feed = HomeFeed.build(HomeFeedInput(now: now(), viewer: viewer))
        rebuild()
    }

    // MARK: Bygging

    /// Råmaterialet slik feeden ser det nå.
    var input: HomeFeedInput {
        var input = raw.input(viewer: viewer, clubs: clubs, now: clock())
        input.live = live ?? ongoingLoose
        input.evening = evening
        input.lastSeen = seenAtOpen
        input.filter = filter
        return input
    }

    private func rebuild() {
        feed = HomeFeed.build(input)
        bellCount = HomeBell.unreadCount(raw.activity, mentions: raw.mentions,
                                         lastSeen: bellSeen?.lastSeen(fallbackClubs: clubs.map(\.id)) ?? bellPreviewSeen,
                                         viewer: viewer, myRounds: raw.myRoundIDs(viewer: viewer))
    }

    /// Bjellas «sist sett» i skjermprøven (ingen lagring).
    private var bellPreviewSeen: Date? { seen == nil ? seenAtOpen : nil }

    /// En løs runde som pågår, der du spiller (når viewet ikke har satt `live`).
    private var ongoingLoose: HomeLiveInput? {
        guard let profile = viewer.profileID,
              let s = raw.rounds.first(where: { $0.isLoose && $0.round.status == .active && viewer.playerID(in: $0) != nil })
        else { return nil }
        return HomeLiveInput(snapshot: s, viewer: LooseRoundRights.viewer(info: s.loose, userID: profile))
    }

    /// Linjene bjella viser (det som angår deg), nyeste først.
    var bellRows: [ActivityRow] {
        HomeBell.rows(raw.activity, viewer: viewer, myRounds: raw.myRoundIDs(viewer: viewer))
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
        guard let client else { return }
        do {
            raw = try await HomeFeedQueries.load(client: client, viewer: viewer, clubs: clubs, now: clock(),
                                                 bellSince: bellSeen?.lastSeen(fallbackClubs: clubs.map(\.id)))
            if !hasOpened {
                hasOpened = true
                seenAtOpen = seen?.lastSeen(fallbackClubs: clubs.map(\.id))
            }
            state = .loaded
            rebuild()
            await startRealtime()
        } catch is CancellationError {
        } catch {
            if state == .loaded { return }  // behold det som vises
            state = .failed(DataError.from(error).message)
        }
    }

    // MARK: Sett

    /// Det nyeste som er hentet (serverens tid).
    var newestDate: Date? {
        (raw.activity.map(\.createdAt) + raw.rounds.compactMap(\.round.lockedAt)).max()
    }

    /// Hjem er vist: alt som er hentet, er sett. Oppsummeringen står til neste gang Hjem åpnes.
    func markSeen() {
        guard let newest = newestDate else { return }
        seen?.markSeen(upTo: newest)
    }

    /// Hjem åpnes på nytt (ny økt): oppsummeringen regnes fra det som var sett nå.
    func reopen() {
        seenAtOpen = seen?.lastSeen(fallbackClubs: clubs.map(\.id)) ?? seenAtOpen
        rebuild()
    }

    /// Bjella er åpnet.
    func markBellSeen() {
        let newest = (raw.activity.map(\.createdAt) + raw.mentions.map(\.createdAt)).max()
        if let newest { bellSeen?.markSeen(upTo: newest) }
        bellCount = 0
    }

    // MARK: Reaksjoner

    /// Vises med en gang og rulles tilbake hvis basen sier nei (som Varsler).
    func toggle(_ reaction: ActivityReaction, on target: HomeReactions) async {
        guard let me = viewer.memberships[target.clubID] else { return }
        let had = ActivityReactions.has(reaction, on: target.activityID, by: me, in: raw.reactions)
        let before = raw.reactions
        raw.reactions = ActivityReactions.toggled(reaction, on: target.activityID, by: me, club: target.clubID,
                                                  in: raw.reactions)
        rebuild()
        guard let client else { return }
        do {
            try await ActivityLog(client: client, clubID: target.clubID)
                .toggle(reaction, on: target.activityID, as: me, currently: had)
        } catch {
            raw.reactions = before
            rebuild()
            errorMessage = "Klarte ikke å lagre reaksjonen: " + error.message
        }
    }

    // MARK: Realtime

    private func startRealtime() async {
        guard channel == nil, let client, let profile = viewer.profileID, !clubs.isEmpty else { return }
        let ids = clubs.map(\.id.uuidString)
        let channel = client.channel("hjem-\(profile.uuidString)")
        let activity = channel.postgresChange(InsertAction.self, schema: "public", table: "activity",
                                              filter: .in("club_id", values: ids))
        let reactionChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "activity_reactions",
                                                     filter: .in("club_id", values: ids))
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
        if let channel, let client { await client.removeChannel(channel) }
        channel = nil
        isLive = false
    }
}
