import Foundation
import Observation
import Supabase

/// Din egen profil: henter den (laget ved første kall, `ensure_profile`) og lagrer navn, handicap og
/// NGF-nummer. Lagringen ber om raden tilbake og sjekker den, så vi vet at RLS slapp den gjennom.
@Observable
final class OwnProfileModel {
    private(set) var row: OwnProfileRow?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var error: OwnProfileError?

    let client: SupabaseClient?
    let userID: UUID

    init(client: SupabaseClient?, userID: UUID) {
        self.client = client
        self.userID = userID
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview row: OwnProfileRow) {
        client = nil
        userID = row.id
        self.row = row
    }
    #endif

    func load() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            row = try await OwnProfileQueries.ensure(client: client)
        } catch {
            self.error = Self.profileError(from: error)
        }
    }

    /// Lagrer skjemaet. Returnerer raden fra serveren når den er lagret og stemmer.
    func save(_ draft: OwnProfileDraft) async -> OwnProfileRow? {
        guard let client else { return nil }
        let change: OwnProfileChange
        switch draft.validate() {
        case .success(let valid): change = valid
        case .failure(let failure):
            error = failure
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let returned: [OwnProfileRow] = try await client
                .from("profiles")
                .update(change.patch)
                .eq("id", value: userID)
                .select(OwnProfileRow.columns)
                .execute()
                .value
            switch OwnProfile.verify(returned: returned, userID: userID, change: change) {
            case .success(let saved):
                row = saved
                return saved
            case .failure(let failure):
                error = failure
                return nil
            }
        } catch {
            self.error = Self.profileError(from: error)
            return nil
        }
    }

    private static func profileError(from error: any Error) -> OwnProfileError {
        if let postgrest = error as? PostgrestError {
            return OwnProfileError.from(sqlState: postgrest.code, message: postgrest.message)
        }
        return .other(DataError.from(error))
    }
}

/// Nettverket for egen profil.
enum OwnProfileQueries {
    /// Profilen din, laget eller fylt fra klubben ved første kall (`ensure_profile`, 017).
    static func ensure(client: SupabaseClient) async throws -> OwnProfileRow {
        try await client.rpc("ensure_profile").execute().value
    }

    /// Navnet Apple ga ved første innlogging, lagret når profilen ikke har navn
    /// (`AppleName.nameToSave`). Filteret `display_name is null` gjør at et navn som er satt i
    /// mellomtiden, står. Etter beste evne: feiler det, ber Deg og Spill om navnet i stedet.
    static func fillMissingName(client: SupabaseClient, userID: UUID, appleName: String?) async {
        guard appleName != nil,
              let profile = try? await ensure(client: client),
              let name = AppleName.nameToSave(apple: appleName, existing: profile.displayName) else { return }
        struct NamePatch: Encodable {
            let displayName: String
            enum CodingKeys: String, CodingKey { case displayName = "display_name" }
        }
        _ = try? await client
            .from("profiles")
            .update(NamePatch(displayName: name))
            .eq("id", value: userID)
            .is("display_name", value: nil)
            .execute()
    }
}
