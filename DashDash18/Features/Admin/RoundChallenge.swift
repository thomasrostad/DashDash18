import Foundation

// «Challenge etter runden»: en konkurranse når alle er inne (f.eks. CP knockout), der vinneren får
// tilleggspoeng (sql/072). Ingen egne tabeller: hver vinner er én rad i point_adjustments med kvelden og
// en grunn som «CP knockout, bås 1» eller «CP knockout runde 2, bås 1» (samme form som 22.10).
// Samme regler som adminpanelet (web/admin/src/kvelden/challenge.ts). Ingen spillregler her.

nonisolated enum ChallengeScope: String, CaseIterable, Sendable {
    /// Én vinner per bås eller flight.
    case group
    /// Én vinner for hele runden.
    case all
}

nonisolated struct ChallengeSetup: Equatable, Sendable {
    var name: String
    var points: Double
    var scope: ChallengeScope
    /// Runde 1, 2, … av challengen samme kveld.
    var round: Int

    static let standard = ChallengeSetup(name: "CP knockout", points: 0.25, scope: .group, round: 1)
}

/// En gruppe som får én vinner.
nonisolated struct ChallengeGroup: Equatable, Identifiable, Sendable {
    /// Bås- eller flightnummer; 0 er «hele runden» (eller «uten bås»).
    let no: Int
    let title: String
    let members: [UUID]
    let reason: String
    var id: Int { no }
}

nonisolated enum RoundChallenge {
    /// Høyst så mange runder av challengen en kveld.
    static let maxRounds = 9
    /// Steget i poengvelgeren: kvarte poeng.
    static let step = 0.25

    /// «CP knockout» i runde 1, «CP knockout runde 2» etter.
    static func base(_ name: String, round: Int) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return round > 1 ? "\(n) runde \(round)" : n
    }

    /// Grunnen som lagres: «CP knockout runde 2, bås 1», eller bare navnet for hele runden. Høyst 80 tegn
    /// (`Tilleggspoeng.reasonLimit`): navnet kortes, halen står.
    static func reason(_ name: String, round: Int, scope: ChallengeScope, term: GroupTerm, groupNo: Int) -> String {
        let tail = scope == .group && groupNo > 0 ? ", \(term.singular) \(groupNo)" : ""
        let room = Tilleggspoeng.reasonLimit - base("", round: round).count - tail.count
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max(1, room)))
        return base(trimmed, round: round) + tail
    }

    /// Gruppene som får en vinner hver. Per bås/flight når spillerne er delt i grupper, ellers hele runden
    /// som én. Spillere uten gruppe (0) havner i «Uten bås» sist når de andre har gruppe.
    static func groups(_ setup: ChallengeSetup, players: [(memberID: UUID, group: Int)], term: GroupTerm) -> [ChallengeGroup] {
        let grouped = setup.scope == .group && players.contains { $0.group > 0 }
        guard grouped else {
            return [ChallengeGroup(no: 0, title: "Hele runden", members: players.map(\.memberID),
                                   reason: reason(setup.name, round: setup.round, scope: .all, term: term, groupNo: 0))]
        }
        var order: [Int] = []
        var by: [Int: [UUID]] = [:]
        for p in players {
            if by[p.group] == nil { order.append(p.group) }
            by[p.group, default: []].append(p.memberID)
        }
        let sorted = order.sorted { a, b in a == 0 ? false : b == 0 ? true : a < b }
        return sorted.map { no in
            ChallengeGroup(no: no, title: no == 0 ? "Uten \(term.singular)" : term.numbered(no), members: by[no] ?? [],
                           reason: reason(setup.name, round: setup.round, scope: .group, term: term, groupNo: no))
        }
    }

    /// Navn, poeng og runde må være i orden før noen vinner kan registreres. nil: i orden.
    static func problem(_ setup: ChallengeSetup) -> String? {
        if setup.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Gi challengen et navn." }
        if !setup.points.isFinite || setup.points <= 0 { return "Vinneren må få mer enn 0 poeng." }
        if setup.points > 100 { return "Høyst 100 poeng av gangen." }
        if abs((setup.points * 100).rounded() - setup.points * 100) > 1e-9 { return "Poengene kan ha høyst to desimaler." }
        return nil
    }

    /// Den høyeste runden av challengen som har en vinner for kvelden, eller 0. Så en ny visning
    /// fortsetter der dere var.
    static func lastRound(_ setup: ChallengeSetup, players: [(memberID: UUID, group: Int)], term: GroupTerm,
                          reasons: [String]) -> Int {
        let have = Set(reasons)
        var last = 0
        for r in 1...maxRounds {
            var s = setup
            s.round = r
            if groups(s, players: players, term: term).contains(where: { have.contains($0.reason) }) { last = r }
        }
        return last
    }
}
