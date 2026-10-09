import Foundation

/// Trekning av sosialkomité, som PWA-ens `trekkSosialkomite` (db-nytt.js):
/// færrest tidligere turer først, tilfeldig blant dem som står likt. Kvelder som
/// allerede har full komité røres ikke, og de som har noen, fylles opp.
nonisolated enum CommitteeDraw {
    struct Evening: Equatable, Sendable {
        let id: UUID
        /// `YYYY-MM-DD`.
        let date: String
        let committee: [UUID]
    }

    struct Assignment: Equatable, Sendable {
        let eventID: UUID
        let date: String
        /// Hele komiteen etter trekningen: de som sto der fra før, så de nye.
        let memberIDs: [UUID]
        /// Bare de nye.
        let added: [UUID]
    }

    /// - Parameters:
    ///   - evenings: alle kvelder. Turer telles på alle, også dem som har vært.
    ///   - members: hvem som kan trekkes, i troppens rekkefølge.
    ///   - perEvening: antall i komiteen per kveld (PWA-en: 2).
    ///   - fillFrom: bare kvelder med dato ≥ denne fylles. nil = alle, som i PWA-en.
    ///   - chooseIndex: tilfeldig indeks i `0..<n` (PWA-en: `Math.floor(Math.random() * n)`).
    ///     Injiseres så testene kan bestemme trekningen.
    /// - Returns: kvelder som fikk full komité, sortert på dato. En kveld som ikke kan
    ///   fylles (for få medlemmer), er ikke med.
    static func draw(
        evenings: [Evening],
        members: [UUID],
        perEvening: Int = 2,
        fillFrom: String? = nil,
        chooseIndex: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) -> [Assignment] {
        guard perEvening > 0 else { return [] }
        var turns = Dictionary(uniqueKeysWithValues: members.map { ($0, 0) })
        for evening in evenings {
            for member in evening.committee where turns[member] != nil {
                turns[member, default: 0] += 1
            }
        }

        let open = evenings
            .filter { $0.committee.count < perEvening }
            .filter { fillFrom == nil || $0.date >= fillFrom! }
            .sorted { $0.date < $1.date }

        var plan: [Assignment] = []
        for evening in open {
            var chosen = evening.committee
            var added: [UUID] = []
            while chosen.count < perEvening {
                let candidates = members.filter { !chosen.contains($0) }
                guard let fewest = candidates.map({ turns[$0, default: 0] }).min() else { break }
                let even = candidates.filter { turns[$0, default: 0] == fewest }
                let index = min(max(chooseIndex(even.count), 0), even.count - 1)
                let picked = even[index]
                chosen.append(picked)
                added.append(picked)
                turns[picked, default: 0] += 1
            }
            if chosen.count == perEvening {
                plan.append(Assignment(eventID: evening.id, date: evening.date, memberIDs: chosen, added: added))
            }
        }
        return plan
    }
}

/// Inndata i kveld-skjemaet: rydding og grenser fra skjemaet (`events.venue` ≤ 80, `note` ≤ 200).
nonisolated enum EventInput {
    static let venueMax = 80
    static let noteMax = 200

    /// Trimmet tekst, nil når tom. `.failure` med norsk melding når den er for lang.
    static func text(_ raw: String, max: Int, field: String) -> Result<String?, DataError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .success(nil) }
        if trimmed.unicodeScalars.count > max {
            return .failure(.invalid("\(field) kan være høyst \(max) tegn."))
        }
        return .success(trimmed)
    }
}

/// Hvilke kvelder terminlista viser, og hvordan.
nonisolated enum Terminliste {
    /// Turneringen med id, ellers hovedturneringen (den aktive). Arrangørsiden og kveldene viser én
    /// turnering om gangen (fase 21), så en velger kan legges til senere.
    static func tournament(_ seasons: [SeasonRow], id: UUID?) -> SeasonRow? {
        if let id { return seasons.first { $0.id == id } }
        return seasons.first { $0.status == .active }
    }

    /// Kveldene som hører til sesongen: den aktive sesongens, og klubbens egne kvelder uten sesong.
    /// Uten aktiv sesong vises bare kvelder uten sesong. Spilledagene til en liga, cup eller morro
    /// (uten sesong, med `competitionID`) hører til den turneringen, ikke hit (sql/033).
    static func eveningsForSeason(_ events: [EventRow], activeSeasonID: UUID?) -> [EventRow] {
        events
            .filter { ($0.seasonID == nil && $0.competitionID == nil) || ($0.seasonID != nil && $0.seasonID == activeSeasonID) }
            .sorted { $0.eventDate < $1.eventDate }
    }

    /// Spilledagene til en turnering uten sesong (liga, cup, morro), eldste først.
    static func days(_ events: [EventRow], competitionID: UUID) -> [EventRow] {
        events.filter { $0.competitionID == competitionID }.sorted { $0.eventDate < $1.eventDate }
    }

    /// Kommende (dato ≥ i dag) og tidligere kvelder. Tidligere står nyeste først.
    static func split(_ events: [EventRow], today: String) -> (upcoming: [EventRow], past: [EventRow]) {
        let sorted = events.sorted { $0.eventDate < $1.eventDate }
        return (sorted.filter { $0.eventDate >= today }, sorted.filter { $0.eventDate < today }.reversed())
    }

    /// Norsk feilmelding når en kveld ikke kunne lagres. Én kveld per dato (`events_one_per_date`).
    static func saveErrorMessage(sqlState: String?, fallback: DataError, date: String) -> String {
        sqlState == "23505" ? "\(EveningDates.longText(date, capitalized: true)) står allerede i terminlista." : fallback.message
    }

    /// Norsk feilmelding når en kveld ikke kunne slettes. Runder peker på kvelden
    /// med `on delete restrict`, så databasen nekter med 23503.
    static func deleteErrorMessage(sqlState: String?, fallback: DataError) -> String {
        sqlState == "23503" ? "Datoen har runder og kan ikke slettes. Slett rundene først." : fallback.message
    }
}
