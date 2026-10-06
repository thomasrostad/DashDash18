import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Tippekupongen for én kveld: henter, holder utkastet og leverer, endrer og trekker.
@Observable
final class TipsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var board: TipsBoard?
    var draft: TipsDraft
    private(set) var isSaving = false

    let eventID: UUID
    private let context: ClubContext

    init(context: ClubContext, eventID: UUID) {
        self.context = context
        self.eventID = eventID
        draft = TipsDraft(me: context.memberID, saved: nil)
    }

    var memberID: UUID { context.memberID }
    private var client: SupabaseClient { context.client }

    func load() async {
        do {
            let input = try await TipsQueries.load(client: client, eventID: eventID)
            let board = TipsBoard(input, me: memberID, isOrganizer: context.isOrganizer)
            // Utkastet beholdes mens du velger; det nullstilles når det leverte endrer seg.
            if self.board?.myCoupon != board.myCoupon || self.board == nil {
                draft = TipsDraft(me: memberID, saved: board.myCoupon)
            }
            self.board = board
            state = .loaded
        } catch is CancellationError {
            // Dra-ned avbrutt: behold det som vises.
        } catch {
            if board == nil { state = .failed(DataError.from(error).message) }
        }
    }

    /// Leverer eller lagrer endringene.
    func submit() async throws(DataError) {
        guard let board, !isSaving else { return }
        guard draft.coupon.isComplete else { throw .invalid("Svar på alle fem først.") }
        guard board.phase == .open else { throw TipsModel.locked }
        isSaving = true
        defer { isSaving = false }
        let row = TipsUpsert(eventID: eventID, memberID: memberID, clubID: context.clubID, coupon: draft.coupon)
        do {
            _ = try await TipsQueries.save(client: client, row)
        } catch {
            throw TipsModel.mapLocked(DataError.from(error))
        }
        await load()
    }

    /// Trekker kupongen. Du kan levere en ny til fristen.
    func withdraw() async throws(DataError) {
        guard let board, board.myCoupon != nil, !isSaving else { return }
        guard board.phase == .open else { throw TipsModel.locked }
        isSaving = true
        defer { isSaving = false }
        do {
            try await TipsQueries.withdraw(client: client, eventID: eventID, memberID: memberID)
        } catch {
            throw TipsModel.mapLocked(DataError.from(error))
        }
        draft = TipsDraft(me: memberID, saved: nil)
        await load()
    }

    /// Arrangøren: innsats og linje for kvelden. `nil` = regelsettets standard.
    func saveSettings(stake: Int?, line: Double?) async throws(DataError) {
        guard let board, board.canEditSettings, !isSaving else {
            throw .invalid("Står fast nå som noen har levert.")
        }
        if let stake, !Tips.stakeLimits.contains(stake) { throw .invalid("Ugyldig innsats.") }
        if let line, !Tips.isValidLine(line) { throw .invalid("Linja må være et halvt slag.") }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await TipsQueries.saveSettings(client: client, eventID: eventID,
                                                   TipsSettingsUpdate(stakePoints: stake, line: line))
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    // MARK: Feil

    nonisolated static let locked = DataError.invalid("Kupongen er låst – kvelden har begynt.")

    /// RLS avviser skriving når kupongen er låst (42501 eller ingen rad tilbake).
    nonisolated static func mapLocked(_ error: DataError) -> DataError {
        error == .notAllowed ? locked : error
    }
}
