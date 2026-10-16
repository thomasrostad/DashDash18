import Foundation
import GolfgutuCore

// V12 (UI-utbedringen, oktober 2026): «I kveld» på arrangørsiden mens runden går. Én rad per bås
// med starttid, spillere, funksjonær, hull og hvor lenge siden båsen sist førte. Bare visning:
// tallene regnes fra radene som allerede finnes (`round_players.bay_no`, `hole_scores.updated_at`
// og `recorded_at`, startlista fra sql/032). Ingen spillregler her.

/// Én bås (eller flight) i runden som går.
nonisolated struct BayLive: Equatable, Identifiable, Sendable {
    let roundID: UUID
    let groupNo: Int
    /// «Bås 1», «Flight 2», eller navnet fra startlista («Simulator 3»).
    let title: String
    /// «18:10» fra startlista, ellers rundens tee-tid. nil: ikke satt.
    let startsAt: String?
    let names: [String]
    /// Funksjonæren som fører for båsen (startlista, sql/032). nil: ingen.
    let scorer: String?
    /// Hull der alle i båsen har slag.
    let holesDone: Int
    /// Hullene som spilles (etter avkorting).
    let holeCount: Int
    /// Hullet båsen står på («Hull 14»). nil før start og når alle hull er ført.
    let currentHole: Int?
    var sync: BaySync

    var id: String { "\(roundID)-\(groupNo)" }

    /// 0…1 til fremdriftsstripa.
    var fraction: Double { holeCount > 0 ? min(Double(holesDone) / Double(holeCount), 1) : 0 }
    var isFinished: Bool { holeCount > 0 && holesDone >= holeCount }

    /// Før scorene er hentet: ingen synklinje (ellers ville starttiden gi «Ingen data»).
    var withoutSync: BayLive {
        var copy = self
        copy.sync = .unknown
        return copy
    }
}

/// Hvor lenge siden båsen sist førte.
nonisolated enum BaySync: Equatable, Sendable {
    /// Starter om så mange minutter.
    case startsIn(minutes: Int)
    /// Startet, men ingenting er ført ennå (under grensen).
    case waiting
    /// Siste score kom for så mange minutter siden.
    case synced(minutes: Int)
    /// Ingenting nytt på så mange minutter (over grensen): rust.
    case stale(minutes: Int)
    /// Alle hull er ført.
    case finished
    /// Ingen tidspunkt å regne fra (scorene mangler tid, eller starttiden er ukjent). Linja utelates.
    case unknown

    var isWarning: Bool { if case .stale = self { true } else { false } }
}

