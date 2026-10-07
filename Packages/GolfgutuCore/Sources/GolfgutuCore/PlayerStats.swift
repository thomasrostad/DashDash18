import Foundation

// Statistikk for én spiller på tvers av alt hen har spilt: klubbrunder og løse runder (fase 16).
// Alt regnes fra rådata (brutto per hull, valgfri føring per hull, banens hull og handicapet som
// ble frosset i runden). Ingenting her lagres.

/// Fairway fra utslaget, bare på par 4 og 5.
public enum FairwayResult: String, Codable, Hashable, Sendable, CaseIterable {
    case left, hit, right
}

/// Den valgfrie føringen for ett hull (`hole_stats`). Hvert felt kan mangle.
public struct HoleDetail: Codable, Hashable, Sendable {
    public var fairway: FairwayResult?
    public var greenInRegulation: Bool?
    public var putts: Int?
    /// Var i bunker på hullet.
    public var bunker: Bool?
    public var penalties: Int?

    public init(fairway: FairwayResult? = nil, greenInRegulation: Bool? = nil, putts: Int? = nil,
                bunker: Bool? = nil, penalties: Int? = nil) {
        self.fairway = fairway
        self.greenInRegulation = greenInRegulation
        self.putts = putts
        self.bunker = bunker
        self.penalties = penalties
    }

    public var isEmpty: Bool {
        fairway == nil && greenInRegulation == nil && putts == nil && bunker == nil && penalties == nil
    }
}

/// Ett hull slik det ble spilt i runden (etter rundens egne overstyringer).
public struct StatsHole: Codable, Hashable, Sendable {
    public var par: Int
    /// Rang blant hullene som spilles (1 = vanskeligst), som `PlayedHole.strokeIndex`.
    public var strokeIndex: Int
    /// Banens hullnummer (1–18).
    public var number: Int

    public init(par: Int, strokeIndex: Int, number: Int) {
        self.par = par
        self.strokeIndex = strokeIndex
        self.number = number
    }
}

/// Én runde for én spiller, med alt statistikken trenger.
public struct StatsRound: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// Klubbrunde (kveld i en klubb).
        case club
        /// Løs runde, uten klubb.
        case loose
    }

    public var id: String
    /// `YYYY-MM-DD`.
    public var date: String
    public var kind: Kind
    public var title: String?
    public var clubName: String?
    public var courseID: String?
    public var courseName: String?
    /// Hullene i spillerekkefølge. Indeksen er rundens 0-baserte hull.
    public var holes: [StatsHole]
    /// Spillehandicapet i runden, i hele slag (frosset, eller 0 når simulatoren deler ut slagene).
    public var playingHandicap: Double
    /// Handicapindeksen som var frosset i runden (WHS).
    public var handicapIndex: Double?
    public var courseRating: Double?
    public var slopeRating: Double?
    /// Brutto per hull: rundens 0-baserte hull → slag.
    public var scores: [Int: Int]
    public var details: [Int: HoleDetail]
    /// Stablefordregelen i regelsettet runden ble spilt med. `nil`: Golfgutu-oppsettet.
    public var scoring: Ruleset.ScoringRules?

    public init(id: String, date: String, kind: Kind, title: String? = nil, clubName: String? = nil,
                courseID: String? = nil, courseName: String? = nil, holes: [StatsHole], playingHandicap: Double = 0,
                handicapIndex: Double? = nil, courseRating: Double? = nil, slopeRating: Double? = nil,
                scores: [Int: Int], details: [Int: HoleDetail] = [:], scoring: Ruleset.ScoringRules? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.clubName = clubName
        self.courseID = courseID
        self.courseName = courseName
        self.holes = holes
        self.playingHandicap = playingHandicap
        self.handicapIndex = handicapIndex
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.scores = scores
        self.details = details
        self.scoring = scoring
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, kind, title, clubName, courseID, courseName, holes, playingHandicap, handicapIndex,
             courseRating, slopeRating, scores, details, scoring
    }

    /// Felt som mangler i JSON, får standardverdien (som `Round`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        kind = try c.decode(Kind.self, forKey: .kind)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        clubName = try c.decodeIfPresent(String.self, forKey: .clubName)
        courseID = try c.decodeIfPresent(String.self, forKey: .courseID)
        courseName = try c.decodeIfPresent(String.self, forKey: .courseName)
        holes = try c.decode([StatsHole].self, forKey: .holes)
        playingHandicap = try c.decodeIfPresent(Double.self, forKey: .playingHandicap) ?? 0
        handicapIndex = try c.decodeIfPresent(Double.self, forKey: .handicapIndex)
        courseRating = try c.decodeIfPresent(Double.self, forKey: .courseRating)
        slopeRating = try c.decodeIfPresent(Double.self, forKey: .slopeRating)
        scores = try c.decodeIfPresent([Int: Int].self, forKey: .scores) ?? [:]
        details = try c.decodeIfPresent([Int: HoleDetail].self, forKey: .details) ?? [:]
        scoring = try c.decodeIfPresent(Ruleset.ScoringRules.self, forKey: .scoring)
    }

    public var holeCount: Int { holes.count }
    /// Alle hull i runden er ført.
    public var isComplete: Bool { !holes.isEmpty && holes.indices.allSatisfy { scores[$0] != nil } }
    /// Hvilke hull på banen: «1–18», «1–9» eller «10–18».
    public var layoutKey: String {
        guard let first = holes.first?.number, let last = holes.last?.number else { return "" }
        return "\(first)-\(last)"
    }
}

