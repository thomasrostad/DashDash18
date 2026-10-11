import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Gjennomføringsplanen steg 1 (sql/034): flere aktive runder, serier og spilledager i en klubb.
// Appen velger hovedturneringen der den trenger én sesong, viser runden som er bedt om, og tåler
// aktivitet uten klubb.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(900)

private func season(_ n: Int, _ status: SeasonStatus) -> SeasonRow {
    SeasonRow(id: id(n), clubID: club, name: "Serie \(n)", status: status, rules: .golfgutu)
}

private func round(_ n: Int, event: Int?, status: RoundStatus = .active) -> RoundRow {
    RoundRow(id: id(n), clubID: club, eventID: event.map(id), courseID: nil, roundNo: 1, name: nil, status: status,
             holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford", handicapAllowance: 1,
             externalHandicap: false, weight: 1, ldEnabled: false, ldHoleIndex: nil, kpEnabled: false,
             kpHoleIndex: nil, cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: nil,
             startedAt: nil, lockedAt: nil)
}

struct HovedturneringTests {
    @Test func denAktiveHovedturneringenVinner() {
        // Nyest først, som fra databasen: serien ved siden av er nyere enn hovedturneringen.
        let siden = season(2, .active), hoved = season(1, .active), ferdig = season(3, .finished)
        let seasons = [siden, hoved, ferdig]
        #expect(MainTournament.activeSeason(seasons, mainSeasonIDs: [hoved.id]) == hoved)
        #expect(MainTournament.tableSeason(seasons, mainSeasonIDs: [hoved.id]) == hoved)
        #expect(Terminliste.tournament(seasons, id: nil, mainSeasonIDs: [hoved.id]) == hoved)
        #expect(Terminliste.tournament(seasons, id: siden.id, mainSeasonIDs: [hoved.id]) == siden)
    }

    @Test func aldriEnVilkårligAktiv() {
        let a = season(1, .active), b = season(2, .active)
        // To aktive, ingen merket: ingen valgt (ikke den første som tilfeldigvis kom).
        #expect(MainTournament.activeSeason([a, b], mainSeasonIDs: []) == nil)
        // Én aktiv (som før 034, eller før turneringsraden fantes): den.
        #expect(MainTournament.activeSeason([a, season(3, .finished)], mainSeasonIDs: []) == a)
    }

    @Test func tabellenFallerTilbakePåSisteHovedturnering() {
        let siden = season(1, .active), forrigeHoved = season(2, .finished), eldre = season(3, .finished)
        // Hovedturneringen er ferdig og en serie går ved siden av: Tavla viser fortsatt hovedturneringen
        // når serien ikke er den eneste aktive.
        let annen = season(4, .active)
        #expect(MainTournament.tableSeason([siden, annen, forrigeHoved, eldre], mainSeasonIDs: [forrigeHoved.id])
                == forrigeHoved)
        // Uten noe merket: den eneste aktive, ellers den sist ferdige.
        #expect(MainTournament.tableSeason([siden, eldre], mainSeasonIDs: []) == siden)
        #expect(MainTournament.tableSeason([forrigeHoved, eldre], mainSeasonIDs: []) == forrigeHoved)
        #expect(MainTournament.tableSeason([], mainSeasonIDs: []) == nil)
    }

    @Test func aktiveringSpørBareNårEnHovedturneringGår() {
        let hoved = season(1, .active), siden = season(2, .active), ny = season(3, .planned)
        #expect(SeasonLifecycle.activeConflict(activating: ny, in: [ny, siden, hoved], mainSeasonIDs: [hoved.id]) == hoved)
        // En serie ved siden av er ikke i veien.
        #expect(SeasonLifecycle.activeConflict(activating: ny, in: [ny, siden], mainSeasonIDs: [hoved.id]) == nil)
        // Hovedturneringen selv er ikke i konflikt med seg selv.
        #expect(SeasonLifecycle.activeConflict(activating: hoved, in: [hoved], mainSeasonIDs: [hoved.id]) == nil)
        #expect(SeasonLifecycle.replaceMessage(main: hoved).contains("«Serie 1» er hovedturneringen"))
    }

    @Test func turneringenLanderPåHovedturneringen() {
        let hoved = season(1, .active), siden = season(2, .active)
        #expect(SeasonLifecycle.landing([siden, hoved], mainSeasonIDs: [hoved.id]) == .season(hoved.id))
        // Flere aktive uten hovedturnering: lista, og ingen «Ingen serie er i gang».
        #expect(SeasonLifecycle.landing([siden, hoved]) == .list)
        #expect(SeasonLifecycle.listPrompt([siden, hoved]) == nil)
    }

    @Test func nySerieStarterNårIngenHovedturneringGår() {
        let siden = season(2, .active), hoved = season(1, .active)
        #expect(TournamentSetup.activatesNewSeason(existing: [siden], mainSeasonIDs: [hoved.id]))
        #expect(!TournamentSetup.activatesNewSeason(existing: [siden, hoved], mainSeasonIDs: [hoved.id]))
    }

    @Test func aktiveringSenderSomHovedturnering() throws {
        let erstatt = try JSONEncoder().encode(ActivateSeasonParams(seasonID: id(1), asMain: true))
        let json = try #require(try JSONSerialization.jsonObject(with: erstatt) as? [String: Any])
        #expect(json["p_season_id"] as? String == id(1).uuidString)
        #expect(json["p_as_main"] as? Bool == true)
        let ved = try JSONEncoder().encode(ActivateSeasonParams(seasonID: id(1), asMain: false))
        #expect((try JSONSerialization.jsonObject(with: ved) as? [String: Any])?["p_as_main"] as? Bool == false)
    }
}

