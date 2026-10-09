import Foundation
import GolfgutuCore

// Feeden på Hjem (fase 19): aktiviteten fra alle klubbene dine, rundene dine og de private
// turneringene, som kort i «I dag · I går · Tidligere», med filterpiller, oppsummering, «Pågår nå» og
// «Neste kveld». Innholdet følger beslutningen 08.10.2026: bragder (brutto eagle og bedre),
// tabellendringer, egne runder, sidepremier, tippekonge, melding til alle og påmeldinger. Ikke alle
// andres runder.
//
// Kildene:
//   * Klubbene: `activity` (RLS: aktivt medlem). Bragder, tabellendringer og linjene.
//   * Dine runder (klubb og løse): «Din runde», regnet av runden selv.
//   * Løse runder og runder utenfor klubbene dine (private turneringer): bragdene regnes av
//     hullscorene, siden de ikke har en klubb å logge i (`activity.club_id` er påkrevd).
//   * Private turneringer: plassbyttet etter siste låste runde regnes her (`TableChange`).

nonisolated extension HomeFeed {
    /// Hvor langt tilbake feeden går.
    static let window: TimeInterval = 30 * 24 * 3600

    static func build(_ input: HomeFeedInput) -> HomeFeed {
        let context = HomeFeedContext(input)
        let drafts = HomeFeedDrafts(context).all
            .filter { $0.date >= input.now.addingTimeInterval(-window) && $0.date <= input.now.addingTimeInterval(600) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
        let filtered = drafts.filter { input.filter == .all || $0.filters.contains(input.filter) }
        return HomeFeed(
            pills: pills(drafts, context: context, selected: input.filter),
            filter: input.filter,
            summary: HomeSummaryBuilder.summary(drafts, context: context),
            live: input.live.map { live($0, context: context) },
            evening: input.evening.map(evening),
            sections: sections(filtered, now: input.now)
        )
    }

    // MARK: Piller

    /// Alt, så kildene som har kort (hovedturneringene først, så etter navn), så «Løse runder».
    /// Det valgte filteret står alltid, også når det er tomt.
    static func pills(_ drafts: [HomeFeedDraft], context: HomeFeedContext, selected: HomeFeedFilter) -> [HomeFeedPill] {
        var sources: [HomeFeedFilter: HomeFeedSource] = [:]
        for d in drafts {
            sources[d.source.filter] = sources[d.source.filter] ?? d.source
            for f in d.filters where sources[f] == nil {
                if let s = context.source(for: f) { sources[f] = s }
            }
        }
        if selected != .all, sources[selected] == nil, let s = context.source(for: selected) { sources[selected] = s }
        let middle = sources.values
            .filter { $0.filter != .loose }
            .sorted { a, b in
                let ra = context.rank(a.filter), rb = context.rank(b.filter)
                return ra != rb ? ra < rb : NorwegianSort.areInIncreasingOrder(a.title, b.title)
            }
        var out = [HomeFeedPill(filter: .all, title: "Alt", tone: nil, isSelected: selected == .all)]
        out += middle.map { HomeFeedPill(filter: $0.filter, title: $0.title, tone: $0.tone, isSelected: $0.filter == selected) }
        if let loose = sources[.loose] {
            out.append(HomeFeedPill(filter: .loose, title: "Løse runder", tone: loose.tone, isSelected: selected == .loose))
        }
        return out
    }

    // MARK: Seksjoner

    /// «I dag», «I går» og «Tidligere» (kalenderdagen i Oslo). Kompakte linjer fra samme kilde som
    /// står etter hverandre, blir ett kort, og påmeldinger til samme kveld blir én linje.
    static func sections(_ drafts: [HomeFeedDraft], now: Date) -> [HomeFeedSection] {
        let today = EveningDates.dateString(from: now)
        func title(_ date: Date) -> String {
            switch EveningDates.daysBetween(EveningDates.dateString(from: date), today) ?? 2 {
            case ...0: "I dag"
            case 1: "I går"
            default: "Tidligere"
            }
        }
        var out: [(title: String, drafts: [HomeFeedDraft])] = []
        for d in drafts {
            let t = title(d.date)
            if out.last?.title == t { out[out.count - 1].drafts.append(d) } else { out.append((t, [d])) }
        }
        return out.map { HomeFeedSection(title: $0.title, cards: cards($0.drafts, now: now)) }
    }

    private static func cards(_ drafts: [HomeFeedDraft], now: Date) -> [HomeFeedCard] {
        var out: [HomeFeedCard] = []
        var pending: [HomeFeedDraft] = []
        func flush() {
            guard let first = pending.first else { return }
            let lines = mergedSignups(pending).map { $0.line(now: now) }
            out.append(HomeFeedCard(id: "l-" + first.id, date: first.date,
                                    time: ActivityFeed.relativeTime(first.date, now: now), source: first.source,
                                    filters: pending.reduce(into: Set()) { $0.formUnion($1.filters) },
                                    content: .lines(lines), isUnread: pending.contains(where: \.isUnread)))
            pending = []
        }
        for d in drafts {
            guard case .line = d.kind else {
                flush()
                out.append(d.card(now: now))
                continue
            }
            if let first = pending.first, first.source != d.source { flush() }
            pending.append(d)
        }
        flush()
        return out
    }

    /// Påmeldinger («kommer») til samme kveld i samme klubb, etter hverandre, blir én linje:
    /// «Anders, Bjørn og 3 til meldte seg på torsdag 15. oktober». Reaksjonene står bare på enkeltlinjer.
    private static func mergedSignups(_ drafts: [HomeFeedDraft]) -> [HomeFeedDraft] {
        var out: [HomeFeedDraft] = []
        for d in drafts {
            if let key = d.signupKey, let last = out.last, last.signupKey == key, case .line(var line) = last.kind {
                line.signupNames.append(contentsOf: d.lineDraft?.signupNames ?? [])
                line.reactions = nil
                line.text = HomeFeedText.signups(line.signupNames, eventDate: line.signupDate)
                var merged = last
                merged.kind = .line(line)
                merged.isUnread = last.isUnread || d.isUnread
                out[out.count - 1] = merged
            } else {
                out.append(d)
            }
        }
        return out
    }

    // MARK: Pågår nå

    static func live(_ input: HomeLiveInput, context: HomeFeedContext) -> HomeLive {
        let s = input.snapshot
        let game = RoundGame(s)
        let rows = game.bayenNaa(viewer: input.viewer)
        let mine = rows.first(where: \.isMe)
        let thru = mine?.thru ?? rows.map(\.thru).max() ?? 0
        let hole = min(game.holeCount, thru + 1)
        let course = s.course?.name ?? "Runde"
        let title = s.isLoose || s.round.roundNo <= 0 ? course : "\(course) · runde \(s.round.roundNo)"
        var detail: [String] = []
        let names = context.competitions(counting: s.round.id).map(\.name)
        if !names.isEmpty { detail.append("Teller i " + NorwegianList.join(names)) }
        if let bay = game.bay(of: input.viewer.memberID)?.number {
            detail.append("\(game.groupTerm.singular) \(bay)")
        }
        func row(_ r: BayenRow) -> HomeLive.Row {
            HomeLive.Row(id: r.id, place: r.place.map { "\($0)." } ?? "–", name: r.name, value: r.value, isMe: r.isMe)
        }
        let top = rows.prefix(3).map(row)
        return HomeLive(roundID: s.round.id, isLoose: s.isLoose, progress: "Hull \(hole) av \(game.holeCount)",
                        title: title, detail: detail.isEmpty ? nil : detail.joined(separator: " · "),
                        top: top, me: top.contains(where: \.isMe) ? nil : mine.map(row),
                        actionTitle: "Fortsett føringen")
    }

    // MARK: Neste kveld

    static func evening(_ e: HomeEveningInput) -> HomeNextEvening {
        let referenceYear = EveningDates.year(of: e.today)
        let days = EveningDates.daysBetween(e.today, e.event.eventDate) ?? 0
        var detail: [String] = []
        if let time = EveningDates.timeText(e.event.startTime) { detail.append("Kl. \(time)") }
        if let venue = e.event.venue?.trimmingCharacters(in: .whitespaces), !venue.isEmpty { detail.append(venue) }
        detail.append("\(e.coming) kommer")
        return HomeNextEvening(clubID: e.clubID, eventID: e.event.id, eyebrow: "\(e.clubName) · neste \(e.term.one)",
                               title: EveningDates.longText(e.event.eventDate, referenceYear: referenceYear,
                                                            capitalized: true),
                               countdown: EveningDates.countdownText(days: days),
                               detail: detail.joined(separator: " · "), answer: e.answer, isOrganizer: e.isOrganizer)
    }
}

// MARK: - Oppslag

/// Oppslagene feeden trenger: turneringer, koblinger, klubber, navn og tonene.
nonisolated struct HomeFeedContext: Sendable {
    let input: HomeFeedInput
    let competitionsByID: [UUID: CompetitionRow]
    let linksByRound: [UUID: [UUID]]
    let clubsByID: [UUID: HomeClub]
    let tones: [UUID: HomeFeedTone]

    init(_ input: HomeFeedInput) {
        self.input = input
        let visible = input.competitions.filter { $0.kind != .game }
        competitionsByID = Dictionary(visible.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        linksByRound = input.links.reduce(into: [:]) { $0[$1.roundID, default: []].append($1.competitionID) }
        clubsByID = Dictionary(input.clubs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Hovedturneringene lime, de andre sol, blush og gull etter tur (etter navn, så fargen står fast).
        let palette: [HomeFeedTone] = [.sun, .blush, .gold]
        var tones: [UUID: HomeFeedTone] = [:]
        let others = visible.filter { !Self.isMain($0) }
            .sorted { a, b in a.name != b.name ? NorwegianSort.areInIncreasingOrder(a.name, b.name) : a.id.uuidString < b.id.uuidString }
        for (i, c) in others.enumerated() { tones[c.id] = palette[i % palette.count] }
        for c in visible where Self.isMain(c) { tones[c.id] = .lime }
        self.tones = tones
    }

    static func isMain(_ c: CompetitionRow) -> Bool { c.isMain || c.kind == .season }

    var viewer: HomeViewer { input.viewer }
    var me: Set<UUID> { input.viewer.ids }

    func name(_ id: UUID) -> String { input.names[id] ?? "Noen" }

    /// Klubbens hovedturnering: den aktive, ellers den sist kjente.
    func mainCompetition(club: UUID) -> CompetitionRow? {
        let mains = competitionsByID.values.filter { $0.clubID == club && Self.isMain($0) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        return mains.first { $0.status == .active } ?? mains.first
    }

    /// Turneringene runden teller i, hovedturneringen først, så etter navn.
    func competitions(counting round: UUID) -> [CompetitionRow] {
        (linksByRound[round] ?? []).compactMap { competitionsByID[$0] }
            .reduce(into: [CompetitionRow]()) { if !$0.contains($1) { $0.append($1) } }
            .sorted { a, b in
                Self.isMain(a) != Self.isMain(b) ? Self.isMain(a) : NorwegianSort.areInIncreasingOrder(a.name, b.name)
            }
    }

    func source(_ c: CompetitionRow) -> HomeFeedSource {
        HomeFeedSource(filter: .competition(c.id), title: c.name, tone: tones[c.id] ?? .sun)
    }

    var looseSource: HomeFeedSource { HomeFeedSource(filter: .loose, title: "Løs runde", tone: .earth) }

    /// Klubbens linjer uten runde: hovedturneringen, ellers klubben selv.
    func clubSource(_ club: UUID) -> HomeFeedSource {
        if let main = mainCompetition(club: club) { return source(main) }
        return HomeFeedSource(filter: .club(club), title: clubsByID[club]?.name ?? "Klubben", tone: .lime)
    }

    func source(for filter: HomeFeedFilter) -> HomeFeedSource? {
        switch filter {
        case .all: nil
        case .competition(let id): competitionsByID[id].map(source)
        case .club(let id): clubsByID[id].map { HomeFeedSource(filter: .club($0.id), title: $0.name, tone: .lime) }
        case .loose: looseSource
        }
    }

    /// Kilden og filtrene for noe som hører til en runde (eller bare en klubb).
    func placement(round: UUID?, club: UUID?) -> (source: HomeFeedSource, filters: Set<HomeFeedFilter>) {
        let counted = round.map(competitions(counting:)) ?? []
        var filters = Set(counted.map { HomeFeedFilter.competition($0.id) })
        let source: HomeFeedSource
        if let first = counted.first {
            source = self.source(first)
        } else if let club {
            source = clubSource(club)
        } else {
            source = looseSource
        }
        filters.insert(source.filter)
        if club == nil, round != nil { filters.insert(.loose) }
        return (source, filters)
    }

    /// Rekkefølgen på pillene: hovedturneringene, klubbene, så de andre.
    func rank(_ filter: HomeFeedFilter) -> Int {
        switch filter {
        case .all: 0
        case .competition(let id): competitionsByID[id].map { Self.isMain($0) ? 1 : 3 } ?? 3
        case .club: 2
        case .loose: 4
        }
    }

    func reactions(_ row: ActivityRow?) -> HomeReactions? {
        guard let row else { return nil }
        return HomeReactions(activityID: row.id, clubID: row.clubID,
                             chips: ActivityReactions.chips(for: row.id, in: input.reactions, me: row.clubMember(of: viewer),
                                                            name: { input.names[$0] }))
    }

    func isUnread(_ date: Date, own: Bool) -> Bool {
        guard let lastSeen = input.lastSeen, !own else { return false }
        return date > lastSeen
    }
}

nonisolated extension ActivityRow {
    /// Medlemmet ditt i klubben linja hører til (for «min reaksjon»).
    func clubMember(of viewer: HomeViewer) -> UUID? { viewer.memberships[clubID] }
}

// MARK: - Tekst

nonisolated enum HomeFeedText {
    /// «AB» fra «Anders Berg», «A» fra «Anders».
    static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    static func featHeadline(_ kind: BigScoreName, hole: Int) -> String {
        switch kind {
        case .holeInOne: "Hole in one på hull \(hole)!"
        case .albatross: "Albatross på hull \(hole)"
        case .eagle: "Eagle på hull \(hole)"
        }
    }

    /// «slo eagle», «fikk hole in one» (oppsummeringen).
    static func featVerb(_ kind: BigScoreName) -> String {
        switch kind {
        case .holeInOne: "fikk hole in one"
        case .albatross: "slo albatross"
        case .eagle: "slo eagle"
        }
    }

    /// «Losby · runde 4».
    static func roundPlace(_ label: HomeRoundLabel?) -> String? {
        guard let label else { return nil }
        let parts = [label.courseName, label.roundNo.flatMap { $0 > 0 ? "runde \($0)" : nil }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// «med Per og Even», «med Anders, Bjørn og 2 andre».
    static func others(_ names: [String]) -> String? {
        let sorted = names.filter { !$0.isEmpty }.sorted(by: NorwegianSort.areInIncreasingOrder)
        switch sorted.count {
        case 0: return nil
        case 1...3: return "med " + NorwegianList.join(sorted)
        default: return "med \(sorted[0]), \(sorted[1]) og \(sorted.count - 2) andre"
        }
    }

    /// Påmeldinger slått sammen: «Anders og Bjørn meldte seg på torsdag 15. oktober»,
    /// «Anders, Bjørn og 3 til meldte seg på …».
    static func signups(_ names: [String], eventDate: String?) -> String {
        let who: String = names.count <= 3 ? NorwegianList.join(names)
            : "\(names[0]), \(names[1]) og \(names.count - 2) til"
        return who + " meldte seg på" + (eventDate.map { " " + EveningDates.longText($0) } ?? "")
    }

    /// «+2», «−1», «0».
    static func signed(_ n: Int) -> String {
        n > 0 ? "+\(n)" : n < 0 ? "−\(-n)" : "0"
    }
}
