import Foundation
import Observation
import Supabase

enum ClubState: Equatable {
    case loading
    /// Innlogget, men ikke med i noen klubb ennå.
    case noClub
    case pending(Membership)
    case active(Membership)
    case failed(ClubError)
}

/// Hvilken klubb den innloggede er med i, og handlingene for å lage eller bli med i en.
@Observable
final class ClubModel {
    private(set) var state: ClubState = .loading
    private(set) var memberships: [Membership] = []
    private let client: SupabaseClient
    private static let rememberedKey = "valgtKlubb"

    init(client: SupabaseClient) {
        self.client = client
    }

    var current: Membership? {
        switch state {
        case .active(let membership), .pending(let membership): membership
        default: nil
        }
    }

    func load(userID: UUID) async {
        do {
            let rows: [Membership] = try await client
                .from("club_members")
                .select(Membership.selectColumns)
                .eq("user_id", value: userID)
                .execute()
                .value
            apply(rows)
        } catch {
            state = .failed(Self.clubError(from: error))
        }
    }

    func select(_ membership: Membership) {
        UserDefaults.standard.set(membership.clubID.uuidString, forKey: Self.rememberedKey)
        apply(memberships)
    }

    func reset() {
        state = .loading
        memberships = []
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
            let result: JoinResult = try await client
                .rpc("join_club", params: Params(
                    p_join_code: code,
                    p_member_id: memberID,
                    p_display_name: displayName,
                    p_handicap_index: handicapIndex
                ))
                .execute()
                .value
            _ = result
        } catch {
            throw Self.clubError(from: error)
        }
        await load(userID: userID)
    }

    private func apply(_ rows: [Membership]) {
        memberships = rows
        let remembered = UserDefaults.standard.string(forKey: Self.rememberedKey).flatMap(UUID.init(uuidString:))
        guard let chosen = Membership.choose(from: rows, remembered: remembered) else {
            state = .noClub
            return
        }
        state = chosen.status == .active ? .active(chosen) : .pending(chosen)
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
