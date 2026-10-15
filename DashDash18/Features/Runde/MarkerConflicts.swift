import Foundation
import Supabase

// K6/6.3 (UI-utbedringen): to markører fører ulikt tall for samme spiller og hull. Serveren tar vare
// på tallet som ble overskrevet (sql/055, `hole_score_conflicts`), og markøren eller arrangøren
// velger hvilket som gjelder (`resolve_hole_conflict`). Tallet i `hole_scores` teller til noen velger.
// Bare visning og valg her; ingen spillregler.

/// Én rad i `hole_score_conflicts` (sql/055). Lesbar for dem som kan føre for spilleren (`can_score`).
nonisolated struct HoleConflictRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundID: UUID
    let memberID: UUID
    let holeIndex: Int
    /// Tallet som står nå (den siste føringen).
    let keptStrokes: Int
    let keptBy: UUID?
    let keptAt: Date
    /// Tallet som ble overskrevet.
    let otherStrokes: Int
    let otherBy: UUID?
    let otherAt: Date
    let createdAt: Date?
    let resolvedAt: Date?

    var isOpen: Bool { resolvedAt == nil }

    enum CodingKeys: String, CodingKey {
        case id
        case roundID = "round_id"
        case memberID = "member_id"
        case holeIndex = "hole_index"
        case keptStrokes = "kept_strokes"
        case keptBy = "kept_by"
        case keptAt = "kept_at"
        case otherStrokes = "other_strokes"
        case otherBy = "other_by"
        case otherAt = "other_at"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }

    static let columns = "id, round_id, member_id, hole_index, kept_strokes, kept_by, kept_at, "
        + "other_strokes, other_by, other_at, created_at, resolved_at"
}

nonisolated enum MarkerConflicts {
    /// Konfliktene som skal vises: den nyeste per spiller og hull, og bare når den ikke er løst.
    /// Fører en tredje markør enda et tall, lager serveren en ny rad; den eldre er da utdatert, selv om
    /// den står åpen. Sortert på hull, så spiller.
    static func open(_ rows: [HoleConflictRow], roundID: UUID? = nil) -> [HoleConflictRow] {
        let relevant = roundID.map { id in rows.filter { $0.roundID == id } } ?? rows
        let groups = Dictionary(grouping: relevant) { Key(round: $0.roundID, member: $0.memberID, hole: $0.holeIndex) }
        return groups.values
            .compactMap { group in group.max(by: isOlder) }
            .filter(\.isOpen)
            .sorted { ($0.holeIndex, $0.memberID.uuidString) < ($1.holeIndex, $1.memberID.uuidString) }
    }

    private struct Key: Hashable {
        let round: UUID
        let member: UUID
        let hole: Int
    }

    private static func isOlder(_ a: HoleConflictRow, _ b: HoleConflictRow) -> Bool {
        let ta = a.createdAt ?? a.keptAt, tb = b.createdAt ?? b.keptAt
        if ta != tb { return ta < tb }
        return a.keptAt < b.keptAt
    }

    /// Spillerne med konflikt på hullet.
    static func members(onHole hole: Int, in conflicts: [HoleConflictRow]) -> Set<UUID> {
        Set(conflicts.filter { $0.holeIndex == hole }.map(\.memberID))
    }

    /// Konflikten arket åpner fra stripa: den på hullet du står på, ellers den første.
    static func first(_ conflicts: [HoleConflictRow], preferring hole: Int) -> HoleConflictRow? {
        conflicts.first { $0.holeIndex == hole } ?? conflicts.first
    }

    // MARK: Valget

    /// Ett av de to tallene i arket.
    struct Option: Equatable, Identifiable, Sendable {
        let strokes: Int
        /// «Ført av Kåre kl. 18:42» eller «Ført av deg kl. 18:42».
        let byline: String
        /// Tallet som står i føringen nå.
        let isCurrent: Bool
        var id: Int { strokes }
    }

    /// Begge tallene, eldste føring først. `current` er tallet som står (nil: ikke kjent).
    static func options(_ conflict: HoleConflictRow, current: Int?, me: UUID?,
                        name: (UUID) -> String?) -> [Option] {
        let current = current ?? conflict.keptStrokes
        func option(_ strokes: Int, by: UUID?, at: Date) -> Option {
            Option(strokes: strokes, byline: byline(by: by, at: at, me: me, name: name), isCurrent: strokes == current)
        }
        return [
            option(conflict.otherStrokes, by: conflict.otherBy, at: conflict.otherAt),
            option(conflict.keptStrokes, by: conflict.keptBy, at: conflict.keptAt),
        ]
    }

    /// «Ført av Kåre kl. 18:42».
    static func byline(by: UUID?, at: Date, me: UUID?, name: (UUID) -> String?) -> String {
        let who: String
        if let by, by == me {
            who = "deg"
        } else {
            who = by.flatMap(name) ?? "ukjent markør"
        }
        return "Ført av \(who) kl. \(clock(at))"
    }

    /// «18:42» i Oslo-tid.
    static func clock(_ date: Date) -> String {
        let c = EveningDates.osloCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Kan tallet velges? Serveren godtar bare ett av de to (`resolve_hole_conflict`, 22023).
    static func isValidChoice(_ strokes: Int, for conflict: HoleConflictRow) -> Bool {
        strokes == conflict.keptStrokes || strokes == conflict.otherStrokes
    }

    // MARK: Tekstene

    /// Stripa over føringen: «Hull 5: to markører førte ulikt for Kåre.» eller
    /// «3 hull har ulike tall fra to markører.» nil uten konflikter.
    static func stripeText(_ conflicts: [HoleConflictRow], holeNumber: (Int) -> Int, name: (UUID) -> String) -> String? {
        guard let first = conflicts.first else { return nil }
        if conflicts.count == 1 {
            return "Hull \(holeNumber(first.holeIndex)): to markører førte ulikt for \(name(first.memberID))."
        }
        let holes = Set(conflicts.map(\.holeIndex))
        if holes.count == 1 {
            return "Hull \(holeNumber(first.holeIndex)): to markører førte ulikt for \(conflicts.count) spillere."
        }
        return "\(holes.count) hull har ulike tall fra to markører."
    }

    /// Linja i «I kveld»: «2 hull har ulike tall fra to markører». nil uten konflikter.
    static func organizerText(_ conflicts: [HoleConflictRow]) -> String? {
        let holes = Set(conflicts.map { "\($0.roundID)-\($0.holeIndex)" }).count
        return holes == 0 ? nil : "\(holes) hull har ulike tall fra to markører"
    }
}

/// Lesing og valg mot sql/055.
enum MarkerConflictQueries {
    /// Alle konfliktene i rundene (også løste, så en utdatert rad ikke vises: `MarkerConflicts.open`).
    static func conflicts(client: SupabaseClient, roundIDs: [UUID]) async throws -> [HoleConflictRow] {
        guard !roundIDs.isEmpty else { return [] }
        return try await client.from("hole_score_conflicts")
            .select(HoleConflictRow.columns)
            .in("round_id", values: roundIDs.map(\.uuidString))
            .execute().value
    }

    /// «Bruk 5 slag»: tallet gjelder, og konflikten er løst. 22023 = ikke ett av de to, 42501 = ikke lov.
    static func resolve(client: SupabaseClient, conflictID: UUID, strokes: Int) async throws {
        struct Params: Encodable {
            let p_conflict: UUID
            let p_strokes: Int
        }
        try await client.rpc("resolve_hole_conflict", params: Params(p_conflict: conflictID, p_strokes: strokes))
            .execute()
    }
}
