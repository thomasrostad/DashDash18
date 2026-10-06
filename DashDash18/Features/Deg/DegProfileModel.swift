import Foundation
import Observation
import Supabase

/// Egen rad i troppen: henter navn og handicap, og lagrer endringer.
/// Lagringen ber om raden tilbake og sjekker den, så vi vet at RLS slapp den gjennom.
@Observable
final class DegProfileModel {
    private(set) var row: ClubMemberRow?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var error: DegProfileError?

    let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [ClubMemberRow] = try await context.client
                .from("club_members")
                .select(DegProfile.columns)
                .eq("id", value: context.memberID)
                .eq("club_id", value: context.clubID)
                .execute()
                .value
            guard let own = rows.first else {
                error = .notSaved
                return
            }
            row = own
        } catch {
            self.error = Self.profileError(from: error)
        }
    }

    /// Lagrer skjemaet. Returnerer raden fra serveren når den er lagret og stemmer.
    func save(_ draft: DegProfileDraft) async -> ClubMemberRow? {
        let change: DegProfileChange
        switch draft.validate() {
        case .success(let valid): change = valid
        case .failure(let failure):
            error = failure
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let returned: [ClubMemberRow] = try await context.client
                .from("club_members")
                .update(change.patch)
                .eq("id", value: context.memberID)
                .eq("club_id", value: context.clubID)
                .select(DegProfile.columns)
                .execute()
                .value
            switch DegProfile.verify(returned: returned, memberID: context.memberID, change: change) {
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

    private static func profileError(from error: any Error) -> DegProfileError {
        if let postgrest = error as? PostgrestError {
            return DegProfileError.from(sqlState: postgrest.code, message: postgrest.message)
        }
        return .other(DataError.from(error))
    }
}
