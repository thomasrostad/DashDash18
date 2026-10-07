import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Én runde for arrangøren: hele runden, avkorting og retting av hull.
/// Hull lagres via `ScoreSubmitting` (save_hole), aldri direkte i tabellen.
@Observable
final class RoundReviewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var game: RoundGame?
    let title: String

    private let context: ClubContext
    private let roundID: UUID

    init(context: ClubContext, round: RoundRow, title: String) {
        self.context = context
        self.roundID = round.id
        self.title = title
    }

    func load() async {
        do {
            let rows: [RoundRow] = try await context.client.from("rounds")
                .select(RundeQueries.roundColumns)
                .eq("id", value: roundID)
                .limit(1)
                .execute().value
            guard let row = rows.first else { throw DataError.invalid("Fant ikke runden. Den kan ha blitt slettet.") }
            game = RoundGame(try await RundeQueries.snapshot(client: context.client, round: row))
            state = .loaded
        } catch {
            if case .loaded = state { return }
            state = .failed(DataError.from(error).message)
        }
    }

    // MARK: Avkorting

    /// Lagrer avkortingen (eller fjerner den med `nil`) og sjekker raden tilbake.
    func saveCut(_ choice: CutChoice?) async throws(DataError) {
        guard let game else { return }
        if game.status == .locked {
            throw .invalid("Runden er låst og kan ikke avkortes. Enkelthull rettes under Rundene.")
        }
        let patch = choice.map { CutPatch.set($0, by: context.memberID, at: Date()) } ?? .remove
        do {
            let rows: [RoundRow] = try await context.client.from("rounds")
                .update(patch)
                .eq("id", value: game.roundID)
                .select(RundeQueries.roundColumns)
                .execute().value
            guard let row = rows.first, patch.matches(row) else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    // MARK: Retting

    /// Rett ett hull (også i låst runde). Gir meldingen som skal vises.
    func correct(_ correction: ScoreCorrection, submitter: (any ScoreSubmitting)?) async throws(DataError) -> String {
        guard let game else { throw .invalid("Runden er ikke lastet.") }
        guard let submitter else { throw .invalid("Lagringen er ikke klar. Prøv igjen om litt.") }
        guard let submission = correction.submission(roundID: game.roundID, recordedAt: Date()) else {
            return "Ingen endring."
        }
        let done = correction.doneText(game)
        let outcome: SubmitOutcome
        do {
            outcome = try await submitter.submit(submission)
        } catch {
            throw DataError.from(error)
        }
        switch outcome {
        case .saved:
            await load()
            return done
        case .queued:
            return "Ingen kontakt med serveren. Rettingen ligger i kø og sendes når nettet er tilbake."
        }
    }
}

/// «Avslutt kvelden»: lås alle pågående runder på kvelden.
@MainActor
enum EveningCloser {
    /// Pågående runder på kvelden, som regelmotorens runder.
    static func games(context: ClubContext, rounds: [RoundRow]) async throws(DataError) -> [RoundGame] {
        do {
            var out: [RoundGame] = []
            for round in rounds where round.status == .active {
                out.append(RoundGame(try await RundeQueries.snapshot(client: context.client, round: round)))
            }
            return out
        } catch {
            throw DataError.from(error)
        }
    }

    /// Låser rundene én for én (de pågående, fra `games`). Gir id-ene som ble låst.
    /// Hver runde som ble låst, logges som «Runde låst».
    static func lock(context: ClubContext, roundIDs: [UUID]) async -> Set<UUID> {
        var locked: Set<UUID> = []
        let log = ActivityLog(client: context.client, clubID: context.clubID)
        for id in roundIDs {
            let rows: [RoundRow]? = try? await context.client.from("rounds")
                .update(RoundStatusPatch(status: .locked))
                .eq("id", value: id)
                .select(RundeQueries.roundColumns)
                .execute().value
            guard let row = rows?.first, row.status == .locked else { continue }
            locked.insert(id)
            let name = await courseName(context: context, courseID: row.courseID)
            if let event = RoundActivity.locked(row, courseName: name) {
                await log.logQuietly(event, eventID: row.eventID, roundID: row.id)
            }
        }
        return locked
    }

    /// Banens navn til «Runde låst». Feiler det, logges runden uten.
    private static func courseName(context: ClubContext, courseID: UUID?) async -> String? {
        struct Name: Decodable { let name: String }
        guard let courseID else { return nil }
        let rows: [Name]? = try? await context.client.from("courses")
            .select("name")
            .eq("id", value: courseID)
            .limit(1)
            .execute().value
        return rows?.first?.name
    }
}

/// Rundene: alle startede runder i klubben, nyeste først (`rundeListe`).
@Observable
final class RundeneModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var items: [RundeneItem] = []
    private let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    func load() async {
        let client = context.client
        do {
            async let roundRows: [RoundRow] = client.from("rounds")
                .select(RundeQueries.roundColumns)
                .eq("club_id", value: context.clubID)
                .neq("status", value: RoundStatus.draft.rawValue)
                .execute().value
            async let eventRows: [EventRow] = client.from("events")
                .select("id, club_id, season_id, event_date, start_time, venue, note")
                .eq("club_id", value: context.clubID)
                .execute().value
            async let courseRows: [CourseRow] = client.from("courses")
                .select(CourseLibraryModel.courseColumns)
                .eq("club_id", value: context.clubID)
                .execute().value
            let rounds = try await roundRows
            let dates = Dictionary(try await eventRows.map { ($0.id, $0.eventDate) }, uniquingKeysWith: { a, _ in a })
            let courses = Dictionary(try await courseRows.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

            struct PlayerRef: Decodable { let round_id: UUID }
            var counts: [UUID: Int] = [:]
            if !rounds.isEmpty {
                let refs: [PlayerRef] = try await client.from("round_players")
                    .select("round_id")
                    .in("round_id", values: rounds.map(\.id.uuidString))
                    .execute().value
                for r in refs { counts[r.round_id, default: 0] += 1 }
            }
            items = RundeneList.sorted(rounds.map { r in
                RundeneItem(round: r, eventDate: r.eventID.flatMap { dates[$0] }, courseName: r.courseID.flatMap { courses[$0] },
                     players: counts[r.id] ?? 0)
            })
            state = .loaded
        } catch {
            if case .loaded = state { return }
            state = .failed(DataError.from(error).message)
        }
    }
}

/// En rad i Rundene.
nonisolated struct RundeneItem: Identifiable, Equatable, Sendable {
    let round: RoundRow
    let eventDate: String?
    let courseName: String?
    let players: Int
    var id: UUID { round.id }
    var title: String { RoundListing.title(roundNo: round.roundNo, courseName: courseName) }
}

nonisolated enum RundeneList {
    /// Nyeste kveld først, så høyeste rundenummer.
    static func sorted(_ items: [RundeneItem]) -> [RundeneItem] {
        items.sorted { a, b in
            let da = a.eventDate ?? "", db = b.eventDate ?? ""
            return da != db ? da > db : a.round.roundNo > b.round.roundNo
        }
    }
}
