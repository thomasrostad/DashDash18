import Foundation
import Observation
import Supabase

/// «Spill»-fanen: profilen din, dine løse runder (pågår og ferdige), klubbrundene du spiller som
/// deltaker i en turnering (sql/059) og vennene du kan spille med.
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
    /// «Turneringsrunder»: klubbrundene som går, der du er deltaker (ikke medlem).
    private(set) var tournamentRounds: [MyRoundItem] = []
    /// Satt når turneringsrundene ikke kunne hentes (da vet vi ikke om noen går).
    private(set) var tournamentRoundsError: String?
    private var participantRounds: [UUID: ParticipantRound] = [:]

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

    /// Profilen er lagret fra Spill (navn og handicap): brukes i neste runde med en gang.
    func profileSaved(_ row: OwnProfileRow) {
        me?.displayName = row.displayName
        me?.handicapIndex = row.handicapIndex
    }

    /// Føringen for en turneringsrunde i lista.
    func participantContext(_ roundID: UUID) -> ParticipantRoundContext? {
        guard let client, let round = participantRounds[roundID] else { return nil }
        return ParticipantRoundContext(client: client, userID: userID, round: round)
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
            await loadTournamentRounds(client: client)
            state = .loaded
        } catch {
            guard !DataError.isCancellation(error) else { return }
            if state != .loaded { state = .failed(DataError.from(error).message) }
        }
    }

    /// Deltakerrundene. Feiler det, står lista som sist (de løse rundene er det viktigste her),
    /// og en feillinje sier fra i stedet for «Ingen runder går nå».
    private func loadTournamentRounds(client: SupabaseClient) async {
        let participations: [Participation]
        let rounds: [RoundSnapshot]
        do {
            participations = try await ParticipationQueries.mine(client: client, userID: userID)
            rounds = try await ParticipationQueries.activeRounds(client: client, participations: participations)
            tournamentRoundsError = nil
        } catch {
            // Uten sql/059 (`club_members.kind`) finnes ingen deltakerrunder: ingen feil å vise.
            let missing = EveningSignupService.isMissing(code: (error as? PostgrestError)?.code)
            if !DataError.isCancellation(error), !missing {
                tournamentRoundsError = "Fikk ikke hentet turneringsrundene. " + DataError.from(error).message
            }
            return
        }
        let items = ParticipantRounds.items(rounds, participations: participations,
                                            referenceYear: EveningDates.year(of: EveningDates.today()))
        tournamentRounds = items.map(\.item)
        participantRounds = Dictionary(items.map { ($0.round.roundID, $0.round) }, uniquingKeysWith: { a, _ in a })
    }
}
