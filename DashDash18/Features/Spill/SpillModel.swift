import Foundation
import Observation
import Supabase

/// «Spill»-fanen: profilen din, dine løse runder (pågår og ferdige) og vennene du kan spille med.
@Observable
final class SpillModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var me: ProfileRow?
    private(set) var ongoing: [MyRoundItem] = []
    private(set) var finished: [MyRoundItem] = []

    let client: SupabaseClient?
    let userID: UUID

    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        self.userID = userID
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview me: ProfileRow, ongoing: [MyRoundItem], finished: [MyRoundItem]) {
        client = nil
        userID = me.id
        self.me = me
        self.ongoing = ongoing
        self.finished = finished
        state = .loaded
    }
    #endif

    var looseContext: (UUID) -> LooseRoundContext? {
        { [client, userID] roundID in client.map { LooseRoundContext(client: $0, userID: userID, roundID: roundID) } }
    }

    func load() async {
        guard let client else { return }
        do {
            // Profilen lages eller fylles fra klubben første gang (017 `ensure_profile`).
            if me == nil { me = try await LooseRoundQueries.ensureProfile(client: client) }
            let rounds = try await LooseRoundQueries.myRounds(client: client)
            let lists = MyRounds.lists(rounds, userID: userID, referenceYear: EveningDates.year(of: EveningDates.today()))
            ongoing = lists.ongoing
            finished = lists.finished
            state = .loaded
        } catch {
            if state != .loaded { state = .failed(DataError.from(error).message) }
        }
    }
}
