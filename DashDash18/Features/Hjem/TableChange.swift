import Foundation
import GolfgutuCore

// Plassbytte i tabellen som hendelse (fase 19, `table_changed`): tabellen før og etter at en runde
// er låst, regnet av regelmotoren (Tavla for jakkeracet, `LeagueStandings` for liga og morro), og
// teksten. Ren logikk; loggingen ligger i `TableChangeLogger`, og teksten står likt i
// `supabase/functions/push-send/logic.ts` (`tableHeadline`).

/// En plass i en tabell, uansett type.
nonisolated struct TableStanding: Equatable, Sendable {
    /// Spilleren slik tabellen kjenner hen (`club_members.id` i klubbens konkurranse, ellers `Entrant.id`).
    let id: UUID
    let place: Int
    let points: Double
}

/// En hel tabell. `hasResults` er false før første runde: da er plassene bare navnerekkefølgen.
nonisolated struct TableBoard: Equatable, Sendable {
    var standings: [TableStanding]
    var hasResults: Bool

    init(standings: [TableStanding], hasResults: Bool) {
        self.standings = standings
        self.hasResults = hasResults
    }

    /// Jakkeracet (og andre konkurranser som regnes som Tavla).
    init(_ tavla: TavlaStandings) {
        standings = tavla.rows.map { TableStanding(id: $0.memberID, place: $0.place, points: $0.total) }
        hasResults = tavla.eveningsPlayed > 0 || tavla.rows.contains { $0.total != 0 }
    }

    /// Liga og morroturnering.
    init(_ league: LeagueStandings) {
        standings = league.rows.map { TableStanding(id: $0.entrant.id, place: $0.place, points: $0.total) }
        hasResults = league.hasResults
    }
}

