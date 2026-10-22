import Foundation
import Observation
import Supabase

/// Hvilken klubb den innloggede er med i, og handlingene for å lage eller bli med i en.
@Observable
final class ClubModel {
    private(set) var state: ClubState = .loading
    private(set) var memberships: [Membership] = []
    /// En henting pågår (så retur fra bakgrunnen eller «Prøv igjen» ikke starter en til).
    var isRefreshing: Bool { loadsInFlight > 0 }
    /// Oppstarten venter på et nytt forsøk fordi den ikke fikk kontakt.
    private(set) var isWaitingForNetwork = false
    /// Rollene per klubb (sql/044). Tom når 044 ikke er kjørt: da gjelder flaggene.
    private(set) var roleAccess: [UUID: ClubRoleAccess] = [:]
    private var loadsInFlight = 0
    private let cache: MembershipCache
    private let fetchRows: @Sendable (UUID) async throws -> [Membership]
    private let network: any NetworkMonitoring
    private let clock: any OutboxClock
    /// Ventetidene før nye forsøk (1, 2 og 4 sekunder med `maxRetries` 3).
    private let backoff: OutboxBackoff
    private let maxRetries: Int
    /// Hvor lenge ett forsøk får holde på. Uten grense venter URLSession 60 sekunder per forsøk.
    private let attemptTimeout: Duration
    private let client: SupabaseClient
    private static let rememberedKey = "valgtKlubb"

    init(client: SupabaseClient, cache: MembershipCache = MembershipCache(),
         network: any NetworkMonitoring = PathNetworkMonitor(), clock: any OutboxClock = SystemOutboxClock(),
         backoff: OutboxBackoff = OutboxBackoff(), maxRetries: Int = 3, attemptTimeout: Duration = .seconds(10),
         fetchRows: (@Sendable (UUID) async throws -> [Membership])? = nil) {
        self.client = client
        self.cache = cache
        self.network = network
        self.clock = clock
        self.backoff = backoff
        self.maxRetries = maxRetries
        self.attemptTimeout = attemptTimeout
        self.fetchRows = fetchRows ?? { userID in
            try await client
                .from("club_members")
                .select(Membership.selectColumns)
                .eq("user_id", value: userID)
                // En deltaker i en turnering (sql/059) er ikke med i klubben.
                .eq("kind", value: MemberKind.member.rawValue)
                .execute()
                .value
        }
    }

    var current: Membership? {
        switch state {
        case .active(let membership), .pending(let membership): membership
        default: nil
        }
    }

    /// Henter medlemskapene. Ved oppstart vises det sist kjente med en gang (uten nett eller
    /// med treg dekning), og byttes når svaret kommer. Feiler hentingen mens noe vises,
    /// blir det stående: da kastes ingen ut av en runde eller et halvferdig skjema.
    /// Avbrytes hentingen (utlogging), røres ikke tilstanden.
    /// Returnerer feilen, så «Sjekk igjen» kan si fra.
    @discardableResult
    func load(userID: UUID) async -> ClubError? {
        if state == .loading, let cached = cache.load(userID: userID) {
            apply(cached)
        }
        loadsInFlight += 1
        defer { loadsInFlight -= 1 }
        do {
            let rows = try await fetchMemberships(userID: userID)
            try Task.checkCancellation()
            cache.save(rows, userID: userID)
            apply(rows)
            await loadRoleAccess()
            return nil
        } catch {
            if error is CancellationError || Task.isCancelled { return nil }
            let failure = Self.clubError(from: error)
            switch state {
            case .loading, .failed: state = .failed(failure)
            case .noClub, .pending, .active: break
            }
            return failure
        }
    }

