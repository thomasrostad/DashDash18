import Foundation
import GolfgutuCore
import Supabase

/// Hjem-feeden (fase 19). Flaggene står her, så del 2 (fanen) og SQL-en kan slås på hver for seg.
nonisolated enum HomeFeedFeature {
    /// Logger plassbytte (`table_changed`) når arrangøren låser en runde eller avslutter kvelden.
    /// **Av** til push-send med teksten for `table_changed` er deployet (ellers får klubben en push
    /// med «Ny hendelse i klubben») og `sql/027_tabellendring.sql` er kjørt (én linje per runde og
    /// konkurranse, også når to telefoner låser samtidig). Hjem leser linjene uansett.
    static let logsTableChanges = false
}

/// Logger plassbyttet i klubbens konkurranser etter at runder er låst: tabellen regnes med og uten
/// rundene, og det som er nytt, skrives som én linje per konkurranse. Feiler noe, står låsingen
/// likevel (som de andre linjene, `logQuietly`).
@MainActor
enum TableChangeLogger {
    /// Konkurransetypene med tabell. Cupen har et tre, og spill på runden har ingen tabell.
    static let kinds: Set<CompetitionKind> = [.season, .league, .fun]

    static func logAfterLocking(client: SupabaseClient, clubID: UUID, roundIDs: [UUID], eventID: UUID?,
                                enabled: Bool = HomeFeedFeature.logsTableChanges) async {
        guard enabled, CompetitionsFeature.isActive, let last = roundIDs.last else { return }
        let log = ActivityLog(client: client, clubID: clubID)
        let locked = Set(roundIDs)
        do {
            let links: [CompetitionRoundRow] = try await client.from("competition_rounds")
                .select(CompetitionQueries.linkColumns)
                .in("round_id", values: roundIDs.map(\.uuidString))
                .execute().value
            let ids = Array(Set(links.map(\.competitionID)))
            guard !ids.isEmpty else { return }
            let competitions: [CompetitionRow] = try await client.from("competitions")
                .select(CompetitionRow.columns)
                .in("id", values: ids.map(\.uuidString))
                .eq("club_id", value: clubID)
                .execute().value
            for competition in competitions where kinds.contains(competition.kind) && competition.status != .planned {
                guard let event = try? await event(client: client, competition: competition, locked: locked) else {
                    continue
                }
                await log.logQuietly(event, eventID: eventID, roundID: last)
            }
        } catch {
            return
        }
    }

    /// Tabellen med og uten de låste rundene.
    private static func event(client: SupabaseClient, competition: CompetitionRow,
                              locked: Set<UUID>) async throws -> ActivityEvent? {
        if competition.kind == .season {
            guard let input = try await CompetitionQueries.season(client: client, competition: competition) else {
                return nil
            }
            var before = input
            before.rounds = input.rounds.filter { !locked.contains($0.round.id) }
            let after = TavlaStandings(input, me: nil)
            return TableChange.event(competition: competition, roundNo: after.snapshots.count,
                                     before: TableBoard(TavlaStandings(before, me: nil)), after: TableBoard(after))
        }
        let participants = try await CompetitionQueries.participants(client: client, competitionID: competition.id)
        let detail = try await CompetitionQueries.detail(client: client, competition: competition,
                                                         participants: participants)
        let input = detail.input
        let before = CompetitionInput(competition: input.competition, entrants: input.entrants, roster: input.roster,
                                      rounds: input.rounds.filter { !locked.contains($0.round.id) })
        return TableChange.event(competition: competition, roundNo: input.rounds.count,
                                 before: TableBoard(LeagueStandings(before, me: [])),
                                 after: TableBoard(LeagueStandings(input, me: [])))
    }
}
