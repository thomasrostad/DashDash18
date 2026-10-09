import Foundation
import GolfgutuCore

// Kontrakten mellom feedmodellen og Hjem-fanen (fase 19, docs/hjem-feed.md, retning 1a med
// 1b-oppsummeringen øverst). Alt her er ferdig tekst og tall: viewene velger bare utseende.
// Ren, uten nettverk og SwiftUI. `HomeFeed.build` lager den av `HomeFeedInput`.

// MARK: - Inn

/// Deg, på tvers av klubbene: profilen og medlemskapet ditt i hver klubb (aktivt).
nonisolated struct HomeViewer: Equatable, Sendable {
    let profileID: UUID?
    /// `clubs.id` → `club_members.id`.
    let memberships: [UUID: UUID]

    init(profileID: UUID?, memberships: [UUID: UUID]) {
        self.profileID = profileID
        self.memberships = memberships
    }

    var memberIDs: Set<UUID> { Set(memberships.values) }

    /// Alle id-ene som er deg: medlemmene og profilen (`Entrant.id` i en privat turnering).
    var ids: Set<UUID> {
        var out = memberIDs
        if let profileID { out.insert(profileID) }
        return out
    }

    /// Spiller-id-en din i runden, eller nil når du ikke spiller. Klubbrunde: medlemmet ditt i klubben.
    /// Løs runde: deltakeren med profilen din.
    func playerID(in snapshot: RoundSnapshot) -> UUID? {
        if let club = snapshot.round.clubID {
            guard let member = memberships[club], snapshot.players.contains(where: { $0.memberID == member }) else {
                return nil
            }
            return member
        }
        guard let profileID, let me = snapshot.loose?.participant(profile: profileID)?.playerID,
              snapshot.players.contains(where: { $0.memberID == me }) else { return nil }
        return me
    }
}

/// En klubb du er aktivt medlem i.
nonisolated struct HomeClub: Equatable, Sendable {
    let id: UUID
    let name: String
}

/// Det en linje trenger å vite om runden den hører til («Losby · runde 4»).
nonisolated struct HomeRoundLabel: Equatable, Sendable {
    var courseName: String?
    /// Rundenummeret på kvelden. Nil for løse runder.
    var roundNo: Int?

    init(courseName: String?, roundNo: Int?) {
        self.courseName = courseName
        self.roundNo = roundNo
    }
}

/// Runden som pågår (fra `RundeModel` eller «Mine runder»).
nonisolated struct HomeLiveInput: Equatable, Sendable {
    var snapshot: RoundSnapshot
    var viewer: Viewer

    init(snapshot: RoundSnapshot, viewer: Viewer) {
        self.snapshot = snapshot
        self.viewer = viewer
    }
}

/// Neste kveld i klubben (fra `KveldModel`): kvelden, ditt svar og hvor mange som kommer.
nonisolated struct HomeEveningInput: Equatable, Sendable {
    var clubID: UUID
    var clubName: String
    var event: EventRow
    /// `YYYY-MM-DD` i Oslo.
    var today: String
    var answer: SignupStatus?
    var coming: Int
    var isOrganizer: Bool
    /// «Kveld» eller «spilledag» (`DayTerm`).
    var term: DayTerm = .evening
    /// Forrige kveld (`KveldModel.previousEvent`).
    var previous: EventRow?

    init(clubID: UUID, clubName: String, event: EventRow, today: String, answer: SignupStatus?, coming: Int,
         isOrganizer: Bool) {
        self.clubID = clubID
        self.clubName = clubName
        self.event = event
        self.today = today
        self.answer = answer
        self.coming = coming
        self.isOrganizer = isOrganizer
    }
}