/// Brutto mot par på ett hull.
public enum ScoreBucket: String, Codable, Hashable, Sendable, CaseIterable {
    case eagleOrBetter, birdie, par, bogey, doubleOrWorse

    public init(toPar: Int) {
        switch toPar {
        case ...(-2): self = .eagleOrBetter
        case -1: self = .birdie
        case 0: self = .par
        case 1: self = .bogey
        default: self = .doubleOrWorse
        }
    }
}

/// Utvalget statistikken regnes over.
public struct StatsFilter: Codable, Hashable, Sendable {
    public var kind: StatsRound.Kind?
    public var courseID: String?
    /// `YYYY-MM-DD`, med.
    public var from: String?
    /// `YYYY-MM-DD`, med.
    public var to: String?

    public init(kind: StatsRound.Kind? = nil, courseID: String? = nil, from: String? = nil, to: String? = nil) {
        self.kind = kind
        self.courseID = courseID
        self.from = from
        self.to = to
    }

    public static let all = StatsFilter()

    public func includes(_ round: StatsRound) -> Bool {
        if let kind, round.kind != kind { return false }
        if let courseID, round.courseID != courseID { return false }
        if let from, round.date < from { return false }
        if let to, round.date > to { return false }
        return true
    }
}

/// Tallene for én runde, regnet fra hullene som er ført.
public struct RoundLine: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var date: String
    public var kind: StatsRound.Kind
    public var title: String?
    public var clubName: String?
    public var courseID: String?
    public var courseName: String?
    public var holeCount: Int
    public var layoutKey: String
    public var holesPlayed: Int
    public var isComplete: Bool
    public var gross: Int
    /// Par for hullene som er ført.
    public var par: Int
    public var toPar: Int { gross - par }
    /// Brutto minus slagene fått på hullene som er ført.
    public var net: Int
    public var stableford: Int
    /// Putter i runden, når alle førte hull har putter.
    public var putts: Int?
    /// WHS score differential, når runden kan gi en.
    public var differential: Double?
}

/// Snitt for fullførte runder med samme antall hull.
public struct RoundAverages: Codable, Hashable, Sendable {
    public var rounds: Int
    public var gross: Double
    public var toPar: Double
    public var net: Double
    public var stableford: Double
}

/// Snitt per par-type.
public struct ParTypeStats: Codable, Hashable, Sendable {
    public var par: Int
    public var holes: Int
    public var averageGross: Double
    public var averageToPar: Double { averageGross - Double(par) }
}

