import Foundation
import Observation
import Supabase

/// «Hva blir push» for arrangøren: leser og skriver `clubs.push_disabled_categories`
/// (policyen `clubs_update` krever arrangør). Hver skriving ber om raden tilbake.
@Observable
final class ClubPushSettingsModel {
    private(set) var disabled: [String] = []
    private(set) var hasLoaded = false
    private(set) var isSaving = false
    var error: String?

    let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    func isOn(_ key: String) -> Bool {
        ClubPushPlan.isOn(key, disabled: disabled)
    }

    func load() async {
        do {
            let rows: [ClubPushRow] = try await context.client
                .from("clubs")
                .select("push_disabled_categories")
                .eq("id", value: context.clubID)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { throw DataError.notAllowed }
            disabled = row.disabledCategories
            hasLoaded = true
            error = nil
        } catch {
            self.error = DataError.from(error).message
        }
    }

    /// Viser valget med en gang, og ruller tilbake hvis databasen sier nei.
    func set(_ key: String, on: Bool) async {
        guard !isSaving else { return }
        let before = disabled
        let next = ClubPushPlan.setting(key, on: on, in: before)
        disabled = next
        isSaving = true
        defer { isSaving = false }
        do {
            let rows: [ClubPushRow] = try await context.client
                .from("clubs")
                .update(ClubPushRow(disabledCategories: next))
                .eq("id", value: context.clubID)
                .select("push_disabled_categories")
                .execute()
                .value
            guard let row = rows.first, ClubPushPlan.matches(row.disabledCategories, next) else {
                throw DataError.notAllowed
            }
            disabled = row.disabledCategories
            error = nil
        } catch {
            disabled = before
            self.error = "Klarte ikke å lagre: \(DataError.from(error).message)"
        }
    }
}

/// «Hvem har push»: `push_status` (bare arrangøren) slått sammen med navnene i troppen.
@Observable
final class PushStatusModel {
    private(set) var sections: PushStatusSections?
    private(set) var isLoading = false
    var error: String?

    let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    func load() async {
        struct Params: Encodable { let p_club_id: UUID }
        isLoading = true
        defer { isLoading = false }
        do {
            let status: [PushStatusRow] = try await context.client
                .rpc("push_status", params: Params(p_club_id: context.clubID))
                .execute()
                .value
            let names: [PushMemberName] = try await context.client
                .from("club_members")
                .select("id, display_name")
                .eq("club_id", value: context.clubID)
                .execute()
                .value
            sections = PushStatusSections(status: status, names: names)
            error = nil
        } catch {
            self.error = DataError.from(error).message
        }
    }
}
