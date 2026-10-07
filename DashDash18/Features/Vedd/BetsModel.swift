import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Veddemålene i sesongen: henter, legger ut, satser og avgjør. Gjør ingenting mens
/// `BetsFeature.isEnabled` er av.
@Observable
final class BetsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case disabled
        case failed(String)
    }

    private(set) var state: LoadState = BetsFeature.isEnabled ? .loading : .disabled
    private(set) var board: BetsBoard?
    private(set) var isSaving = false

    private let context: ClubContext
    private var isSweeping = false

    init(context: ClubContext) {
        self.context = context
    }

    var clubContext: ClubContext { context }
    private var client: SupabaseClient { context.client }

    func load() async {
        guard BetsFeature.isEnabled else { state = .disabled; return }
        do {
            let input = try await BetsQueries.load(client: client, clubID: context.clubID)
            board = input.map { BetsBoard($0, me: context.memberID, isOrganizer: context.isOrganizer) }
            state = .loaded
            await sweep()
        } catch is CancellationError {
            // Dra-ned avbrutt: behold det som vises.
        } catch {
            if board == nil { state = .failed(DataError.from(error).message) }
        }
    }

    /// Legger ut veddemålet med din innsats.
    func create(_ draft: BetSheetDraft) async throws(DataError) {
        guard BetsFeature.isEnabled, let board, !isSaving else { return }
        if let problem = draft.problem(board: board) { throw .invalid(problem) }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await BetsQueries.create(client: client, draft.params(clubID: context.clubID))
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    /// En innsats på et veddemål som finnes.
    func stake(_ item: BetsBoard.Item, side: BetSide, points: Int) async throws(DataError) {
        guard BetsFeature.isEnabled, let board, !isSaving else { return }
        if let problem = BetStakeCheck.problem(item, side: side, points: points, board: board) { throw .invalid(problem) }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BetsQueries.stake(client: client, betID: item.id, side: side, points: points)
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    /// Arrangøren avgjør (JA, NEI) eller annullerer. Kan ikke angres. Ikke når hun selv har
    /// satset på veddemålet (`resolve_bet` avviser det også).
    func resolve(_ item: BetsBoard.Item, verdict: BetVerdict) async throws(DataError) {
        guard BetsFeature.isEnabled, context.isOrganizer, !isSaving else { return }
        if item.resolverHasStake { throw .invalid(BetTexts.resolverHasStake) }
        guard item.canResolve else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BetsQueries.resolve(client: client, betID: item.id, verdict: verdict)
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    /// Arrangørens telefon avgjør det vilkårene gir svar på (`feiMarkeder`), og annullerer delt
    /// hull og likt resultat (`settle_bet`). Feiler et kall, står veddemålet åpent til neste
    /// henting eller til en arrangør tar det for hånd.
    private func sweep() async {
        guard let plan = board?.sweepPlan, !plan.isEmpty, !isSweeping else { return }
        isSweeping = true
        defer { isSweeping = false }
        var changed = false
        for (id, verdict) in plan {
            do {
                try await BetsQueries.settle(client: client, betID: id, verdict: verdict)
                changed = true
            } catch {
                continue
            }
        }
        if changed, let input = try? await BetsQueries.load(client: client, clubID: context.clubID) {
            board = BetsBoard(input, me: context.memberID, isOrganizer: context.isOrganizer)
        }
    }
}
