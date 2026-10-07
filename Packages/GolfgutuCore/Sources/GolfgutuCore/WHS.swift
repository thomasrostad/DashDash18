import Foundation

/// World Handicap System: score differential og handicapindeks regnet fra rundene i appen.
///
/// Kilde: *Rules of Handicapping* (R&A og USGA), utgaven som gjelder fra 1. januar 2024.
/// Regelnummeret står ved hver konstant og funksjon. Tallene her er WHS-definisjonen, ikke
/// regelverdier for en turnering, og de står bare her.
///
/// Avgrensning (fase 16, se også `sql/021_statistikk.sql`):
/// - Bare 18-hullsrunder der alle hull er ført, og banen har course rating og slope, gir en
///   differential. Ni hull (regel 5.1b, «expected score») og runder med hull som ikke er spilt
///   (regel 3.2) tas ikke med, fordi de krever tabeller som ikke er offentlige som formel.
/// - Playing Conditions Calculation (regel 5.6) krever alle scorene på banen den dagen. Den
///   settes til 0.
/// - Indeksen er uoffisiell: den regnes bare fra runder som er ført i appen.
public enum WHS {
    // MARK: Konstanter (WHS-definisjonen)

    /// Standard slope (regel 5.1a og 6.1a): en bane med gjennomsnittlig vanskelighet.
    public static let standardSlope: Double = 113
    /// Netto dobbel bogey (regel 3.1a): høyeste hullscore er par + 2 + slag fått.
    public static let netDoubleBogeyOverPar = 2
    /// Uten handicapindeks (regel 3.1b): høyeste hullscore er par + 5.
    public static let maximumOverParWithoutIndex = 5
    /// Antall scorer i grunnlaget (regel 5.2a): de siste 20.
    public static let scoresInRecord = 20
    /// Høyeste handicapindeks (regel 5.2a).
    public static let maximumIndex: Double = 54.0
    /// Myk grense (regel 5.8): økning over laveste indeks ut over 3,0 halveres.
    public static let softCapThreshold: Double = 3.0
    /// Myk grense (regel 5.8): andelen av økningen over grensen som står.
    public static let softCapFactor: Double = 0.5
    /// Hard grense (regel 5.8): indeksen kan ikke bli mer enn 5,0 over laveste indeks.
    public static let hardCap: Double = 5.0
    /// Laveste indeks (regel 5.7) ser 365 dager bakover fra dagen for den siste scoren.
    public static let lowIndexWindowDays = 365
    /// Laveste indeks (regel 5.7) finnes først når det er minst 20 scorer i grunnlaget.
    public static let lowIndexMinimumScores = 20
    /// Eksepsjonell score (regel 5.9): differentialen er minst så mye lavere enn indeksen → antall
    /// slag som trekkes fra de siste 20 differentialene. Høyeste terskel først.
    public static let exceptionalScoreReductions: [(threshold: Double, reduction: Double)] = [(10.0, 2.0), (7.0, 1.0)]

    /// Tabellen i regel 5.2a: med færre enn 20 scorer, hvor mange av de laveste som brukes, og
    /// justeringen som legges til snittet. Under 3 scorer finnes ingen indeks.
    public static func selection(forScores count: Int) -> (lowest: Int, adjustment: Double)? {
        switch count {
        case ..<3: nil
        case 3: (1, -2.0)
        case 4: (1, -1.0)
        case 5: (1, 0)
        case 6: (2, -1.0)
        case 7...8: (2, 0)
        case 9...11: (3, 0)
        case 12...14: (4, 0)
        case 15...16: (5, 0)
        case 17...18: (6, 0)
        case 19: (7, 0)
        default: (8, 0)
        }
    }

    // MARK: Avrunding

    /// Nærmeste tidel, ,5 bort fra null (regel 5.1 og 5.2: «rounded to the nearest tenth»).
    public static func roundTenth(_ x: Double) -> Double {
        let scaled = x * 10
        // Tåler binær støy (12,25 kan bli 12,2499999…).
        let nudged = scaled + (scaled >= 0 ? 1e-9 : -1e-9)
        return nudged.rounded(.toNearestOrAwayFromZero) / 10
    }