struct FlereRunderTests {
    @Test func rundenSomVises() {
        let a = round(1, event: 10), b = round(2, event: 11), c = round(3, event: 11)
        // Bedt om: den, så lenge den går.
        #expect(ActiveRounds.pick([a, b, c], mine: [], preferred: c.id) == c)
        // Ikke lenger aktiv: en du spiller i.
        #expect(ActiveRounds.pick([a, b], mine: [b.id], preferred: c.id) == b)
        // Ingen av dine: den første (nyest startet).
        #expect(ActiveRounds.pick([a, b], mine: [], preferred: nil) == a)
        #expect(ActiveRounds.pick([], mine: [], preferred: nil) == nil)
    }

    @Test func arrangørsidenFølgerTurneringensKvelder() {
        let annenTurnering = round(1, event: 20), egen = round(2, event: 10)
        #expect(ActiveRounds.focus([annenTurnering, egen], eventIDs: [id(10)]) == egen)
        #expect(ActiveRounds.focus([annenTurnering], eventIDs: [id(10)]) == annenTurnering)
    }

    @Test func barePuljenPåSammeKveldErIVeien() {
        let annenKveld = round(1, event: 20), sammeKveld = round(2, event: 10)
        let ny = id(3)
        #expect(ActiveRounds.blocking([annenKveld], roundID: ny, eventID: id(10), waves: [:]) == nil)
        #expect(ActiveRounds.blocking([annenKveld, sammeKveld], roundID: ny, eventID: id(10), waves: [:]) == sammeKveld)
        // Pulje 2 på samme kveld kan starte mens pulje 1 går.
        #expect(ActiveRounds.blocking([sammeKveld], roundID: ny, eventID: id(10), waves: [ny: 2, sammeKveld.id: 1]) == nil)
        // Runden selv er ikke i veien.
        #expect(ActiveRounds.blocking([sammeKveld], roundID: sammeKveld.id, eventID: id(10), waves: [:]) == nil)
    }

    @Test func feilmeldingenNavngirPuljen() {
        let ny = "duplicate key value violates unique constraint \"rounds_one_active_per_event_wave\""
        let gammel = "duplicate key value violates unique constraint \"rounds_one_active_per_club\""
        #expect(RoundErrors.startMessage(sqlState: "23505", message: ny, fallback: .unknown("x"))
                == "En runde går allerede i denne puljen. Lås den før du starter en ny.")
        #expect(RoundErrors.startMessage(sqlState: "23505", message: gammel, fallback: .unknown("x"))
                == "En runde går allerede. Lås den før du starter en ny.")
    }

    @Test func båsGrensenErDatabasens() {
        #expect(BayPlan.maxBays == 99)
    }
}

struct AktivitetUtenKlubbTests {
    @Test func radenTålerManglendeKlubb() throws {
        let json = """
        {"id":"\(id(100).uuidString)","club_id":null,"kind":"announcement","category":"social",
         "data":{"text":"Hei"},"actor_member_id":null,"event_id":null,"round_id":null,"recipients":null,
         "created_at":"2026-10-06T19:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(ActivityRow.self, from: Data(json.utf8))
        #expect(row.clubID == nil)
        // Bjella krever klubb: linja angår ingen ennå.
        let viewer = HomeViewer(profileID: id(1), memberships: [club: id(9)])
        #expect(HomeBell.reason(row, viewer: viewer) == nil)
        #expect(row.clubMember(of: viewer) == nil)
    }
}
