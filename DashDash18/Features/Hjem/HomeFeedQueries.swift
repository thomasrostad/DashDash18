import Foundation
import GolfgutuCore
import Supabase

/// Henter råmaterialet til Hjem-feeden (fase 19). Bare lesing, og bare med RLS slik den er i dag:
///   * `activity` og `activity_reactions` med `club_id in (klubbene dine)` (`is_club_member`, sql/008),
///   * turneringene du ser (`can_read_competition`, 017/022),
///   * dine runder: klubbrundene du spilte (låst i vinduet) og løse runder (eier eller med, 017/018),
///   * klubbrundene som går og angår deg (du spiller eller arrangerer), til «Pågår nå»,
///   * rundene i private turneringer (via turneringen, `can_read_round` fra 017).
/// Ingen ny SQL trengs for å lese.
enum HomeFeedQueries {
    static let activityLimit = 150
    /// Dine klubbrunder med alt under: én henting per runde, så antallet holdes nede.
    static let clubRoundLimit = 8
    /// Klubbrunder som går, til «Pågår nå». Flere kan gå samtidig etter sql/034.
    static let activeRoundLimit = 6
    static let looseRoundLimit = 20
    static let privateCompetitionLimit = 5
    /// Id-er per `in`-filter, så adressen holder seg kort.
    nonisolated static let chunkSize = 50

    /// Alt feeden trenger, slik databasen leverer det.
    struct Raw: Sendable {
        var activity: [ActivityRow] = []
        var reactions: [ActivityReactionRow] = []
        var members: [ClubMemberRow] = []
        var competitions: [CompetitionRow] = []
        var links: [CompetitionRoundRow] = []
        var roundLabels: [UUID: HomeRoundLabel] = [:]
        /// Løse runder først (originalen vinner over turneringens omnavnede kopi), så klubbrundene,
        /// så rundene i private turneringer.
        var rounds: [RoundSnapshot] = []
        var competitionInputs: [CompetitionInput] = []
        /// Tråden: meldinger der du er nevnt, til bjella.
        var mentions: [ThreadMessageRow] = []
        /// Reaksjoner og kommentarer per hendelse fra `feed_page` (sql/050).
        var social: [UUID: ActivitySocial] = [:]
        /// Sidene fra `feed_page`. nil: den gamle hentingen (uten 050), med vinduet på 30 dager.
        var paging: Paging?

        struct Paging: Equatable, Sendable {
            /// Der neste side starter (den eldste linja som er hentet, også linjer uten klubb).
            var cursor: FeedCursor?
            var hasMore: Bool
        }

        /// Navn på medlemmer i alle klubbene, deltakere i rundene og spillerne i turneringene.
        var names: [UUID: String] {
            var out: [UUID: String] = [:]
            for s in rounds { out.merge(s.names) { a, _ in a } }
            for ci in competitionInputs {
                for (e, p) in zip(ci.entrants, ci.roster) where out[e.id] == nil { out[e.id] = p.name }
            }
            for m in members { out[m.id] = m.displayName }
            return out
        }

        /// Rundene du spilte (for bjella: «din runde»).
        func myRoundIDs(viewer: HomeViewer) -> Set<UUID> {
            Set(rounds.filter { viewer.playerID(in: $0) != nil }.map(\.round.id))
        }

        func input(viewer: HomeViewer, clubs: [HomeClub], now: Date) -> HomeFeedInput {
            var input = HomeFeedInput(now: now, viewer: viewer)
            input.clubs = clubs
            input.competitions = competitions
            input.links = links
            input.activity = activity
            input.reactions = reactions
            input.social = social
            input.paged = paging != nil
            input.names = names
            input.roundLabels = roundLabels
            input.rounds = rounds
            input.competitionInputs = competitionInputs
            return input
        }
    }

    /// `my_activity` (sql/037).
    nonisolated private struct ActivityParams: Encodable {
        let p_club_ids: [UUID]
        let p_since: Date
    }