    /// Nærmeste hele tall, ,5 bort fra null (regel 6.1: banehandicap).
    public static func roundWhole(_ x: Double) -> Int {
        let nudged = x + (x >= 0 ? 1e-9 : -1e-9)
        return Int(nudged.rounded(.toNearestOrAwayFromZero))
    }

    // MARK: Banehandicap og justert score

    /// Banehandicap (regel 6.1a): indeks × (slope / 113) + (course rating − par), avrundet.
    public static func courseHandicap(index: Double, slope: Double, courseRating: Double, par: Int) -> Int {
        roundWhole(index * (slope / standardSlope) + (courseRating - Double(par)))
    }

    /// Slag fått på hullet med et banehandicap over 18 hull (regel 6.2, appendiks E).
    /// Et plusshandicap gir slag tilbake på de letteste hullene (høyest indeks først).
    public static func strokesReceived(courseHandicap: Int, strokeIndex: Int, holes: Int = 18) -> Int {
        if courseHandicap >= 0 {
            return courseHandicap / holes + (strokeIndex <= courseHandicap % holes ? 1 : 0)
        }
        let plus = -courseHandicap
        return -(plus / holes + (strokeIndex > holes - plus % holes ? 1 : 0))
    }

    /// Høyeste score som teller på hullet (regel 3.1): netto dobbel bogey med indeks, ellers par + 5.
    public static func maximumHoleScore(par: Int, strokeIndex: Int, courseHandicap: Int?) -> Int {
        guard let courseHandicap else { return par + maximumOverParWithoutIndex }
        return par + netDoubleBogeyOverPar + strokesReceived(courseHandicap: courseHandicap, strokeIndex: strokeIndex)
    }

    /// Ett hull i en runde: par, indeks (1–18) og brutto.
    public struct Hole: Codable, Hashable, Sendable {
        public var par: Int
        public var strokeIndex: Int
        public var gross: Int

        public init(par: Int, strokeIndex: Int, gross: Int) {
            self.par = par
            self.strokeIndex = strokeIndex
            self.gross = gross
        }
    }

    /// Justert bruttoscore (regel 3.1): hvert hull kuttes ved høyeste score.
    public static func adjustedGrossScore(_ holes: [Hole], courseHandicap: Int?) -> Int {
        holes.reduce(0) { sum, h in
            sum + min(h.gross, maximumHoleScore(par: h.par, strokeIndex: h.strokeIndex, courseHandicap: courseHandicap))
        }
    }

    /// Score differential (regel 5.1a): (113 / slope) × (justert brutto − course rating − PCC),
    /// avrundet til nærmeste tidel.
    public static func scoreDifferential(adjustedGross: Int, courseRating: Double, slope: Double,
                                         pcc: Double = 0) -> Double {
        roundTenth((standardSlope / slope) * (Double(adjustedGross) - courseRating - pcc))
    }

    // MARK: Indeks over tid

    /// En runde som kan gi en differential.
    public struct Score: Codable, Hashable, Sendable {
        public var id: String
        /// `YYYY-MM-DD`.
        public var date: String
        public var holes: [Hole]
        public var courseRating: Double
        public var slope: Double
        /// Indeksen spilleren hadde da runden ble spilt (frosset i runden). `nil`: den utregnede
        /// indeksen før runden brukes, og finnes ingen, gjelder par + 5.
        public var handicapIndex: Double?

        public init(id: String, date: String, holes: [Hole], courseRating: Double, slope: Double,
                    handicapIndex: Double? = nil) {
            self.id = id
            self.date = date
            self.holes = holes
            self.courseRating = courseRating
            self.slope = slope
            self.handicapIndex = handicapIndex
        }

        public var par: Int { holes.reduce(0) { $0 + $1.par } }
    }

