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
    /// som i PWA-en: arrangøren tar ut dem som ikke kommer. Ventelista er ikke med (sql/045).
    static func initial(roster: [ClubMemberRow], signups: [SignupRow]) -> (ids: [UUID], source: Source) {
        let coming = Set(signups.filter(\.isConfirmed).map(\.memberID))
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

/// Hvordan matchene trekkes (steg 6, `formats.drawMethod`): etter tabellen (som i dag), tilfeldig uten
/// gjentakelser (med møtene fra turneringens tidligere runder), eller manuelt (arrangøren setter dem opp).
nonisolated struct MatchDrawPlan: Equatable, Sendable {
    var method: Ruleset.DrawMethod
    /// Hvor mange ganger hvert par har møtt hverandre før (`Draw.pairKey` → antall).
    var previous: [String: Int]

    /// Som i dag: etter tabellen, uten historikk.
    static let standings = MatchDrawPlan(method: .standings, previous: [:])

    /// Planen for regelsettet, med møtene i rundene som er spilt (`Draw.meetings`, regnet fra radene).
    /// Kladder og runden som settes opp, teller ikke.
    static func make(rules: Ruleset, rounds: [RoundRow], matches: [RoundMatchRow],
                     players: [UUID: [RoundPlayerRow]], excluding roundID: UUID? = nil) -> MatchDrawPlan {
        let played = Set(rounds.filter { $0.status != .draft && $0.id != roundID }.map(\.id))
        return MatchDrawPlan(method: rules.formats.drawMethod,
                             previous: meetings(matches.filter { played.contains($0.roundID) }, players: players))
    }

    /// `Draw.meetings` for lagrede matcher: motstanderne møter hverandre; i en trekant møter alle tre
    /// hverandre. En lagmatch slår opp lagene i rundens spillere (`team_no`).
    static func meetings(_ matches: [RoundMatchRow], players: [UUID: [RoundPlayerRow]]) -> [String: Int] {
        var out: [String: Int] = [:]
        for m in matches {
            if let a = m.teamA, let b = m.teamB {
                let roster = players[m.roundID] ?? []
                let sideA = roster.filter { $0.teamNo == a }.map(\.memberID.uuidString)
                let sideB = roster.filter { $0.teamNo == b }.map(\.memberID.uuidString)
                for x in sideA { for y in sideB where x != y { out[Draw.pairKey(x, y), default: 0] += 1 } }
                continue
            }
            let ids = [m.playerA, m.playerB, m.playerC].compactMap { $0?.uuidString }
            if m.playerC != nil {
                Draw.addMeetings([ids], to: &out)
            } else if ids.count == 2 {
                out[Draw.pairKey(ids[0], ids[1]), default: 0] += 1
            }
        }
        return out
    }

    /// Hvor mange møter i matchene som har vært før.
    func repeats(in matches: [MatchDraft]) -> Int {
        Draw.repeats(matches.filter { !$0.isTeamMatch }.map { $0.members().map(\.uuidString) }, previous: previous)
    }
}

nonisolated enum MatchPlanner {
    /// Trekningen etter planen: etter tabellen (`drawIndividual`, som i dag), tilfeldig uten gjentakelser
    /// (`Draw.avoidingRepeats` med `seed`), eller ingen matcher når arrangøren setter dem opp selv.
    static func draw(_ participants: [ClubMemberRow], plan: MatchDrawPlan, seed: UInt64) -> [MatchDraft] {
        switch plan.method {
        case .standings:
            return drawIndividual(participants)
        case .manual:
            return []
        case .avoidRepeats:
            let players = participants.map { Player(id: $0.id.uuidString, name: $0.displayName) }
            return Draw.avoidingRepeats(players, previous: plan.previous, seed: seed).compactMap(matchDraft)
        }
    }

    private static func matchDraft(_ ids: [String]) -> MatchDraft? {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        guard uuids.count >= 2 else { return nil }
        return .players(uuids[0], uuids[1], uuids.count > 2 ? uuids[2] : nil)
    }

    /// `trekkMatcher` (første omgang) for de som er med. Uten stilling sorteres det på navn (norsk).
    static func drawIndividual(_ participants: [ClubMemberRow], standing: [UUID: Double] = [:]) -> [MatchDraft] {
        let players = participants.map { Player(id: $0.id.uuidString, name: $0.displayName) }
        let byString = Dictionary(uniqueKeysWithValues: standing.map { ($0.key.uuidString, $0.value) })
        return Triangle.drawMatches(players, round: 0, standing: byString).compactMap(matchDraft)
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

/// Linja under matchene: hvordan de trekkes, og hvor mange møter som har vært før. Nil som i dag (etter tabellen).
nonisolated enum MatchDrawText {
    static func footer(plan: MatchDrawPlan, matches: [MatchDraft]) -> String? {
        switch plan.method {
        case .standings:
            return nil
        case .manual:
            return "Du setter opp matchene selv."
        case .avoidRepeats:
            let repeats = plan.repeats(in: matches)
            let tail = switch repeats {
            case 0: "Ingen har møtt hverandre før."
            case 1: "1 møte har vært før."
            default: "\(repeats) møter har vært før."
            }
            return "Trekkes tilfeldig uten gjentakelser. " + tail
        }
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

    /// Tilfeldige lag (`Teams.random`): deltakerne stokkes med frøet, så fylles lagstørrelsene fra formen
    /// som i `suggested`. Tomt når formen ikke går opp med antallet.
    static func random(participants: [UUID], form: CompetitionForm, maxPerBay: Int, seed: UInt64) -> [UUID: Int] {
        let shuffled = Teams.random(participants.map(\.uuidString), teamSize: 1, seed: seed)
        let order = participants.sorted { (shuffled[$0.uuidString] ?? 0) < (shuffled[$1.uuidString] ?? 0) }
        return suggested(participants: order, form: form, maxPerBay: maxPerBay)
    }

    /// Bytter lagene til to spillere (`Teams.swap`). Uendret når de er på samme lag eller en mangler lag.
    static func swap(_ teams: [UUID: Int], _ a: UUID, _ b: UUID) -> [UUID: Int] {
        let swapped = Teams.swap(Dictionary(uniqueKeysWithValues: teams.map { ($0.key.uuidString, $0.value) }),
                                 a.uuidString, b.uuidString)
        return Dictionary(uniqueKeysWithValues: swapped.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    /// `lesLagOppsett`: går lagene opp? `nil` = i orden. Bare deltakerne telles, og alle må ha lag.
    static func problem(teams: [UUID: Int], participants: [UUID], form: CompetitionForm, maxPerBay: Int,
                        term: GroupTerm = .bay) -> String? {
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
                return "Lag \(tooBig.map(String.init).joined(separator: " og ")) har flere enn \(maxPerBay). Et lag får ikke plass i en \(term.singular) da."
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
