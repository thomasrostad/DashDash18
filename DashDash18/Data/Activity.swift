import Foundation
import GolfgutuCore
import Supabase

// Aktivitetsloggen (`sql/008_sosialt.sql`, tabellene `activity` og `activity_reactions`).
// En hendelse lagres strukturert: `kind` sier hva, `data` har detaljene (id-er, hull, tall),
// og appen lager teksten. Ingen HTML, ingen ferdig tekst i databasen (utenom «Melding til alle»,
// der teksten ER hendelsen). Navn slås opp når linja vises, så et nytt visningsnavn slår igjennom.

// MARK: - Kategorier og reaksjoner

/// Push-kategorien (fase 8). Samme liste som `check` på `activity.category`.
nonisolated enum ActivityCategory: String, Codable, CaseIterable, Sendable {
    case score
    case lead
    case sidePrize = "side_prize"
    case round
    case setup
    case bet
    case signup
    case social
    case club
    case tips
    case announcement
    case nudge
    case reminder

    /// Bare arrangøren kan skrive disse (triggeren `activity_before_insert`).
    var isOrganizerOnly: Bool {
        self == .announcement || self == .nudge || self == .reminder
    }

    /// Navnet i «Hva blir push» (PWA: `VARSEL_KATEGORIER`).
    var title: String {
        switch self {
        case .score: "Store scorer"
        case .lead: "Ledelsen underveis"
        case .sidePrize: "Sidepremier"
        case .round: "Rundene"
        case .setup: "Oppsett og rettinger"
        case .bet: "Veddemål"
        case .signup: "Påmeldinger"
        case .social: "Sosialkomiteen"
        case .club: "Klubben"
        case .tips: "Tippekupongen"
        case .announcement: "Melding til alle"
        case .nudge: "Purring"
        case .reminder: "Påminnelser"
        }
    }
}

/// Det faste reaksjonssettet. Må stå likt som `check` på `activity_reactions.emoji`
/// (PWA: `REAKSJONER`). Rekkefølgen er visningsrekkefølgen.
nonisolated enum ActivityReaction: String, Codable, CaseIterable, Sendable {
    case thumbsUp = "👍"
    case laugh = "😂"
    case flag = "⛳"
    case fire = "🔥"
    case heart = "❤️"

    var accessibilityName: String {
        switch self {
        case .thumbsUp: "Tommel opp"
        case .laugh: "Ler"
        case .flag: "Flagg"
        case .fire: "Ild"
        case .heart: "Hjerte"
        }
    }
}

// MARK: - Rader