    /// Én runde i historikken: differentialen og indeksen etter at runden ble lagt inn.
    public struct Revision: Codable, Hashable, Sendable {
        public var scoreID: String
        public var date: String
        public var courseHandicap: Int?
        public var adjustedGross: Int
        public var differential: Double
        /// Slag trukket fra differentialen etter eksepsjonelle scorer (regel 5.9), sist kjent.
        public var exceptionalReduction: Double
        /// Indeksen etter runden. `nil` til det finnes tre scorer.
        public var index: Double?
        /// Antall scorer i grunnlaget (høyst 20).
        public var scoresInRecord: Int
        /// Laveste indeks som gjaldt da (regel 5.7), når den finnes.
        public var lowIndex: Double?
        /// Myk eller hard grense ble brukt.
        public var capped: Bool
    }

    /// Indeksen runde for runde (regel 5.2, 5.7, 5.8 og 5.9). Rundene sorteres på dato; samme
    /// dato beholder rekkefølgen de kom i.
    public static func history(_ scores: [Score]) -> [Revision] {
        let ordered = scores.enumerated().sorted { a, b in
            a.element.date == b.element.date ? a.offset < b.offset : a.element.date < b.element.date
        }.map(\.element)

        struct Entry {
            var differential: Double
            var reduction: Double
        }
        var record: [Entry] = []
        var revisions: [Revision] = []
        // Indekser regnet med minst 20 scorer: dato → indeks (regel 5.7).
        var established: [(date: String, index: Double)] = []
        var current: Double?

        for score in ordered where score.holes.count == 18 && score.slope > 0 {
            let indexForRound = score.handicapIndex ?? current
            let ch = indexForRound.map { courseHandicap(index: $0, slope: score.slope,
                                                        courseRating: score.courseRating, par: score.par) }
            let ags = adjustedGrossScore(score.holes, courseHandicap: ch)
            let diff = scoreDifferential(adjustedGross: ags, courseRating: score.courseRating, slope: score.slope)
            record.append(Entry(differential: diff, reduction: 0))

            // Regel 5.9: sammenlignet med indeksen før runden.
            if let before = current,
               let esr = exceptionalScoreReductions.first(where: { before - diff >= $0.threshold }) {
                for i in record.indices.suffix(scoresInRecord) {
                    record[i].reduction += esr.reduction
                }
            }

            let recent = Array(record.suffix(scoresInRecord))
            var lowIndex: Double?
            var capped = false
            var index: Double?
            if let sel = selection(forScores: recent.count) {
                let lowest = recent.map { $0.differential - $0.reduction }.sorted().prefix(sel.lowest)
                var calc = roundTenth(lowest.reduce(0, +) / Double(sel.lowest) + sel.adjustment)
                if record.count >= lowIndexMinimumScores {
                    lowIndex = lowHandicapIndex(established, mostRecentScore: score.date)
                    if let low = lowIndex, calc - low > softCapThreshold {
                        let soft = low + softCapThreshold + (calc - low - softCapThreshold) * softCapFactor
                        calc = roundTenth(min(soft, low + hardCap))
                        capped = true
                    }
                }
                index = min(calc, maximumIndex)
            }
            if let index, record.count >= lowIndexMinimumScores {
                established.append((score.date, index))
            }
            current = index ?? current
            revisions.append(Revision(scoreID: score.id, date: score.date, courseHandicap: ch, adjustedGross: ags,
                                      differential: diff, exceptionalReduction: record.last?.reduction ?? 0,
                                      index: index, scoresInRecord: recent.count, lowIndex: lowIndex,
                                      capped: capped))
        }
        return revisions
    }

    /// Laveste indeks (regel 5.7): den laveste som gjaldt i de 365 dagene før dagen den siste
    /// scoren ble spilt. Også indeksen som gjaldt da perioden startet, teller.
    static func lowHandicapIndex(_ established: [(date: String, index: Double)], mostRecentScore date: String) -> Double? {
        guard let end = day(date),
              let start = Calendar.utc.date(byAdding: .day, value: -lowIndexWindowDays, to: end) else { return nil }
        var held: [Double] = []
        var beforeWindow: Double?
        for e in established {
            guard let d = day(e.date) else { continue }
            if d < start { beforeWindow = e.index } else if d < end { held.append(e.index) }
        }
        if let beforeWindow { held.append(beforeWindow) }
        return held.min()
    }

    static func day(_ s: String) -> Date? {
        let parts = s.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

extension Calendar {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