nonisolated enum TonightLive {
    /// Minutter uten nye scorer før båsen markeres med rust. Et hull i simulatoren tar rundt 10 minutter
    /// for en bås på tre; 15 gir rom for et tregt hull. En visningsgrense, ikke en regel.
    static let staleMinutes = 15

    /// Båsene i runden, i nummerrekkefølge.
    /// - Parameters:
    ///   - groups: startlista (sql/032) når den finnes, ellers tom: båsene fra `bay_no` med rundens tee-tid.
    ///   - scorerName: navnet på funksjonæren (staben).
    static func bays(round: RoundRow, eventDate: String, players: [RoundPlayerRow], scores: [HoleScoreRow],
                     groups: [StartGroupDraft], name: (UUID) -> String, scorerName: (UUID) -> String?,
                     now: Date) -> [BayLive] {
        let term = GroupTerm.for(stored: round.venue)
        let byBay = Dictionary(grouping: players.filter { $0.bayNo != nil }, by: { $0.bayNo! })
        let savedByNo = Dictionary(groups.map { ($0.groupNo, $0) }, uniquingKeysWith: { first, _ in first })
        let holes = playedHoles(round)
        let defaultStart = EveningDates.timeText(round.teeTime)
        return byBay.keys.sorted().map { no in
            let members = byBay[no] ?? []
            let ids = Set(members.map(\.memberID))
            let own = scores.filter { $0.roundID == round.id && ids.contains($0.memberID) }
            let group = savedByNo[no]
            let done = completeHoles(own, players: ids, holes: holes)
            let start = group?.startsAt ?? defaultStart
            let label = group?.resourceLabel.trimmingCharacters(in: .whitespaces) ?? ""
            return BayLive(
                roundID: round.id, groupNo: no,
                title: label.isEmpty ? term.numbered(no) : label,
                startsAt: start,
                names: members.map { name($0.memberID) },
                scorer: group?.scorerID.flatMap(scorerName),
                holesDone: done.count, holeCount: holes,
                currentHole: currentHole(done: done, holes: holes, startHole: group?.startHole,
                                         firstHole: round.firstHole, hasScores: !own.isEmpty),
                sync: sync(scores: own, isFinished: holes > 0 && done.count >= holes,
                           start: startDate(eventDate: eventDate, time: start), now: now))
        }
    }

    /// Hullene som spilles: etter avkorting bare fram til avkortingen (som `Tonight.isComplete`).
    static func playedHoles(_ round: RoundRow) -> Int {
        round.cutAfter.map { min($0, round.holeCount) } ?? round.holeCount
    }

    /// Hullindeksene (0-baserte) der alle spillerne i båsen har slag.
    static func completeHoles(_ scores: [HoleScoreRow], players: Set<UUID>, holes: Int) -> Set<Int> {
        guard !players.isEmpty else { return [] }
        let byHole = Dictionary(grouping: scores.filter { $0.holeIndex < holes }, by: \.holeIndex)
        return Set(byHole.filter { Set($0.value.map(\.memberID)).isSuperset(of: players) }.keys)
    }

    /// Hullet båsen står på: det første uførte i spillerekkefølgen fra starthullet (kanonstart starter
    /// midt i runden). Som banens hullnummer (`firstHole` 10 gir hull 10–18). nil før første score og
    /// når alle hull er ført.
    static func currentHole(done: Set<Int>, holes: Int, startHole: Int?, firstHole: Int, hasScores: Bool) -> Int? {
        guard hasScores, holes > 0, done.count < holes else { return nil }
        let start = min(max((startHole ?? 1) - 1, 0), holes - 1)
        let order = (0..<holes).map { (start + $0) % holes }
        return order.first { !done.contains($0) }.map { firstHole + $0 }
    }

    /// Starten som tidspunkt: kveldens dato og klokkeslettet, i Oslo.
    static func startDate(eventDate: String, time: String?) -> Date? {
        guard let time, let day = EveningDates.date(from: eventDate) else { return nil }
        return EveningDates.time(from: time, on: day)
    }

    /// Siste score (rettet eller ført), ellers starttiden.
    static func sync(scores: [HoleScoreRow], isFinished: Bool, start: Date?, now: Date) -> BaySync {
        if isFinished { return .finished }
        if let last = scores.compactMap({ $0.updatedAt ?? $0.recordedAt }).max() {
            let minutes = wholeMinutes(from: last, to: now)
            return minutes >= staleMinutes ? .stale(minutes: minutes) : .synced(minutes: minutes)
        }
        guard scores.isEmpty, let start else { return .unknown }
        if start > now { return .startsIn(minutes: Int((start.timeIntervalSince(now) / 60).rounded(.up))) }
        let minutes = wholeMinutes(from: start, to: now)
        return minutes >= staleMinutes ? .stale(minutes: minutes) : .waiting
    }

    private static func wholeMinutes(from: Date, to: Date) -> Int {
        max(Int(to.timeIntervalSince(from) / 60), 0)
    }

    /// «Synket for 2 min siden», «Ingen data på 18 min», «Om 25 min». nil: ingen linje.
    static func syncText(_ sync: BaySync, startsAt: String? = nil) -> String? {
        switch sync {
        case .startsIn(let minutes):
            if minutes > 60, let startsAt { return "Starter \(startsAt)" }
            return "Om \(durationText(minutes))"
        case .waiting: return "Ingen data ennå"
        case .synced(let minutes): return minutes < 1 ? "Synket nå" : "Synket for \(durationText(minutes)) siden"
        case .stale(let minutes): return "Ingen data på \(durationText(minutes))"
        case .finished: return "Alle hull ført"
        case .unknown: return nil
        }
    }

    /// «18 min», «1 t 5 min», «2 t».
    static func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) t" : "\(h) t \(m) min"
    }

    /// «Hull 14», «Ikke startet», «Ferdig».
    static func holeText(_ bay: BayLive) -> String {
        if bay.isFinished { return "Ferdig" }
        return bay.currentHole.map { "Hull \($0)" } ?? "Ikke startet"
    }

    /// Linja under rundens tittel: «Stableford · 4 båser à 3», eller «4 båser · 11 spillere» når båsene
    /// er ulike store.
    /// «Ingen båser er fordelt i oppsettet.» / «Ingen flighter …».
    static func noGroupsText(_ term: GroupTerm) -> String {
        "Ingen \(term.plural) er fordelt i oppsettet."
    }

    static func shapeText(formatName: String, venue: String?, bays: [BayLive]) -> String {
        var parts = [formatName]
        let term = GroupTerm.for(stored: venue)
        let sizes = Set(bays.map(\.names.count))
        if bays.isEmpty {
            // Ingen båser fordelt: bare formen.
        } else if sizes.count == 1, let size = sizes.first {
            parts.append(term.count(bays.count) + " à \(size)")
        } else {
            let players = bays.reduce(0) { $0 + $1.names.count }
            parts.append(term.count(bays.count) + " · \(players) spillere")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Sidepremier og det som gjenstår

    /// En sidepremie i runden: «Nærmest pinnen · hull 7», og hvor mange som har meldt inn.
    struct SidePrize: Equatable, Identifiable, Sendable {
        let roundID: UUID
        let kind: SideClaimKind
        let title: String
        /// Banens hullnummer.
        let hole: Int
        let claims: Int
        var id: String { "\(roundID)-\(kind.rawValue)" }

        var statusText: String {
            switch claims {
            case 0: "Ingen innmeldt ennå"
            case 1: "1 innmeldt"
            default: "\(claims) innmeldt"
            }
        }
    }

    /// Sidepremiene som er slått på i runden, i rekkefølge på banen.
    static func sidePrizes(_ round: RoundRow, claims: [SideClaimRow]) -> [SidePrize] {
        var out: [SidePrize] = []
        if round.kpEnabled, let index = round.kpHoleIndex {
            out.append(SidePrize(roundID: round.id, kind: .kp, title: "Nærmest pinnen", hole: round.firstHole + index,
                                 claims: claims.filter { $0.roundID == round.id && $0.kind == .kp }.count))
        }
        if round.ldEnabled, let index = round.ldHoleIndex {
            out.append(SidePrize(roundID: round.id, kind: .drive, title: "Lengste drive", hole: round.firstHole + index,
                                 claims: claims.filter { $0.roundID == round.id && $0.kind == .drive }.count))
        }
        return out.sorted { $0.hole < $1.hole }
    }

    /// Et punkt i «Før Ferdig»: ✓ når det er i orden.
    struct Remaining: Equatable, Identifiable, Sendable {
        let title: String
        let detail: String?
        let isDone: Bool
        var id: String { title }
    }

    /// Det som gjenstår før kvelden kan avsluttes: alle hull ført, sidepremiene meldt inn, og til
    /// slutt å avslutte kvelden (som låser rundene).
    static func remaining(bays: [BayLive], prizes: [SidePrize], term: DayTerm, groupTerm: GroupTerm) -> [Remaining] {
        var out: [Remaining] = []
        let left = bays.filter { !$0.isFinished }
        let holesLeft: String? = switch left.count {
        case 0: nil
        case 1: "\(left[0].title) har \(holesLeftText(left[0]))"
        default: "\(groupTerm.count(left.count)) har hull igjen"
        }
        out.append(Remaining(title: "Alle hull ført", detail: holesLeft, isDone: !bays.isEmpty && left.isEmpty))
        for prize in prizes {
            out.append(Remaining(title: "\(prize.title) meldt inn", detail: prize.claims == 0 ? "Hull \(prize.hole)" : nil,
                                 isDone: prize.claims > 0))
        }
        out.append(Remaining(title: "Avslutt \(term.the)", detail: "Låser rundene, så resultatet står på Tavla.",
                             isDone: false))
        return out
    }

    private static func holesLeftText(_ bay: BayLive) -> String {
        let n = max(bay.holeCount - bay.holesDone, 0)
        return n == 1 ? "1 hull igjen" : "\(n) hull igjen"
    }

    // MARK: Påmelding

    /// «Nils har ikke svart. Magne er usikker.» nil når alle har svart sikkert.
    static func signupFollowUp(notAnswered: [String], maybe: [String]) -> String? {
        var parts: [String] = []
        if !notAnswered.isEmpty {
            parts.append(names(notAnswered) + " har ikke svart.")
        }
        if !maybe.isEmpty {
            parts.append(names(maybe) + (maybe.count == 1 ? " er usikker." : " er usikre."))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Tre navn eller færre står ut; flere blir «Nils, Ola og 3 til».
    private static func names(_ list: [String]) -> String {
        guard list.count > 3 else { return NorwegianList.join(list) }
        return list.prefix(2).joined(separator: ", ") + " og \(list.count - 2) til"
    }

    /// «12 av 14 kommer». Uten gjester og venteliste (de står på Kvelden).
    static func comingText(coming: Int, roster: Int) -> String {
        "\(coming) av \(roster) kommer"
    }
}
