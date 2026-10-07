import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Statistikk-skjermen: henter rådata én gang og regner utvalget på nytt når filteret endres.
@Observable
final class StatsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Hvor mye som trengs før tallene vises (tomtilstand før det).
    static let minimumRoundsForStats = 1
    /// Antall runder i trendlinjas glidende snitt.
    static let trendWindow = 5

    private(set) var state: LoadState = .loading
    private(set) var rounds: [StatsRound] = []
    var kind: StatsRound.Kind? {
        didSet { if kind != oldValue { recompute() } }
    }
    var courseID: String? {
        didSet { if courseID != oldValue { recompute() } }
    }
    var period = StatsPeriod.all {
        didSet { if period != oldValue { recompute() } }
    }
    /// I dag, for periodefilteret (settes fast i skjermprøver og tester).
    var today = Date.now
    private(set) var summary = PlayerStats.summary([])

    var filter: StatsFilter {
        StatsFilter(kind: kind, courseID: courseID, from: period.from(today: today))
    }

    /// Filteret er snevret inn.
    var isFiltered: Bool { kind != nil || courseID != nil || period != .all }

    func resetFilter() {
        kind = nil
        courseID = nil
        period = .all
    }

    let scope: StatsScope
    private let client: SupabaseClient?

    init(client: SupabaseClient, scope: StatsScope) {
        self.client = client
        self.scope = scope
    }

    /// Med ferdige runder (skjermprøver og tester).
    init(scope: StatsScope, rounds: [StatsRound]) {
        client = nil
        self.scope = scope
        self.rounds = rounds
        state = .loaded
        recompute()
    }

    func load() async {
        guard let client else { return }
        do {
            let input = try await StatsQueries.load(client: client, scope: scope)
            rounds = input.statsRounds()
            state = .loaded
            recompute()
        } catch {
            if rounds.isEmpty { state = .failed(DataError.from(error).message) }
        }
    }

    private func recompute() {
        summary = PlayerStats.summary(rounds, filter: filter)
    }

    /// Nok til å vise tallene.
    var hasEnoughData: Bool { summary.completeRounds.count >= Self.minimumRoundsForStats }
    /// Det finnes runder, men ingen i utvalget.
    var isFilteredEmpty: Bool { !rounds.isEmpty && summary.rounds.isEmpty }

    /// Banene spilleren har spilt, til filteret (id, navn), sortert på navn.
    var courses: [(id: String, name: String)] {
        var seen: [String: String] = [:]
        for r in rounds { if let id = r.courseID { seen[id] = r.courseName ?? "Ukjent bane" } }
        return seen.map { ($0.key, $0.value) }.sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
    }

    /// Både klubbrunder og løse runder finnes (ellers vises ikke det filteret).
    var hasBothKinds: Bool { Set(rounds.map(\.kind)).count > 1 }

    /// Antall hull som snitt og beste runder vises for: 18 når det finnes, ellers 9.
    var primaryHoleCount: Int? {
        if summary.averages[18] != nil { return 18 }
        return summary.averages.keys.max()
    }
}