    /// Henter medlemskapene. Hvert forsøk får `attemptTimeout`. Uten noe å vise (første oppstart,
    /// ingen lagret kopi) prøves en nettverksfeil på nytt etter `backoff`, så et kort brudd i
    /// dekningen ikke gir feilskjermen.
    private func fetchMemberships(userID: UUID) async throws -> [Membership] {
        let fetchRows = fetchRows
        var attempt = 0
        while true {
            do {
                return try await Self.withTimeout(attemptTimeout) { try await fetchRows(userID) }
            } catch {
                guard Self.shouldRetry(error, attempt: attempt, retries: maxRetries, state: state) else { throw error }
                attempt += 1
                isWaitingForNetwork = true
                defer { isWaitingForNetwork = false }
                try await clock.sleep(for: backoff.delay(afterFailures: attempt))
            }
        }
    }

    /// Kaster `URLError(.timedOut)` når `operation` bruker lenger enn `limit`.
    private nonisolated static func withTimeout<T: Sendable>(
        _ limit: Duration, _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Nytt forsøk bare for nettverksfeil (ikke avbrutt), bare ved første oppstart (ingenting
    /// vises, ingen feilskjerm ennå), og bare `retries` ganger.
    nonisolated static func shouldRetry(_ error: any Error, attempt: Int, retries: Int, state: ClubState) -> Bool {
        guard attempt < retries, let urlError = error as? URLError, urlError.code != .cancelled else { return false }
        return state == .loading
    }

    /// Når appen kommer tilbake fra bakgrunnen, og fra «Prøv igjen»: ny rolle (arrangør),
    /// godkjenning eller arkivering slår inn uten omstart. Pågår en henting, startes ingen ny.
    func refresh(userID: UUID) async {
        guard !isRefreshing else { return }
        await load(userID: userID)
    }

    /// Mens feilskjermen vises: henter på nytt når nettet kommer tilbake etter å ha vært borte,
    /// og bare når feilen var manglende nett. Første verdi (slik nettet er nå) utløser ingenting.
    func reloadWhenOnline(userID: UUID) async {
        var wasOnline: Bool?
        for await online in network.availability() {
            defer { wasOnline = online }
            guard online, wasOnline == false, case .failed(.offline) = state else { continue }
            await refresh(userID: userID)
        }
    }

    /// Rollene og hvilke du har, i klubbene du er aktiv i. Feiler det (044 ikke kjørt, uten nett),
    /// blir det som var: uten roller gjelder flaggene.
    func loadRoleAccess() async {
        let active = memberships.filter { $0.status == .active }
        guard !active.isEmpty else {
            roleAccess = [:]
            return
        }
        do {
            async let roles: [ClubRoleRow] = client
                .from("club_roles")
                .select(ClubRoleRow.columns)
                .in("club_id", values: active.map(\.clubID.uuidString))
                .execute()
                .value
            async let mine: [ClubMemberRoleRow] = client
                .from("club_member_roles")
                .select(ClubMemberRoleRow.columns)
                .in("member_id", values: active.map(\.id.uuidString))
                .execute()
                .value
            let next = ClubRoleAccess.byClub(roles: try await roles, mine: try await mine,
                                             memberIDs: Set(active.map(\.id)))
            if next != roleAccess { roleAccess = next }
        } catch {
            // Beholder det som var.
        }
    }

    func select(_ membership: Membership) {
        select(clubID: membership.clubID)
    }

    /// Bytt til klubben (en invitasjon fra en lenke). Er den ikke aktiv ennå, blir du stående der du er.
    func select(clubID: UUID) {
        UserDefaults.standard.set(clubID.uuidString, forKey: Self.rememberedKey)
        apply(memberships)
    }

    /// Etter «Bli med» i en klubb du er med i fra før (lenke eller Deg): aktiv → bytt til klubben,
    /// venter → bli der du er. Svarer med teksten som sier hva som skjedde.
    func finishJoin(clubID: UUID, clubName: String, status: MemberStatus) -> String {
        if status == .active { select(clubID: clubID) }
        return ClubInviteFlow.joinedText(clubName: clubName, status: status)
    }

    /// Ved utlogging. Det lagrede medlemskapet slettes også.
    func reset() {
        state = .loading
        memberships = []
        roleAccess = [:]
        cache.clear()
    }

    func createClub(name: String, displayName: String, handicapIndex: Double?, userID: UUID) async throws(ClubError) {
        struct Params: Encodable {
            let p_name: String
            let p_display_name: String
            let p_handicap_index: Double?
        }
        do {
            let clubID: UUID = try await client
                .rpc("create_club", params: Params(p_name: name, p_display_name: displayName, p_handicap_index: handicapIndex))
                .execute()
                .value
            UserDefaults.standard.set(clubID.uuidString, forKey: Self.rememberedKey)
        } catch {
            throw Self.clubError(from: error)
        }
        await load(userID: userID)
    }

    func preview(code: String) async throws(ClubError) -> ClubPreview {
        struct Params: Encodable { let p_join_code: String }
        do {
            let preview: ClubPreview? = try await client
                .rpc("club_preview", params: Params(p_join_code: code))
                .execute()
                .value
            guard let preview else { throw ClubError.notFound }
            return preview
        } catch let error as ClubError {
            throw error
        } catch {
            throw Self.clubError(from: error)
        }
    }

    /// Ta et ledig navn (`memberID`) eller be om å bli med som ny (`displayName`). Svarer med
    /// statusen du fikk: aktiv (ledig navn) eller venter (ny, arrangøren må godkjenne).
    @discardableResult
    func join(code: String, memberID: UUID?, displayName: String?, handicapIndex: Double?,
              userID: UUID) async throws(ClubError) -> MemberStatus {
        struct Params: Encodable {
            let p_join_code: String
            let p_member_id: UUID?
            let p_display_name: String?
            let p_handicap_index: Double?
        }
        let result: JoinResult
        do {
            // Svaret dekodes for å sjekke at serveren ga et medlemskap tilbake.
            result = try await client
                .rpc("join_club", params: Params(
                    p_join_code: code,
                    p_member_id: memberID,
                    p_display_name: displayName,
                    p_handicap_index: handicapIndex
                ))
                .execute()
                .value
        } catch {
            throw Self.clubError(from: error)
        }
        await load(userID: userID)
        return result.status
    }

    /// Gå ut av klubben, eller trekk forespørselen (`leave_club`, sql/069). Klubben forsvinner med en
    /// gang, og appen viser neste aktive klubb, en som venter, eller klubbvalget. Så hentes
    /// medlemskapene på nytt.
    func leave(clubID: UUID, userID: UUID) async throws(ClubError) {
        struct Params: Encodable { let p_club_id: UUID }
        do {
            try await client.rpc("leave_club", params: Params(p_club_id: clubID)).execute()
        } catch {
            if let postgrest = error as? PostgrestError {
                throw LeaveClub.error(sqlState: postgrest.code, message: postgrest.message)
            }
            throw Self.clubError(from: error)
        }
        let remembered = UserDefaults.standard.string(forKey: Self.rememberedKey).flatMap(UUID.init(uuidString:))
        if LeaveClub.remembered(remembered, afterLeaving: clubID) == nil {
            UserDefaults.standard.removeObject(forKey: Self.rememberedKey)
        }
        let remaining = LeaveClub.remaining(memberships, afterLeaving: clubID)
        cache.save(remaining, userID: userID)
        apply(remaining)
        await load(userID: userID)
    }

    private func apply(_ rows: [Membership]) {
        if memberships != rows { memberships = rows }
        let remembered = UserDefaults.standard.string(forKey: Self.rememberedKey).flatMap(UUID.init(uuidString:))
        let next = Membership.state(for: rows, remembered: remembered)
        // Samme svar som før: ikke tegn appen på nytt.
        if next != state { state = next }
    }

    private static func clubError(from error: any Error) -> ClubError {
        if let postgrest = error as? PostgrestError {
            return ClubError.from(sqlState: postgrest.code, message: postgrest.message)
        }
        if error is URLError {
            return .offline
        }
        return .unknown(error.localizedDescription)
    }
}
