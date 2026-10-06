import Foundation

/// Score per hull for én spiller: rundens 0-baserte hullindeks → slag.
/// Et hull uten score står ikke i ordboka (JS: `typeof x !== 'number'`).
public typealias HoleScores = [Int: Int]

/// En spiller, med bare det regelmotoren trenger.
public struct Player: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Handicapindeks (WHS). `nil` regnes som 0, som `Number(x) || 0` i JS.
    public var handicap: Double?
    /// Seedet gruppe (1, 2, 3 i Golfgutu-oppsettet). `nil` = ikke seedet.
    public var seedGroup: Int?

    public init(id: String, name: String = "", handicap: Double? = nil, seedGroup: Int? = nil) {
        self.id = id
        self.name = name
        self.handicap = handicap
        self.seedGroup = seedGroup
    }
}

/// Ett hull i banebiblioteket (`courses.holes` / `course_holes`).
public struct CourseHole: Codable, Hashable, Sendable {
    public var par: Int?
    /// Stroke index slik den står på scorekortet (`hcp_index`).
    public var si: Int?
    public var meters: Double?

    public init(par: Int?, si: Int? = nil, meters: Double? = nil) {
        self.par = par
        self.si = si
        self.meters = meters
    }
}

/// En bane i biblioteket.
public struct Course: Codable, Hashable, Sendable {
    public var id: String?
    public var name: String?
    public var par: Int?
    public var courseRating: Double?
    public var slopeRating: Double?
    public var holes: [CourseHole]?

    public init(id: String? = nil, name: String? = nil, par: Int? = nil,
                courseRating: Double? = nil, slopeRating: Double? = nil, holes: [CourseHole]? = nil) {
        self.id = id
        self.name = name
        self.par = par
        self.courseRating = courseRating
        self.slopeRating = slopeRating
        self.holes = holes
    }
}

/// Rundens egen overstyring av et hull (`round_holes`).
public struct RoundHole: Codable, Hashable, Sendable {
    public var par: Int?
    public var strokeIndex: Int?
    public var meters: Double?

    public init(par: Int?, strokeIndex: Int? = nil, meters: Double? = nil) {
        self.par = par
        self.strokeIndex = strokeIndex
        self.meters = meters
    }
}

/// En runde (kveld), med bare feltene regelmotoren leser.
public struct Round: Codable, Hashable, Sendable {
    public var id: String?
    /// Konkurranseform (`game_type`). Eldre runder har «Stableford».
    public var gameType: String?
    /// 9 eller 18. Alt annet regnes som 18. Les `numberOfHoles`.
    public var holeCount: Int?
    /// 9 betyr hull 10–18 på en 18-hullsbane (bare når runden er 9 hull).
    public var holeStart: Int?
    public var course: Course?
    /// Rundens egne hull, 0-basert indeks.
    public var holes: [Int: RoundHole]?
    /// Handicaptildeling lagret på runden. `nil` (eldre runder) betyr 1.
    public var hcpAllowance: Double?
    /// Simulatoren deler ut slagene. Da gir appen ingen.
    public var hcpExtern: Bool
    /// Lag: spiller-id → lagnummer (`round_teams`).
    public var teams: [String: Int]
    /// Score: spiller-id → hullindeks → slag.
    public var holeScores: [String: HoleScores]
    /// `felles`, `nettopar`, `null` (strengen) eller `nil` (ikke avkortet).
    public var avkortRegel: String?
    public var avkortetEtter: Double?
    /// Rundens matcher (`round_matches`), i lagret rekkefølge.
    public var matches: [Match]
    /// Longest drive er med i runden (`ld_aktiv`). Mangler feltet, er premien med.
    public var ldEnabled: Bool
    /// Nærmest pinnen er med i runden (`kp_aktiv`).
    public var kpEnabled: Bool
    /// Hullet for longest drive (0-basert). `nil`: forslaget brukes.
    public var ldHoleIndex: Int?
    /// Hullet for nærmest pinnen (0-basert). `nil`: forslaget brukes.
    public var kpHoleIndex: Int?
    /// Rundevekt (`multiplier`). 1 til vanlig, 2 på en dobbeltrunde. 0: kvelden teller ikke.
    public var weight: Double
    /// Kveldens dato, `YYYY-MM-DD`. To runder med samme dato er én kveld.
    public var date: String?
    /// Runden er låst (ferdig).
    public var locked: Bool