nonisolated enum TableChange {
    /// Topp 3 står alltid i linja (minitabellen på Hjem).
    static let topCount = 3
    /// Linja holder seg godt under 8 kB (`activity.data`, sql/008) også i store konkurranser.
    static let maxSpots = 40

    /// Plassene etter runden: topp 3 og alle som flyttet seg, i tabellens rekkefølge. Nil når ingen
    /// flyttet seg, eller tabellen fortsatt er tom. Før første runde har ingen en plass å komme fra.
    static func spots(before: TableBoard, after: TableBoard) -> [ActivityTableSpot]? {
        guard after.hasResults else { return nil }
        var previous: [UUID: Int] = [:]
        if before.hasResults {
            for s in before.standings { previous[s.id] = min(previous[s.id] ?? .max, s.place) }
        }
        let sorted = after.standings.sorted { $0.place < $1.place }
        let moved = Set(sorted.filter { s in previous[s.id].map { $0 != s.place } ?? false }.map(\.id))
        if before.hasResults && moved.isEmpty { return nil }
        return sorted
            .filter { $0.place <= topCount || moved.contains($0.id) }
            .prefix(maxSpots)
            .map { ActivityTableSpot(member: $0.id, place: $0.place, from: previous[$0.id], points: rounded($0.points)) }
    }

    /// Hendelsen for konkurransen, eller nil når tabellen står som før.
    static func event(competition: CompetitionRow, roundNo: Int?, before: TableBoard,
                      after: TableBoard) -> ActivityEvent? {
        guard let table = spots(before: before, after: after) else { return nil }
        return .tableChanged(competition: competition.id, competitionName: competition.name, roundNo: roundNo,
                             table: table)
    }

    /// To desimaler holder for poengene (halve og kvarte poeng finnes).
    static func rounded(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}

/// Teksten for et plassbytte. `headline` er den samme for alle (Varsler og push), `personal` er sett
/// fra deg (Hjem). Samme regler som `tableHeadline` i push-send.
nonisolated enum TableChangeText {
    enum Kind: Equatable, Sendable {
        /// Første runde: «Anders leder Jakkeracet».
        case leads
        /// Ny leder: «Anders har tatt ledelsen i Jakkeracet».
        case tookLead
        /// Den som klatret mest: «Anders klatret til 3. plass i Jakkeracet».
        case climbed
    }

    /// « etter runde 3», eller ingenting.
    static func after(_ roundNo: Int?) -> String {
        guard let roundNo, roundNo > 0 else { return "" }
        return " etter runde \(roundNo)"
    }

    /// Den linja handler om. Ny leder går foran; ellers den som klatret flest plasser (likt: best
    /// plass). Nil når ingen klatret.
    static func subject(_ table: [ActivityTableSpot]) -> (spot: ActivityTableSpot, kind: Kind)? {
        if let leader = table.first(where: { $0.place == 1 }) {
            if table.allSatisfy({ $0.from == nil }) { return (leader, .leads) }
            if leader.from != 1 { return (leader, .tookLead) }
        }
        let climber = table
            .filter { ($0.move ?? 0) > 0 }
            .min { a, b in a.move! != b.move! ? a.move! > b.move! : a.place < b.place }
        return climber.map { ($0, .climbed) }
    }

    static func headline(table: [ActivityTableSpot], competitionName: String, roundNo: Int?,
                         name: (UUID) -> String) -> String {
        let tail = after(roundNo)
        guard let (spot, kind) = subject(table) else {
            return "Tabellen i \(competitionName) er oppdatert\(tail)"
        }
        let who = name(spot.member)
        switch kind {
        case .leads: return "\(who) leder \(competitionName)\(tail)"
        case .tookLead: return "\(who) har tatt ledelsen i \(competitionName)\(tail)"
        case .climbed: return "\(who) klatret til \(spot.place). plass i \(competitionName)\(tail)"
        }
    }

    /// Sett fra deg (`me` er medlems- og profil-id-ene dine): «Du klatret til 3. plass i …»,
    /// «Anders gikk forbi deg i …», «Du falt til 5. plass i …». Står du ikke i linja, er det den
    /// vanlige teksten.
    static func personal(table: [ActivityTableSpot], competitionName: String, roundNo: Int?, me: Set<UUID>,
                         name: (UUID) -> String) -> String {
        let tail = after(roundNo)
        guard let mine = table.first(where: { me.contains($0.member) }) else {
            return headline(table: table, competitionName: competitionName, roundNo: roundNo, name: name)
        }
        if let move = mine.move, move > 0 {
            return mine.place == 1
                ? "Du tok ledelsen i \(competitionName)\(tail)"
                : "Du klatret til \(mine.place). plass i \(competitionName)\(tail)"
        }
        if let move = mine.move, move < 0, let from = mine.from {
            let passers = table.filter { s in s.place < mine.place && (s.from.map { $0 > from } ?? false) }
            if !passers.isEmpty {
                return NorwegianList.join(passers.map { name($0.member) }) + " gikk forbi deg i \(competitionName)\(tail)"
            }
            return "Du falt til \(mine.place). plass i \(competitionName)\(tail)"
        }
        if mine.place == 1, table.allSatisfy({ $0.from == nil }) {
            return "Du leder \(competitionName)\(tail)"
        }
        return headline(table: table, competitionName: competitionName, roundNo: roundNo, name: name)
    }

    /// Kort til oppsummeringen på Hjem, uten konkurransen sist: «du klatret til 3. plass i Jakkeracet»
    /// med liten forbokstav. Nil når du ikke flyttet deg.
    static func summaryPhrase(table: [ActivityTableSpot], competitionName: String, me: Set<UUID>,
                              name: (UUID) -> String) -> String? {
        guard let mine = table.first(where: { me.contains($0.member) }), let move = mine.move, move != 0,
              let from = mine.from else { return nil }
        if move > 0 {
            return mine.place == 1 ? "du tok ledelsen i \(competitionName)"
                : "du klatret til \(mine.place). plass i \(competitionName)"
        }
        let passers = table.filter { s in s.place < mine.place && (s.from.map { $0 > from } ?? false) }
        if !passers.isEmpty {
            return NorwegianList.join(passers.map { name($0.member) }) + " gikk forbi deg i \(competitionName)"
        }
        return "du falt til \(mine.place). plass i \(competitionName)"
    }
}
