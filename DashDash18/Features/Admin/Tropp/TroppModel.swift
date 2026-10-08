import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Troppen for arrangøren: henter spillerne og seedinggruppene, og skriver endringer.
/// Hver skriving ber om raden tilbake, så vi vet at RLS slapp den gjennom.
@Observable
final class TroppModel {
    private(set) var rows: [ClubMemberRow] = []
    private(set) var seedGroups: [SeedingGroup] = SeedingGroup.golfgutu
    private(set) var seasonName: String?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var busyIDs: Set<UUID> = []
    var error: TroppError?

    let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    var sections: TroppSections { TroppSections(rows) }

    func row(_ id: UUID) -> ClubMemberRow? {
        rows.first { $0.id == id }
    }

    func availability(_ action: TroppAction, for row: ClubMemberRow) -> TroppAvailability {
        TroppRules.availability(action, for: row, in: rows, me: context.memberID)
    }

    // MARK: Lesing

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            rows = try await context.client
                .from("club_members")
                .select(KveldQueries.memberColumns)
                .eq("club_id", value: context.clubID)
                .execute()
                .value
            hasLoaded = true
        } catch {
            self.error = Self.troppError(from: error)
        }
        await loadSeedGroups()
    }

    /// Gruppene fra aktiv sesong. Feiler oppslaget, brukes Golfgutu-gruppene.
    private func loadSeedGroups() async {
        do {
            let seasons: [SeasonRow] = try await context.client
                .from("seasons")
                .select("id, club_id, name, status, rules")
                .eq("club_id", value: context.clubID)
                .eq("status", value: SeasonStatus.active.rawValue)
                .limit(1)
                .execute()
                .value
            seedGroups = TroppSeeding.groups(activeSeason: seasons.first)
            seasonName = seasons.first?.name
        } catch {
            seedGroups = TroppSeeding.groups(activeSeason: nil)
            seasonName = nil
        }
    }

    // MARK: Skriving

    /// Legger til et ledig navn. Returnerer `true` når det er lagret.
    func add(name: String, handicap: String) async -> Bool {
        let value: TroppInputValue
        switch TroppInput.validate(name: name, handicap: handicap, rows: rows) {
        case .success(let valid): value = valid
        case .failure(let failure):
            error = failure
            return false
        }
        do {
            let row: ClubMemberRow = try await context.client
                .from("club_members")
                .insert(NewMember(clubID: context.clubID, displayName: value.name, handicapIndex: value.handicapIndex))
                .select(KveldQueries.memberColumns)
                .single()
                .execute()
                .value
            rows.append(row)
            return true
        } catch {
            self.error = Self.troppError(from: error)
            return false
        }
    }

    /// Lagrer navn og handicap. Returnerer `true` når det er lagret.
    func saveDetails(of id: UUID, name: String, handicap: String) async -> Bool {
        switch TroppInput.validate(name: name, handicap: handicap, rows: rows, editing: id) {
        case .success(let value):
            return await update(id, with: .details(value))
        case .failure(let failure):
            error = failure
            return false
        }
    }

    func perform(_ action: TroppAction, on id: UUID) async {
        guard let row = row(id) else { return }
        let availability = availability(action, for: row)
        guard availability.isAllowed else {
            if let reason = availability.reason { error = .invalid(reason) }
            return
        }
        switch action {
        case .approve: await update(id, with: .approve)
        case .reject: await update(id, with: .reject)
        case .grantOrganizer: await update(id, with: MemberPatch(isOrganizer: true))
        case .revokeOrganizer: await update(id, with: MemberPatch(isOrganizer: false))
        case .grantTreasurer: await update(id, with: MemberPatch(isTreasurer: true))
        case .revokeTreasurer: await update(id, with: MemberPatch(isTreasurer: false))
        case .releaseLogin: await update(id, with: .releaseLogin)
        case .archive: await update(id, with: .archive)
        case .restore: await update(id, with: .restore)
        case .delete: await delete(id)
        case .edit, .setSeedGroup: break
        }
    }

    func setSeedGroup(_ group: Int?, of id: UUID) async {
        guard let row = row(id), availability(.setSeedGroup, for: row).isAllowed, row.seedGroup != group else { return }
        await update(id, with: .seed(group))
    }

    func isBusy(_ id: UUID) -> Bool { busyIDs.contains(id) }

    @discardableResult
    private func update(_ id: UUID, with patch: MemberPatch) async -> Bool {
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            let updated: ClubMemberRow = try await context.client
                .from("club_members")
                .update(patch)
                .eq("id", value: id)
                .eq("club_id", value: context.clubID)
                .select(KveldQueries.memberColumns)
                .single()
                .execute()
                .value
            replace(updated)
            return true
        } catch {
            self.error = Self.troppError(from: error)
            return false
        }
    }

    private func delete(_ id: UUID) async {
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            let deleted: [ClubMemberRow] = try await context.client
                .from("club_members")
                .delete()
                .eq("id", value: id)
                .eq("club_id", value: context.clubID)
                .select(KveldQueries.memberColumns)
                .execute()
                .value
            guard deleted.contains(where: { $0.id == id }) else {
                error = .notSaved
                return
            }
            rows.removeAll { $0.id == id }
        } catch {
            self.error = Self.troppError(from: error)
        }
    }

    private func replace(_ row: ClubMemberRow) {
        if let index = rows.firstIndex(where: { $0.id == row.id }) {
            rows[index] = row
        } else {
            rows.append(row)
        }
    }

    private static func troppError(from error: any Error) -> TroppError {
        if let postgrest = error as? PostgrestError {
            return TroppError.from(sqlState: postgrest.code, message: postgrest.message)
        }
        return .other(DataError.from(error))
    }
}
