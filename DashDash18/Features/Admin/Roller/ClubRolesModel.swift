import Foundation
import Observation
import Supabase

/// Rollene i klubben (sql/044): lister roller og hvem som har dem, og skriver gjennom RPC-ene
/// `club_role_save`, `club_role_delete`, `club_member_set_roles` og `club_transfer_ownership`.
/// Finnes ikke tabellene (044 ikke kjørt) eller klubben har ingen roller, er `isAvailable` false,
/// og troppen viser bryterne for arrangør og kasserer som før.
@Observable
final class ClubRolesModel {
    private(set) var roles: [ClubRoleRow] = []
    private(set) var assignments: [ClubMemberRoleRow] = []
    private(set) var hasLoaded = false
    private(set) var isSaving = false
    var error: String?

    let context: ClubContext
    /// Kalles etter hver endring, så rettighetene i appen (Arrangør-fanen) følger med.
    var onChange: () async -> Void = {}

    init(context: ClubContext) {
        self.context = context
    }

    var isAvailable: Bool { !roles.isEmpty }

    /// Det du har, slik det står nå (hentet her, ikke fra oppstarten).
    var viewer: ClubRights {
        ClubRights(roles: roles.filter { roleIDs(of: context.memberID).contains($0.id) })
    }

    func roleIDs(of member: UUID) -> Set<UUID> {
        Set(assignments.filter { $0.memberID == member }.map(\.roleID))
    }

    func roles(of member: UUID) -> [ClubRoleRow] {
        let ids = roleIDs(of: member)
        return roles.filter { ids.contains($0.id) }
    }

    func memberCount(of role: UUID) -> Int {
        assignments.count { $0.roleID == role }
    }

    func isOwner(_ member: UUID) -> Bool {
        roles(of: member).contains(where: \.isOwner)
    }

    // MARK: Lesing

    func load() async {
        do {
            async let roles: [ClubRoleRow] = context.client
                .from("club_roles")
                .select(ClubRoleRow.columns)
                .eq("club_id", value: context.clubID)
                .execute()
                .value
            async let assignments: [ClubMemberRoleRow] = context.client
                .from("club_member_roles")
                .select(ClubMemberRoleRow.columns)
                .eq("club_id", value: context.clubID)
                .execute()
                .value
            self.roles = ClubRoleOrder.sorted(try await roles)
            self.assignments = try await assignments
        } catch {
            // 044 ikke kjørt (tabellen finnes ikke) eller uten nett: ingen roller å vise.
            roles = []
            assignments = []
        }
        hasLoaded = true
    }

    // MARK: Skriving

    /// Lager (`id` nil) eller endrer en rolle. Eierens rettigheter sendes ikke (de står fast).
    func save(id: UUID?, name: String, rights: Set<ClubRight>) async -> Bool {
        let valid: String
        switch ClubRoleInput.validate(name: name, roles: roles, editing: id) {
        case .success(let name): valid = name
        case .failure(let failure):
            error = failure.message
            return false
        }
        let isOwnerRole = id.flatMap { id in roles.first { $0.id == id } }?.isOwner ?? false
        // Null sendes som null (ikke utelatt), ellers finner ikke PostgREST funksjonen.
        struct Params: Encodable {
            let p_club_id: UUID
            let p_role_id: UUID?
            let p_name: String
            let p_rights: [String]?

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_club_id, forKey: .p_club_id)
                try c.encode(p_role_id, forKey: .p_role_id)
                try c.encode(p_name, forKey: .p_name)
                try c.encode(p_rights, forKey: .p_rights)
            }

            enum CodingKeys: String, CodingKey { case p_club_id, p_role_id, p_name, p_rights }
        }
        let params = Params(p_club_id: context.clubID, p_role_id: id, p_name: valid,
                            p_rights: isOwnerRole ? nil : ClubRoleInput.rightsParameter(rights))
        return await write {
            let _: ClubRoleRow = try await self.context.client.rpc("club_role_save", params: params).execute().value
        }
    }

    func delete(_ role: ClubRoleRow) async -> Bool {
        struct Params: Encodable { let p_role_id: UUID }
        return await write {
            try await self.context.client.rpc("club_role_delete", params: Params(p_role_id: role.id)).execute()
        }
    }

    func setRoles(_ ids: Set<UUID>, for member: UUID) async -> Bool {
        struct Params: Encodable {
            let p_member_id: UUID
            let p_role_ids: [UUID]
        }
        let params = Params(p_member_id: member, p_role_ids: Array(ids))
        return await write {
            let _: [UUID] = try await self.context.client.rpc("club_member_set_roles", params: params).execute().value
        }
    }

    func transferOwnership(to member: UUID) async -> Bool {
        struct Params: Encodable {
            let p_club_id: UUID
            let p_to_member: UUID
        }
        let params = Params(p_club_id: context.clubID, p_to_member: member)
        return await write {
            try await self.context.client.rpc("club_transfer_ownership", params: params).execute()
        }
    }

    /// Kjører skrivingen, henter rollene på nytt og sier fra til resten av appen.
    private func write(_ body: () async throws -> Void) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await body()
            error = nil
        } catch {
            self.error = DataError.from(error).message
            await load()
            return false
        }
        await load()
        await onChange()
        return true
    }
}