/// Detaljene i `activity.data`. Alle felt er valgfrie; hver `kind` bruker sine.
/// Nøklene er snake_case i jsonb. Tomme felt skrives ikke.
nonisolated struct ActivityData: Codable, Equatable, Sendable {
    var member: UUID?
    var members: [UUID]?
    /// Hullnummeret slik det står på scorekortet (1-basert, `holeNumber`).
    var hole: Int?
    /// Rundens 0-baserte hull.
    var holeIndex: Int?
    /// `big_score`: `eagle`, `albatross` eller `hole_in_one`.
    var name: String?
    var strokes: Int?
    var par: Int?
    /// `lead_changed`: antall hull ledelsen er målt over.
    var afterHole: Int?
    var leaders: [UUID]?
    var points: Int?
    /// `lead_changed`: se `LeadOutcome`.
    var outcome: String?
    /// `side_prize`: `drive` eller `kp`.
    var kind: String?
    var meters: Double?
    /// `side_prize`: den som ledet før.
    var passed: UUID?
    var passedMeters: Double?
    /// `signup`: `yes`, `maybe` eller `no`.
    var status: String?
    /// Kvelden, `YYYY-MM-DD`.
    var eventDate: String?
    var roundNo: Int?
    var courseName: String?
    var holeCount: Int?
    var bays: Int?
    var ldHole: Int?
    var kpHole: Int?
    /// «Melding til alle».
    var text: String?
    var from: Int?
    var to: Int?
    var coming: Int?
    var unsure: Int?
    var correct: Int?
    var possible: Int?

    init(member: UUID? = nil, members: [UUID]? = nil, hole: Int? = nil, holeIndex: Int? = nil, name: String? = nil,
         strokes: Int? = nil, par: Int? = nil, afterHole: Int? = nil, leaders: [UUID]? = nil, points: Int? = nil,
         outcome: String? = nil, kind: String? = nil, meters: Double? = nil, passed: UUID? = nil,
         passedMeters: Double? = nil, status: String? = nil, eventDate: String? = nil, roundNo: Int? = nil,
         courseName: String? = nil, holeCount: Int? = nil, bays: Int? = nil, ldHole: Int? = nil, kpHole: Int? = nil,
         text: String? = nil, from: Int? = nil, to: Int? = nil, coming: Int? = nil, unsure: Int? = nil,
         correct: Int? = nil, possible: Int? = nil) {
        self.member = member
        self.members = members
        self.hole = hole
        self.holeIndex = holeIndex
        self.name = name
        self.strokes = strokes
        self.par = par
        self.afterHole = afterHole
        self.leaders = leaders
        self.points = points
        self.outcome = outcome
        self.kind = kind
        self.meters = meters
        self.passed = passed
        self.passedMeters = passedMeters
        self.status = status
        self.eventDate = eventDate
        self.roundNo = roundNo
        self.courseName = courseName
        self.holeCount = holeCount
        self.bays = bays
        self.ldHole = ldHole
        self.kpHole = kpHole
        self.text = text
        self.from = from
        self.to = to
        self.coming = coming
        self.unsure = unsure
        self.correct = correct
        self.possible = possible
    }

    enum CodingKeys: String, CodingKey {
        case member, members, hole
        case holeIndex = "hole_index"
        case name, strokes, par
        case afterHole = "after_hole"
        case leaders, points, outcome, kind, meters, passed
        case passedMeters = "passed_meters"
        case status
        case eventDate = "event_date"
        case roundNo = "round_no"
        case courseName = "course_name"
        case holeCount = "hole_count"
        case bays
        case ldHole = "ld_hole"
        case kpHole = "kp_hole"
        case text, from, to, coming, unsure, correct, possible
    }

    /// Tåler felt med feil type (en annen klient, en eldre versjon): feltet blir nil,
    /// resten leses. Én rar rad skal ikke ta ned hele varslinga.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        member = get(.member)
        members = get(.members)
        hole = get(.hole)
        holeIndex = get(.holeIndex)
        name = get(.name)
        strokes = get(.strokes)
        par = get(.par)
        afterHole = get(.afterHole)
        leaders = get(.leaders)
        points = get(.points)
        outcome = get(.outcome)
        kind = get(.kind)
        meters = get(.meters)
        passed = get(.passed)
        passedMeters = get(.passedMeters)
        status = get(.status)
        eventDate = get(.eventDate)
        roundNo = get(.roundNo)
        courseName = get(.courseName)
        holeCount = get(.holeCount)
        bays = get(.bays)
        ldHole = get(.ldHole)
        kpHole = get(.kpHole)
        text = get(.text)
        from = get(.from)
        to = get(.to)
        coming = get(.coming)
        unsure = get(.unsure)
        correct = get(.correct)
        possible = get(.possible)
    }
}

/// En rad i `activity`. Append-only: ingen oppdatering eller sletting fra appen.
nonisolated struct ActivityRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let clubID: UUID
    var kind: String
    /// Ukjent kategori (en nyere server) leses som nil i stedet for å feile.
    var category: ActivityCategory?
    var data: ActivityData
    /// Settes av serveren. nil = systemet (cron, import), eller et medlem som er slettet.
    var actorMemberID: UUID?
    var eventID: UUID?
    var roundID: UUID?
    /// nil = alle i klubben. En liste = bare dem (purring). RLS viser linja bare for dem,
    /// den som laget den og arrangøren.
    var recipients: [UUID]?
    var createdAt: Date

    init(id: UUID, clubID: UUID, kind: String, category: ActivityCategory?, data: ActivityData,
         actorMemberID: UUID? = nil, eventID: UUID? = nil, roundID: UUID? = nil, recipients: [UUID]? = nil,
         createdAt: Date) {
        self.id = id
        self.clubID = clubID
        self.kind = kind
        self.category = category
        self.data = data
        self.actorMemberID = actorMemberID
        self.eventID = eventID
        self.roundID = roundID
        self.recipients = recipients
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case kind
        case category
        case data
        case actorMemberID = "actor_member_id"
        case eventID = "event_id"
        case roundID = "round_id"
        case recipients
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clubID = try c.decode(UUID.self, forKey: .clubID)
        kind = try c.decode(String.self, forKey: .kind)
        category = (try? c.decodeIfPresent(ActivityCategory.self, forKey: .category)) ?? nil
        data = (try? c.decodeIfPresent(ActivityData.self, forKey: .data)) ?? ActivityData()
        actorMemberID = try c.decodeIfPresent(UUID.self, forKey: .actorMemberID)
        eventID = try c.decodeIfPresent(UUID.self, forKey: .eventID)
        roundID = try c.decodeIfPresent(UUID.self, forKey: .roundID)
        recipients = try c.decodeIfPresent([UUID].self, forKey: .recipients)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }

    var event: ActivityEvent { ActivityEvent(kind: kind, data: data) }
}

