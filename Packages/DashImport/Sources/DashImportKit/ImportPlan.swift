import Foundation

/// Det som skal skrives til appens database, i appens skjema (sql/001–011). Én verdi per rad.
/// Alle id-er er stabile (`StableID`), så samme øyeblikksbilde gir samme plan.
public struct ImportPlan: Sendable, Equatable {
    public struct Club: Sendable, Equatable {
        public var id: UUID
        public var name: String
    }

    public struct Member: Sendable, Equatable {
        public var id: UUID
        public var pwaID: String
        public var displayName: String
        public var handicapIndex: Double?
        public var seedGroup: Int?
        public var isOrganizer: Bool
        public var isTreasurer: Bool
        public var createdAt: String?
    }

    public struct Season: Sendable, Equatable {
        public var id: UUID
        public var name: String
        /// `planned`, `active` eller `finished`.
        public var status: String
        /// Regelsettet som JSON (Golfgutu-oppsettet).
        public var rulesJSON: String
    }

    public struct Course: Sendable, Equatable {
        public var id: UUID
        public var pwaID: String
        public var name: String
        public var externalName: String?
        public var courseRating: Double?
        public var slopeRating: Int?
        public var inUse: Bool
        public var confirmedBy: UUID?
        public var confirmedAt: String?
        public var createdAt: String?
    }

    public struct CourseHole: Sendable, Equatable {
        public var courseID: UUID
        public var holeNumber: Int
        public var par: Int
        public var strokeIndex: Int?
        public var lengthM: Int?
    }

    public struct Event: Sendable, Equatable {
        public var id: UUID
        public var eventDate: String
        public var startTime: String?
        public var tipsLine: Double?
        public var tipsStakePoints: Int?
    }

    public struct Committee: Sendable, Equatable {
        public var eventID: UUID
        public var memberID: UUID
    }

    public struct Signup: Sendable, Equatable {
        public var eventID: UUID
        public var memberID: UUID
        /// `yes`, `maybe` eller `no`.
        public var status: String
        public var comment: String?
        public var createdAt: String?
    }

    public struct Round: Sendable, Equatable {
        public var id: UUID
        public var pwaID: String
        public var eventID: UUID
        public var courseID: UUID?
        public var roundNo: Int
        public var name: String?
        /// `draft`, `active` eller `locked`.
        public var status: String
        public var holeCount: Int
        /// 1, eller 10 for siste ni.
        public var firstHole: Int
        public var teeTime: String?
        public var format: String
        public var handicapAllowance: Double
        public var externalHandicap: Bool
        public var weight: Double
        public var ldEnabled: Bool
        public var ldHoleIndex: Int?
        public var kpEnabled: Bool
        public var kpHoleIndex: Int?
        /// `common`, `net_par` eller `zero`.
        public var cutRule: String?
        public var cutAfter: Int?
        public var cutBy: UUID?
        public var cutAt: String?
        public var parConfirmedBy: UUID?
        public var parConfirmedAt: String?
        public var startedAt: String?
        public var lockedAt: String?
        public var createdAt: String?
    }

    public struct RoundHole: Sendable, Equatable {
        public var roundID: UUID
        public var holeIndex: Int
        public var par: Int?
        public var strokeIndex: Int?
        public var lengthM: Int?
    }

    public struct RoundPlayer: Sendable, Equatable {
        public var roundID: UUID
        public var memberID: UUID
        public var handicapIndex: Double?
        public var seedGroup: Int?
        public var bayNo: Int?
        public var isMarker: Bool
        public var teamNo: Int?
    }

    public struct Match: Sendable, Equatable {
        public var roundID: UUID
        public var matchNo: Int
        public var playerA: UUID?
        public var playerB: UUID?
        public var playerC: UUID?
        public var teamA: Int?
        public var teamB: Int?
        /// `a`, `b` eller `halved`.
        public var result: String?
    }

    public struct Score: Sendable, Equatable {
        public var roundID: UUID
        public var memberID: UUID
        public var holeIndex: Int
        public var strokes: Int
        public var recordedAt: String?
    }

    public struct SideClaim: Sendable, Equatable {
        public var id: UUID
        public var roundID: UUID
        public var memberID: UUID
        /// `drive` eller `kp`.
        public var kind: String
        public var meters: Double
        public var holeIndex: Int?
        public var createdAt: String?
    }

    public struct Tip: Sendable, Equatable {
        public var eventID: UUID
        public var memberID: UUID
        public var winner: UUID?
        public var frontNine: UUID?
        public var mostPars: UUID?
        public var birdie: Bool?
        public var overLine: Bool?
    }

    public struct ThreadMessage: Sendable, Equatable {
        public var id: UUID
        public var eventID: UUID
        public var memberID: UUID
        public var body: String
        public var mentions: [UUID]
        public var createdAt: String?
    }

    /// PWA-ens lagrede rundepoeng (`round_points`), bare til paritetssjekken. Importeres ikke.
    public struct StoredPoints: Sendable, Equatable {
        public var roundID: UUID
        public var memberID: UUID
        public var points: Int
    }

    public var club: Club
    /// `true`: klubben finnes fra før (`--club-id`), og importen lager den ikke.
    public var clubExists: Bool
    public var members: [Member]
    public var season: Season
    public var courses: [Course]
    public var courseHoles: [CourseHole]
    public var events: [Event]
    public var committee: [Committee]
    public var signups: [Signup]
    public var rounds: [Round]
    public var roundHoles: [RoundHole]
    public var roundPlayers: [RoundPlayer]
    public var matches: [Match]
    public var scores: [Score]
    public var sideClaims: [SideClaim]
    public var tips: [Tip]
    public var threadMessages: [ThreadMessage]
    public var storedPoints: [StoredPoints]
    /// Det som ble rettet, kuttet eller hoppet over, i lesbar form (uten navn).
    public var warnings: [String]
}
