import Foundation

/// Øyeblikksbildet av PWA-basen, slik `sql/import/export_pwa.sql` leverer det.
/// Feltnavnene er PWA-ens kolonnenavn. Tall kan komme som tall eller tekst (numeric).
public struct PWASnapshot: Decodable, Sendable {
    public var format: Int?
    public var exportedAt: String?
    public var settings: [Settings]
    public var players: [Player]
    public var courses: [Course]
    public var courseHoles: [CourseHole]
    public var schedule: [ScheduleRow]
    public var signups: [Signup]
    public var rounds: [Round]
    public var roundHoles: [RoundHole]
    public var roundBays: [RoundBay]
    public var roundTeams: [RoundTeam]
    public var roundMatches: [RoundMatch]
    public var holeScores: [HoleScore]
    public var sideClaims: [SideClaim]
    public var roundPoints: [RoundPoints]
    public var tips: [Tip]
    public var meldinger: [Melding]
    /// Radtall per tabell i PWA-basen (bare tall).
    public var counts: [String: Int]

    public init(format: Int? = 1, exportedAt: String? = nil, settings: [Settings] = [], players: [Player] = [],
                courses: [Course] = [], courseHoles: [CourseHole] = [], schedule: [ScheduleRow] = [],
                signups: [Signup] = [], rounds: [Round] = [], roundHoles: [RoundHole] = [],
                roundBays: [RoundBay] = [], roundTeams: [RoundTeam] = [], roundMatches: [RoundMatch] = [],
                holeScores: [HoleScore] = [], sideClaims: [SideClaim] = [], roundPoints: [RoundPoints] = [],
                tips: [Tip] = [], meldinger: [Melding] = [], counts: [String: Int] = [:]) {
        self.format = format; self.exportedAt = exportedAt; self.settings = settings; self.players = players
        self.courses = courses; self.courseHoles = courseHoles; self.schedule = schedule; self.signups = signups
        self.rounds = rounds; self.roundHoles = roundHoles; self.roundBays = roundBays; self.roundTeams = roundTeams
        self.roundMatches = roundMatches; self.holeScores = holeScores; self.sideClaims = sideClaims
        self.roundPoints = roundPoints; self.tips = tips; self.meldinger = meldinger; self.counts = counts
    }

    enum CodingKeys: String, CodingKey {
        case format, exportedAt = "exported_at", settings, players, courses, courseHoles = "course_holes",
             schedule, signups, rounds, roundHoles = "round_holes", roundBays = "round_bays",
             roundTeams = "round_teams", roundMatches = "round_matches", holeScores = "hole_scores",
             sideClaims = "side_claims", roundPoints = "round_points", tips, meldinger, counts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(Int.self, forKey: .format)
        exportedAt = try c.decodeIfPresent(String.self, forKey: .exportedAt)
        settings = try c.decodeIfPresent([Settings].self, forKey: .settings) ?? []
        players = try c.decodeIfPresent([Player].self, forKey: .players) ?? []
        courses = try c.decodeIfPresent([Course].self, forKey: .courses) ?? []
        courseHoles = try c.decodeIfPresent([CourseHole].self, forKey: .courseHoles) ?? []
        schedule = try c.decodeIfPresent([ScheduleRow].self, forKey: .schedule) ?? []
        signups = try c.decodeIfPresent([Signup].self, forKey: .signups) ?? []
        rounds = try c.decodeIfPresent([Round].self, forKey: .rounds) ?? []
        roundHoles = try c.decodeIfPresent([RoundHole].self, forKey: .roundHoles) ?? []
        roundBays = try c.decodeIfPresent([RoundBay].self, forKey: .roundBays) ?? []
        roundTeams = try c.decodeIfPresent([RoundTeam].self, forKey: .roundTeams) ?? []
        roundMatches = try c.decodeIfPresent([RoundMatch].self, forKey: .roundMatches) ?? []
        holeScores = try c.decodeIfPresent([HoleScore].self, forKey: .holeScores) ?? []
        sideClaims = try c.decodeIfPresent([SideClaim].self, forKey: .sideClaims) ?? []
        roundPoints = try c.decodeIfPresent([RoundPoints].self, forKey: .roundPoints) ?? []
        tips = try c.decodeIfPresent([Tip].self, forKey: .tips) ?? []
        meldinger = try c.decodeIfPresent([Melding].self, forKey: .meldinger) ?? []
        counts = try c.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
    }

    // MARK: Rader

