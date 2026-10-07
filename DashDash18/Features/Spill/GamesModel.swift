import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Spillene i én runde: henter, lager, markerer og gjør opp. Gjør ingenting mens
/// `GamesFeature.isEnabled` er av.
@Observable
final class GamesModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case disabled
        case failed(String)
    }

    private(set) var state: LoadState = GamesFeature.isEnabled ? .loading : .disabled
    private(set) var input = GamesInput()
    private(set) var isSaving = false

    let roundID: UUID
    private let client: SupabaseClient?

    init(client: SupabaseClient?, roundID: UUID) {
        self.client = client
        self.roundID = roundID
    }

    /// Skjermprøver og tester: ferdige rader, ingen nettverk.
    init(sample input: GamesInput, roundID: UUID) {
        client = nil
        self.roundID = roundID
        self.input = input
        state = .loaded
    }

    func load() async {
        guard GamesFeature.isEnabled, let client else { return }
        do {
            input = try await GamesQueries.load(client: client, roundID: roundID)
            state = .loaded
        } catch is CancellationError {
            // Behold det som vises.
        } catch {
            if input.games.isEmpty { state = .failed(DataError.from(error).message) }
        }
    }

    func create(_ draft: GameDraft) async throws(DataError) {
        if let problem = draft.problems().first {
            throw .invalid(GameTexts.problem(problem, names: { _ in "En spiller" }))
        }
        try await write { client in _ = try await GamesQueries.create(client: client, draft.params(roundID: self.roundID)) }
    }

    func delete(_ gameID: UUID) async throws(DataError) {
        try await write { client in try await GamesQueries.delete(client: client, gameID: gameID) }
    }

    func setWolf(_ gameID: UUID, hole: Int, choice: WolfChoice?) async throws(DataError) {
        let params = GameMarkParams(p_game_id: gameID, p_hole: hole, p_award: .wolf,
                                    p_player_id: choice?.partner.flatMap(UUID.init(uuidString:)),
                                    p_wolf_mode: choice?.mode)
        try await write { client in try await GamesQueries.setMark(client: client, params) }
    }

    func setAward(_ gameID: UUID, hole: Int, award: RoundGameMarkRow.Award, player: UUID?) async throws(DataError) {
        let params = GameMarkParams(p_game_id: gameID, p_hole: hole, p_award: award, p_player_id: player, p_wolf_mode: nil)
        try await write { client in try await GamesQueries.setMark(client: client, params) }
    }

    func settle(_ card: GameCard) async throws(DataError) {
        guard card.canSettle else { return }
        try await write { client in try await GamesQueries.settle(client: client, gameID: card.id, points: card.settlement) }
    }

    /// Ett kall om gangen, så henting på nytt. Feilen fra RPC-en på norsk (`GameErrors`).
    private func write(_ call: @escaping (SupabaseClient) async throws -> Void) async throws(DataError) {
        guard GamesFeature.isEnabled, let client, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await call(client)
        } catch {
            let mapped: DataError
            if let postgrest = error as? PostgrestError,
               let text = GameErrors.text(sqlState: postgrest.code, message: postgrest.message) {
                mapped = .invalid(text)
            } else {
                mapped = DataError.from(error)
            }
            await load()
            throw mapped
        }
        await load()
    }
}