/// Råmaterialet til feeden. Alt er valgfritt: det som mangler, gir bare færre kort.
nonisolated struct HomeFeedInput: Sendable {
    var now: Date = .now
    var viewer: HomeViewer
    var clubs: [HomeClub] = []
    /// Turneringene du ser (`CompetitionAccess.canSee`), også private og ferdige.
    var competitions: [CompetitionRow] = []
    /// `competition_rounds` for rundene i feeden.
    var links: [CompetitionRoundRow] = []
    /// `activity` fra alle klubbene dine (RLS), nyeste først.
    var activity: [ActivityRow] = []
    var reactions: [ActivityReactionRow] = []
    /// Navn på medlemmer (alle klubbene), deltakere og profiler.
    var names: [UUID: String] = [:]
    /// Bane og rundenummer for rundene aktivitetslinjene peker på.
    var roundLabels: [UUID: HomeRoundLabel] = [:]
    /// Runder med alt under: dine runder (klubb og løse) og rundene i private turneringer. Gir
    /// «Din runde» og bragdene utenfor klubbene dine.
    var rounds: [RoundSnapshot] = []
    /// Tabellgrunnlaget for private turneringer (liga og morro): plassbyttet regnes her, det logges ikke.
    var competitionInputs: [CompetitionInput] = []
    var live: HomeLiveInput?
    var evening: HomeEveningInput?
    /// Sist du så Hjem (`HomeSeenStore`). Nil = aldri: ingen oppsummering, ingenting merket ulest.
    var lastSeen: Date?
    var filter: HomeFeedFilter = .all

    init(now: Date = .now, viewer: HomeViewer) {
        self.now = now
        self.viewer = viewer
    }
}

// MARK: - Ut

/// Filterpillene: Alt · én per turnering (eller klubb uten hovedturnering) · Løse runder.
nonisolated enum HomeFeedFilter: Hashable, Sendable {
    case all
    case competition(UUID)
    /// Klubb uten hovedturnering: klubbens linjer (påmeldinger, meldinger) samles her.
    case club(UUID)
    case loose
}

/// Fargen på kilde-pillen (`DDTone` i appen): hovedturneringen lime, løse runder earth, de andre
/// turneringene sol, blush og gull etter tur.
nonisolated enum HomeFeedTone: Equatable, Sendable {
    case lime, sun, earth, blush, gold
}

/// Hvor et kort kommer fra: pillen på kortet («Jakkeracet», «Morrocupen», «Løs runde»).
nonisolated struct HomeFeedSource: Hashable, Sendable {
    let filter: HomeFeedFilter
    let title: String
    let tone: HomeFeedTone
}

nonisolated struct HomeFeedPill: Identifiable, Equatable, Sendable {
    let filter: HomeFeedFilter
    let title: String
    let tone: HomeFeedTone?
    let isSelected: Bool

    var id: String {
        switch filter {
        case .all: "alle"
        case .competition(let id): "k-\(id.uuidString)"
        case .club(let id): "c-\(id.uuidString)"
        case .loose: "lose"
        }
    }
}

/// Reaksjonene under et kort, og hvor et trykk skal (`ActivityLog(clubID:).toggle`).
nonisolated struct HomeReactions: Equatable, Sendable {
    let activityID: UUID
    let clubID: UUID
    let chips: [ReactionChip]
}

/// «Birdie 2»: et scoremerke på «Din runde», med tonen fra `ScoreName.tone`.
nonisolated struct HomeScoreMark: Equatable, Sendable {
    let name: ScoreName
    let count: Int
    var label: String { "\(name.label) \(count)" }
}

/// Din runde (stort kort).
nonisolated struct HomeMyRoundCard: Equatable, Sendable {
    let roundID: UUID
    let isLoose: Bool
    /// Banen.
    let title: String
    /// «Runde 4 · med Anders og Bjørn», «med Per og Even».
    let subtitle: String?
    /// Stablefordpoengene (52 lett). Nil når runden avgjøres hull for hull.
    let points: Int?
    /// Det som står når det ikke er poeng: «1 opp», ellers «34 p».
    let value: String
    let place: Int?
    /// «2. plass».
    let placeText: String?
    /// «av 3 spillere».
    let ofText: String
    let marks: [HomeScoreMark]
    /// Innsikt («Beste runde på … i år»). Krever statistikken (fase 16); nil til den kobles på.
    let insight: String?
    /// «Vinner: Per · 36 p».
    let winner: String?
    let reactions: HomeReactions?
}

/// Bragd: eagle, albatross eller hole in one (brutto).
nonisolated struct HomeFeatCard: Equatable, Sendable {
    let memberID: UUID
    let name: String
    /// «AB».
    let initials: String
    let isMe: Bool
    let kind: BigScoreName
    let strokes: Int
    let par: Int
    let hole: Int
    /// «Eagle på hull 5», «Hole in one på hull 12!».
    let headline: String
    /// «3 slag på par 5 · Losby».
    let detail: String
    /// «Losby · runde 4 · hull 5».
    let place: String
    let roundID: UUID?
    let reactions: HomeReactions?
}

/// En rad i minitabellen.
nonisolated struct HomeTableRow: Equatable, Identifiable, Sendable {
    let id: UUID
    let place: Int
    let name: String
    let points: String?
    /// Plasser opp (positivt) eller ned.
    let move: Int?
    let isMe: Bool

    /// «↑1», «↓2», eller nil.
    var moveText: String? {
        guard let move, move != 0 else { return nil }
        return move > 0 ? "↑\(move)" : "↓\(-move)"
    }
}