    public struct Settings: Decodable, Sendable {
        public var id: Int?
        public var name: String?
        public var year: Int?
        public var location: String?
        public var finished: Bool?
        public var treasurerId: String?
        public init(id: Int? = 1, name: String? = nil, year: Int? = nil, location: String? = nil,
                    finished: Bool? = false, treasurerId: String? = nil) {
            self.id = id; self.name = name; self.year = year; self.location = location
            self.finished = finished; self.treasurerId = treasurerId
        }
        enum CodingKeys: String, CodingKey { case id, name, year, location, finished, treasurerId = "treasurer_id" }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.flexInt(.id); name = try c.decodeIfPresent(String.self, forKey: .name)
            year = try c.flexInt(.year); location = try c.decodeIfPresent(String.self, forKey: .location)
            finished = try c.decodeIfPresent(Bool.self, forKey: .finished)
            treasurerId = try c.decodeIfPresent(String.self, forKey: .treasurerId)
        }
    }

    public struct Player: Decodable, Sendable {
        public var id: String
        public var name: String
        public var commissioner: Bool
        public var joinedAt: String?
        public var handicap: Double?
        public var seedGroup: Int?
        public init(id: String, name: String, commissioner: Bool = false, joinedAt: String? = nil,
                    handicap: Double? = nil, seedGroup: Int? = nil) {
            self.id = id; self.name = name; self.commissioner = commissioner; self.joinedAt = joinedAt
            self.handicap = handicap; self.seedGroup = seedGroup
        }
        enum CodingKeys: String, CodingKey { case id, name, commissioner, joinedAt = "joined_at", handicap, seedGroup = "seed_group" }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
            commissioner = try c.decodeIfPresent(Bool.self, forKey: .commissioner) ?? false
            joinedAt = try c.decodeIfPresent(String.self, forKey: .joinedAt)
            handicap = try c.flexDouble(.handicap); seedGroup = try c.flexInt(.seedGroup)
        }
    }

    /// Et hull i `courses.holes` (eldre jsonb-form).
    public struct JSONHole: Decodable, Sendable {
        public var par: Int?
        public var si: Int?
        public var meters: Double?
        public init(par: Int?, si: Int? = nil, meters: Double? = nil) { self.par = par; self.si = si; self.meters = meters }
        enum CodingKeys: String, CodingKey { case par, si, meters }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            par = try c.flexInt(.par); si = try c.flexInt(.si); meters = try c.flexDouble(.meters)
        }
    }

    public struct Course: Decodable, Sendable {
        public var id: String
        public var name: String
        public var par: Int?
        public var courseRating: Double?
        public var slopeRating: Double?
        public var holes: [JSONHole]?
        public var trackmanName: String?
        public var inUse: Bool
        public var confirmedBy: String?
        public var confirmedAt: String?
        public var createdAt: String?
        public init(id: String, name: String, par: Int? = nil, courseRating: Double? = nil, slopeRating: Double? = nil,
                    holes: [JSONHole]? = nil, trackmanName: String? = nil, inUse: Bool = true,
                    confirmedBy: String? = nil, confirmedAt: String? = nil, createdAt: String? = nil) {
            self.id = id; self.name = name; self.par = par; self.courseRating = courseRating
            self.slopeRating = slopeRating; self.holes = holes; self.trackmanName = trackmanName; self.inUse = inUse
            self.confirmedBy = confirmedBy; self.confirmedAt = confirmedAt; self.createdAt = createdAt
        }
        enum CodingKeys: String, CodingKey {
            case id, name, par, courseRating = "course_rating", slopeRating = "slope_rating", holes,
                 trackmanName = "trackman_name", inUse = "i_bruk", confirmedBy = "bekreftet_av",
                 confirmedAt = "bekreftet_at", createdAt = "created_at"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
            par = try c.flexInt(.par); courseRating = try c.flexDouble(.courseRating)
            slopeRating = try c.flexDouble(.slopeRating)
            holes = try? c.decodeIfPresent([JSONHole].self, forKey: .holes)
            trackmanName = try c.decodeIfPresent(String.self, forKey: .trackmanName)
            inUse = try c.decodeIfPresent(Bool.self, forKey: .inUse) ?? true
            confirmedBy = try c.decodeIfPresent(String.self, forKey: .confirmedBy)
            confirmedAt = try c.decodeIfPresent(String.self, forKey: .confirmedAt)
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        }
    }

    public struct CourseHole: Decodable, Sendable {
        public var courseId: String
        public var holeNumber: Int
        public var par: Int?
        public var hcpIndex: Int?
        public var distanceMeters: Double?
        public init(courseId: String, holeNumber: Int, par: Int?, hcpIndex: Int? = nil, distanceMeters: Double? = nil) {
            self.courseId = courseId; self.holeNumber = holeNumber; self.par = par
            self.hcpIndex = hcpIndex; self.distanceMeters = distanceMeters
        }
        enum CodingKeys: String, CodingKey {
            case courseId = "course_id", holeNumber = "hole_number", par, hcpIndex = "hcp_index", distanceMeters = "distance_meters"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            courseId = try c.decode(String.self, forKey: .courseId)
            holeNumber = try c.flexInt(.holeNumber) ?? 0
            par = try c.flexInt(.par); hcpIndex = try c.flexInt(.hcpIndex); distanceMeters = try c.flexDouble(.distanceMeters)
        }
    }

    public struct ScheduleRow: Decodable, Sendable {
        public var id: String
        public var date: String
        public var time: String?
        public var social1: String?
        public var social2: String?
        public var tipsInnsats: Double?
        public var tipsLinje: Double?
        public init(id: String, date: String, time: String? = nil, social1: String? = nil, social2: String? = nil,
                    tipsInnsats: Double? = nil, tipsLinje: Double? = nil) {
            self.id = id; self.date = date; self.time = time; self.social1 = social1; self.social2 = social2
            self.tipsInnsats = tipsInnsats; self.tipsLinje = tipsLinje
        }
        enum CodingKeys: String, CodingKey {
            case id, date, time, social1 = "social_1", social2 = "social_2", tipsInnsats = "tips_innsats", tipsLinje = "tips_linje"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id); date = try c.decode(String.self, forKey: .date)
            time = try c.decodeIfPresent(String.self, forKey: .time)
            social1 = try c.decodeIfPresent(String.self, forKey: .social1)
            social2 = try c.decodeIfPresent(String.self, forKey: .social2)
            tipsInnsats = try c.flexDouble(.tipsInnsats); tipsLinje = try c.flexDouble(.tipsLinje)
        }
    }

    public struct Signup: Decodable, Sendable {
        public var scheduleId: String
        public var playerId: String
        public var status: String?
        public var kommentar: String?
        public var createdAt: String?
        public init(scheduleId: String, playerId: String, status: String? = "kommer", kommentar: String? = nil, createdAt: String? = nil) {
            self.scheduleId = scheduleId; self.playerId = playerId; self.status = status
            self.kommentar = kommentar; self.createdAt = createdAt
        }
        enum CodingKeys: String, CodingKey {
            case scheduleId = "schedule_id", playerId = "player_id", status, kommentar, createdAt = "created_at"
        }
    }

    public struct Round: Decodable, Sendable {
        public var id: String
        public var name: String?
        public var gameType: String?
        public var date: String?
        public var teeTime: String?
        public var courseId: String?
        public var locked: Bool
        public var kladd: Bool
        public var createdAt: String?
        public var ldHoleIndex: Int?
        public var kpHoleIndex: Int?
        public var ldActive: Bool
        public var kpActive: Bool
        public var multiplier: Double?
        public var hcpAllowance: Double?
        public var holeCount: Int?
        public var hcpExtern: Bool
        public var holeStart: Int?
        public var parConfirmedBy: String?
        public var parConfirmedAt: String?
        public var cutAfter: Int?
        public var cutRule: String?
        public var cutBy: String?
        public var cutAt: String?

        public init(id: String, name: String? = nil, gameType: String? = "stableford", date: String? = nil,
                    teeTime: String? = nil, courseId: String? = nil, locked: Bool = false, kladd: Bool = false,
                    createdAt: String? = nil, ldHoleIndex: Int? = nil, kpHoleIndex: Int? = nil,
                    ldActive: Bool = true, kpActive: Bool = true, multiplier: Double? = 1, hcpAllowance: Double? = 1,
                    holeCount: Int? = 18, hcpExtern: Bool = false, holeStart: Int? = 0,
                    parConfirmedBy: String? = nil, parConfirmedAt: String? = nil,
                    cutAfter: Int? = nil, cutRule: String? = nil, cutBy: String? = nil, cutAt: String? = nil) {
            self.id = id; self.name = name; self.gameType = gameType; self.date = date; self.teeTime = teeTime
            self.courseId = courseId; self.locked = locked; self.kladd = kladd; self.createdAt = createdAt
            self.ldHoleIndex = ldHoleIndex; self.kpHoleIndex = kpHoleIndex; self.ldActive = ldActive
            self.kpActive = kpActive; self.multiplier = multiplier; self.hcpAllowance = hcpAllowance
            self.holeCount = holeCount; self.hcpExtern = hcpExtern; self.holeStart = holeStart
            self.parConfirmedBy = parConfirmedBy; self.parConfirmedAt = parConfirmedAt
            self.cutAfter = cutAfter; self.cutRule = cutRule; self.cutBy = cutBy; self.cutAt = cutAt
        }

        enum CodingKeys: String, CodingKey {
            case id, name, gameType = "game_type", date, teeTime = "tee_time", courseId = "course_id", locked, kladd,
                 createdAt = "created_at", ldHoleIndex = "longest_drive_hole_index", kpHoleIndex = "kp_hole_index",
                 ldActive = "ld_aktiv", kpActive = "kp_aktiv", multiplier, hcpAllowance = "hcp_allowance",
                 holeCount = "hole_count", hcpExtern = "hcp_extern", holeStart = "hole_start",
                 parConfirmedBy = "par_bekreftet_av", parConfirmedAt = "par_bekreftet_at",
                 cutAfter = "avkortet_etter", cutRule = "avkort_regel", cutBy = "avkortet_av", cutAt = "avkortet_at"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            gameType = try c.decodeIfPresent(String.self, forKey: .gameType)
            date = try c.decodeIfPresent(String.self, forKey: .date)
            teeTime = try c.decodeIfPresent(String.self, forKey: .teeTime)
            courseId = try c.decodeIfPresent(String.self, forKey: .courseId)
            locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
            kladd = try c.decodeIfPresent(Bool.self, forKey: .kladd) ?? false
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            ldHoleIndex = try c.flexInt(.ldHoleIndex); kpHoleIndex = try c.flexInt(.kpHoleIndex)
            // PWA: «mangler kolonnen, er premien med» (`ld_aktiv !== false`).
            ldActive = try c.decodeIfPresent(Bool.self, forKey: .ldActive) ?? true
            kpActive = try c.decodeIfPresent(Bool.self, forKey: .kpActive) ?? true
            multiplier = try c.flexDouble(.multiplier); hcpAllowance = try c.flexDouble(.hcpAllowance)
            holeCount = try c.flexInt(.holeCount)
            hcpExtern = try c.decodeIfPresent(Bool.self, forKey: .hcpExtern) ?? false
            holeStart = try c.flexInt(.holeStart)
            parConfirmedBy = try c.decodeIfPresent(String.self, forKey: .parConfirmedBy)
            parConfirmedAt = try c.decodeIfPresent(String.self, forKey: .parConfirmedAt)
            cutAfter = try c.flexInt(.cutAfter); cutRule = try c.decodeIfPresent(String.self, forKey: .cutRule)
            cutBy = try c.decodeIfPresent(String.self, forKey: .cutBy)
            cutAt = try c.decodeIfPresent(String.self, forKey: .cutAt)
        }
    }

    public struct RoundHole: Decodable, Sendable {
        public var roundId: String
        public var holeIndex: Int
        public var par: Int?
        public var strokeIndex: Int?
        public var meters: Double?
        public init(roundId: String, holeIndex: Int, par: Int?, strokeIndex: Int? = nil, meters: Double? = nil) {
            self.roundId = roundId; self.holeIndex = holeIndex; self.par = par; self.strokeIndex = strokeIndex; self.meters = meters
        }
        enum CodingKeys: String, CodingKey { case roundId = "round_id", holeIndex = "hole_index", par, strokeIndex = "stroke_index", meters }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roundId = try c.decode(String.self, forKey: .roundId); holeIndex = try c.flexInt(.holeIndex) ?? -1
            par = try c.flexInt(.par); strokeIndex = try c.flexInt(.strokeIndex); meters = try c.flexDouble(.meters)
        }
    }

    public struct RoundBay: Decodable, Sendable {
        public var roundId: String
        public var playerId: String
        public var bayNo: Int
        public var isMarker: Bool
        public init(roundId: String, playerId: String, bayNo: Int, isMarker: Bool = false) {
            self.roundId = roundId; self.playerId = playerId; self.bayNo = bayNo; self.isMarker = isMarker
        }
        enum CodingKeys: String, CodingKey { case roundId = "round_id", playerId = "player_id", bayNo = "bay_no", isMarker = "er_markor" }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roundId = try c.decode(String.self, forKey: .roundId); playerId = try c.decode(String.self, forKey: .playerId)
            bayNo = try c.flexInt(.bayNo) ?? 0; isMarker = try c.decodeIfPresent(Bool.self, forKey: .isMarker) ?? false
        }
    }

    public struct RoundTeam: Decodable, Sendable {
        public var roundId: String
        public var playerId: String
        public var teamNo: Int
        public init(roundId: String, playerId: String, teamNo: Int) {
            self.roundId = roundId; self.playerId = playerId; self.teamNo = teamNo
        }
        enum CodingKeys: String, CodingKey { case roundId = "round_id", playerId = "player_id", teamNo = "team_no" }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roundId = try c.decode(String.self, forKey: .roundId); playerId = try c.decode(String.self, forKey: .playerId)
            teamNo = try c.flexInt(.teamNo) ?? 0
        }
    }

    public struct RoundMatch: Decodable, Sendable {
        public var roundId: String
        public var matchNo: Int
        public var playerA: String?
        public var playerB: String?
        public var playerC: String?
        public var teamA: Int?
        public var teamB: Int?
        public var result: String?
        public init(roundId: String, matchNo: Int, playerA: String? = nil, playerB: String? = nil, playerC: String? = nil,
                    teamA: Int? = nil, teamB: Int? = nil, result: String? = nil) {
            self.roundId = roundId; self.matchNo = matchNo; self.playerA = playerA; self.playerB = playerB
            self.playerC = playerC; self.teamA = teamA; self.teamB = teamB; self.result = result
        }
        enum CodingKeys: String, CodingKey {
            case roundId = "round_id", matchNo = "match_no", playerA = "player_a", playerB = "player_b",
                 playerC = "player_c", teamA = "team_a", teamB = "team_b", result
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roundId = try c.decode(String.self, forKey: .roundId); matchNo = try c.flexInt(.matchNo) ?? 0
            playerA = try c.decodeIfPresent(String.self, forKey: .playerA)
            playerB = try c.decodeIfPresent(String.self, forKey: .playerB)
            playerC = try c.decodeIfPresent(String.self, forKey: .playerC)
            teamA = try c.flexInt(.teamA); teamB = try c.flexInt(.teamB)
            result = try c.decodeIfPresent(String.self, forKey: .result)
        }
    }

    public struct HoleScore: Decodable, Sendable {
        public var roundId: String
        public var playerId: String
        public var holeIndex: Int
        public var strokes: Int
        public var updatedAt: String?
        public init(roundId: String, playerId: String, holeIndex: Int, strokes: Int, updatedAt: String? = nil) {
            self.roundId = roundId; self.playerId = playerId; self.holeIndex = holeIndex
            self.strokes = strokes; self.updatedAt = updatedAt
        }
        enum CodingKeys: String, CodingKey {
            case roundId = "round_id", playerId = "player_id", holeIndex = "hole_index", strokes, updatedAt = "updated_at"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roundId = try c.decode(String.self, forKey: .roundId); playerId = try c.decode(String.self, forKey: .playerId)
            holeIndex = try c.flexInt(.holeIndex) ?? -1; strokes = try c.flexInt(.strokes) ?? 0
            updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        }
    }

    public struct SideClaim: Decodable, Sendable {
        public var id: String
        public var type: String
        public var playerId: String
        public var meters: Double
        public var roundId: String?
        public var holeIndex: Int?
        public var createdAt: String?
        public init(id: String, type: String, playerId: String, meters: Double, roundId: String?,
                    holeIndex: Int? = nil, createdAt: String? = nil) {
            self.id = id; self.type = type; self.playerId = playerId; self.meters = meters
            self.roundId = roundId; self.holeIndex = holeIndex; self.createdAt = createdAt
        }
        enum CodingKeys: String, CodingKey {
            case id, type, playerId = "player_id", meters, roundId = "round_id", holeIndex = "hole_index", createdAt = "created_at"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id); type = try c.decode(String.self, forKey: .type)
            playerId = try c.decode(String.self, forKey: .playerId); meters = try c.flexDouble(.meters) ?? 0
            roundId = try c.decodeIfPresent(String.self, forKey: .roundId); holeIndex = try c.flexInt(.holeIndex)
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        }
    }

    public struct RoundPoints: Decodable, Sendable {
        public var roundId: String
        public var playerId: String
        public var points: Int?
        public init(roundId: String, playerId: String, points: Int?) {
            self.roundId = roundId; self.playerId = playerId; self.points = points
        }
        enum CodingKeys: String, CodingKey { case roundId = "round_id", playerId = "player_id", points }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            roundId = try c.decode(String.self, forKey: .roundId); playerId = try c.decode(String.self, forKey: .playerId)
            points = try c.flexInt(.points)
        }
    }

    public struct Tip: Decodable, Sendable {
        public var scheduleId: String
        public var playerId: String
        public var vinner: String?
        public var forsteNi: String?
        public var flestPar: String?
        public var birdie: Bool?
        public var overLinja: Bool?
        public init(scheduleId: String, playerId: String, vinner: String? = nil, forsteNi: String? = nil,
                    flestPar: String? = nil, birdie: Bool? = nil, overLinja: Bool? = nil) {
            self.scheduleId = scheduleId; self.playerId = playerId; self.vinner = vinner; self.forsteNi = forsteNi
            self.flestPar = flestPar; self.birdie = birdie; self.overLinja = overLinja
        }
        enum CodingKeys: String, CodingKey {
            case scheduleId = "schedule_id", playerId = "player_id", vinner, forsteNi = "forste_ni",
                 flestPar = "flest_par", birdie, overLinja = "over_linja"
        }
    }

    public struct Melding: Decodable, Sendable {
        public var id: String
        public var scheduleId: String
        public var playerId: String
        public var tekst: String
        public var nevnt: [String]
        public var createdAt: String?
        public var hasImage: Bool
        public init(id: String, scheduleId: String, playerId: String, tekst: String, nevnt: [String] = [],
                    createdAt: String? = nil, hasImage: Bool = false) {
            self.id = id; self.scheduleId = scheduleId; self.playerId = playerId; self.tekst = tekst
            self.nevnt = nevnt; self.createdAt = createdAt; self.hasImage = hasImage
        }
        enum CodingKeys: String, CodingKey {
            case id, scheduleId = "schedule_id", playerId = "player_id", tekst, nevnt, createdAt = "created_at", hasImage = "har_bilde"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id); scheduleId = try c.decode(String.self, forKey: .scheduleId)
            playerId = try c.decode(String.self, forKey: .playerId)
            tekst = try c.decodeIfPresent(String.self, forKey: .tekst) ?? ""
            nevnt = try c.decodeIfPresent([String].self, forKey: .nevnt) ?? []
            createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
            hasImage = try c.decodeIfPresent(Bool.self, forKey: .hasImage) ?? false
        }
    }
}