/// Fordelingen av hullene brutto mot par.
public struct ScoreDistribution: Codable, Hashable, Sendable {
    public var counts: [ScoreBucket: Int]
    public var total: Int { counts.values.reduce(0, +) }

    public func count(_ bucket: ScoreBucket) -> Int { counts[bucket] ?? 0 }

    public func share(_ bucket: ScoreBucket) -> Double? {
        total == 0 ? nil : Double(count(bucket)) / Double(total)
    }
}

/// Fairway, green og putter fra den valgfrie føringen.
public struct ShotStats: Codable, Hashable, Sendable {
    /// Par 4- og 5-hull der fairway er ført.
    public var fairwayHoles = 0
    public var fairwayHit = 0
    public var fairwayLeft = 0
    public var fairwayRight = 0
    /// Hull der green i regulering er ført.
    public var girHoles = 0
    public var girHit = 0
    /// Hull med putter ført, og summen.
    public var puttHoles = 0
    public var puttTotal = 0
    /// Fullførte runder der alle hull har putter, og summen.
    public var puttRounds = 0
    public var puttRoundTotal = 0
    /// Hull der bunker er ført, og hvor mange av dem spilleren var i bunker.
    public var bunkerHoles = 0
    public var bunkerVisits = 0
    /// Bunkerhull spilt på par eller bedre (sand save).
    public var sandSaves = 0
    /// Hull der straffeslag er ført, og summen.
    public var penaltyHoles = 0
    public var penaltyTotal = 0

    public var fairwayShare: Double? { fairwayHoles == 0 ? nil : Double(fairwayHit) / Double(fairwayHoles) }
    public var girShare: Double? { girHoles == 0 ? nil : Double(girHit) / Double(girHoles) }
    public var puttsPerHole: Double? { puttHoles == 0 ? nil : Double(puttTotal) / Double(puttHoles) }
    public var puttsPerRound: Double? { puttRounds == 0 ? nil : Double(puttRoundTotal) / Double(puttRounds) }
    public var sandSaveShare: Double? { bunkerVisits == 0 ? nil : Double(sandSaves) / Double(bunkerVisits) }
    /// Er noe av den valgfrie føringen gjort?
    public var hasAny: Bool { fairwayHoles + girHoles + puttHoles + bunkerHoles + penaltyHoles > 0 }
}

/// Spillerens beste på en bane (samme hull), brutto og netto.
public struct CourseRecord: Codable, Hashable, Sendable, Identifiable {
    public var courseID: String?
    public var courseName: String
    public var layoutKey: String
    public var holeCount: Int
    public var rounds: Int
    public var bestGross: RoundLine
    public var bestNet: RoundLine
    public var id: String { "\(courseID ?? courseName)|\(layoutKey)" }
}

/// Alt statistikken viser for et utvalg.
public struct StatsSummary: Codable, Hashable, Sendable {
    public var filter: StatsFilter
    /// Alle runder i utvalget med minst ett hull ført, nyeste først.
    public var rounds: [RoundLine]
    /// Snitt per antall hull (9, 18), bare fullførte runder.
    public var averages: [Int: RoundAverages]
    public var parTypes: [ParTypeStats]
    public var distribution: ScoreDistribution
    public var shots: ShotStats
    public var courseRecords: [CourseRecord]
    /// WHS runde for runde, regnet over alle runder (ikke bare utvalget), og så filtrert på datoene.
    public var handicap: [WHS.Revision]