    /// Bare aktiviteten og troppene er påkrevd. Feiler noe av resten (turneringer, runder, koblinger),
    /// vises feeden uten de kortene i stedet for å feile.
    static func load(client: SupabaseClient, viewer: HomeViewer, clubs: [HomeClub], now: Date,
                     bellSince: Date?) async throws -> Raw {
        let since = now.addingTimeInterval(-HomeFeed.window)
        let clubIDs = clubs.map(\.id.uuidString)
        var raw = Raw()

        // Klubbene: aktiviteten og troppene. Etter sql/050 første side av `feed_page`, med reaksjonene
        // og antall kommentarer. Mangler 050, hentes det som før.
        if !clubIDs.isEmpty, let page = try await firstPage(client: client, clubs: clubs) {
            async let members: [ClubMemberRow] = client.from("club_members")
                .select(ClubMemberRow.columns)
                .in("club_id", values: clubIDs)
                .execute().value
            raw.apply(page: page, limit: FeedPaging.pageSize)
            raw.members = try await members
            raw.mentions = (try? await mentions(client: client, viewer: viewer, clubIDs: clubIDs,
                                                since: bellSince ?? since)) ?? []
        } else if !clubIDs.isEmpty {
            async let activity: [ActivityRow] = (SetQueriesFeature.isEnabled
                ? client.rpc("my_activity", params: ActivityParams(p_club_ids: clubs.map(\.id), p_since: since))
                    .select(ActivityLog.columns)
                : client.from("activity")
                    .select(ActivityLog.columns)
                    .in("club_id", values: clubIDs)
                    .gte("created_at", value: since))
                .order("created_at", ascending: false)
                .limit(activityLimit)
                .execute().value
            async let members: [ClubMemberRow] = client.from("club_members")
                .select(ClubMemberRow.columns)
                .in("club_id", values: clubIDs)
                .execute().value
            // Hendelser uten klubb (sql/034, fra steg 9) hører ikke til klubbfeeden ennå.
            raw.activity = try await activity.filter { $0.clubID != nil }
            raw.members = try await members
            raw.reactions = (try? await chunked(raw.activity.map(\.id)) { ids in
                try await client.from("activity_reactions")
                    .select(ActivityLog.reactionColumns)
                    .in("activity_id", values: ids)
                    .execute().value
            }) ?? []
            raw.mentions = (try? await mentions(client: client, viewer: viewer, clubIDs: clubIDs,
                                                since: bellSince ?? since)) ?? []
        }

        // Dine runder: løse først, så klubbrundene.
        if LooseRoundsFeature.isEnabled {
            let loose = (try? await LooseRoundQueries.myRounds(client: client, limit: looseRoundLimit)) ?? []
            raw.rounds += loose.filter { $0.round.status == .active || ($0.round.lockedAt ?? $0.round.startedAt ?? .distantPast) >= since }
        }
        if !clubIDs.isEmpty {
            raw.rounds += (try? await myClubRounds(client: client, viewer: viewer, clubIDs: clubIDs, since: since)) ?? []
            raw.rounds += (try? await activeClubRounds(client: client, viewer: viewer, clubIDs: clubIDs)) ?? []
        }

        // Turneringene, og tabellgrunnlaget for de private.
        if let overview = try? await CompetitionQueries.overview(client: client) {
            // Deltakerradene (sql/059): turneringer i klubber du ikke er medlem i, men er påmeldt.
            var participations: [Participation] = []
            if let profile = viewer.profileID {
                participations = (try? await ParticipationQueries.mine(client: client, userID: profile)) ?? []
            }
            let access = CompetitionAccess(profileID: viewer.profileID, memberships: viewer.memberships.map {
                CompetitionAccess.Membership(clubID: $0.key, memberID: $0.value, isOrganizer: false, isActive: true)
            }).with(participations: participations)
            raw.competitions = overview.competitions.filter { access.canSee($0, overview.participants) }
            let privates = raw.competitions.filter { c in
                (c.kind == .league || c.kind == .fun) && c.status == .active
                    && (c.clubID.map { viewer.memberships[$0] == nil } ?? true)
            }
            for c in privates.prefix(privateCompetitionLimit) {
                let participants = overview.participants.filter { $0.competitionID == c.id }
                guard let detail = try? await CompetitionQueries.detail(client: client, competition: c,
                                                                        participants: participants) else { continue }
                raw.competitionInputs.append(detail.input)
                raw.rounds += detail.input.rounds
            }
        }

        // Koblingene og rundenavnene for det som er hentet.
        let roundIDs = Array(Set(raw.activity.compactMap(\.roundID) + raw.rounds.map(\.round.id)))
        raw.links = (try? await chunked(roundIDs) { ids in
            try await client.from("competition_rounds")
                .select(CompetitionQueries.linkColumns)
                .in("round_id", values: ids)
                .execute().value
        }) ?? []
        raw.roundLabels = (try? await labels(client: client, activity: raw.activity, known: raw.rounds)) ?? [:]
        return raw
    }

