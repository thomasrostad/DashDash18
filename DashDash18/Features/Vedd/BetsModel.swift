import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Veddemålene i én bank: henter, legger ut, satser og avgjør. Banken er hovedturneringen (Kveld,
/// Tavla, Hjem), en turnering (turneringssiden, runden) eller en enkeltrunde (løse runder). Gjør
/// ingenting mens `BetsFeature.isEnabled` er av.
@Observable
final class BetsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case disabled
        case failed(String)
    }

    /// Hvor veddemålene hentes fra.
    enum Target: Equatable, Sendable {
        /// Klubbens hovedturnering. Uten 052: sesongen som før.
        case main(clubID: UUID)
        case competition(UUID)
        case round(UUID)
    }

    private(set) var state: LoadState = BetsFeature.isEnabled ? .loading : .disabled
    private(set) var board: BetsBoard?
    private(set) var input: BetsInput?
    private(set) var isSaving = false

    let client: SupabaseClient
    let viewer: BetViewer
    let target: Target
    private var isSweeping = false

    init(client: SupabaseClient, viewer: BetViewer, target: Target) {
        self.client = client
        self.viewer = viewer
        self.target = target
    }

    /// Hovedturneringen i klubben som er valgt.
    convenience init(context: ClubContext) {
        self.init(client: context.client, viewer: context.betViewer, target: .main(clubID: context.clubID))
    }

    /// Kan du slå veddemål av og på her (052)?
    var canToggle: Bool { input.map(viewer.canToggle) ?? false }

    /// Serveren gjør opp når runden låses (052).
    var serverSettles: Bool { input?.serverSettles ?? false }

    func load() async {
        guard BetsFeature.isEnabled else { state = .disabled; return }
        do {
            apply(try await fetch())
            state = .loaded
            await sweep()
        } catch is CancellationError {
            // Dra-ned avbrutt: behold det som vises.
        } catch {
            if board == nil { state = .failed(DataError.from(error).message) }
        }
    }

    private func fetch() async throws -> BetsInput? {
        switch target {
        case .main(let clubID): try await BetsQueries.load(client: client, clubID: clubID)
        case .competition(let id): try await BetsQueries.load(client: client, competitionID: id)
        case .round(let id): try await BetsQueries.load(client: client, roundID: id)
        }
    }

    private func apply(_ input: BetsInput?) {
        self.input = input
        board = input.map { BetsBoard($0, me: viewer.me(in: $0), isOrganizer: viewer.canResolve($0)) }
    }

    /// Legger ut veddemålet med din innsats: `create_bet_v2` i bankens turnering eller runde (052),
    /// ellers `create_bet` i sesongen.
    func create(_ draft: BetSheetDraft) async throws(DataError) {
        guard BetsFeature.isEnabled, let board, !isSaving else { return }
        if let problem = draft.problem(board: board) { throw .invalid(problem) }
        isSaving = true
        defer { isSaving = false }
        do {
            if let scope = board.scope {
                _ = try await BetsQueries.create(client: client, draft.params(scope: scope))
            } else if case .main(let clubID) = target {
                _ = try await BetsQueries.create(client: client, draft.params(clubID: clubID))
            }
        } catch {
            throw await rejected(error)
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
            throw await rejected(error)
        }
        await load()
    }

    /// Arrangøren avgjør (JA, NEI) eller annullerer. Kan ikke angres. Ikke når hun selv har
    /// satset på veddemålet (`resolve_bet` avviser det også).
    func resolve(_ item: BetsBoard.Item, verdict: BetVerdict) async throws(DataError) {
        guard BetsFeature.isEnabled, board?.isOrganizer == true, !isSaving else { return }
        if item.resolverHasStake { throw .invalid(BetTexts.resolverHasStake) }
        guard item.canResolve else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BetsQueries.resolve(client: client, betID: item.id, verdict: verdict)
        } catch {
            throw await rejected(error)
        }
        await load()
    }

    /// Slår veddemål på eller av i banken (`bets_set_enabled`, 052).
    func setEnabled(_ on: Bool) async throws(DataError) {
        guard BetsFeature.isEnabled, let scope = input?.scope, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await BetsQueries.setEnabled(client: client, scope: scope, enabled: on)
        } catch {
            throw await rejected(error)
        }
        await load()
    }

    /// Feilen fra RPC-en på forståelig norsk (`BetErrors`). Avviste serveren, hentes lista på nytt:
    /// veddemålet kan ha stengt eller blitt avgjort i mellomtiden, og kortet skal vise det som gjelder.
    private func rejected(_ error: any Error) async -> DataError {
        let mapped: DataError
        if let postgrest = error as? PostgrestError,
           let text = BetErrors.text(sqlState: postgrest.code, message: postgrest.message) {
            mapped = .invalid(text)
        } else {
            mapped = DataError.from(error)
        }
        if case .invalid = mapped { await load() }
        return mapped
    }

    /// Arrangørens telefon avgjør det vilkårene gir svar på (`feiMarkeder`), og annullerer delt
    /// hull og likt resultat (`settle_bet`). Med 052 gjør serveren det når runden låses, og
    /// telefonen tar bare det serveren ikke har rukket (`BetSweep.phoneMaySettle`). Feiler et kall,
    /// står veddemålet åpent til neste henting eller til en arrangør tar det for hånd.
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
        if changed, let input = try? await fetch() {
            apply(input)
        }
    }
}

extension ClubContext {
    /// Deg i klubben som er valgt, sett fra veddemålene.
    var betViewer: BetViewer {
        BetViewer(userID: user.id, memberships: [clubID: memberID],
                  moneyClubs: can(.money) ? [clubID] : [],
                  organizerClubs: (can(.tournaments) || can(.rounds)) ? [clubID] : [])
    }
}
