import Foundation
import Supabase
import Synchronization

/// Følge andre spillere (sql/054). Før 054 er kjørt finnes ikke funksjonene: appen spør én gang
/// per innlogging (`detect`) og husker svaret. Uten 054 er alt om følging skjult.
nonisolated enum FollowFeature {
    private static let key = "follow054"
    private static let state = Mutex<Bool>(UserDefaults.standard.bool(forKey: key))

    /// Funksjonene fra 054 finnes (sist appen sjekket).
    static var isAvailable: Bool { state.withLock { $0 } }

    static func set(_ available: Bool) {
        state.withLock { $0 = available }
        UserDefaults.standard.set(available, forKey: key)
    }

    /// Spør databasen om `my_follows` finnes. En annen feil (nettet borte) endrer ingenting.
    @discardableResult
    static func detect(client: SupabaseClient) async -> Bool {
        do {
            _ = try await client.rpc("my_follows").limit(1).execute()
            set(true)
        } catch where FollowService.isMissing(error) {
            set(false)
        } catch {
            // Behold det vi visste.
        }
        return isAvailable
    }
}

/// Kallene for følging (sql/054). Alle skrivinger går gjennom RPC-ene.
nonisolated struct FollowService: Sendable {
    let client: SupabaseClient

    /// Mangler 054 (ukjent funksjon, tabell eller kolonne)?
    static func isMissing(_ error: any Error) -> Bool {
        guard let postgrest = error as? PostgrestError else { return false }
        return EveningSignupService.isMissing(postgrest) || postgrest.code == "PGRST205"
    }

    /// Norsk tekst for feilen, med grensene fra 054.
    static func message(_ error: any Error) -> String {
        FollowError.message(DataError.from(error), code: (error as? PostgrestError)?.code)
    }

    // MARK: Lister og innstillinger

    func myFollows() async throws -> [FollowRow] {
        try await client.rpc("my_follows").execute().value
    }

    struct Settings: Codable, Equatable, Sendable {
        var followApproval: Bool
        var searchable: Bool

        enum CodingKeys: String, CodingKey {
            case followApproval = "follow_approval"
            case searchable
        }
    }

    /// Mine innstillinger (egen profilrad).
    func settings(userID: UUID) async throws -> Settings? {
        let rows: [Settings] = try await client.from("profiles")
            .select("follow_approval, searchable")
            .eq("id", value: userID)
            .limit(1)
            .execute().value
        return rows.first
    }

    /// `follow_settings`: nil = uendret. Svarer begge.
    func setSettings(approval: Bool? = nil, searchable: Bool? = nil) async throws -> Settings {
        struct Params: Encodable {
            let p_approval: Bool?
            let p_searchable: Bool?
        }
        return try await client.rpc("follow_settings", params: Params(p_approval: approval, p_searchable: searchable))
            .execute().value
    }

    // MARK: Følge

    /// `follow_request`: svarer `pending` eller `accepted`.
    func request(_ profileID: UUID, source: FollowSource) async throws -> FollowStatus {
        struct Params: Encodable {
            let p_profile_id: UUID
            let p_source: String
        }
        let answer: String = try await client.rpc("follow_request", params: Params(p_profile_id: profileID,
                                                                                 p_source: source.rawValue))
            .execute().value
        return FollowButton.after(.request, answer: answer)
    }

    /// Godta (true) eller avslå (false) en forespørsel.
    func respond(to followerID: UUID, accept: Bool) async throws {
        struct Params: Encodable {
            let p_follower_id: UUID
            let p_accept: Bool
        }
        _ = try await client.rpc("follow_respond", params: Params(p_follower_id: followerID, p_accept: accept)).execute()
    }

    private struct ProfileParams: Encodable { let p_profile_id: UUID }

    /// Slutt å følge, eller trekk forespørselen.
    func remove(_ profileID: UUID) async throws {
        _ = try await client.rpc("follow_remove", params: ProfileParams(p_profile_id: profileID)).execute()
    }

    /// Fjern en følger (eller en forespørsel).
    func removeFollower(_ profileID: UUID) async throws {
        _ = try await client.rpc("follower_remove", params: ProfileParams(p_profile_id: profileID)).execute()
    }

    // MARK: Koden

    /// Min kode. `renew` gir ny, og den gamle virker ikke lenger.
    func code(renew: Bool = false) async throws -> FollowLink? {
        struct Params: Encodable { let p_renew: Bool }
        let code: String = try await client.rpc("follow_code", params: Params(p_renew: renew)).execute().value
        return FollowLink(code: code)
    }

    /// Følg eieren av koden med en gang (`qr` fra skanneren, `link` fra en lenke).
    func follow(_ link: FollowLink, source: FollowSource) async throws -> FollowByCodeResult {
        struct Params: Encodable {
            let p_code: String
            let p_source: String
        }
        return try await client.rpc("follow_by_code", params: Params(p_code: link.code, p_source: source.rawValue))
            .execute().value
    }

    // MARK: Søk

    func search(_ query: String, limit: Int = 20) async throws -> [PersonSearchRow] {
        struct Params: Encodable {
            let p_query: String
            let p_limit: Int
        }
        return try await client.rpc("search_people", params: Params(p_query: query, p_limit: limit)).execute().value
    }

    // MARK: «Følger»-fanen

    func feedPage(before: FeedCursor?, limit: Int = FollowingFeedPages.pageSize) async throws -> [FollowingCard] {
        struct Params: Encodable {
            let p_before_ts: String?
            let p_before_id: UUID?
            let p_limit: Int
        }
        return try await client.rpc("following_feed_page", params: Params(p_before_ts: before?.timestamp,
                                                                          p_before_id: before?.id, p_limit: limit))
            .execute().value
    }

    // MARK: Varsler

    /// Personlige linjer til meg (følging og kommentarer på kort), nyeste først. RLS viser bare
    /// dem du er aktør eller mottaker på (og kortene til dem du følger, som filtreres bort her).
    func notifications(limit: Int = 50) async throws -> [PersonalActivity] {
        try await client.from("activity")
            .select(PersonalActivity.columns)
            .is("club_id", value: nil)
            .is("competition_id", value: nil)
            .not("actor_profile_id", operator: .is, value: "null")
            .in("kind", values: PersonalActivity.notificationKinds)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    // MARK: Profiler

    /// Profilene du kan se (`known_profiles`), til navnene i kommentarene.
    func knownNames(userID: UUID) async -> [UUID: String] {
        let rows = (try? await LooseRoundQueries.friends(client: client, userID: userID)) ?? []
        return Dictionary(rows.compactMap { r in followTrimmed(r.displayName).map { (r.id, $0) } },
                          uniquingKeysWith: { a, _ in a })
    }

    /// Dem du følger (godtatt), eller tomt uten 054.
    func followingIDs(userID: UUID) async -> Set<UUID> {
        struct Row: Decodable {
            let followeeID: UUID
            enum CodingKeys: String, CodingKey { case followeeID = "followee_id" }
        }
        let rows: [Row] = (try? await client.from("follows")
            .select("followee_id")
            .eq("follower_id", value: userID)
            .eq("status", value: "accepted")
            .execute().value) ?? []
        return Set(rows.map(\.followeeID))
    }

    /// Innloggingen bak klubbmedlemmene (for «Følg» etter en klubbrunde).
    func users(forMembers ids: [UUID]) async -> [UUID: UUID] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable {
            let id: UUID
            let userID: UUID?
            enum CodingKeys: String, CodingKey {
                case id
                case userID = "user_id"
            }
        }
        let rows: [Row] = (try? await client.from("club_members")
            .select("id, user_id")
            .in("id", values: ids.map(\.uuidString))
            .execute().value) ?? []
        return Dictionary(rows.compactMap { r in r.userID.map { (r.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }
}