    /// Første side av `feed_page`, eller nil når 050 mangler (eller er slått av).
    private static func firstPage(client: SupabaseClient, clubs: [HomeClub]) async throws -> [FeedPageRow]? {
        guard SocialFeature.isEnabled else { return nil }
        do {
            return try await SocialService(client: client).feedPage(clubIDs: clubs.map(\.id), before: nil)
        } catch where SocialService.isMissing(error) {
            return nil
        }
    }

    /// Neste side av feeden, med rundenavnene for det som er nytt.
    static func nextPage(client: SupabaseClient, clubs: [HomeClub], raw: Raw) async throws -> Raw {
        guard let paging = raw.paging, paging.hasMore, let cursor = paging.cursor else { return raw }
        let page = try await SocialService(client: client).feedPage(clubIDs: clubs.map(\.id), before: cursor)
        var out = raw
        out.apply(page: page, limit: FeedPaging.pageSize, appending: true)
        if let more = try? await labels(client: client, activity: out.activity, known: out.rounds) {
            out.roundLabels.merge(more) { a, _ in a }
        }
        return out
    }

    /// Klubbrundene du spilte, låst i vinduet, nyeste først, med alt under.
    private static func myClubRounds(client: SupabaseClient, viewer: HomeViewer, clubIDs: [String],
                                     since: Date) async throws -> [RoundSnapshot] {
        let allRounds: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .in("club_id", values: clubIDs)
            .eq("status", value: RoundStatus.locked.rawValue)
            .gte("locked_at", value: since)
            .order("locked_at", ascending: false)
            .limit(40)
            .execute().value
        let rounds = allRounds.ordinary
        guard !rounds.isEmpty, !viewer.memberIDs.isEmpty else { return [] }
        struct Played: Decodable {
            let roundID: UUID
            enum CodingKeys: String, CodingKey { case roundID = "round_id" }
        }
        let played: [Played] = try await client.from("round_players")
            .select("round_id")
            .in("round_id", values: rounds.map(\.id.uuidString))
            .in("member_id", values: viewer.memberIDs.map(\.uuidString))
            .execute().value
        let mine = Set(played.map(\.roundID))
        let chosen = rounds.filter { mine.contains($0.id) }.prefix(clubRoundLimit)
        return try await withThrowingTaskGroup(of: RoundSnapshot.self) { group in
            for round in chosen {
                group.addTask { try await RundeQueries.snapshot(client: client, round: round) }
            }
            var out: [RoundSnapshot] = []
            for try await s in group { out.append(s) }
            return out.sorted { ($0.round.lockedAt ?? .distantPast) > ($1.round.lockedAt ?? .distantPast) }
        }
    }