/// En rad i `activity_reactions`: én per hendelse, medlem og emoji.
nonisolated struct ActivityReactionRow: Codable, Equatable, Hashable, Sendable {
    let activityID: UUID
    let memberID: UUID
    let clubID: UUID
    /// Ukjent emoji (en nyere server) leses som nil og vises ikke.
    var emoji: ActivityReaction?
    var createdAt: Date?

    init(activityID: UUID, memberID: UUID, clubID: UUID, emoji: ActivityReaction?, createdAt: Date? = nil) {
        self.activityID = activityID
        self.memberID = memberID
        self.clubID = clubID
        self.emoji = emoji
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case activityID = "activity_id"
        case memberID = "member_id"
        case clubID = "club_id"
        case emoji
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activityID = try c.decode(UUID.self, forKey: .activityID)
        memberID = try c.decode(UUID.self, forKey: .memberID)
        clubID = try c.decode(UUID.self, forKey: .clubID)
        emoji = (try? c.decodeIfPresent(ActivityReaction.self, forKey: .emoji)) ?? nil
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

// MARK: - Katalogen over hendelser

/// `big_score`: brutto, ikke netto (README «Varsler underveis i en runde»).
nonisolated enum BigScoreName: String, Codable, Sendable {
    case eagle
    case albatross
    case holeInOne = "hole_in_one"
}

/// `lead_changed`: hva som skjedde ved sjekkpunktet (`loggLedelseHvisEndret`).
nonisolated enum LeadOutcome: String, Codable, Sendable {
    /// Første sjekkpunkt: «leder».
    case leads
    /// Ny leder: «har tatt ledelsen».
    case tookLead = "took_lead"
    /// Delt ledelse underveis: «deler ledelsen».
    case shares
    /// Siste hull, samme leder som før: «vant runden».
    case won
    /// Siste hull, ny leder: «snappet runden på siste hull».
    case snatched
    /// Siste hull, delt: «endte likt».
    case tiedFinish = "tied_finish"
}

/// Alle hendelsestypene appen skriver og leser. `kind` er nøkkelen i databasen.
/// En ukjent `kind` (en nyere klient) blir `.unknown` og vises med en nøytral tekst.
nonisolated enum ActivityEvent: Equatable, Sendable {
    case roundStarted(roundNo: Int, courseName: String?, holeCount: Int?, bays: Int?, ldHole: Int?, kpHole: Int?)
    case roundLocked(roundNo: Int, courseName: String?)
    case roundDeleted(roundNo: Int, courseName: String?)
    /// `hole` er hullnummeret på kortet, `holeIndex` rundens 0-baserte hull.
    case bigScore(member: UUID, hole: Int, holeIndex: Int?, name: BigScoreName, strokes: Int, par: Int)
    case leadChanged(afterHole: Int, leaders: [UUID], points: Int, outcome: LeadOutcome)
    /// Ny leder på longest drive eller nærmest pinnen. `hole` er hullnummeret på kortet.
    case sidePrize(kind: SideClaimKind, member: UUID, hole: Int, meters: Double, passed: UUID?, passedMeters: Double?)
    case scoreCorrected(member: UUID, hole: Int, from: Int?, to: Int?, roundNo: Int?, courseName: String?)
    /// Bare det som er nytt: kommer, meldte forfall, eller likevel usikker (`svarLinje`).
    case signup(member: UUID, status: SignupStatus, eventDate: String?)
    /// Purring. Mottakerne står i `recipients` på raden, ikke her.
    case nudge(eventDate: String?)
    case reminder(eventDate: String?, coming: Int?, unsure: Int?)
    case announcement(text: String)
    case committeeDrawn(eventDate: String?, members: [UUID])
    case memberJoined(member: UUID)
    case tipsKing(members: [UUID], correct: Int, possible: Int, eventDate: String?)
    case unknown(kind: String)

    /// Alle kjente nøkler, for tester og dokumentasjon.
    static let knownKinds = [
        "round_started", "round_locked", "round_deleted", "big_score", "lead_changed", "side_prize",
        "score_corrected", "signup", "nudge", "reminder", "announcement", "committee_drawn",
        "member_joined", "tips_king",
    ]

    var kind: String {
        switch self {
        case .roundStarted: "round_started"
        case .roundLocked: "round_locked"
        case .roundDeleted: "round_deleted"
        case .bigScore: "big_score"
        case .leadChanged: "lead_changed"
        case .sidePrize: "side_prize"
        case .scoreCorrected: "score_corrected"
        case .signup: "signup"
        case .nudge: "nudge"
        case .reminder: "reminder"
        case .announcement: "announcement"
        case .committeeDrawn: "committee_drawn"
        case .memberJoined: "member_joined"
        case .tipsKing: "tips_king"
        case .unknown(let kind): kind
        }
    }

    var category: ActivityCategory {
        switch self {
        case .roundStarted, .roundLocked, .roundDeleted: .round
        case .bigScore: .score
        case .leadChanged: .lead
        case .sidePrize: .sidePrize
        case .scoreCorrected: .setup
        case .signup: .signup
        case .nudge: .nudge
        case .reminder: .reminder
        case .announcement: .announcement
        case .committeeDrawn: .social
        case .memberJoined: .club
        case .tipsKing: .tips
        case .unknown: .club
        }
    }

    var data: ActivityData {
        switch self {
        case let .roundStarted(roundNo, courseName, holeCount, bays, ldHole, kpHole):
            ActivityData(roundNo: roundNo, courseName: courseName, holeCount: holeCount, bays: bays,
                         ldHole: ldHole, kpHole: kpHole)
        case let .roundLocked(roundNo, courseName), let .roundDeleted(roundNo, courseName):
            ActivityData(roundNo: roundNo, courseName: courseName)
        case let .bigScore(member, hole, holeIndex, name, strokes, par):
            ActivityData(member: member, hole: hole, holeIndex: holeIndex, name: name.rawValue, strokes: strokes, par: par)
        case let .leadChanged(afterHole, leaders, points, outcome):
            ActivityData(afterHole: afterHole, leaders: leaders, points: points, outcome: outcome.rawValue)
        case let .sidePrize(kind, member, hole, meters, passed, passedMeters):
            ActivityData(member: member, hole: hole, kind: kind.rawValue, meters: meters, passed: passed,
                         passedMeters: passedMeters)
        case let .scoreCorrected(member, hole, from, to, roundNo, courseName):
            ActivityData(member: member, hole: hole, roundNo: roundNo, courseName: courseName, from: from, to: to)
        case let .signup(member, status, eventDate):
            ActivityData(member: member, status: status.rawValue, eventDate: eventDate)
        case let .nudge(eventDate):
            ActivityData(eventDate: eventDate)
        case let .reminder(eventDate, coming, unsure):
            ActivityData(eventDate: eventDate, coming: coming, unsure: unsure)
        case let .announcement(text):
            ActivityData(text: text)
        case let .committeeDrawn(eventDate, members):
            ActivityData(members: members, eventDate: eventDate)
        case let .memberJoined(member):
            ActivityData(member: member)
        case let .tipsKing(members, correct, possible, eventDate):
            ActivityData(members: members, eventDate: eventDate, correct: correct, possible: possible)
        case .unknown:
            ActivityData()
        }
    }

    /// Leser en rad tilbake. Mangler et felt hendelsen ikke klarer seg uten, blir den `.unknown`.
    init(kind: String, data d: ActivityData) {
        switch kind {
        case "round_started":
            self = .roundStarted(roundNo: d.roundNo ?? 0, courseName: d.courseName, holeCount: d.holeCount,
                                 bays: d.bays, ldHole: d.ldHole, kpHole: d.kpHole)
        case "round_locked":
            self = .roundLocked(roundNo: d.roundNo ?? 0, courseName: d.courseName)
        case "round_deleted":
            self = .roundDeleted(roundNo: d.roundNo ?? 0, courseName: d.courseName)
        case "big_score":
            guard let member = d.member, let hole = d.hole, let name = d.name.flatMap(BigScoreName.init),
                  let strokes = d.strokes, let par = d.par else { self = .unknown(kind: kind); return }
            self = .bigScore(member: member, hole: hole, holeIndex: d.holeIndex, name: name, strokes: strokes, par: par)
        case "lead_changed":
            guard let after = d.afterHole, let leaders = d.leaders, !leaders.isEmpty, let points = d.points,
                  let outcome = d.outcome.flatMap(LeadOutcome.init) else { self = .unknown(kind: kind); return }
            self = .leadChanged(afterHole: after, leaders: leaders, points: points, outcome: outcome)
        case "side_prize":
            guard let prize = d.kind.flatMap(SideClaimKind.init), let member = d.member, let hole = d.hole,
                  let meters = d.meters else { self = .unknown(kind: kind); return }
            self = .sidePrize(kind: prize, member: member, hole: hole, meters: meters, passed: d.passed,
                              passedMeters: d.passedMeters)
        case "score_corrected":
            guard let member = d.member, let hole = d.hole else { self = .unknown(kind: kind); return }
            self = .scoreCorrected(member: member, hole: hole, from: d.from, to: d.to, roundNo: d.roundNo,
                                   courseName: d.courseName)
        case "signup":
            guard let member = d.member, let status = d.status.flatMap(SignupStatus.init) else {
                self = .unknown(kind: kind); return
            }
            self = .signup(member: member, status: status, eventDate: d.eventDate)
        case "nudge":
            self = .nudge(eventDate: d.eventDate)
        case "reminder":
            self = .reminder(eventDate: d.eventDate, coming: d.coming, unsure: d.unsure)
        case "announcement":
            guard let text = d.text else { self = .unknown(kind: kind); return }
            self = .announcement(text: text)
        case "committee_drawn":
            self = .committeeDrawn(eventDate: d.eventDate, members: d.members ?? [])
        case "member_joined":
            guard let member = d.member else { self = .unknown(kind: kind); return }
            self = .memberJoined(member: member)
        case "tips_king":
            guard let members = d.members, let correct = d.correct, let possible = d.possible else {
                self = .unknown(kind: kind); return
            }
            self = .tipsKing(members: members, correct: correct, possible: possible, eventDate: d.eventDate)
        default:
            self = .unknown(kind: kind)
        }
    }
}

// MARK: - Visningstekst

/// Det en linje i Varsler viser: ikon og tekst. `emoji` er for push (fase 8), der ikonet
/// ikke finnes.
nonisolated struct ActivityDisplay: Equatable, Sendable {
    /// SF Symbol.
    let symbol: String
    let emoji: String
    let text: String
}

nonisolated enum ActivityText {
    /// «Melding til alle»: linjeskift og doble mellomrom blir ett mellomrom, maks 300 tegn
    /// (PWA: `KUNNGJORING_MAKS`, `kunngjoring-test.js`).
    static let announcementMaxLength = 300

    static func cleanAnnouncement(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(announcementMaxLength))
    }

    /// Teksten for en rad. `name` slår opp visningsnavnet; ukjent gir «Noen» (som PWA-en).
    static func display(_ row: ActivityRow, name: (UUID) -> String?) -> ActivityDisplay {
        display(row.event, actor: row.actorMemberID, recipients: row.recipients, name: name)
    }

    static func display(_ event: ActivityEvent, actor: UUID?, recipients: [UUID]? = nil,
                        name lookup: (UUID) -> String?) -> ActivityDisplay {
        func who(_ id: UUID?) -> String { id.flatMap(lookup) ?? "Noen" }
        func list(_ ids: [UUID]) -> String { NorwegianList.join(ids.map { who($0) }) }
        func evening(_ date: String?) -> String? { date.map { EveningDates.longText($0) } }
        func round(_ no: Int?, _ course: String?) -> String {
            guard let no, no > 0 else { return course ?? "runden" }
            return RoundListing.title(roundNo: no, courseName: course)
        }

        switch event {
        case let .roundStarted(roundNo, courseName, holeCount, bays, ldHole, kpHole):
            var text = "Ny runde: " + round(roundNo, courseName)
            if let holeCount { text += " · \(holeCount) hull" }
            var extras: [String] = []
            if let ldHole { extras.append("longest drive på hull \(ldHole)") }
            if let kpHole { extras.append("nærmest pinnen på hull \(kpHole)") }
            if let bays, bays > 0 { extras.append(bays == 1 ? "1 bås" : "\(bays) båser") }
            if !extras.isEmpty { text += " — " + extras.joined(separator: ", ") }
            return ActivityDisplay(symbol: "flag.fill", emoji: "🏌️", text: text)

        case let .roundLocked(roundNo, courseName):
            return ActivityDisplay(symbol: "lock.fill", emoji: "🔒",
                                   text: "\(who(actor)) låste \(round(roundNo, courseName))")

        case let .roundDeleted(roundNo, courseName):
            return ActivityDisplay(symbol: "trash", emoji: "🗑️",
                                   text: "\(who(actor)) slettet \(round(roundNo, courseName))")

        case let .bigScore(member, hole, _, name, strokes, par):
            // Varselet sier alltid slag og par: terskelen er brutto (README).
            switch name {
            case .holeInOne:
                return ActivityDisplay(symbol: "target", emoji: "🎯", text: "\(who(member)) HOLE IN ONE på hull \(hole)!")
            case .albatross:
                return ActivityDisplay(symbol: "bird.fill", emoji: "🦅",
                                       text: "\(who(member)) albatross på hull \(hole) — \(strokes) slag på par \(par)")
            case .eagle:
                return ActivityDisplay(symbol: "bird.fill", emoji: "🦅",
                                       text: "\(who(member)) eagle på hull \(hole) — \(strokes) slag på par \(par)")
            }

        case let .leadChanged(afterHole, leaders, points, outcome):
            let tail = " etter \(afterHole) hull · \(points) poeng"
            let verb = switch outcome {
            case .leads: "leder"
            case .tookLead: "har tatt ledelsen"
            case .shares: "deler ledelsen"
            case .won: "vant runden"
            case .snatched: "snappet runden på siste hull"
            case .tiedFinish: "endte likt"
            }
            return ActivityDisplay(symbol: "chart.line.uptrend.xyaxis", emoji: "📈", text: list(leaders) + " " + verb + tail)

        case let .sidePrize(kind, member, hole, meters, passed, passedMeters):
            let m = SideClaimFormat.meters(kind, meters)
            var text: String
            switch kind {
            case .drive: text = "\(who(member)) leder longest drive på hull \(hole) med \(m)"
            case .kp: text = "\(who(member)) nærmest pinnen på hull \(hole) med \(m)"
            }
            if let passed {
                text += " — forbi \(who(passed))"
                if let passedMeters { text += " (\(SideClaimFormat.meters(kind, passedMeters)))" }
            }
            return ActivityDisplay(symbol: kind == .drive ? "ruler" : "scope", emoji: kind == .drive ? "🚀" : "🎯",
                                   text: text)

        case let .scoreCorrected(member, hole, from, to, roundNo, courseName):
            var text = "\(who(actor)) rettet hull \(hole) for \(who(member))"
            if roundNo != nil || courseName != nil { text += " i " + round(roundNo, courseName) }
            let before = from.map(String.init) ?? "–"
            let after = to.map(String.init) ?? "–"
            text += ": \(before) → \(after)"
            return ActivityDisplay(symbol: "pencil", emoji: "✏️", text: text)

        case let .signup(member, status, eventDate):
            let date = evening(eventDate)
            switch status {
            case .yes:
                return ActivityDisplay(symbol: "checkmark.circle.fill", emoji: "✅",
                                       text: "\(who(member)) meldte seg på" + (date.map { " \($0)" } ?? ""))
            case .no:
                return ActivityDisplay(symbol: "arrow.uturn.backward", emoji: "↩️",
                                       text: "\(who(member)) meldte forfall" + (date.map { " til \($0)" } ?? ""))
            case .maybe:
                return ActivityDisplay(symbol: "arrow.uturn.backward", emoji: "↩️",
                                       text: "\(who(member)) er likevel usikker" + (date.map { " på \($0)" } ?? ""))
            }

        case let .nudge(eventDate):
            var text = "Hvem kommer" + (evening(eventDate).map { " \($0)" } ?? "") + "?"
            if let recipients, !recipients.isEmpty {
                text += " Mangler svar fra \(list(recipients)) — svar i appen."
            } else {
                text += " Svar i appen."
            }
            return ActivityDisplay(symbol: "alarm", emoji: "⏰", text: text)

        case let .reminder(eventDate, coming, unsure):
            var text = "Påminnelse: " + (evening(eventDate).map { "\($0) om en uke" } ?? "neste kveld nærmer seg")
            var counts: [String] = []
            if let coming { counts.append("\(coming) kommer") }
            if let unsure, unsure > 0 { counts.append(unsure == 1 ? "1 usikker" : "\(unsure) usikre") }
            if !counts.isEmpty { text += " · " + counts.joined(separator: ", ") }
            return ActivityDisplay(symbol: "calendar", emoji: "📅", text: text)

        case let .announcement(text):
            return ActivityDisplay(symbol: "megaphone.fill", emoji: "📣", text: "\(who(actor)): \(text)")

        case let .committeeDrawn(eventDate, members):
            var text = "Sosialkomiteen"
            if let date = evening(eventDate) { text += " \(date)" }
            text += members.isEmpty ? " er trukket" : ": " + list(members)
            return ActivityDisplay(symbol: "mug.fill", emoji: "🍺", text: text)

        case let .memberJoined(member):
            return ActivityDisplay(symbol: "person.badge.plus", emoji: "⛳", text: "\(who(member)) ble med i klubben")

        case let .tipsKing(members, correct, possible, eventDate):
            let title = members.count > 1 ? "Tippekongene" : "Tippekongen"
            var text = title + (evening(eventDate).map { " \($0)" } ?? "") + ": "
            text += list(members) + " med \(correct) av \(possible) riktige"
            return ActivityDisplay(symbol: "crown.fill", emoji: "👑", text: text)

        case .unknown:
            return ActivityDisplay(symbol: "clock", emoji: "🔔", text: "Ny hendelse i klubben")
        }
    }
}

/// Meter som på hullkortet: én desimal, desimalkomma («272,5 m», «3,4 m»), `fmtMeter`.
nonisolated enum SideClaimFormat {
    static func meters(_ kind: SideClaimKind, _ meters: Double) -> String {
        SidePrizes.formatMeters(meters)
    }
}

// MARK: - Tid, gruppering og uleste

nonisolated enum ActivityFeed {
    struct Section: Equatable, Sendable {
        let title: String
        let rows: [ActivityRow]
    }

    /// «I dag» (kalenderdagen i Oslo) og «Tidligere», nyeste først. Tomme seksjoner tas ikke med.
    static func sections(_ rows: [ActivityRow], now: Date = .now) -> [Section] {
        let today = EveningDates.dateString(from: now)
        let sorted = rows.sorted { $0.createdAt > $1.createdAt }
        let todayRows = sorted.filter { EveningDates.dateString(from: $0.createdAt) == today }
        let earlier = sorted.filter { EveningDates.dateString(from: $0.createdAt) != today }
        return [Section(title: "I dag", rows: todayRows), Section(title: "Tidligere", rows: earlier)]
            .filter { !$0.rows.isEmpty }
    }

    /// Uleste: nyere enn sist sett, og ikke dine egne. Aldri sett = alt er ulest (som PWA-en).
    static func unreadCount(_ rows: [ActivityRow], lastSeen: Date?, me: UUID?) -> Int {
        rows.filter { isUnread($0, lastSeen: lastSeen, me: me) }.count
    }

    static func isUnread(_ row: ActivityRow, lastSeen: Date?, me: UUID?) -> Bool {
        if let me, row.actorMemberID == me { return false }
        guard let lastSeen else { return true }
        return row.createdAt > lastSeen
    }

    /// Tiden ved linja, i Oslo: «nå», «3 min», «2 t», «i går 21:04», «3. okt.», «3. okt. 2025».
    static func relativeTime(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "nå" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min" }
        let calendar = EveningDates.osloCalendar
        let today = EveningDates.dateString(from: now)
        let day = EveningDates.dateString(from: date)
        if day == today { return "\(minutes / 60) t" }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        if let days = EveningDates.daysBetween(day, today), days == 1 {
            return String(format: "i går %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        var text = "\(parts.day ?? 0). \(shortMonths[(parts.month ?? 1) - 1])"
        if parts.year != calendar.component(.year, from: now) { text += " \(parts.year ?? 0)" }
        return text
    }

    private static let shortMonths = ["jan.", "feb.", "mars", "apr.", "mai", "juni",
                                      "juli", "aug.", "sep.", "okt.", "nov.", "des."]
}

/// Brikkene under en linje: bare emojiene noen har brukt, med antall, i fast rekkefølge.
nonisolated struct ReactionChip: Equatable, Identifiable, Sendable {
    let reaction: ActivityReaction
    let count: Int
    let isMine: Bool
    /// Hvem som har reagert, sortert på navn (norsk).
    let names: [String]
    var id: String { reaction.rawValue }
}

nonisolated enum ActivityReactions {
    static func chips(for activityID: UUID, in rows: [ActivityReactionRow], me: UUID?,
                      name: (UUID) -> String?) -> [ReactionChip] {
        let mine = rows.filter { $0.activityID == activityID }
        return ActivityReaction.allCases.compactMap { reaction in
            let hits = mine.filter { $0.emoji == reaction }
            guard !hits.isEmpty else { return nil }
            let names = hits.map { name($0.memberID) ?? "Noen" }
                .sorted(by: NorwegianSort.areInIncreasingOrder)
            return ReactionChip(reaction: reaction, count: hits.count, isMine: hits.contains { $0.memberID == me },
                                names: names)
        }
    }

    /// Har jeg allerede reagert med denne?
    static func has(_ reaction: ActivityReaction, on activityID: UUID, by me: UUID, in rows: [ActivityReactionRow]) -> Bool {
        rows.contains { $0.activityID == activityID && $0.memberID == me && $0.emoji == reaction }
    }

    /// Settet etter et trykk: finnes reaksjonen, fjernes den; ellers legges den til.
    static func toggled(_ reaction: ActivityReaction, on activityID: UUID, by me: UUID, club: UUID,
                        in rows: [ActivityReactionRow], now: Date = .now) -> [ActivityReactionRow] {
        if has(reaction, on: activityID, by: me, in: rows) {
            return rows.filter { !($0.activityID == activityID && $0.memberID == me && $0.emoji == reaction) }
        }
        return rows + [ActivityReactionRow(activityID: activityID, memberID: me, clubID: club, emoji: reaction,
                                           createdAt: now)]
    }
}

// MARK: - API mot databasen

/// Logg, hent og reager. Alle skrivinger sjekker raden tilbake (RLS kan si nei uten feil).
/// Kladdrunder logges ikke: den som kaller, sender bare for runder som går eller er låst.
nonisolated struct ActivityLog: Sendable {
    let client: SupabaseClient
    let clubID: UUID

    static let columns =
        "id, club_id, kind, category, data, actor_member_id, event_id, round_id, recipients, created_at"
    static let reactionColumns = "activity_id, member_id, club_id, emoji, created_at"
    /// Hvor mange linjer Varsler henter.
    static let defaultLimit = 50

    private struct Insert: Encodable {
        let club_id: UUID
        let kind: String
        let category: String
        let data: ActivityData
        let event_id: UUID?
        let round_id: UUID?
        let recipients: [UUID]?
    }

    private struct ReactionInsert: Encodable {
        let activity_id: UUID
        let member_id: UUID
        let club_id: UUID
        let emoji: String
    }

    /// Skriver én hendelse. `recipients` krever arrangør (ellers 42501), og en tom liste betyr ingen.
    @discardableResult
    func log(_ event: ActivityEvent, eventID: UUID? = nil, roundID: UUID? = nil,
             recipients: [UUID]? = nil) async throws(DataError) -> ActivityRow {
        let insert = Insert(club_id: clubID, kind: event.kind, category: event.category.rawValue, data: event.data,
                            event_id: eventID, round_id: roundID, recipients: recipients)
        do {
            let rows: [ActivityRow] = try await client.from("activity")
                .insert(insert)
                .select(Self.columns)
                .execute().value
            guard let row = rows.first, row.kind == event.kind else { throw DataError.notAllowed }
            return row
        } catch {
            throw DataError.from(error)
        }
    }

    /// Logger uten å la en feil stoppe det som skjedde (en eagle er lagret selv om varselet feilet).
    func logQuietly(_ event: ActivityEvent, eventID: UUID? = nil, roundID: UUID? = nil, recipients: [UUID]? = nil) async {
        _ = try? await log(event, eventID: eventID, roundID: roundID, recipients: recipients)
    }

    /// De siste `limit` hendelsene i klubben som du får se, nyeste først.
    func recent(limit: Int = ActivityLog.defaultLimit) async throws(DataError) -> [ActivityRow] {
        do {
            return try await client.from("activity")
                .select(Self.columns)
                .eq("club_id", value: clubID)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute().value
        } catch {
            throw DataError.from(error)
        }
    }

    /// Hendelser nyere enn `date` (for bjella), uten dataene.
    func newer(than date: Date?, limit: Int = ActivityLog.defaultLimit) async throws(DataError) -> [ActivityRow] {
        do {
            var query = client.from("activity").select(Self.columns).eq("club_id", value: clubID)
            if let date { query = query.gt("created_at", value: date) }
            return try await query.order("created_at", ascending: false).limit(limit).execute().value
        } catch {
            throw DataError.from(error)
        }
    }

    /// Reaksjonene på hendelsene.
    func reactions(for activityIDs: [UUID]) async throws(DataError) -> [ActivityReactionRow] {
        guard !activityIDs.isEmpty else { return [] }
        do {
            return try await client.from("activity_reactions")
                .select(Self.reactionColumns)
                .eq("club_id", value: clubID)
                .in("activity_id", values: activityIDs)
                .execute().value
        } catch {
            throw DataError.from(error)
        }
    }

    /// Setter din reaksjon. Fantes den allerede (dobbelttrykk, en annen telefon), er målet nådd.
    func react(_ reaction: ActivityReaction, on activityID: UUID, as memberID: UUID) async throws(DataError) {
        do {
            let rows: [ActivityReactionRow] = try await client.from("activity_reactions")
                .insert(ReactionInsert(activity_id: activityID, member_id: memberID, club_id: clubID,
                                       emoji: reaction.rawValue))
                .select(Self.reactionColumns)
                .execute().value
            guard rows.first?.emoji == reaction else { throw DataError.notAllowed }
        } catch {
            let mapped = DataError.from(error)
            if mapped == .duplicate { return }
            throw mapped
        }
    }

    /// Fjerner din reaksjon. Var den borte allerede, er målet nådd.
    func unreact(_ reaction: ActivityReaction, on activityID: UUID, as memberID: UUID) async throws(DataError) {
        do {
            _ = try await client.from("activity_reactions")
                .delete()
                .eq("activity_id", value: activityID)
                .eq("member_id", value: memberID)
                .eq("emoji", value: reaction.rawValue)
                .execute()
        } catch {
            throw DataError.from(error)
        }
    }

    /// Setter eller fjerner, ut fra om du har den fra før.
    func toggle(_ reaction: ActivityReaction, on activityID: UUID, as memberID: UUID,
                currently has: Bool) async throws(DataError) {
        if has {
            try await unreact(reaction, on: activityID, as: memberID)
        } else {
            try await react(reaction, on: activityID, as: memberID)
        }
    }

    /// «Melding til alle» (bare arrangøren). Teksten renses og kuttes; tom tekst sendes ikke.
    @discardableResult
    func announce(_ raw: String) async throws(DataError) -> ActivityRow {
        let text = ActivityText.cleanAnnouncement(raw)
        guard !text.isEmpty else { throw .invalid("Skriv en beskjed først.") }
        return try await log(.announcement(text: text))
    }

    /// Purring: linja går bare til dem som mangler svar. Tom liste sendes ikke (ingen, aldri alle).
    @discardableResult
    func nudge(eventID: UUID, eventDate: String, missing: [UUID]) async throws(DataError) -> ActivityRow {
        guard !missing.isEmpty else { throw .invalid("Alle har svart.") }
        return try await log(.nudge(eventDate: eventDate), eventID: eventID, recipients: missing)
    }
}
