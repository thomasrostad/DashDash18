import Foundation

/// En innmelding til longest drive eller nærmest pinnen (`side_claims`).
public struct SideClaim: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// Longest drive (`SIDE_CLAIM_LONGEST_DRIVE = 'drive'`).
        case drive
        /// Nærmest pinnen (`SIDE_CLAIM_KP`).
        case kp

        /// `SIDE_CLAIM_LABEL`.
        public var label: String {
            switch self {
            case .drive: "Longest drive"
            case .kp: "Nærmest pinnen"
            }
        }
    }

    public var id: String?
    public var kind: Kind
    public var playerId: String
    public var roundId: String?
    public var meters: Double
    public var holeIndex: Int?
    /// Når den ble meldt inn (ISO 8601). Avgjør rekkefølgen ved lik lengde, ikke poengene.
    public var ts: String?

    public init(id: String? = nil, kind: Kind, playerId: String, roundId: String?, meters: Double,
                holeIndex: Int? = nil, ts: String? = nil) {
        self.id = id
        self.kind = kind
        self.playerId = playerId
        self.roundId = roundId
        self.meters = meters
        self.holeIndex = holeIndex
        self.ts = ts
    }
}

/// Longest drive og nærmest pinnen (db-nytt.js linje 717–722 og 2836–2925).
public enum SidePrizes {
    // MARK: Hullene

    /// `harLongestDrive`.
    public static func hasLongestDrive(_ round: Round) -> Bool { round.ldEnabled }

    /// `harKp`.
    public static func hasClosestToPin(_ round: Round) -> Bool { round.kpEnabled }

    /// `longestDriveHullFor`: det lagrede hullet, ellers forslaget. `nil` når premien er av (JS: −1).
    public static func longestDriveHole(_ round: Round) -> Int? {
        guard hasLongestDrive(round) else { return nil }
        return round.ldHoleIndex ?? suggestedLongestDriveHole(round)
    }

    /// `kpHullFor`: det lagrede hullet, ellers forslaget. `nil` når premien er av (JS: −1).
    public static func closestToPinHole(_ round: Round) -> Int? {
        guard hasClosestToPin(round) else { return nil }
        return round.kpHoleIndex ?? suggestedClosestToPinHole(round)
    }

    /// `foreslaattLongestDriveHull`: med lengder det lengste hullet som ikke er par 3. Uten: første
    /// par 5 fra og med hull 4, så første par 5, så første par 4, ellers hull 1.
    public static func suggestedLongestDriveHole(_ round: Round) -> Int {
        let course = round.courseHoles()
        func hasMeters(_ h: PlayedHole) -> Bool { (h.meters ?? 0) != 0 }
        if course.contains(where: { $0.par >= 4 && hasMeters($0) }) {
            var best = -1
            var bestValue = -1.0
            for (i, h) in course.enumerated() where h.par >= 4 && hasMeters(h) && h.meters! > bestValue {
                best = i
                bestValue = h.meters!
            }
            return best
        }
        if let i = course.indices.first(where: { $0 >= 3 && course[$0].par >= 5 }) { return i }
        if let i = course.indices.first(where: { course[$0].par >= 5 }) { return i }
        if let i = course.indices.first(where: { course[$0].par >= 4 }) { return i }
        return 0
    }

    /// `foreslaattKpHull`: første par 3 fra og med hull 4, så første par 3, ellers hull 3.
    public static func suggestedClosestToPinHole(_ round: Round) -> Int {
        let course = round.courseHoles()
        if let i = course.indices.first(where: { $0 >= 3 && course[$0].par == 3 }) { return i }
        if let i = course.indices.first(where: { course[$0].par == 3 }) { return i }
        return 2
    }

    // MARK: Innmeldinger

    /// `longestDriveClaims`: rundens innmeldinger, lengst først; ved likt den som meldte først.
    /// Tom når premien er av.
    public static func longestDriveClaims(_ round: Round, claims: [SideClaim]) -> [SideClaim] {
        guard hasLongestDrive(round) else { return [] }
        return claims.filter { $0.kind == .drive && $0.roundId == round.id }.sorted(by: longestFirst)
    }

    /// `kpClaims`: rundens innmeldinger, nærmest først; ved likt den som meldte først.
    public static func closestToPinClaims(_ round: Round, claims: [SideClaim]) -> [SideClaim] {
        guard hasClosestToPin(round) else { return [] }
        return claims.filter { $0.kind == .kp && $0.roundId == round.id }.sorted(by: closestFirst)
    }

    /// Innmeldingene som teller for premien i runden, sortert.
    public static func claims(_ kind: SideClaim.Kind, in round: Round, claims: [SideClaim]) -> [SideClaim] {
        switch kind {
        case .drive: longestDriveClaims(round, claims: claims)
        case .kp: closestToPinClaims(round, claims: claims)
        }
    }

    /// `sidepremieVinnere`: alle med samme lengde som den første i den sorterte lista. Likt deler.
    public static func winners(_ sortedClaims: [SideClaim]) -> [String] {
        guard let best = sortedClaims.first?.meters else { return [] }
        return sortedClaims.filter { $0.meters == best }.map(\.playerId)
    }

    /// `besteClaimPerSpiller`: hver spillers beste innmelding, i rekkefølgen spillerne dukker opp.
    /// - Parameter isBetter: `(ny, gammel)`: lengst for drive, kortest for KP.
    public static func bestClaimPerPlayer(_ claims: [SideClaim], isBetter: (Double, Double) -> Bool) -> [SideClaim] {
        var order: [String] = []
        var best: [String: SideClaim] = [:]
        for c in claims {
            if let now = best[c.playerId] {
                if isBetter(c.meters, now.meters) { best[c.playerId] = c }
            } else {
                order.append(c.playerId)
                best[c.playerId] = c
            }
        }
        return order.compactMap { best[$0] }
    }

    /// `longestDriveSesong`: hver spillers lengste drive i sesongen, lengst først.
    public static func seasonLongestDrive(_ claims: [SideClaim]) -> [SideClaim] {
        bestClaimPerPlayer(claims.filter { $0.kind == .drive }, isBetter: >).sorted(by: longestFirst)
    }

    /// `kpSesong`: hver spillers nærmeste i sesongen, nærmest først.
    public static func seasonClosestToPin(_ claims: [SideClaim]) -> [SideClaim] {
        bestClaimPerPlayer(claims.filter { $0.kind == .kp }, isBetter: <).sorted(by: closestFirst)
    }

    /// `fmtMeter`: én desimal, desimalkomma: «272,5 m».
    public static func formatMeters(_ meters: Double) -> String {
        JS.norwegianString(JS.round(meters * 10) / 10) + " m"
    }

    // MARK: Sortering

    private static func longestFirst(_ a: SideClaim, _ b: SideClaim) -> Bool {
        a.meters != b.meters ? a.meters > b.meters : earlier(a, b)
    }

    private static func closestFirst(_ a: SideClaim, _ b: SideClaim) -> Bool {
        a.meters != b.meters ? a.meters < b.meters : earlier(a, b)
    }

    /// `(a.ts||'').localeCompare(b.ts||'')`. Lik tid beholder rekkefølgen (Swifts sortering er stabil).
    private static func earlier(_ a: SideClaim, _ b: SideClaim) -> Bool {
        NorwegianSort.compare(a.ts ?? "", b.ts ?? "") == .orderedAscending
    }
}
