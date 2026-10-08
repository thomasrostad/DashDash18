import Foundation
import GolfgutuCore

// MARK: - Deltakere

/// Hvem som er med i runden når oppsettet åpnes (`startRundeDeltakere`, `aapneRedigerKladd`).
nonisolated enum RoundParticipants {
    enum Source: Equatable, Sendable {
        /// De som har svart «Kommer».
        case signups
        /// Ingen har svart «Kommer» ennå, så alle i troppen står som med (`paameldingSierMed`).
        case everyone
        /// Kladden som redigeres: de som er satt opp.
        case saved
    }

    /// De som har svart «Kommer», i troppens rekkefølge. Har ingen svart «Kommer», er alle med,
    /// som i PWA-en: arrangøren tar ut dem som ikke kommer.
    static func initial(roster: [ClubMemberRow], signups: [SignupRow]) -> (ids: [UUID], source: Source) {
        let coming = Set(signups.filter { $0.status == .yes }.map(\.memberID))
        let ids = roster.filter { coming.contains($0.id) }.map(\.id)
        if ids.isEmpty { return (roster.map(\.id), .everyone) }
        return (ids, .signups)
    }

    /// Rediger kladd: de som er satt opp, i troppens rekkefølge. Er ingen satt opp ennå, gjelder påmeldingen.
    static func forDraft(roster: [ClubMemberRow], saved: [RoundPlayerRow], signups: [SignupRow]) -> (ids: [UUID], source: Source) {
        let inRound = Set(saved.map(\.memberID))
        let ids = roster.filter { inRound.contains($0.id) }.map(\.id)
        if ids.isEmpty { return initial(roster: roster, signups: signups) }
        return (ids, .saved)
    }
}

// MARK: - Matcher

/// En match i oppsettet: to spillere (tre i en trekant), eller to lag.
nonisolated struct MatchDraft: Equatable, Sendable {
    var playerA: UUID?
    var playerB: UUID?
    var playerC: UUID?
    var teamA: Int?
    var teamB: Int?
    /// Manuelt resultat fra en lagret match (`a`, `b`, `halved`). Beholdes uendret.
    var result: String?

    static func players(_ a: UUID, _ b: UUID, _ c: UUID? = nil) -> MatchDraft {
        MatchDraft(playerA: a, playerB: b, playerC: c)
    }

    static func teams(_ a: Int, _ b: Int) -> MatchDraft {
        MatchDraft(teamA: a, teamB: b)
    }

    var isTeamMatch: Bool { teamA != nil || teamB != nil }
    var isTriangle: Bool { playerC != nil }

    /// Spillerne i matchen. For en lagmatch: lagkameratene slått opp i `teams`.
    func members(teams: [UUID: Int] = [:]) -> [UUID] {
        if isTeamMatch {
            return teams.filter { $0.value == teamA || $0.value == teamB }
                .sorted { ($0.value == teamA ? 0 : 1, $0.key.uuidString) < ($1.value == teamA ? 0 : 1, $1.key.uuidString) }
                .map(\.key)
        }
        return [playerA, playerB, playerC].compactMap { $0 }
    }

    init(playerA: UUID? = nil, playerB: UUID? = nil, playerC: UUID? = nil,
         teamA: Int? = nil, teamB: Int? = nil, result: String? = nil) {
        self.playerA = playerA
        self.playerB = playerB
        self.playerC = playerC
        self.teamA = teamA
        self.teamB = teamB
        self.result = result
    }

    init(_ row: RoundMatchRow) {
        self.init(playerA: row.playerA, playerB: row.playerB, playerC: row.playerC,
                  teamA: row.teamA, teamB: row.teamB, result: row.result)
    }
}