    public init(id: String? = nil, gameType: String? = nil, holeCount: Int? = nil, holeStart: Int? = nil,
                course: Course? = nil, holes: [Int: RoundHole]? = nil, hcpAllowance: Double? = nil,
                hcpExtern: Bool = false, teams: [String: Int] = [:], holeScores: [String: HoleScores] = [:],
                avkortRegel: String? = nil, avkortetEtter: Double? = nil, matches: [Match] = [],
                ldEnabled: Bool = true, kpEnabled: Bool = true, ldHoleIndex: Int? = nil, kpHoleIndex: Int? = nil,
                weight: Double = 1, date: String? = nil, locked: Bool = false) {
        self.id = id
        self.gameType = gameType
        self.holeCount = holeCount
        self.holeStart = holeStart
        self.course = course
        self.holes = holes
        self.hcpAllowance = hcpAllowance
        self.hcpExtern = hcpExtern
        self.teams = teams
        self.holeScores = holeScores
        self.avkortRegel = avkortRegel
        self.avkortetEtter = avkortetEtter
        self.matches = matches
        self.ldEnabled = ldEnabled
        self.kpEnabled = kpEnabled
        self.ldHoleIndex = ldHoleIndex
        self.kpHoleIndex = kpHoleIndex
        self.weight = weight
        self.date = date
        self.locked = locked
    }

    private enum CodingKeys: String, CodingKey {
        case id, gameType, holeCount, holeStart, course, holes, hcpAllowance, hcpExtern,
             teams, holeScores, avkortRegel, avkortetEtter, matches,
             ldEnabled, kpEnabled, ldHoleIndex, kpHoleIndex, weight, date, locked
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        gameType = try c.decodeIfPresent(String.self, forKey: .gameType)
        holeCount = try c.decodeIfPresent(Int.self, forKey: .holeCount)
        holeStart = try c.decodeIfPresent(Int.self, forKey: .holeStart)
        course = try c.decodeIfPresent(Course.self, forKey: .course)
        holes = try c.decodeIfPresent([Int: RoundHole].self, forKey: .holes)
        hcpAllowance = try c.decodeIfPresent(Double.self, forKey: .hcpAllowance)
        hcpExtern = try c.decodeIfPresent(Bool.self, forKey: .hcpExtern) ?? false
        teams = try c.decodeIfPresent([String: Int].self, forKey: .teams) ?? [:]
        holeScores = try c.decodeIfPresent([String: HoleScores].self, forKey: .holeScores) ?? [:]
        avkortRegel = try c.decodeIfPresent(String.self, forKey: .avkortRegel)
        avkortetEtter = try c.decodeIfPresent(Double.self, forKey: .avkortetEtter)
        matches = try c.decodeIfPresent([Match].self, forKey: .matches) ?? []
        ldEnabled = try c.decodeIfPresent(Bool.self, forKey: .ldEnabled) ?? true
        kpEnabled = try c.decodeIfPresent(Bool.self, forKey: .kpEnabled) ?? true
        ldHoleIndex = try c.decodeIfPresent(Int.self, forKey: .ldHoleIndex)
        kpHoleIndex = try c.decodeIfPresent(Int.self, forKey: .kpHoleIndex)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
        date = try c.decodeIfPresent(String.self, forKey: .date)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

/// Et hull slik det spilles i runden (utdata fra `courseForRound`).
public struct PlayedHole: Codable, Hashable, Sendable {
    public var par: Int
    /// Tallet som står på scorekortet og i simulatoren.
    public var cardIndex: Int
    public var meters: Double?
    /// Rangen blant hullene som spilles (1 = vanskeligst). Slagene fordeles etter denne.
    public var strokeIndex: Int

    public init(par: Int, cardIndex: Int, meters: Double?, strokeIndex: Int) {
        self.par = par
        self.cardIndex = cardIndex
        self.meters = meters
        self.strokeIndex = strokeIndex
    }
}