    public var completeRounds: [RoundLine] { rounds.filter(\.isComplete) }
    /// Beste fullførte runder på stableford, flest poeng først (dato avgjør likhet: eldst først).
    /// `holes`: bare runder med så mange hull (9 og 18 kan ikke sammenlignes).
    public func bestByStableford(_ limit: Int, holes: Int? = nil) -> [RoundLine] {
        Array(completeRounds.filter { holes == nil || $0.holeCount == holes }.sorted { a, b in
            a.stableford != b.stableford ? a.stableford > b.stableford : a.date < b.date
        }.prefix(limit))
    }
    /// Beste fullførte runder brutto mot par.
    public func bestByGross(_ limit: Int, holes: Int? = nil) -> [RoundLine] {
        Array(completeRounds.filter { holes == nil || $0.holeCount == holes }.sorted { a, b in
            a.toPar != b.toPar ? a.toPar < b.toPar : a.date < b.date
        }.prefix(limit))
    }
    /// Fullførte runder eldst først (trend over tid).
    public var trend: [RoundLine] { completeRounds.reversed() }
    /// Siste kjente WHS-indeks i utvalget.
    public var currentIndex: Double? { handicap.last(where: { $0.index != nil })?.index }
}

/// Statistikkmotoren.
public enum PlayerStats {
    /// Tallene for én runde. `differential` settes av `summary` (krever hele historikken).
    public static func line(_ r: StatsRound) -> RoundLine {
        let holes = r.holeCount
        var gross = 0, par = 0, net = 0, stableford = 0, played = 0
        var putts = 0, puttsComplete = true
        var rules = Ruleset.golfgutu
        if let scoring = r.scoring { rules.scoring = scoring }
        for (i, hole) in r.holes.enumerated() {
            guard let g = r.scores[i] else { continue }
            played += 1
            gross += g
            par += hole.par
            let received = Scoring.handicapStrokes(handicap: r.playingHandicap, strokeIndex: hole.strokeIndex, holes: holes)
            net += g - received
            stableford += Scoring.points(par: hole.par, gross: g, handicap: r.playingHandicap,
                                         strokeIndex: hole.strokeIndex, holes: holes, rules: rules)
            if let p = r.details[i]?.putts { putts += p } else { puttsComplete = false }
        }
        return RoundLine(id: r.id, date: r.date, kind: r.kind, title: r.title, clubName: r.clubName,
                         courseID: r.courseID, courseName: r.courseName, holeCount: holes, layoutKey: r.layoutKey,
                         holesPlayed: played, isComplete: r.isComplete, gross: gross, par: par, net: net,
                         stableford: stableford, putts: played > 0 && puttsComplete ? putts : nil,
                         differential: nil)
    }

    /// Runden som WHS-score, når den kan gi en differential: 18 hull, alle ført, med CR og slope.
    public static func whsScore(_ r: StatsRound) -> WHS.Score? {
        guard r.holeCount == 18, r.isComplete, let cr = r.courseRating, let slope = r.slopeRating, slope > 0 else {
            return nil
        }
        let holes = r.holes.enumerated().map { i, h in WHS.Hole(par: h.par, strokeIndex: h.strokeIndex, gross: r.scores[i]!) }
        return WHS.Score(id: r.id, date: r.date, holes: holes, courseRating: cr, slope: slope,
                         handicapIndex: r.handicapIndex)
    }

