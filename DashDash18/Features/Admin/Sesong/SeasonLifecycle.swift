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

    /// Den aktive hovedturneringen i klubben, som `season` ville erstattet. Da spør appen om serien
    /// skal erstatte den («Erstatt») eller gå ved siden av («Kjør ved siden av», sql/034).
    static func activeConflict(activating season: SeasonRow, in seasons: [SeasonRow],
                               mainSeasonIDs: Set<UUID> = []) -> SeasonRow? {
        MainTournament.activeMain(otherThan: season, in: seasons, mainSeasonIDs: mainSeasonIDs)
    }

    /// Teksten i spørsmålet «Skal serien erstatte hovedturneringen?».
    static func replaceMessage(main: SeasonRow) -> String {
        "«\(main.name)» er hovedturneringen. Erstatt: den blir ferdig, og serien blir hovedturnering. "
            + "Kjør ved siden av: begge går, og «\(main.name)» er fortsatt hovedturneringen."
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

    /// Hovedturneringen når den er i gang, ellers lista. Flere serier kan være aktive (sql/034); da
    /// lander siden på hovedturneringen, og uten en merket hovedturnering på lista.
    static func landing(_ seasons: [SeasonRow], mainSeasonIDs: Set<UUID> = []) -> Landing {
        MainTournament.activeSeason(seasons, mainSeasonIDs: mainSeasonIDs).map { .season($0.id) } ?? .list
    }

    /// Oppfordringen øverst i lista når ingen sesong er aktiv (nil når en er aktiv, eller når lista er tom
    /// og tom-tilstanden sier det selv).
    static func listPrompt(_ seasons: [SeasonRow], mainSeasonIDs: Set<UUID> = []) -> String? {
        guard !seasons.isEmpty, !seasons.contains(where: { $0.status == .active }),
              landing(seasons, mainSeasonIDs: mainSeasonIDs) == .list else { return nil }
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

/// Feltene som sendes ved ny sesong. id lages her, så raden kan leses tilbake fra turneringsraden
/// (`competitions.season_id`) uten å lese `seasons`.
nonisolated struct NewSeasonPayload: Encodable, Sendable {
    var id = UUID()
    let clubID: UUID
    let name: String
    let status: SeasonStatus
    let rules: Ruleset

    enum CodingKeys: String, CodingKey {
        case id
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
