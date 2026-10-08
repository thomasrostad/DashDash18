import Foundation
import GolfgutuCore

/// «Ny runde» med venner: bane, start, form, spillere og hvem som fører. Alt annet (andel,
/// sidepremier, flight og markør, matcher) regnes av regelsettet og sendes i ett kall
/// (`start_loose_round`, sql/018).
nonisolated struct LooseRoundDraft: Equatable, Sendable {
    /// Hvem fører kortene.
    enum Scoring: String, CaseIterable, Sendable {
        /// Alle i én flight med deg som markør: du fører for alle.
        case oneCard
        /// Du fører for deg selv og gjestene; hver venn med profil fører sitt eget kort.
        case ownCards

        var title: String {
            switch self {
            case .oneCard: "Jeg fører for alle"
            case .ownCards: "Hver fører sitt eget kort"
            }
        }
    }

    /// En gjest med bare navn, og handicap om du vet det.
    struct Guest: Equatable, Identifiable, Sendable {
        let id: UUID
        var name: String
        var handicapText: String

        init(id: UUID = UUID(), name: String, handicapText: String = "") {
            self.id = id
            self.name = name
            self.handicapText = handicapText
        }

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var courseID: UUID?
    /// Teen på en ekte bane (sql/029, `SlopeNoFeature`). nil = banens CR og slope gjelder.
    var teeID: UUID?
    var holeCount = 18
    /// 1, eller 10 for «siste ni» på en 18-hullsbane.
    var firstHole = 1
    var formID: String
    /// Venner (profiler), i den rekkefølgen de ble lagt til.
    var friends: [UUID] = []
    var guests: [Guest] = []
    var scoring: Scoring = .oneCard
    /// Longest drive og nærmest pinnen, der regelsettet har dem.
    var sidePrizes: Bool

    /// Ny runde med regelsettets standard.
    static func new(rules: Ruleset = LooseRoundRules.template) -> LooseRoundDraft {
        LooseRoundDraft(
            formID: LooseRoundRules.defaultForm(rules)?.id ?? rules.formats.defaultFormID,
            sidePrizes: rules.sidePrizes.longestDrive.enabled || rules.sidePrizes.closestToPin.enabled
        )
    }

    var form: CompetitionForm { CompetitionForm.form(id: formID) }

    /// Deg, vennene og gjestene.
    var playerCount: Int { 1 + friends.count + guests.count }

    var start: QuickStartStart { QuickStartStart(firstHole: firstHole, holeCount: holeCount) }

    // MARK: Endringer

    /// Ny bane: 9 hull på en 9-hullsbane, og hull 10 bare der det går.
    mutating func setCourse(_ id: UUID?, courseHoles: Int?) {
        guard id != courseID else { return }
        courseID = id
        // Teen hører til banen.
        teeID = nil
        if courseHoles == 9 { holeCount = 9 }
        if !RoundDraft.canStartAtTen(holeCount: holeCount, courseHoles: courseHoles) { firstHole = 1 }
    }

    mutating func setStart(_ start: QuickStartStart, courseHoles: Int?) {
        holeCount = start.holeCount
        firstHole = RoundDraft.canStartAtTen(holeCount: start.holeCount, courseHoles: courseHoles) ? start.firstHole : 1
    }

    mutating func toggleFriend(_ id: UUID) {
        if let i = friends.firstIndex(of: id) {
            friends.remove(at: i)
        } else {
            friends.append(id)
        }
    }

    /// Legger til en gjest. Tomt navn legges ikke til.
    @discardableResult
    mutating func addGuest(name: String, handicapText: String = "") -> Bool {
        let guest = Guest(name: name, handicapText: handicapText)
        guard !guest.trimmedName.isEmpty else { return false }
        guests.append(guest)
        return true
    }

    mutating func removeGuest(_ id: UUID) {
        guests.removeAll { $0.id == id }
    }
}

// MARK: - Mangler

/// Det som stopper «Start runden».
nonisolated enum LooseRoundIssue: Equatable, Sendable {
    case noCourse
    case courseNotReady(String)
    case guestWithoutName
    case guestHandicap(name: String, message: String)
    /// Formen går ikke opp med antallet (matchspill trenger minst to).
    case form(String)
    case tooManyPlayers(max: Int)
    case tooManyGroups(max: Int)

    var message: String {
        switch self {
        case .noCourse: "Velg en bane."
        case .courseNotReady(let name): "«\(name)» mangler par på noen hull. Rett banen først."
        case .guestWithoutName: "En gjest mangler navn."
        case .guestHandicap(let name, let message): "\(name): \(message)"
        case .form(let reason): reason
        case .tooManyPlayers(let max): "Høyst \(max) spillere i én runde."
        case .tooManyGroups(let max): "Når hver fører sitt eget kort, får hver venn en egen flight, og det er plass til \(max). Velg «Jeg fører for alle»."
        }
    }
}

nonisolated enum LooseRoundSetup {
    /// Hva som mangler før runden kan startes. Tom liste = klar.
    static func issues(_ draft: LooseRoundDraft, course: CourseListItem?,
                       rules: Ruleset = LooseRoundRules.template) -> [LooseRoundIssue] {
        var issues: [LooseRoundIssue] = []
        if let course {
            if !course.isReady { issues.append(.courseNotReady(course.course.name)) }
        } else {
            issues.append(.noCourse)
        }
        for guest in draft.guests {
            if guest.trimmedName.isEmpty {
                issues.append(.guestWithoutName)
            } else if case .failure(let error) = ClubInput.handicapIndex(guest.handicapText) {
                issues.append(.guestHandicap(name: guest.trimmedName, message: error.message))
            }
        }
        if LooseRoundRules.isHoleByHole(draft.form),
           let reason = rules.setup(formID: draft.formID, players: draft.playerCount).reason {
            issues.append(.form(reason))
        }
        if draft.playerCount > LooseRoundLimits.maxPlayers {
            issues.append(.tooManyPlayers(max: LooseRoundLimits.maxPlayers))
        }
        if draft.scoring == .ownCards, 1 + draft.friends.count > LooseRoundLimits.maxGroups {
            issues.append(.tooManyGroups(max: LooseRoundLimits.maxGroups))
        }
        return issues
    }
}

// MARK: - Flight, markør og matcher

/// Hvem står hvor: indeks 0 er deg, så vennene, så gjestene (samme rekkefølge som `start_loose_round`).
nonisolated struct LooseRoundPlan: Equatable, Sendable {
    struct Seat: Equatable, Sendable {
        var bay: Int?
        var isMarker: Bool
    }

    let seats: [Seat]
    /// Matcher som indekser i lista: to spillere, eller tre i en trekant.
    let matches: [[Int]]

    /// - Jeg fører for alle: alle i flight 1, du markør. Venner med profil fører ikke selv.
    /// - Hver fører sitt eget kort: du og gjestene i flight 1 (du markør når det er gjester), og hver
    ///   venn i sin egen flight uten markør, så de fører selv.
    /// Matcher trekkes bare når formen avgjøres hull for hull, som regelmotoren trekker dem
    /// (`trekkMatcher`, sortert på navn).
    static func make(_ draft: LooseRoundDraft, names: [String]) -> LooseRoundPlan {
        let friends = draft.friends.count, guests = draft.guests.count
        var seats: [Seat]
        switch draft.scoring {
        case .oneCard:
            seats = [Seat(bay: 1, isMarker: true)]
                + Array(repeating: Seat(bay: 1, isMarker: false), count: friends + guests)
        case .ownCards:
            seats = [Seat(bay: 1, isMarker: guests > 0)]
                + (0..<friends).map { Seat(bay: 2 + $0, isMarker: false) }
                + Array(repeating: Seat(bay: 1, isMarker: false), count: guests)
        }
        var matches: [[Int]] = []
        if LooseRoundRules.isHoleByHole(draft.form) {
            let players = seats.indices.map { i in Player(id: String(i), name: names.indices.contains(i) ? names[i] : "") }
            matches = Triangle.drawMatches(players, round: 0, standing: [:]).map { $0.compactMap { Int($0) } }
        }
        return LooseRoundPlan(seats: seats, matches: matches)
    }
}

// MARK: - Kallet

/// Det `start_loose_round` får (sql/018). Regelverdiene (andel, sidepremier, Trackman) kommer fra
/// regelsettet; stedet (bås eller flight) fra banetypen.
nonisolated struct LooseRoundStart: Encodable, Equatable, Sendable {
    struct Seat: Encodable, Equatable, Sendable {
        let bayNo: Int?
        let isMarker: Bool

        enum CodingKeys: String, CodingKey {
            case bayNo = "bay_no"
            case isMarker = "is_marker"
        }
    }

    struct Entry: Encodable, Equatable, Sendable {
        var profileID: UUID?
        var guestName: String?
        var handicapIndex: Double?
        let bayNo: Int?
        let isMarker: Bool

        enum CodingKeys: String, CodingKey {
            case profileID = "profile_id"
            case guestName = "guest_name"
            case handicapIndex = "handicap_index"
            case bayNo = "bay_no"
            case isMarker = "is_marker"
        }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(profileID, forKey: .profileID)
            try c.encodeIfPresent(guestName, forKey: .guestName)
            try c.encodeIfPresent(handicapIndex, forKey: .handicapIndex)
            try c.encode(bayNo, forKey: .bayNo)
            try c.encode(isMarker, forKey: .isMarker)
        }
    }

    struct MatchRef: Encodable, Equatable, Sendable {
        let a: Int
        let b: Int
        let c: Int?
    }

    let courseID: UUID
    /// Teen (sql/029). Sendes bare når den er valgt; `start_loose_round` før 029 ville ignorert den.
    var teeID: UUID?
    let holeCount: Int
    let firstHole: Int
    let format: String
    let venue: String
    let handicapAllowance: Double
    let externalHandicap: Bool
    let ldEnabled: Bool
    let kpEnabled: Bool
    let me: Seat
    let players: [Entry]
    let matches: [MatchRef]
    let start: Bool

    enum CodingKeys: String, CodingKey {
        case courseID = "course_id"
        case teeID = "tee_id"
        case holeCount = "hole_count"
        case firstHole = "first_hole"
        case format, venue
        case handicapAllowance = "handicap_allowance"
        case externalHandicap = "external_handicap"
        case ldEnabled = "ld_enabled"
        case kpEnabled = "kp_enabled"
        case me, players, matches, start
    }

    /// Kallet for utkastet, eller nil når noe mangler. `names` er navnene i lista (deg først), brukt
    /// når matchene trekkes.
    static func make(_ draft: LooseRoundDraft, course: CourseListItem?, names: [String],
                     rules: Ruleset = LooseRoundRules.template) -> LooseRoundStart? {
        guard let course, LooseRoundSetup.issues(draft, course: course, rules: rules).isEmpty else { return nil }
        let plan = LooseRoundPlan.make(draft, names: names)
        let venue: Venue = course.kind == .course ? .course : .simulator
        var entries: [Entry] = []
        for (i, friend) in draft.friends.enumerated() {
            let seat = plan.seats[1 + i]
            entries.append(Entry(profileID: friend, bayNo: seat.bay, isMarker: seat.isMarker))
        }
        for (i, guest) in draft.guests.enumerated() {
            let seat = plan.seats[1 + draft.friends.count + i]
            let handicap = (try? ClubInput.handicapIndex(guest.handicapText).get()) ?? nil
            entries.append(Entry(guestName: guest.trimmedName, handicapIndex: handicap, bayNo: seat.bay,
                                 isMarker: seat.isMarker))
        }
        return LooseRoundStart(
            courseID: course.id,
            teeID: SlopeNoFeature.isEnabled ? course.tee(draft.teeID)?.id : nil,
            holeCount: draft.holeCount,
            firstHole: draft.firstHole,
            format: draft.formID,
            venue: venue.rawValue,
            handicapAllowance: rules.allowance(for: draft.form),
            externalHandicap: venue == .simulator ? rules.handicap.externalHandicap : false,
            ldEnabled: draft.sidePrizes && rules.sidePrizes.longestDrive.enabled,
            kpEnabled: draft.sidePrizes && rules.sidePrizes.closestToPin.enabled,
            me: Seat(bayNo: plan.seats[0].bay, isMarker: plan.seats[0].isMarker),
            players: entries,
            matches: plan.matches.compactMap { ids in
                guard ids.count >= 2 else { return nil }
                return MatchRef(a: ids[0], b: ids[1], c: ids.count > 2 ? ids[2] : nil)
            },
            start: true
        )
    }
}