nonisolated enum MatchPlanner {
    /// `trekkMatcher` (første omgang) for de som er med. Uten stilling sorteres det på navn (norsk).
    static func drawIndividual(_ participants: [ClubMemberRow], standing: [UUID: Double] = [:]) -> [MatchDraft] {
        let players = participants.map { Player(id: $0.id.uuidString, name: $0.displayName) }
        let byString = Dictionary(uniqueKeysWithValues: standing.map { ($0.key.uuidString, $0.value) })
        return Triangle.drawMatches(players, round: 0, standing: byString).compactMap { ids in
            let uuids = ids.compactMap(UUID.init(uuidString:))
            guard uuids.count >= 2 else { return nil }
            return .players(uuids[0], uuids[1], uuids.count > 2 ? uuids[2] : nil)
        }
    }

    /// Lag mot lag i lagnummerets rekkefølge: 1 mot 2, 3 mot 4 (`handleStartRunde`).
    static func teamMatches(_ teams: [UUID: Int]) -> [MatchDraft] {
        let numbers = Array(Set(teams.values)).sorted()
        return stride(from: 0, to: numbers.count - 1, by: 2).map { .teams(numbers[$0], numbers[$0 + 1]) }
    }

    /// Kan de lagrede matchene stå? Bare når de samme spillerne er med (`behold` i `handleStartRunde`).
    /// Individuell form: alle i matchene, og bare dem, er med. Lagform: matchene er lagene, så lag mot lag gjelder.
    static func canKeep(_ matches: [MatchDraft], participants: [UUID], teams: [UUID: Int], isTeamForm: Bool) -> Bool {
        guard !matches.isEmpty else { return false }
        if isTeamForm {
            let numbers = Set(teams.values)
            return matches.allSatisfy { m in
                guard m.isTeamMatch, let a = m.teamA, let b = m.teamB else { return false }
                return numbers.contains(a) && numbers.contains(b)
            }
        }
        guard matches.allSatisfy({ !$0.isTeamMatch }) else { return false }
        let inMatches = matches.flatMap { $0.members() }
        return Set(inMatches) == Set(participants) && inMatches.count == Set(inMatches).count
    }

    /// Hva som er galt med matchene. Tom liste = i orden.
    static func problems(_ matches: [MatchDraft], participants: [UUID], teams: [UUID: Int],
                         names: [UUID: String]) -> [String] {
        var problems: [String] = []
        let included = Set(participants)
        var seen: [UUID: Int] = [:]
        for (i, match) in matches.enumerated() {
            let number = i + 1
            if match.isTeamMatch {
                guard let a = match.teamA, let b = match.teamB, a != b else {
                    problems.append("Match \(number) mangler to forskjellige lag.")
                    continue
                }
                let numbers = Set(teams.values)
                if !numbers.contains(a) || !numbers.contains(b) {
                    problems.append("Match \(number) har et lag uten spillere.")
                }
                continue
            }
            let ids = match.members()
            guard match.playerA != nil, match.playerB != nil, Set(ids).count == ids.count else {
                problems.append("Match \(number) mangler to forskjellige spillere.")
                continue
            }
            for id in ids {
                if !included.contains(id) {
                    problems.append("\(names[id] ?? "En spiller") i match \(number) er ikke med i runden.")
                }
                if let other = seen[id] {
                    problems.append("\(names[id] ?? "En spiller") står i både match \(other) og \(number).")
                }
                seen[id] = number
            }
        }
        return problems
    }
}

// MARK: - Lag

nonisolated enum TeamPlanner {
    /// Forslag til lag: lagstørrelsene fra `oppsettForAntall`, fylt i deltakernes rekkefølge.
    /// Tomt når formen ikke er en lagform eller ikke går opp med antallet.
    static func suggested(participants: [UUID], form: CompetitionForm, maxPerBay: Int) -> [UUID: Int] {
        guard case .teams(let split, _, _) = form.setup(players: participants.count, maxPerBay: maxPerBay) else { return [:] }
        var teams: [UUID: Int] = [:]
        var i = 0
        for (number, size) in split.sizes.enumerated() {
            for _ in 0..<size where i < participants.count {
                teams[participants[i]] = number + 1
                i += 1
            }
        }
        return teams
    }

    /// `lesLagOppsett`: går lagene opp? `nil` = i orden. Bare deltakerne telles, og alle må ha lag.
    static func problem(teams: [UUID: Int], participants: [UUID], form: CompetitionForm, maxPerBay: Int) -> String? {
        let withoutTeam = participants.filter { teams[$0] == nil }.count
        var counts: [Int: Int] = [:]
        for id in participants {
            if let team = teams[id] { counts[team, default: 0] += 1 }
        }
        if counts.isEmpty { return "Sett opp lagene før du starter runden." }
        if counts.count < 2 { return "Det må være minst to lag." }
        if withoutTeam > 0 {
            return withoutTeam == 1 ? "Én av deltakerne har ikke lag." : "\(withoutTeam) av deltakerne har ikke lag."
        }
        let numbers = counts.keys.sorted()
        if form.allowsUnevenTeams {
            let tooBig = numbers.filter { counts[$0]! > maxPerBay }
            if !tooBig.isEmpty {
                return "Lag \(tooBig.map(String.init).joined(separator: " og ")) har flere enn \(maxPerBay). Et lag får ikke plass i en bås da."
            }
            return nil
        }
        let wrong = numbers.filter { counts[$0]! != form.teamSize }
        if !wrong.isEmpty {
            return "Lag \(wrong.map(String.init).joined(separator: " og ")) har ikke \(form.teamSize) spillere."
        }
        return nil
    }
}
