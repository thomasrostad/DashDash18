import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Tilleggspoeng i én sesong (sql/072): poeng arrangøren gir en spiller for hånd, med en grunn.
/// RLS slipper bare rettigheten «tournaments» til å skrive; hver skriving leser raden tilbake, så en
/// skriving RLS stoppet blir en feil og ikke en stille glipp.
@Observable
final class TilleggspoengModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(DataError)
    }

    let season: SeasonRow
    /// Eldste først.
    private(set) var rows: [PointAdjustmentRow] = []
    /// Troppen som kan få poeng: aktive i klubben, i norsk navnerekkefølge.
    private(set) var members: [ClubMemberRow] = []
    /// Sesongens kvelder, nyeste først.
    private(set) var events: [EventRow] = []
    private(set) var loadState: LoadState = .loading
    /// nil bare i skjermprøvene: da går ingenting til nettet.
    private let context: ClubContext?

    init(context: ClubContext, season: SeasonRow) {
        self.context = context
        self.season = season
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview season: SeasonRow, rows: [PointAdjustmentRow], members: [ClubMemberRow], events: [EventRow] = []) {
        context = nil
        self.season = season
        self.rows = rows
        self.members = members
        self.events = events
        loadState = .loaded
    }
    #endif

    private func connection() throws(DataError) -> ClubContext {
        guard let context else { throw .notAllowed }
        return context
    }

    func load() async {
        guard let context else { return }
        do {
            async let adjustmentRows: [PointAdjustmentRow] = context.client.from("point_adjustments")
                .select(PointAdjustmentRow.columns)
                .eq("season_id", value: season.id)
                .order("created_at")
                .execute().value
            async let memberRows: [ClubMemberRow] = context.client.from("club_members")
                .select(ClubMemberRow.columns)
                .eq("club_id", value: season.clubID)
                .eq("status", value: MemberStatus.active.rawValue)
                .execute().value
            async let eventRows: [EventRow] = context.client.from("events")
                .select(EventRow.columns)
                .eq("season_id", value: season.id)
                .execute().value
            rows = try await adjustmentRows
            members = try await memberRows.sorted { NorwegianSort.areInIncreasingOrder($0.displayName, $1.displayName) }
            events = try await eventRows.sorted { $0.eventDate > $1.eventDate }
            loadState = .loaded
        } catch {
            loadState = .failed(DataError.from(error))
        }
    }

    func add(_ draft: TilleggspoengDraft) async throws(DataError) {
        if let problem = draft.problem { throw .invalid(problem) }
        guard let memberID = draft.memberID else { throw .invalid("Velg en spiller.") }
        let context = try connection()
        let payload = NewPointAdjustmentPayload(clubID: season.clubID, seasonID: season.id, memberID: memberID,
                                                eventID: draft.eventID, points: draft.points,
                                                reason: draft.trimmedReason)
        let row: PointAdjustmentRow = try await write {
            try await context.client.from("point_adjustments")
                .insert(payload)
                .select(PointAdjustmentRow.columns)
                .single()
                .execute().value
        }
        rows.append(row)
    }

    func delete(_ row: PointAdjustmentRow) async throws(DataError) {
        let context = try connection()
        let deleted: [PointAdjustmentRow] = try await write {
            try await context.client.from("point_adjustments")
                .delete()
                .eq("id", value: row.id)
                .select(PointAdjustmentRow.columns)
                .execute().value
        }
        // Ingen rad tilbake: RLS stoppet slettingen (eller den var borte fra før).
        guard deleted.contains(where: { $0.id == row.id }) else { throw .notAllowed }
        rows.removeAll { $0.id == row.id }
    }

    func name(_ memberID: UUID) -> String {
        members.first { $0.id == memberID }?.displayName ?? "Ukjent spiller"
    }

    /// «22. oktober» for kvelden tillegget hører til, ellers nil.
    func eventText(_ eventID: UUID?) -> String? {
        guard let eventID, let event = events.first(where: { $0.id == eventID }) else { return nil }
        return EveningDates.dayMonthText(event.eventDate)
    }

    /// «+1», «0,5», «−2»: poengene med regelsettets avrunding og fortegn.
    func pointsText(_ points: Double) -> String {
        Tilleggspoeng.pointsText(points, rules: season.rules)
    }

    private func write<T>(_ body: () async throws -> T) async throws(DataError) -> T {
        do {
            return try await body()
        } catch {
            throw DataError.from(error)
        }
    }
}

/// Grensene for et tilleggspoeng, som i databasen (sql/072). Ingen regelverdier: poengene gis for hånd.
nonisolated enum Tilleggspoeng {
    /// Høyst så mange tegn i grunnen.
    static let reasonLimit = 80
    /// Poengene kan være negative (straff eller rettelse), men ikke 0.
    static let pointsRange: ClosedRange<Double> = -100...100
    /// Steget i velgeren: halve poeng.
    static let step = 0.5

    /// Hva som mangler før tillegget kan lagres, eller nil.
    static func problem(memberID: UUID?, points: Double, reason: String) -> String? {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if memberID == nil { return "Velg en spiller." }
        if points == 0 { return "Poengene kan ikke være 0." }
        if !pointsRange.contains(points) { return "Høyst 100 poeng av gangen." }
        if reason.isEmpty { return "Skriv en grunn." }
        if reason.count > reasonLimit { return "Grunnen kan ha høyst \(reasonLimit) tegn." }
        return nil
    }

    /// «+1», «0,5» blir «+0,5», «−2».
    static func pointsText(_ points: Double, rules: Ruleset) -> String {
        let text = Season.formatPoints(abs(points), rules: rules)
        return points < 0 ? "−" + text : "+" + text
    }
}

/// Det arrangøren fyller inn.
nonisolated struct TilleggspoengDraft: Equatable, Sendable {
    var memberID: UUID?
    var points: Double = 1
    var reason = ""
    var eventID: UUID?

    var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
    var problem: String? { Tilleggspoeng.problem(memberID: memberID, points: points, reason: reason) }
}

/// Feltene som sendes ved nytt tilleggspoeng. `created_by` settes av databasen.
nonisolated struct NewPointAdjustmentPayload: Encodable, Sendable {
    var id = UUID()
    let clubID: UUID
    let seasonID: UUID
    let memberID: UUID
    let eventID: UUID?
    let points: Double
    let reason: String

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case seasonID = "season_id"
        case memberID = "member_id"
        case eventID = "event_id"
        case points, reason
    }
}