/// Tabellendring: tekst sett fra deg, topp 3 (og deg under når du er lenger ned), og lenken til tabellen.
nonisolated struct HomeTableCard: Equatable, Sendable {
    let competitionID: UUID
    let competitionName: String
    /// «Du klatret til 3. plass i Jakkeracet etter runde 3», «Anders gikk forbi deg i …».
    let text: String
    let rows: [HomeTableRow]
    let myPlace: Int?
    let myMove: Int?
    let reactions: HomeReactions?
}

/// En kompakt linje (sidepremie, tippekonge, melding til alle, påmelding, sosialkomiteen).
nonisolated struct HomeLine: Equatable, Identifiable, Sendable {
    let id: String
    /// SF Symbol (`ActivityDisplay.symbol`).
    let symbol: String
    let text: String
    /// «Jakkeracet · runde 3», eller klubbens navn.
    let context: String
    let time: String
    let reactions: HomeReactions?
}

nonisolated struct HomeFeedCard: Identifiable, Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case myRound(HomeMyRoundCard)
        case feat(HomeFeatCard)
        case table(HomeTableCard)
        /// Én eller flere kompakte linjer fra samme kilde, etter hverandre.
        case lines([HomeLine])
    }

    let id: String
    let date: Date
    /// «3 min», «i går 21:04», «3. okt.» (`ActivityFeed.relativeTime`).
    let time: String
    let source: HomeFeedSource
    /// Filtrene kortet står under: kilden, andre turneringer runden teller i, og «Løse runder».
    let filters: Set<HomeFeedFilter>
    let content: Content
    /// Nyere enn sist du så Hjem, og ikke noe du gjorde selv.
    let isUnread: Bool
}

nonisolated struct HomeFeedSection: Identifiable, Equatable, Sendable {
    /// «I dag», «I går», «Tidligere».
    let title: String
    let cards: [HomeFeedCard]
    var id: String { title }
}

/// 1b-oppsummeringen: én setning og tre tall.
nonisolated struct HomeSummary: Equatable, Sendable {
    struct Stat: Equatable, Sendable {
        let value: String
        let label: String
    }

    /// «Siden sist · søndag».
    let eyebrow: String
    /// «Du klatret til 3. plass i Jakkeracet, og Anders slo eagle.»
    let sentence: String
    /// Nye runder, bragder og plasser (med fortegn).
    let stats: [Stat]
}

/// «Pågår nå».
nonisolated struct HomeLive: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        let id: UUID
        /// «1.», eller «–» når runden avgjøres hull for hull.
        let place: String
        let name: String
        let value: String
        let isMe: Bool
    }

    let roundID: UUID
    let isLoose: Bool
    /// «Hull 10 av 18».
    let progress: String
    /// «Losby · runde 4».
    let title: String
    /// «Teller i Jakkeracet og Morrocupen · bås 2».
    let detail: String?
    /// Bayen nå, topp 3.
    let top: [Row]
    /// Deg, når du er lenger ned enn topp 3.
    let me: Row?
    let actionTitle: String
}

/// «Neste kveld», med svarknappene.
nonisolated struct HomeNextEvening: Equatable, Sendable {
    let clubID: UUID
    let eventID: UUID
    /// «Golfgutu Invitational · neste kveld».
    let eyebrow: String
    /// «Torsdag 15. oktober».
    let title: String
    /// «I dag», «I morgen», «Om 8 dager».
    let countdown: String
    /// «Kl. 18:00 · Golfstudio Bryn · 6 kommer».
    let detail: String
    let answer: SignupStatus?
    /// Arrangøren får hovedknappen (sett opp runden) og lenken til arrangørsiden.
    let isOrganizer: Bool
    /// Forrige kveld, for «Forrige kupong» (resultatet og tippekongen).
    var previousEventID: UUID? = nil
    /// «Torsdag 8. oktober».
    var previousTitle: String? = nil
}

/// Hele Hjem-feeden.
nonisolated struct HomeFeed: Equatable, Sendable {
    let pills: [HomeFeedPill]
    let filter: HomeFeedFilter
    let summary: HomeSummary?
    let live: HomeLive?
    let evening: HomeNextEvening?
    let sections: [HomeFeedSection]

    var isEmpty: Bool { sections.isEmpty }
}