    /// Statistikken for utvalget. WHS regnes over alle rundene, fordi indeksen bygger på historikken.
    public static func summary(_ all: [StatsRound], filter: StatsFilter = .all) -> StatsSummary {
        let history = WHS.history(all.compactMap(whsScore))
        let differentials = Dictionary(history.map { ($0.scoreID, $0.differential) }, uniquingKeysWith: { a, _ in a })

        let selected = all.filter(filter.includes)
        var lines: [RoundLine] = []
        var parTotals: [Int: (holes: Int, gross: Int)] = [:]
        var buckets: [ScoreBucket: Int] = [:]
        var shots = ShotStats()

        for r in selected {
            var line = line(r)
            guard line.holesPlayed > 0 else { continue }
            line.differential = differentials[r.id]
            lines.append(line)

            for (i, hole) in r.holes.enumerated() {
                guard let g = r.scores[i] else { continue }
                parTotals[hole.par, default: (0, 0)].holes += 1
                parTotals[hole.par, default: (0, 0)].gross += g
                buckets[ScoreBucket(toPar: g - hole.par), default: 0] += 1
                guard let d = r.details[i] else { continue }
                if hole.par >= 4, let fw = d.fairway {
                    shots.fairwayHoles += 1
                    switch fw {
                    case .hit: shots.fairwayHit += 1
                    case .left: shots.fairwayLeft += 1
                    case .right: shots.fairwayRight += 1
                    }
                }
                if let gir = d.greenInRegulation {
                    shots.girHoles += 1
                    if gir { shots.girHit += 1 }
                }
                if let p = d.putts {
                    shots.puttHoles += 1
                    shots.puttTotal += p
                }
                if let bunker = d.bunker {
                    shots.bunkerHoles += 1
                    if bunker {
                        shots.bunkerVisits += 1
                        if g <= hole.par { shots.sandSaves += 1 }
                    }
                }
                if let pen = d.penalties {
                    shots.penaltyHoles += 1
                    shots.penaltyTotal += pen
                }
            }
            if line.isComplete, let p = line.putts {
                shots.puttRounds += 1
                shots.puttRoundTotal += p
            }
        }

        lines.sort { a, b in a.date != b.date ? a.date > b.date : a.id > b.id }
        let complete = lines.filter(\.isComplete)

        var averages: [Int: RoundAverages] = [:]
        for (count, group) in Dictionary(grouping: complete, by: \.holeCount) {
            let n = Double(group.count)
            averages[count] = RoundAverages(
                rounds: group.count,
                gross: Double(group.reduce(0) { $0 + $1.gross }) / n,
                toPar: Double(group.reduce(0) { $0 + $1.toPar }) / n,
                net: Double(group.reduce(0) { $0 + $1.net }) / n,
                stableford: Double(group.reduce(0) { $0 + $1.stableford }) / n
            )
        }

        let parTypes = parTotals.keys.sorted().map { par in
            let t = parTotals[par]!
            return ParTypeStats(par: par, holes: t.holes, averageGross: Double(t.gross) / Double(t.holes))
        }

        // Indeksen etter hver runde er regnet over alt; utvalget avgjør bare hvilke runder som vises.
        let selectedIDs = Set(selected.map(\.id))
        let shown = history.filter { selectedIDs.contains($0.scoreID) }

        return StatsSummary(filter: filter, rounds: lines, averages: averages, parTypes: parTypes,
                            distribution: ScoreDistribution(counts: buckets), shots: shots,
                            courseRecords: courseRecords(complete), handicap: shown)
    }

    /// Beste brutto og netto per bane og hull-oppsett. Likt: den eldste runden står.
    public static func courseRecords(_ complete: [RoundLine]) -> [CourseRecord] {
        let groups = Dictionary(grouping: complete.filter { $0.courseID != nil || $0.courseName != nil }) {
            "\($0.courseID ?? $0.courseName ?? "")|\($0.layoutKey)"
        }
        return groups.values.compactMap { group -> CourseRecord? in
            let oldestFirst = group.sorted { a, b in a.date != b.date ? a.date < b.date : a.id < b.id }
            guard let first = oldestFirst.first,
                  let gross = oldestFirst.min(by: { $0.gross < $1.gross }),
                  let net = oldestFirst.min(by: { $0.net < $1.net }) else { return nil }
            return CourseRecord(courseID: first.courseID, courseName: first.courseName ?? "Ukjent bane",
                                layoutKey: first.layoutKey, holeCount: first.holeCount, rounds: group.count,
                                bestGross: gross, bestNet: net)
        }
        .sorted { a, b in
            a.rounds != b.rounds ? a.rounds > b.rounds : NorwegianSort.areInIncreasingOrder(a.courseName, b.courseName)
        }
    }

    /// Glidende snitt over de siste `window` verdiene (trendlinja). Første verdier bruker det som finnes.
    public static func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard window > 0 else { return values }
        return values.indices.map { i in
            let slice = values[max(0, i - window + 1)...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }
}
