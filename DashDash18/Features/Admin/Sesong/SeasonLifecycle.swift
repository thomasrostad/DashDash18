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

    /// Regelsettet ny sesong får. Malen er Golfgutu-oppsettet eller en kopi av en annen sesongs regler.
    enum Template: Hashable, Sendable {
        case golfgutu
        case copy(UUID)
    }

    static func rules(for template: Template, seasons: [SeasonRow]) -> Ruleset {
        switch template {
        case .golfgutu: .golfgutu
        case .copy(let id): seasons.first { $0.id == id }?.rules ?? .golfgutu
        }
    }

    /// Standardmalen: kopi av forrige sesong (den første i listen, som er nyest), ellers Golfgutu.
    static func defaultTemplate(seasons: [SeasonRow]) -> Template {
        seasons.first.map { .copy($0.id) } ?? .golfgutu
    }

    /// Sesongene i visningsrekkefølgen: aktiv, planlagt, ferdig. Innenfor hver status som fra databasen (nyest først).
    static func grouped(_ seasons: [SeasonRow]) -> [(status: SeasonStatus, seasons: [SeasonRow])] {
        [SeasonStatus.active, .planned, .finished].compactMap { status in
            let rows = seasons.filter { $0.status == status }
            return rows.isEmpty ? nil : (status, rows)
        }
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

/// Endring av navn.
nonisolated struct SeasonNamePatch: Encodable, Sendable {
    let name: String
}
