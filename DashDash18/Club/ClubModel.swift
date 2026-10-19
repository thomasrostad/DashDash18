import Foundation
import Observation
import Supabase

/// Hvilken klubb den innloggede er med i, og handlingene for å lage eller bli med i en.
@Observable
final class ClubModel {
    private(set) var state: ClubState = .loading
    private(set) var memberships: [Membership] = []
    /// En henting pågår (så retur fra bakgrunnen ikke starter en til).
    private(set) var isRefreshing = false
    /// Rollene per klubb (sql/044). Tom når 044 ikke er kjørt: da gjelder flaggene.
    private(set) var roleAccess: [UUID: ClubRoleAccess] = [:]
    private let client: SupabaseClient
    private let cache: MembershipCache
    /// Ventetidene før nye forsøk når oppstarten ikke får kontakt (1, 2 og 4 sekunder).
    private let retryDelays: [Duration]
    private static let rememberedKey = "valgtKlubb"

    init(client: SupabaseClient, cache: MembershipCache = MembershipCache(),
         retryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]) {
        self.client = client
        self.cache = cache
        self.retryDelays = retryDelays
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
    /// Returnerer feilen, så «Sjekk igjen» kan si fra.
    @discardableResult
    func load(userID: UUID) async -> ClubError? {
        if state == .loading, let cached = cache.load(userID: userID) {
            apply(cached)
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let rows = try await fetchMemberships(userID: userID)
            cache.save(rows, userID: userID)
            apply(rows)
            await loadRoleAccess()
            return nil
        } catch {
            let failure = Self.clubError(from: error)
            switch state {
            case .loading, .failed: state = .failed(failure)
            case .noClub, .pending, .active: break
            }
            return failure
        }
    }

    /// Henter medlemskapene. Uten noe å vise (første oppstart, ingen lagret kopi) prøves en
    /// nettverksfeil på nytt etter `retryDelays`, så et kort brudd i dekningen ikke gir feilskjermen.
    private func fetchMemberships(userID: UUID) async throws -> [Membership] {
        var attempt = 0
        while true {
            do {
                return try await client
                    .from("club_members")
                    .select(Membership.selectColumns)
                    .eq("user_id", value: userID)
                    .execute()
                    .value
            } catch {
                guard Self.shouldRetry(error, attempt: attempt, retries: retryDelays.count, state: state) else { throw error }
                try await Task.sleep(for: retryDelays[attempt])
                attempt += 1
            }
        }
    }

    /// Nytt forsøk bare for nettverksfeil (ikke avbrutt), bare mens ingenting vises, og bare
    /// så mange ganger som det finnes ventetider.
    nonisolated static func shouldRetry(_ error: any Error, attempt: Int, retries: Int, state: ClubState) -> Bool {
        guard attempt < retries, let urlError = error as? URLError, urlError.code != .cancelled else { return false }
        switch state {
        case .loading, .failed: return true
        case .noClub, .pending, .active: return false
        }
    }

    /// Når appen kommer tilbake fra bakgrunnen: ny rolle (arrangør), godkjenning eller
    /// arkivering slår inn uten omstart.
    func refresh(userID: UUID) async {
        guard !isRefreshing else { return }
        await load(userID: userID)
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
