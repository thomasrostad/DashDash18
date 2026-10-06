import Foundation
import GolfgutuCore

// Longest drive og nærmest pinnen på riktig hull: hvem leder, lista og «Meld inn».
// Som PWA-ens renderDriveBoks, renderKpBoks, renderLongestDriveKort og renderKpKort
// (app-nytt.js 8447–8630). Sorteringen og delingen ligger i GolfgutuCore (SidePrizes).

/// Meter fra tastaturet: desimal med komma (eller punktum), én desimal som i databasen
/// (`numeric(5,1)`), og 0 < m ≤ 500 (`side_claims.meters`-sjekken). En inndatagrense, ikke en regel.
nonisolated enum MeterInput {
    static let maximum = 500.0

    static let hint = "Skriv inn meter, f.eks. 245 eller 3,4 (høyst 500)."

    /// Tallet, avrundet til én desimal, eller nil når teksten ikke er gyldige meter.
    static func parse(_ text: String) -> Double? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if s.lowercased().hasSuffix("m") { s = String(s.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              s.filter({ $0 == "." }).count <= 1, let raw = Double(s), raw.isFinite else { return nil }
        let m = JS.round(raw * 10) / 10
        return m > 0 && m <= maximum ? m : nil
    }

    /// Til feltet: «3,4», «245».
    static func text(_ meters: Double) -> String {
        JS.norwegianString(JS.round(meters * 10) / 10)
    }
}

nonisolated extension SideClaimKind {
    var core: SideClaim.Kind {
        switch self {
        case .drive: .drive
        case .kp: .kp
        }
    }

    var label: String { core.label }
}

/// Boksen på LD- eller KP-hullet.
nonisolated struct SidePrizeBox: Equatable, Sendable {
    struct Line: Equatable, Identifiable, Sendable {
        let claimID: UUID
        let memberID: UUID
        let rank: Int
        let name: String
        let isMe: Bool
        let meters: String
        /// Leder (alle med samme lengde som den første).
        let isLeader: Bool
        let canDelete: Bool
        var id: UUID { claimID }
    }

    let kind: SideClaimKind
    let holeIndex: Int
    /// «Longest drive nå» / «Nærmest pinnen nå».
    let title: String
    /// «272,5 m · Anders», «250 m · Anders og Bjørn», eller «Ingen ennå».
    let leader: String
    /// Ved likt: «Delt · 0,5 poeng hver». Nil uten likt, eller når premien ikke gir poeng.
    let tieNote: String?
    let lines: [Line]
    /// Kan jeg melde inn (for meg selv, eller som arrangør for andre)?
    let canClaim: Bool
    /// Hvem jeg kan melde for. Arrangøren: alle i runden. Ellers bare meg.
    let claimants: [UUID]
}

nonisolated extension RoundGame {
    /// Hullet premien går på, eller nil når den er av for runden.
    func sidePrizeHole(_ kind: SideClaimKind) -> Int? {
        kind == .drive ? longestDriveHole : closestToPinHole
    }

    /// Rundens innmeldinger som regelmotorens type. Sortert på navn først, så likt står fast
    /// (databasen gir ikke tidspunktet med i dag).
    var coreSideClaims: [SideClaim] {
        snapshot.sideClaims
            .sorted { NorwegianSort.areInIncreasingOrder(name($0.memberID), name($1.memberID)) }
            .map { c in
                SideClaim(id: c.id.uuidString, kind: c.kind.core, playerId: c.memberID.uuidString,
                          roundId: c.roundID.uuidString, meters: c.meters, holeIndex: c.holeIndex)
            }
    }

    /// Spillerens innmelding av typen, om den finnes (én per runde, spiller og type).
    func sideClaim(_ kind: SideClaimKind, for member: UUID) -> SideClaimRow? {
        snapshot.sideClaims.first { $0.kind == kind && $0.memberID == member }
    }

    /// Kan `viewer` melde inn eller rette for `member`? Samme regel som `side_claims`-policyene:
    /// arrangøren alltid; ellers egen innmelding i en runde som går.
    func canClaim(_ viewer: Viewer, for member: UUID) -> Bool {
        guard isPlaying(member) else { return false }
        if viewer.isOrganizer { return true }
        return member == viewer.memberID && status == .active
    }

    /// Boksen for premien på hullet, eller nil når hullet ikke er premiens (eller premien er av).
    func sidePrizeBox(_ kind: SideClaimKind, hole: Int, viewer: Viewer) -> SidePrizeBox? {
        guard let prizeHole = sidePrizeHole(kind), prizeHole == hole else { return nil }
        let sorted = SidePrizes.claims(kind.core, in: round, claims: coreSideClaims)
        let winners = SidePrizes.winners(sorted)
        let best = sorted.first?.meters

        let leader: String
        if let best {
            leader = SidePrizes.formatMeters(best) + " · " + HoleMath.list(winners.map(matchName))
        } else {
            leader = "Ingen ennå"
        }

        var tieNote: String?
        let prize = rules.sidePrizes[kind.core]
        if winners.count > 1, prize.enabled {
            let share = rules.sidePrizes.splitTies ? Double(winners.count) : 1
            let weight = round.weight.isNaN ? 0 : round.weight
            tieNote = "Delt · " + Season.formatPoints(prize.points / share * weight, rules: rules) + " poeng hver"
        }

        let lines = sorted.enumerated().compactMap { i, c -> SidePrizeBox.Line? in
            guard let claimID = c.id.flatMap(UUID.init(uuidString:)),
                  let member = UUID(uuidString: c.playerId) else { return nil }
            return SidePrizeBox.Line(claimID: claimID, memberID: member, rank: i + 1, name: name(member),
                                     isMe: member == viewer.memberID, meters: SidePrizes.formatMeters(c.meters),
                                     isLeader: c.meters == best, canDelete: canClaim(viewer, for: member))
        }

        let claimants = viewer.isOrganizer
            ? snapshot.players.map(\.memberID).sorted { NorwegianSort.areInIncreasingOrder(name($0), name($1)) }
            : (canClaim(viewer, for: viewer.memberID) ? [viewer.memberID] : [])

        return SidePrizeBox(kind: kind, holeIndex: hole, title: kind.label + " nå", leader: leader,
                            tieNote: tieNote, lines: lines, canClaim: !claimants.isEmpty, claimants: claimants)
    }
}

/// Det «Meld inn» sender.
nonisolated struct SideClaimDraft: Equatable, Sendable {
    let roundID: UUID
    let memberID: UUID
    let kind: SideClaimKind
    let holeIndex: Int
    let meters: Double
    /// Raden som rettes, når spilleren har meldt inn før.
    let existing: UUID?
}

nonisolated extension RoundGame {
    /// Innmeldingen fra feltet, eller en feilmelding på norsk.
    func sideClaimDraft(_ kind: SideClaimKind, member: UUID, text: String,
                        viewer: Viewer) -> Result<SideClaimDraft, DataError> {
        guard let hole = sidePrizeHole(kind) else {
            return .failure(.invalid("Runden har ikke \(kind.label.lowercased())."))
        }
        guard canClaim(viewer, for: member) else { return .failure(.notAllowed) }
        guard let meters = MeterInput.parse(text) else { return .failure(.invalid(MeterInput.hint)) }
        return .success(SideClaimDraft(roundID: roundID, memberID: member, kind: kind, holeIndex: hole,
                                       meters: meters, existing: sideClaim(kind, for: member)?.id))
    }
}

nonisolated extension RoundSnapshot {
    /// Legger inn raden serveren svarte med (erstatter samme spiller og type).
    mutating func apply(claim row: SideClaimRow) {
        sideClaims.removeAll { $0.id == row.id || ($0.memberID == row.memberID && $0.kind == row.kind) }
        sideClaims.append(row)
    }

    mutating func removeClaim(_ id: UUID) {
        sideClaims.removeAll { $0.id == id }
    }
}
