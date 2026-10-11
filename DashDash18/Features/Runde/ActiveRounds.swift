import Foundation

/// Flere runder kan gå samtidig i en klubb etter sql/034: høyst én per spilledag og pulje
/// (`rounds_one_active_per_event_wave`), og løse runder ved siden av. Før 034 var det høyst én per
/// klubb. Her velges hvilken runde en skjerm viser, og hvilken som er i veien for en ny.
nonisolated enum ActiveRounds {
    /// Runden Kveld og «Gå til runden» viser: den som er bedt om (om den fortsatt går), ellers en du
    /// spiller i, ellers den første (nyest startet først, som fra spørringen).
    /// - Parameters:
    ///   - rounds: rundene som går i klubben.
    ///   - mine: rundene du spiller i.
    ///   - preferred: runden som er valgt på Hjem eller arrangørsiden.
    static func pick(_ rounds: [RoundRow], mine: Set<UUID>, preferred: UUID?) -> RoundRow? {
        if let preferred, let round = rounds.first(where: { $0.id == preferred }) { return round }
        return rounds.first { mine.contains($0.id) } ?? rounds.first
    }

    /// Runden som går for kveldene arrangørsiden viser: den første på en av kveldene, ellers den
    /// første i klubben.
    static func focus(_ rounds: [RoundRow], eventIDs: Set<UUID>) -> RoundRow? {
        rounds.first { $0.eventID.map(eventIDs.contains) ?? false } ?? rounds.first
    }

    /// Runden som stopper start av `roundID`: en annen runde som går på samme kveld og i samme pulje.
    /// Puljer som ikke er kjent, regnes som 1 (standarden i `rounds.wave_no`).
    static func blocking(_ rounds: [RoundRow], roundID: UUID, eventID: UUID, waves: [UUID: Int]) -> RoundRow? {
        let wave = waves[roundID] ?? 1
        return rounds.first { $0.id != roundID && $0.eventID == eventID && (waves[$0.id] ?? 1) == wave }
    }
}
