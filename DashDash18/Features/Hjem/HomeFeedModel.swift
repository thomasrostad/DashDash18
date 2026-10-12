import Foundation
import Observation
import Supabase

/// Hjem-feeden (fase 19): henter alt fra klubbene, turneringene og rundene dine, bygger `HomeFeed`,
/// og holder den oppdatert. Etter sql/050 i sider (`feed_page`) med reaksjoner og kommentarer.
/// Realtime på `activity` og `reactions`/`comments` (uten 050: `activity_reactions`) i alle klubbene dine;
/// i tillegg hentes alt på nytt når appen blir aktiv (`load()` fra viewet), fordi realtime ikke sender
/// det som kom mens den var borte (som Varsler).
///
/// «Pågår nå» og «Neste kveld» kommer fra modellene som allerede holder dem levende (`RundeModel`,
/// `KveldModel`): viewet setter `live` og `evening`. I tillegg står de andre rundene som går og angår
/// deg (du spiller eller arrangerer, også løse runder), siden flere kan gå samtidig (sql/034).
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
    /// Personlige varsler (sql/054): følging og kommentarer på kort i «Følger». Tom uten 054.
    private(set) var personal: [PersonalActivity] = []
    private(set) var isLive = false
    var errorMessage: String?
    /// Henter neste side (`feed_page`).
    private(set) var isLoadingMore = false
    /// Er det eldre linjer å hente? Bare med sider (sql/050).
    var canLoadMore: Bool { raw.paging?.hasMore == true }

    var filter: HomeFeedFilter = .all { didSet { if filter != oldValue { rebuild() } } }
    /// Realtime bare mens Hjem står framme (settes av Hjem). Bjella i de andre fanene henter uten.
    var wantsRealtime = false
    /// Runden Kveld følger (`RundeModel`), med realtime.
    var live: HomeLiveInput? { didSet { if live != oldValue { rebuild() } } }
    /// Klubben Hjem står i: klubbrundene i «Pågår nå» åpnes der, så bare de står.
    var liveClubID: UUID? { didSet { if liveClubID != oldValue { rebuild() } } }
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
                            memberships: Dictionary(active.map { ($0.clubID, $0.id) }, uniquingKeysWith: { a, _ in a }),
                            organizerClubs: Set(active.filter(\.isOrganizer).map(\.clubID)))
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
        input.live = HomeFeed.liveInputs(focused: live, rounds: raw.rounds, viewer: viewer, club: liveClubID)
        input.evening = evening
        input.lastSeen = seenAtOpen
        input.filter = filter
        return input
    }

    private func rebuild() {
        feed = HomeFeed.build(input)
        let bellLastSeen = bellSeen?.lastSeen(fallbackClubs: clubs.map(\.id)) ?? bellPreviewSeen
        bellCount = HomeBell.unreadCount(raw.activity, mentions: raw.mentions, lastSeen: bellLastSeen,
                                         viewer: viewer, myRounds: raw.myRoundIDs(viewer: viewer))
            + (viewer.profileID.map { PersonalActivityText.unreadCount(personal, me: $0, lastSeen: bellLastSeen) } ?? 0)
    }

    /// De personlige varslene som vises i Varsler, nyeste først.
    var personalRows: [PersonalActivity] {
        viewer.profileID.map { PersonalActivityText.notifications(personal, me: $0) } ?? []
    }

    /// Henter de personlige varslene på nytt (etter Godta eller Avslå).
    func reloadPersonal() async {
        guard let client, FollowFeature.isAvailable else { return }
        if let rows = try? await FollowService(client: client).notifications() {
            personal = rows
            rebuild()
        }
    }

    /// Bjellas «sist sett» i skjermprøven (ingen lagring).
    private var bellPreviewSeen: Date? { seen == nil ? seenAtOpen : nil }

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
            var fresh = try await HomeFeedQueries.load(client: client, viewer: viewer, clubs: clubs, now: clock(),
                                                       bellSince: bellSeen?.lastSeen(fallbackClubs: clubs.map(\.id)))
            // Sidene som alt er hentet, blir stående (Realtime og dra ned henter bare første side).
            fresh.keepOlderPages(from: raw, limit: FeedPaging.pageSize)
            raw = fresh
            if FollowFeature.isAvailable {
                personal = (try? await FollowService(client: client).notifications()) ?? personal
            }
            if !hasOpened {
                hasOpened = true
                seenAtOpen = seen?.lastSeen(fallbackClubs: clubs.map(\.id))
            }
            state = .loaded
            rebuild()
            if wantsRealtime { await startRealtime() }
        } catch is CancellationError {
        } catch {
            if state == .loaded { return }  // behold det som vises
            state = .failed(DataError.from(error).message)
        }
    }

    /// Neste side av feeden (eldre linjer), når det finnes mer.
    func loadMore() async {
        guard let client, canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            raw = try await HomeFeedQueries.nextPage(client: client, clubs: clubs, raw: raw)
            rebuild()
        } catch is CancellationError {
        } catch {
            errorMessage = "Fikk ikke hentet eldre: " + DataError.from(error).message
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
        let newest = (raw.activity.map(\.createdAt) + raw.mentions.map(\.createdAt) + personal.map(\.createdAt)).max()
        if let newest { bellSeen?.markSeen(upTo: newest) }
        bellCount = 0
    }

    // MARK: Varsler (bjella)

    /// Bjellas «sist sett» da Varsler ble åpnet: prikkene viser det som var nytt da.
    private(set) var bellSeenAtOpen: Date?

    /// Varsler er åpnet fra bjella: husk hva som var nytt, og merk alt som sett.
    func openBell() {
        bellSeenAtOpen = bellSeen?.lastSeen(fallbackClubs: clubs.map(\.id)) ?? bellPreviewSeen
        markBellSeen()
    }

    /// Linjene i Varsler: det som angår deg, med reaksjoner og navn.
    func bellSections(now: Date? = nil) -> [HomeBellSection] {
        HomeBellList.sections(bellRows, reactions: raw.reactions, social: raw.social, names: raw.names, viewer: viewer,
                              lastSeen: bellSeenAtOpen, now: now ?? clock())
    }

    /// Har du reagert med denne på linja?
    func hasReacted(_ emoji: String, on target: HomeReactions) -> Bool {
        if let social = raw.social[target.activityID] { return social.summary.has(emoji) }
        guard let me = viewer.memberships[target.clubID], let reaction = ActivityReaction(rawValue: emoji) else {
            return false
        }
        return ActivityReactions.has(reaction, on: target.activityID, by: me, in: raw.reactions)
    }

    func hasReacted(_ reaction: ActivityReaction, on target: HomeReactions) -> Bool {
        hasReacted(reaction.rawValue, on: target)
    }

    // MARK: Oppslag for kortene

    /// Turneringen et tabellkort peker på.
    func competition(_ id: UUID) -> CompetitionRow? {
        raw.competitions.first { $0.id == id }
    }

    /// Resultatet av runden til deling («Del» på «Din runde»), når runden er hentet.
    func share(round id: UUID) -> ResultShare? {
        guard let s = raw.rounds.first(where: { $0.round.id == id }), let me = viewer.playerID(in: s) else {
            return nil
        }
        return RoundGame(s).share(viewer: Viewer(memberID: me, isOrganizer: false))
    }

    // MARK: Reaksjoner

    /// Vises med en gang og rulles tilbake hvis basen sier nei (som Varsler). Etter sql/050 med
    /// `react` og hvilken som helst emoji; ellers det faste settet i `activity_reactions`.
    func toggle(_ emoji: String, on target: HomeReactions) async {
        if let social = raw.social[target.activityID] {
            let had = social.summary.has(emoji)
            raw.social[target.activityID]?.summary = social.summary.toggled(emoji)
            rebuild()
            guard let client else { return }
            do {
                try await SocialService(client: client).react(emoji, on: target.target, !had)
            } catch {
                raw.social[target.activityID]?.summary = social.summary
                rebuild()
                errorMessage = "Klarte ikke å lagre reaksjonen: " + DataError.from(error).message
            }
            return
        }
        guard let reaction = ActivityReaction(rawValue: emoji) else { return }
        await toggleLegacy(reaction, on: target)
    }

    func toggle(_ reaction: ActivityReaction, on target: HomeReactions) async {
        await toggle(reaction.rawValue, on: target)
    }

    private func toggleLegacy(_ reaction: ActivityReaction, on target: HomeReactions) async {
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

    /// «Hvem har reagert»: radene fra `reactions` (050), ellers navnene som alt er hentet.
    func who(_ target: HomeReactions) async throws -> [ReactionWhoGroup] {
        guard raw.social[target.activityID] != nil, let client else { return ReactionWho.groups(target.chips) }
        let rows = try await SocialService(client: client).reactions(.activity, ids: [target.activityID])
        let names = raw.names
        return ReactionWho.groups(rows, name: { names[$0] })
    }

    // MARK: Kommentarer

    /// Kommentarene på en hendelse eller en melding i en av klubbene dine. `canModerate`: rettigheten
    /// «penger» i klubben (kan slette andres); uten svar brukes arrangøren.
    func comments(for target: SocialTarget, canModerate: Bool? = nil) -> CommentsModel? {
        guard let club = target.clubID, let me = viewer.memberships[club] else { return nil }
        let author = target.kind == .activity ? raw.activity.first { $0.id == target.id }?.actorMemberID : nil
        let people = raw.members.filter { $0.clubID == club && $0.status != .archived }
            .map { TradPerson(id: $0.id, name: $0.displayName) }
        let model = CommentsModel(target: target, me: me, isModerator: canModerate ?? viewer.organizerClubs.contains(club),
                                  isTargetAuthor: author == me, people: people, names: raw.names, client: client)
        model.onCountChange = { [weak self] count in self?.setCommentCount(count, on: target.id) }
        return model
    }

    private func setCommentCount(_ count: Int, on activityID: UUID) {
        guard raw.social[activityID] != nil, raw.social[activityID]?.commentCount != count else { return }
        raw.social[activityID]?.commentCount = count
        rebuild()
    }

    // MARK: Realtime

    private func startRealtime() async {
        guard channel == nil, let client, let profile = viewer.profileID, !clubs.isEmpty else { return }
        let ids = clubs.map(\.id.uuidString)
        let channel = client.channel("hjem-\(profile.uuidString)")
        let activity = channel.postgresChange(InsertAction.self, schema: "public", table: "activity",
                                              filter: .in("club_id", values: ids))
        // Etter sql/050: `reactions` og `comments`. Ellers det faste settet.
        let social = raw.paging != nil
        let reactionChanges = channel.postgresChange(AnyAction.self, schema: "public",
                                                     table: social ? "reactions" : "activity_reactions",
                                                     filter: .in("club_id", values: ids))
        let commentChanges = social
            ? channel.postgresChange(AnyAction.self, schema: "public", table: "comments", filter: .in("club_id", values: ids))
            : nil
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
            Task { [weak self] in
                guard let commentChanges else { return }
                for await _ in commentChanges { await self?.load() }
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
