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
    private let client: SupabaseClient
    private let cache: MembershipCache
    private static let rememberedKey = "valgtKlubb"

    init(client: SupabaseClient, cache: MembershipCache = MembershipCache()) {
        self.client = client
        self.cache = cache
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
            let rows: [Membership] = try await client
                .from("club_members")
                .select(Membership.selectColumns)
                .eq("user_id", value: userID)
                .execute()
                .value
            cache.save(rows, userID: userID)
            apply(rows)
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

    /// Når appen kommer tilbake fra bakgrunnen: ny rolle (arrangør), godkjenning eller
    /// arkivering slår inn uten omstart.
    func refresh(userID: UUID) async {
        guard !isRefreshing else { return }
        await load(userID: userID)
    }

    func select(_ membership: Membership) {
        UserDefaults.standard.set(membership.clubID.uuidString, forKey: Self.rememberedKey)
        apply(memberships)
    }

    /// Ved utlogging. Det lagrede medlemskapet slettes også.
    func reset() {
        state = .loading
        memberships = []
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

    /// Ta et ledig navn (`memberID`) eller be om å bli med som ny (`displayName`).
    func join(code: String, memberID: UUID?, displayName: String?, handicapIndex: Double?, userID: UUID) async throws(ClubError) {
        struct Params: Encodable {
            let p_join_code: String
            let p_member_id: UUID?
            let p_display_name: String?
            let p_handicap_index: Double?
        }
        do {
            // Svaret dekodes for å sjekke at serveren ga et medlemskap tilbake.
            let _: JoinResult = try await client
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
