import Foundation
import GolfgutuCore

/// Det arrangøren kan gjøre med en sesong, og hva det krever. Ren logikk, testbar uten database.
nonisolated enum SeasonLifecycle {
    enum Action: Equatable, Sendable {
        case activate
        case finish
        case delete
    }

    /// Planlagt: aktiver eller slett. Aktiv: avslutt. Ferdig: aktiver igjen (om den ble avsluttet ved en feil).
    static func actions(for status: SeasonStatus) -> [Action] {
        switch status {
        case .planned: [.activate, .delete]
        case .active: [.finish]
        case .finished: [.activate]
        }
    }

    /// Den andre aktive sesongen i klubben, som må avsluttes før `season` kan aktiveres
    /// (databasen tillater høyst én aktiv per klubb).
    static func activeConflict(activating season: SeasonRow, in seasons: [SeasonRow]) -> SeasonRow? {
        seasons.first { $0.status == .active && $0.id != season.id && $0.clubID == season.clubID }
    }

    /// Sesongene i visningsrekkefølgen: aktiv, planlagt, ferdig. Innenfor hver status som fra databasen (nyest først).
    static func grouped(_ seasons: [SeasonRow]) -> [(status: SeasonStatus, seasons: [SeasonRow])] {
        [SeasonStatus.active, .planned, .finished].compactMap { status in
            let rows = seasons.filter { $0.status == status }
            return rows.isEmpty ? nil : (status, rows)
        }
    }

    /// Hvor «Turneringen» lander.
    enum Landing: Equatable, Sendable {
        /// Rett på den aktive sesongen.
        case season(UUID)
        /// Lista over turneringene, fordi ingen sesong er aktiv.
        case list
    }

    /// Den aktive sesongen hvis klubben har én, ellers lista. Databasen tillater høyst én aktiv per klubb;
    /// skulle det likevel finnes flere, vinner den første (nyest, som fra databasen).
    static func landing(_ seasons: [SeasonRow]) -> Landing {
        seasons.first { $0.status == .active }.map { .season($0.id) } ?? .list
    }

    /// Oppfordringen øverst i lista når ingen sesong er aktiv (nil når en er aktiv, eller når lista er tom
    /// og tom-tilstanden sier det selv).
    static func listPrompt(_ seasons: [SeasonRow]) -> String? {
        guard !seasons.isEmpty, landing(seasons) == .list else { return nil }
        return seasons.contains { $0.status == .planned }
            ? "Ingen serie er i gang. Åpne en planlagt og aktiver den, eller lag en ny turnering."
            : "Ingen serie er i gang. Lag en ny turnering."
    }

    static func title(_ status: SeasonStatus) -> String {
        switch status {
        case .planned: "Planlagt"
        case .active: "Aktiv"
        case .finished: "Ferdig"
        }
    }
}

/// Feltene som sendes ved ny sesong.
nonisolated struct NewSeasonPayload: Encodable, Sendable {
    let clubID: UUID
    let name: String
    let status: SeasonStatus
    let rules: Ruleset

    enum CodingKeys: String, CodingKey {
        case clubID = "club_id"
        case name, status, rules
    }
}

/// Endring av regelsettet.
nonisolated struct SeasonRulesPatch: Encodable, Sendable {
    let rules: Ruleset
}

/// Endring av status.
nonisolated struct SeasonStatusPatch: Encodable, Sendable {
    let status: SeasonStatus
}
