import Foundation
import GolfgutuCore

/// En rad fra `event_lineups` (sql/076): én spiller i en kladd arrangøren har vist for spillerne.
nonisolated struct EventLineupRow: Decodable, Equatable, Sendable {
    let roundID: UUID
    let roundNo: Int
    let roundName: String?
    let format: String?
    /// `18:00:00`.
    let teeTime: String?
    let memberID: UUID
    let name: String
    let bayNo: Int?
    let teamNo: Int?
    let isMarker: Bool
    let sharedAt: Date?
    /// `rounds.venue`. 076 gir den ikke ennå: da er det bås (simulator).
    var venue: String? = nil

    enum CodingKeys: String, CodingKey {
        case roundID = "round_id"
        case roundNo = "round_no"
        case roundName = "round_name"
        case format
        case teeTime = "tee_time"
        case memberID = "member_id"
        case name
        case bayNo = "bay_no"
        case teamNo = "team_no"
        case isMarker = "is_marker"
        case sharedAt = "shared_at"
        case venue
    }
}

/// Oppstillingen for kvelden før runden starter (sql/076): ditt lag og din bås øverst, og hele
/// oppstillingen runde for runde, bås for bås, lag for lag. Bygges fra radene og medlems-id-ene dine.
nonisolated struct EveningLineup: Equatable, Sendable {
    struct Player: Equatable, Sendable, Identifiable {
        let id: UUID
        let name: String
        let isMarker: Bool
        let isMe: Bool
    }

    struct Team: Equatable, Sendable, Identifiable {
        /// nil: individuelt (ingen lag).
        let number: Int?
        let players: [Player]
        var id: Int { number ?? -1 }
        /// «Lag 3».
        var title: String? { number.map(EveningLineup.teamTitle) }
    }

    struct Group: Equatable, Sendable, Identifiable {
        /// nil: ikke fordelt på bås.
        let number: Int?
        let teams: [Team]
        var id: Int { number ?? -1 }
    }

    struct Round: Equatable, Sendable, Identifiable {
        let id: UUID
        let number: Int
        /// «Runde 1», eller navnet arrangøren ga runden.
        let title: String
        /// «Fourball · kl. 18:00».
        let detail: String?
        let term: GroupTerm
        let groups: [Group]

        /// «Bås 2», «Uten bås».
        func groupTitle(_ group: Group) -> String {
            group.number.map(term.numbered) ?? "Uten \(term.singular)"
        }
    }

    /// Din plass i én runde.
    struct Mine: Equatable, Sendable, Identifiable {
        let roundID: UUID
        let roundTitle: String
        let term: GroupTerm
        let bayNo: Int?
        let teamNo: Int?
        let isMarker: Bool
        /// Lagkameratene (samme lag), sortert.
        let teammates: [String]
        /// Lagene du møter i båsen (andre lag i samme bås).
        let opponents: [Team]
        /// De andre i båsen uten lag (individuelle former).
        let bayMates: [String]
        var id: UUID { roundID }

        /// «Lag 3 med Preben Huseby · Bås 2 mot Lag 4 (Sebastian Thuen og Thomas Seim Breivik)».
        var summary: String {
            var parts: [String] = []
            if let teamNo {
                var team = EveningLineup.teamTitle(teamNo)
                if !teammates.isEmpty { team += " med " + NorwegianList.join(teammates) }
                parts.append(team)
                if let bayNo {
                    var bay = term.numbered(bayNo)
                    let against = opponents.map { team in
                        let names = NorwegianList.join(team.players.map(\.name))
                        return team.title.map { "\($0) (\(names))" } ?? names
                    }
                    if !against.isEmpty { bay += " mot " + NorwegianList.join(against) }
                    parts.append(bay)
                }
            } else if let bayNo {
                var bay = term.numbered(bayNo)
                if !bayMates.isEmpty { bay += " med " + NorwegianList.join(bayMates) }
                parts.append(bay)
            } else {
                parts.append("Du er satt opp i \(roundTitle.lowercased())")
            }
            return parts.joined(separator: " · ")
        }

        /// «Du er markør i båsen».
        var markerText: String? {
            isMarker ? "Du er \(term.marker) i \(term.definite)" : nil
        }
    }

    let rounds: [Round]
    /// Der du er satt opp, én per runde. Tom: du er ikke i oppstillingen.
    let mine: [Mine]

    /// nil når det ikke er noe å vise (ingen rader).
    init?(rows: [EventLineupRow], viewer: Set<UUID>) {
        guard !rows.isEmpty else { return nil }
        let byRound = Dictionary(grouping: rows, by: \.roundID)
        let ordered = byRound.values.compactMap(\.first).sorted { $0.roundNo < $1.roundNo }
        var rounds: [Round] = []
        var mine: [Mine] = []
        for first in ordered {
            let roundRows = byRound[first.roundID] ?? []
            let round = Self.round(first, rows: roundRows, viewer: viewer)
            rounds.append(round)
            if let me = roundRows.first(where: { viewer.contains($0.memberID) }) {
                mine.append(Self.mine(me, round: round, rows: roundRows, viewer: viewer))
            }
        }
        self.rounds = rounds
        self.mine = mine
    }

    /// Overskriften på kortet: «Laget ditt», «Båsen din» / «Flighten din», ellers «Oppstillingen».
    var title: String {
        guard let first = mine.first else { return "Oppstillingen" }
        if first.teamNo != nil { return "Laget ditt" }
        if first.bayNo != nil { return "\(first.term.definiteTitle) din" }
        return "Oppstillingen"
    }

    /// Teksten når du ikke er satt opp: «Oppstillingen for runde 1 er klar.»
    var notInLineupText: String {
        let titles = rounds.map { $0.title.lowercased() }
        return "Oppstillingen for \(NorwegianList.join(titles)) er klar."
    }

    /// Rundenavnet foran din plass, bare når kvelden har flere runder.
    var showsRoundTitles: Bool { rounds.count > 1 }

    static func teamTitle(_ number: Int) -> String { "Lag \(number)" }

    // MARK: Bygging

    private static func round(_ first: EventLineupRow, rows: [EventLineupRow], viewer: Set<UUID>) -> Round {
        let name = first.roundName?.trimmingCharacters(in: .whitespaces) ?? ""
        var detail: [String] = []
        if let format = first.format, !format.isEmpty { detail.append(CompetitionForm.form(id: format).name) }
        if let time = EveningDates.timeText(first.teeTime) { detail.append("kl. \(time)") }
        let groups = Dictionary(grouping: rows, by: \.bayNo)
            .sorted { lessNilLast($0.key, $1.key) }
            .map { bay, bayRows in
                Group(number: bay, teams: Dictionary(grouping: bayRows, by: \.teamNo)
                    .sorted { lessNilLast($0.key, $1.key) }
                    .map { team, teamRows in Team(number: team, players: players(teamRows, viewer: viewer)) })
            }
        return Round(id: first.roundID, number: first.roundNo,
                     title: name.isEmpty ? "Runde \(first.roundNo)" : name,
                     detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
                     term: GroupTerm.for(stored: first.venue), groups: groups)
    }

    private static func mine(_ me: EventLineupRow, round: Round, rows: [EventLineupRow], viewer: Set<UUID>) -> Mine {
        let others = rows.filter { !viewer.contains($0.memberID) }
        let teammates = me.teamNo.map { team in others.filter { $0.teamNo == team } } ?? []
        // Uten bås er det ingen å møte, og ingen båskamerater.
        let bay = me.bayNo.map { bay in others.filter { $0.bayNo == bay } } ?? []
        let opponents = me.teamNo == nil ? [] : round.groups.first { $0.number == me.bayNo && me.bayNo != nil }?
            .teams.filter { $0.number != me.teamNo }
            .map { Team(number: $0.number, players: $0.players.filter { !$0.isMe }) }
            .filter { !$0.players.isEmpty } ?? []
        return Mine(roundID: round.id, roundTitle: round.title, term: round.term, bayNo: me.bayNo, teamNo: me.teamNo,
                    isMarker: me.isMarker, teammates: sortedNames(teammates),
                    opponents: opponents, bayMates: me.teamNo == nil ? sortedNames(bay) : [])
    }

    private static func players(_ rows: [EventLineupRow], viewer: Set<UUID>) -> [Player] {
        rows.sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
            .map { Player(id: $0.memberID, name: $0.name, isMarker: $0.isMarker, isMe: viewer.contains($0.memberID)) }
    }

    private static func sortedNames(_ rows: [EventLineupRow]) -> [String] {
        rows.map(\.name).sorted(by: NorwegianSort.areInIncreasingOrder)
    }

    private static func lessNilLast(_ a: Int?, _ b: Int?) -> Bool {
        switch (a, b) {
        case let (a?, b?): a < b
        case (_?, nil): true
        default: false
        }
    }
}
