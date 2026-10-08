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
    /// nil bare i skjermprøvene (`init(preview:)`): da går ingenting til nettet.
    private let context: ClubContext?

    init(context: ClubContext) {
        self.context = context
    }

    #if DEBUG
    /// Skjermprøve med oppdiktede sesonger, uten nett.
    init(preview seasons: [SeasonRow]) {
        context = nil
        self.seasons = seasons
        loadState = .loaded
    }
    #endif

    /// Klubbens tilkobling, eller `.notAllowed` i en skjermprøve.
    private func connection() throws(DataError) -> ClubContext {
        guard let context else { throw .notAllowed }
        return context
    }

    private var table: PostgrestQueryBuilder {
        get throws(DataError) { try connection().client.from("seasons") }
    }

    func season(id: UUID) -> SeasonRow? {
        seasons.first { $0.id == id }
    }

    func load() async {
        guard let context else { return }
        do {
            seasons = try await table
                .select(SeasonRow.columns)
                .eq("club_id", value: context.clubID)
                .order("created_at", ascending: false)
                .execute()
                .value
            loadState = .loaded
        } catch {
            loadState = .failed(DataError.from(error))
        }
    }

    /// Ny sesong (en serie i «Ny turnering»). Den lages planlagt og aktiveres så med `activate_season`
    /// når `activate` er satt, samme vei som «Aktiver turneringen».
    @discardableResult
    func create(name: String, rules: Ruleset, activate: Bool) async throws(DataError) -> SeasonRow {
        let payload = NewSeasonPayload(clubID: try connection().clubID, name: name, status: .planned, rules: rules)
        let row: SeasonRow = try await write {
            try await table.insert(payload).select().single().execute().value
        }
        seasons.insert(row, at: 0)
        guard activate else { return row }
        try await self.activate(row)
        return season(id: row.id) ?? row
    }

    func saveRules(_ rules: Ruleset, for season: SeasonRow) async throws(DataError) {
        try await update(season.id, SeasonRulesPatch(rules: rules))
    }

    /// Aktiverer sesongen og avslutter en annen aktiv i samme transaksjon
    /// (RPC `activate_season`, sql/004, kjørt på test 06.10).
    func activate(_ season: SeasonRow) async throws(DataError) {
        struct Params: Encodable { let p_season_id: UUID }
        let row: SeasonRow = try await write {
            try await connection().client.rpc("activate_season", params: Params(p_season_id: season.id)).execute().value
        }
        for i in seasons.indices where seasons[i].status == .active && seasons[i].id != row.id {
            seasons[i].status = .finished
        }
        if let i = seasons.firstIndex(where: { $0.id == row.id }) {
            seasons[i] = row
        }
    }

    func finish(_ season: SeasonRow) async throws(DataError) {
        try await update(season.id, SeasonStatusPatch(status: .finished))
    }

    /// Sletter en planlagt sesong. Aktive og ferdige slettes ikke fra appen.
    func delete(_ season: SeasonRow) async throws(DataError) {
        guard season.status == .planned else {
            throw .invalid("Bare planlagte turneringer kan slettes.")
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
                throw .invalid("Turneringen har kvelder i terminlista. Flytt eller slett dem først.")
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