    /// Klubbrundene som går nå der du spiller, eller i klubber der du er arrangør, med alt under.
    /// Nyest startet først.
    private static func activeClubRounds(client: SupabaseClient, viewer: HomeViewer,
                                         clubIDs: [String]) async throws -> [RoundSnapshot] {
        let allRounds: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .in("club_id", values: clubIDs)
            .eq("status", value: RoundStatus.active.rawValue)
            .order("started_at", ascending: false)
            .limit(40)
            .execute().value
        let rounds = allRounds.ordinary
        guard !rounds.isEmpty, !viewer.memberIDs.isEmpty else { return [] }
        struct Played: Decodable {
            let roundID: UUID
            enum CodingKeys: String, CodingKey { case roundID = "round_id" }
        }
        let played: [Played] = try await client.from("round_players")
            .select("round_id")
            .in("round_id", values: rounds.map(\.id.uuidString))
            .in("member_id", values: viewer.memberIDs.map(\.uuidString))
            .execute().value
        let mine = Set(played.map(\.roundID))
        let chosen = rounds.filter { round in
            mine.contains(round.id) || round.clubID.map(viewer.organizerClubs.contains) ?? false
        }.prefix(activeRoundLimit)
        let order = Dictionary(chosen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        return try await withThrowingTaskGroup(of: RoundSnapshot.self) { group in
            for round in chosen {
                group.addTask { try await RundeQueries.snapshot(client: client, round: round) }
            }
            var out: [RoundSnapshot] = []
            for try await s in group { out.append(s) }
            return out.sorted { (order[$0.round.id] ?? 0) < (order[$1.round.id] ?? 0) }
        }
    }

    /// Bane og rundenummer for rundene aktiviteten peker på («Losby · runde 4»).
    private static func labels(client: SupabaseClient, activity: [ActivityRow],
                               known: [RoundSnapshot]) async throws -> [UUID: HomeRoundLabel] {
        var out: [UUID: HomeRoundLabel] = [:]
        for s in known {
            out[s.round.id] = HomeRoundLabel(courseName: s.course?.name, roundNo: s.isLoose ? nil : s.round.roundNo)
        }
        let missing = Array(Set(activity.compactMap(\.roundID)).subtracting(out.keys))
        guard !missing.isEmpty else { return out }
        struct Round: Decodable {
            let id: UUID
            let roundNo: Int
            let courseID: UUID?
            let clubID: UUID?
            enum CodingKeys: String, CodingKey {
                case id
                case roundNo = "round_no"
                case courseID = "course_id"
                case clubID = "club_id"
            }
        }
        struct Course: Decodable { let id: UUID; let name: String }
        let rounds: [Round] = try await chunked(missing) { ids in
            try await client.from("rounds").select("id, round_no, course_id, club_id").in("id", values: ids)
                .execute().value
        }
        let courseIDs = Array(Set(rounds.compactMap(\.courseID)))
        let courses: [Course] = try await chunked(courseIDs) { ids in
            try await client.from("courses").select("id, name").in("id", values: ids).execute().value
        }
        let names = Dictionary(courses.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for r in rounds {
            out[r.id] = HomeRoundLabel(courseName: r.courseID.flatMap { names[$0] }, roundNo: r.clubID == nil ? nil : r.roundNo)
        }
        return out
    }

    /// Trådmeldinger der du er nevnt (bjella).
    private static func mentions(client: SupabaseClient, viewer: HomeViewer, clubIDs: [String],
                                 since: Date) async throws -> [ThreadMessageRow] {
        guard !viewer.memberIDs.isEmpty else { return [] }
        return try await client.from("thread_messages")
            .select(ThreadMessageRow.columns)
            .in("club_id", values: clubIDs)
            .gt("created_at", value: since)
            .overlaps("mentions", value: viewer.memberIDs.map(\.uuidString))
            .order("created_at", ascending: false)
            .limit(50)
            .execute().value
    }

    /// Kjører spørringen i biter av `chunkSize` id-er og slår svarene sammen.
    private static func chunked<T: Sendable>(_ ids: [UUID],
                                             _ query: @Sendable ([String]) async throws -> [T]) async throws -> [T] {
        var out: [T] = []
        for start in stride(from: 0, to: ids.count, by: chunkSize) {
            out += try await query(ids[start..<min(start + chunkSize, ids.count)].map(\.uuidString))
        }
        return out
    }
}


extension HomeFeedQueries.Raw {
    /// Legger inn en side fra `feed_page`. Hendelser uten klubb hører ikke til klubbfeeden ennå, men
    /// teller for neste side (nøkkelen og om det er mer).
    mutating func apply(page: [FeedPageRow], limit: Int, appending: Bool = false) {
        let rows = page.filter { $0.activity.clubID != nil }
        for row in rows { social[row.activity.id] = row.social }
        let pageCursor = FeedCursor(last: page.map(\.activity))
        if appending {
            activity = FeedPaging.appending(rows.map(\.activity), to: activity)
            paging = Paging(cursor: pageCursor ?? paging?.cursor, hasMore: FeedPaging.hasMore(pageCount: page.count, limit: limit))
        } else {
            activity = rows.map(\.activity)
            paging = Paging(cursor: pageCursor, hasMore: FeedPaging.hasMore(pageCount: page.count, limit: limit))
        }
    }

    /// Første side hentet på nytt, med eldre sider som alt var hentet (`FeedPaging.refreshed`).
    mutating func keepOlderPages(from previous: Self, limit: Int) {
        guard let paging, let old = previous.paging, paging.hasMore else { return }
        let merged = FeedPaging.refreshed(first: activity, limit: 1, existing: previous.activity)
        let kept = merged.filter { row in !activity.contains(where: { $0.id == row.id }) }
        guard !kept.isEmpty else { return }
        activity = merged
        for row in kept {
            if let s = previous.social[row.id] { social[row.id] = s }
            if let roundID = row.roundID, roundLabels[roundID] == nil { roundLabels[roundID] = previous.roundLabels[roundID] }
        }
        self.paging = old
    }
}
