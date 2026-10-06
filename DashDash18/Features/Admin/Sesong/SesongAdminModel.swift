import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Sesongene i klubben og handlingene arrangøren gjør med dem. RLS slipper bare arrangører til å skrive;
/// hver skriving leser raden tilbake, så en skriving RLS stoppet blir en feil og ikke en stille glipp.
@Observable
final class SesongAdminModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(DataError)
    }

    private(set) var seasons: [SeasonRow] = []
    private(set) var loadState: LoadState = .loading
    private let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    private var table: PostgrestQueryBuilder { context.client.from("seasons") }

    func season(id: UUID) -> SeasonRow? {
        seasons.first { $0.id == id }
    }

    func load() async {
        do {
            seasons = try await table
                .select("id, club_id, name, status, rules")
                .eq("club_id", value: context.clubID)
                .order("created_at", ascending: false)
                .execute()
                .value
            loadState = .loaded
        } catch {
            loadState = .failed(DataError.from(error))
        }
    }

    @discardableResult
    func create(name: String, template: SeasonLifecycle.Template) async throws(DataError) -> SeasonRow {
        let payload = NewSeasonPayload(clubID: context.clubID, name: name, status: .planned,
                                       rules: SeasonLifecycle.rules(for: template, seasons: seasons))
        let row: SeasonRow = try await write {
            try await table.insert(payload).select().single().execute().value
        }
        seasons.insert(row, at: 0)
        return row
    }

    func rename(_ season: SeasonRow, to name: String) async throws(DataError) {
        try await update(season.id, SeasonNamePatch(name: name))
    }

    func saveRules(_ rules: Ruleset, for season: SeasonRow) async throws(DataError) {
        try await update(season.id, SeasonRulesPatch(rules: rules))
    }

    /// Aktiverer sesongen. Er en annen aktiv, avsluttes den først (`finishing`).
    /// To skrivinger etter hverandre; se `sql/004_sesong.sql` for en RPC som gjør det i én transaksjon.
    func activate(_ season: SeasonRow, finishing other: SeasonRow?) async throws(DataError) {
        if let other {
            try await update(other.id, SeasonStatusPatch(status: .finished))
        }
        do {
            try await update(season.id, SeasonStatusPatch(status: .active))
        } catch DataError.duplicate {
            throw .invalid("Klubben har allerede en aktiv sesong. Avslutt den først.")
        }
    }

    func finish(_ season: SeasonRow) async throws(DataError) {
        try await update(season.id, SeasonStatusPatch(status: .finished))
    }

    /// Sletter en planlagt sesong. Aktive og ferdige slettes ikke fra appen.
    func delete(_ season: SeasonRow) async throws(DataError) {
        guard season.status == .planned else {
            throw .invalid("Bare planlagte sesonger kan slettes.")
        }
        let deleted: [SeasonRow]
        do {
            deleted = try await write {
                try await table.delete().eq("id", value: season.id).eq("status", value: SeasonStatus.planned.rawValue)
                    .select().execute().value
            }
        } catch {
            // 23503 (blir `.invalid`): kvelder i terminlista peker på sesongen (on delete restrict).
            if case .invalid = error {
                throw .invalid("Sesongen har kvelder i terminlista. Flytt eller slett dem først.")
            }
            throw error
        }
        guard !deleted.isEmpty else { throw .notAllowed }
        seasons.removeAll { $0.id == season.id }
    }

    // MARK: Hjelpere

    private func update(_ id: UUID, _ patch: some Encodable & Sendable) async throws(DataError) {
        let rows: [SeasonRow] = try await write {
            try await table.update(patch).eq("id", value: id).select().execute().value
        }
        // Ingen rad tilbake: RLS stoppet skrivingen (eller raden finnes ikke lenger).
        guard let row = rows.first else { throw .notAllowed }
        if let i = seasons.firstIndex(where: { $0.id == row.id }) {
            seasons[i] = row
        }
    }

    private func write<T>(_ body: () async throws -> T) async throws(DataError) -> T {
        do {
            return try await body()
        } catch {
            throw DataError.from(error)
        }
    }
}