// MARK: - Lesing fra mappe

public enum SnapshotError: Error, CustomStringConvertible, Equatable {
    case notFound(String)
    case unreadable(String, String)

    public var description: String {
        switch self {
        case .notFound(let path): "Fant ingen snapshot.json i \(path)"
        case .unreadable(let path, let why): "Klarte ikke å lese \(path): \(why)"
        }
    }
}

extension PWASnapshot {
    /// Leser `snapshot.json` i mappa. Godtar objektet selv, `{"snapshot": {...}}` og en liste med én
    /// rad (slik SQL Editor eksporterer), også når `snapshot` er en JSON-streng.
    public static func load(directory: URL) throws -> (snapshot: PWASnapshot, rawData: Data) {
        let file = directory.appendingPathComponent("snapshot.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw SnapshotError.notFound(directory.path) }
        let data = try Data(contentsOf: file)
        do {
            return (try decode(data), data)
        } catch let error as SnapshotError {
            throw error
        } catch {
            throw SnapshotError.unreadable(file.path, String(describing: error))
        }
    }

    public static func decode(_ data: Data) throws -> PWASnapshot {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let inner = try unwrap(object)
        let normalized = try JSONSerialization.data(withJSONObject: inner)
        return try JSONDecoder().decode(PWASnapshot.self, from: normalized)
    }

    private static func unwrap(_ object: Any) throws -> Any {
        if let list = object as? [Any] {
            guard let first = list.first else { throw SnapshotError.unreadable("snapshot.json", "tom liste") }
            return try unwrap(first)
        }
        if let text = object as? String, let data = text.data(using: .utf8) {
            return try unwrap(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        }
        if let dict = object as? [String: Any] {
            if dict["players"] == nil, let inner = dict["snapshot"] { return try unwrap(inner) }
            return dict
        }
        throw SnapshotError.unreadable("snapshot.json", "ukjent form")
    }
}

// MARK: - Fleksible tall

extension KeyedDecodingContainer {
    func flexDouble(_ key: Key) throws -> Double? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    func flexInt(_ key: Key) throws -> Int? {
        guard contains(key) else { return nil }
        guard let d = try flexDouble(key) else { return nil }
        return Int(d.rounded())
    }
}
