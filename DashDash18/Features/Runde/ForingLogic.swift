import Foundation
import GolfgutuCore

// Føringen per bås: hvem får skrive, hvem står på kortet, hvilket hull båsen er på,
// og hva «Lagre hull» sender. Som PWA-ens kanFore, hullkortSpillere, hullkortRadKanFores,
// baasensHull og handleLagreHull (db-nytt.js 2033, app-nytt.js 687 og 6075–6380).

/// Tallet på stepperen holdes innenfor dette (PWA: `Math.max(1, Math.min(12, …))`).
/// En inndatagrense for skjermen, ikke en spilleregel. Databasen tåler 1–20.
nonisolated enum StrokeInput {
    static let range = 1...12

    static func clamp(_ value: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

/// Hvem som ser på runden.
nonisolated struct Viewer: Equatable, Sendable {
    let memberID: UUID
    let isOrganizer: Bool
}

nonisolated extension RoundGame {
    // MARK: Skriverett

    /// `kanFore`: kan `writer` føre for `target`? Samme regel som `can_score` i databasen:
    /// arrangøren alltid; runden går ikke (kladd eller låst): ingen andre; spillerens bås har
    /// markør: bare markøren; ellers spilleren selv.
    func canScore(_ viewer: Viewer, for target: UUID) -> Bool {
        if viewer.isOrganizer { return true }
        guard status == .active else { return false }
        if let marker = bay(of: target)?.marker { return marker == viewer.memberID }
        return viewer.memberID == target
    }

    /// `spillereJegForerFor`: alle i runden `viewer` kan føre for, i rundens rekkefølge.
    func playersScorable(by viewer: Viewer) -> [UUID] {
        snapshot.players.map(\.memberID).filter { canScore(viewer, for: $0) }
    }

    // MARK: Kortet

    /// `hullkortSpillere`: båsen din med deg først. Uten båsoppsett eller uten bås: bare deg.
    /// Er du ikke med i runden, står ingen på kortet.
    func cardPlayers(for viewer: Viewer) -> [UUID] {
        let me = viewer.memberID
        guard isPlaying(me) else { return [] }
        guard let bay = bay(of: me) else { return [me] }
        return [me] + bay.players.filter { $0 != me }
    }

    /// `hullkortRadKanFores`: får jeg føre raden på kortet? Strengere enn `canScore`:
    /// en arrangør i en bås med markør fører ikke på kortet (han retter i stedet).
    func cardRowEditable(_ member: UUID, for viewer: Viewer) -> Bool {
        if status != .active && !viewer.isOrganizer { return false }
        let me = viewer.memberID
        guard let bay = bay(of: me) else { return member == me && canScore(viewer, for: me) }
        if let marker = bay.marker { return marker == me && canScore(viewer, for: member) }
        return member == me && canScore(viewer, for: me)
    }

    /// Hullet er ført for alle disse spillerne.
    func isComplete(hole: Int, for players: [UUID]) -> Bool {
        !players.isEmpty && players.allSatisfy { scores($0)[hole] != nil }
    }

    /// `baasensHull`: første hull der ikke alle på kortet er ført. Alle ført: siste hull.
    func bayHole(for viewer: Viewer) -> Int {
        let players = cardPlayers(for: viewer)
        guard !players.isEmpty else { return 0 }
        return (0..<holeCount).first { !isComplete(hole: $0, for: players) } ?? holeCount - 1
    }

    // MARK: Lagring

    /// Det «Lagre hull» sender: radene `viewer` får føre på kortet, med tallet som står
    /// (utkastet, ellers det lagrede, ellers par). Bare rader som er endret mot serveren.
    /// I en form med ett kort per lag skrives samme tall på hele laget (`saveHoleScore`).
    /// `nil` når ingenting er endret.
    func submission(hole: Int, drafts: HoleDrafts, viewer: Viewer, recordedAt: Date) -> HoleSubmission? {
        guard holes.indices.contains(hole) else { return nil }
        let par = holes[hole].par
        var entries: [HoleSubmission.Entry] = []
        var seen: Set<UUID> = []
        for member in cardPlayers(for: viewer) where cardRowEditable(member, for: viewer) {
            let saved = scores(member)[hole]
            let value = drafts[hole, member] ?? saved ?? par
            guard value != saved else { continue }
            for recipient in recipients(for: member) where !seen.contains(recipient) && canScore(viewer, for: recipient) {
                seen.insert(recipient)
                entries.append(HoleSubmission.Entry(memberID: recipient, strokes: value))
            }
        }
        guard !entries.isEmpty else { return nil }
        return HoleSubmission(roundID: roundID, holeIndex: hole, entries: entries, recordedAt: recordedAt)
    }

    /// Hvem et hulltall skrives på: hele laget når laget spiller én ball, ellers spilleren.
    func recipients(for member: UUID) -> [UUID] {
        guard round.form.card == .perTeam,
              let mates = Handicap.teammates(of: member.uuidString, in: round) else { return [member] }
        let ids = mates.compactMap(UUID.init(uuidString:)).filter(isPlaying)
        return ids.isEmpty ? [member] : [member] + ids.filter { $0 != member }
    }

}

nonisolated extension RoundSnapshot {
    /// Legger inn det serveren har for hullet etter en lagring (`save_hole` svarer med radene).
    /// Spillere i `members` uten rad i svaret har ikke noe ført på hullet.
    mutating func apply(saved rows: [HoleScoreRow], hole: Int, members: [UUID]) {
        let touched = Set(members).union(rows.map(\.memberID))
        scores.removeAll { $0.holeIndex == hole && touched.contains($0.memberID) }
        scores += rows.filter { $0.holeIndex == hole }
    }

    /// Runden med tall som ligger i kø lagt oppå. De er ikke på serveren ennå, men skal stå.
    func overlaying(_ queued: [QueuedHole]) -> RoundSnapshot {
        var s = self
        for q in queued {
            for e in q.entries {
                s.scores.removeAll { $0.holeIndex == q.hole && $0.memberID == e.memberID }
                if let strokes = e.strokes {
                    s.scores.append(HoleScoreRow(roundID: round.id, memberID: e.memberID, holeIndex: q.hole,
                                                 strokes: strokes, recordedAt: nil, updatedBy: nil, updatedAt: nil))
                }
            }
        }
        return s
    }
}

/// Et hull som ligger i utboksen, med tallene som ble sendt.
nonisolated struct QueuedHole: Equatable, Sendable {
    let hole: Int
    let entries: [HoleSubmission.Entry]
}

/// Tallene markøren har trykket fram, før de er lagret. En verdi som finnes ER bekreftelsen
/// (PWA-ens `scoreUtkast`). Overlever realtime-hentinger.
nonisolated struct HoleDrafts: Equatable, Sendable {
    private struct Key: Hashable, Sendable {
        let hole: Int
        let member: UUID
    }

    private var values: [Key: Int] = [:]

    subscript(hole: Int, member: UUID) -> Int? {
        get { values[Key(hole: hole, member: member)] }
        set { values[Key(hole: hole, member: member)] = newValue }
    }

    mutating func clear(hole: Int) {
        values = values.filter { $0.key.hole != hole }
    }
}

// MARK: - Hullkortet

/// Det hullkortet viser for ett hull. Regnes av `RoundGame.card`.
nonisolated struct HoleCard: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        let memberID: UUID
        let name: String
        let isMe: Bool
        /// Raden har stepper.
        let editable: Bool
        /// Bekreftet (eller trenger ikke bekreftelse). Ubekreftet vises stiplet.
        let confirmed: Bool
        /// Lagret på serveren (eller i kø).
        let saved: Int?
        /// Tallet som står: utkastet, ellers det lagrede, ellers par.
        let value: Int
        let strokesReceived: Int
        /// «5 brutto − 1 = 4 netto». Nil med eksternt handicap eller ubekreftet rad.
        let calculation: String?
        /// Nil når det ikke er noe å vise (ubekreftet, eller ikke ført i seer-modus).
        let scoreName: ScoreName?
        /// Nil i en match (der er det hullet som vinnes, ikke poengene).
        let points: Int?
        var id: UUID { memberID }
    }

    enum Action: Equatable, Sendable {
        /// «Lagre hull N → hull N+1». Låst til alle er bekreftet.
        case save(title: String, enabled: Bool, blocker: String?)
        /// Lagret og urørt: videre uten å lagre.
        case next(title: String, hole: Int)
        /// Alt er lagret på siste hull.
        case scorecard
        /// Seer: ingen knapp.
        case none
    }

    let holeIndex: Int
    let title: String
    let detail: String
    let isLongestDrive: Bool
    let isClosestToPin: Bool
    let header: String
    let strokesLabel: String
    let rows: [Row]
    let mustConfirm: Bool
    let showsParHint: Bool
    let outsideTruncation: String?
    let action: Action
    /// Seer-modus: «Feil tall? Si det til Anders.»
    let viewerHint: String?
}

nonisolated extension RoundGame {
    /// `renderHullkort` + `renderHullRad` for hullet.
    func card(hole index: Int, drafts: HoleDrafts, viewer: Viewer) -> HoleCard {
        let hole = holes[index]
        let count = holeCount
        let players = cardPlayers(for: viewer)
        let editable = players.filter { cardRowEditable($0, for: viewer) }
        let canEdit = !editable.isEmpty
        let mustConfirm = editable.count > 1

        func isConfirmed(_ member: UUID) -> Bool {
            !mustConfirm || drafts[index, member] != nil || scores(member)[index] != nil
        }

        let rows = players.map { member -> HoleCard.Row in
            let saved = scores(member)[index]
            let isEditable = editable.contains(member)
            let confirmed = isEditable ? isConfirmed(member) : saved != nil
            let value = drafts[index, member] ?? saved ?? hole.par
            let hcp = handicap(member)
            let received = round.hcpExtern ? 0
                : Scoring.handicapStrokes(handicap: hcp, strokeIndex: hole.strokeIndex, holes: count)
            let show = isEditable ? confirmed : saved != nil
            let inMatch = MatchPlay.holeMatch(for: member.uuidString, in: round) != nil
            return HoleCard.Row(
                memberID: member,
                name: name(member),
                isMe: member == viewer.memberID,
                editable: isEditable,
                confirmed: confirmed,
                saved: saved,
                value: value,
                strokesReceived: received,
                calculation: (isEditable && confirmed && !round.hcpExtern)
                    ? HoleMath.calculation(gross: value, received: received) : nil,
                scoreName: show ? Scoring.scoreName(par: hole.par, gross: value, handicap: hcp,
                                                    strokeIndex: hole.strokeIndex, holes: count) : nil,
                points: (show && !inMatch) ? Scoring.points(par: hole.par, gross: value, handicap: hcp,
                                                            strokeIndex: hole.strokeIndex, holes: count, rules: rules) : nil
            )
        }

        var detail = ["Par \(hole.par)"]
        if let m = hole.meters { detail.append("\(HoleMath.meters(m)) m") }
        if !round.hcpExtern { detail.append("indeks \(hole.cardIndex)") }

        let title = count == 18
            ? "Hull \(holeNumber(index)) av 18"
            : "Hull \(holeNumber(index)) · \(index + 1) av \(count) i runden"

        let header: String
        if players.count > 1 { header = "Båsen" }
        else if let only = players.first { header = only == viewer.memberID ? "Deg" : name(only) }
        else { header = "" }

        let outside = index >= Truncation.countingHoles(round)
            ? "Hull \(holeNumber(index)) er utenfor avkortingen og teller ikke. Du kan fortsatt føre det. Det står på scorekortet, men ikke i poengsummen."
            : nil

        let action: HoleCard.Action
        var viewerHint: String?
        if canEdit {
            let confirmed = editable.filter(isConfirmed)
            let all = confirmed.count == editable.count
            let allSaved = editable.allSatisfy { scores($0)[index] != nil }
            let changed = editable.contains { m in
                guard let d = drafts[index, m] else { return false }
                return d != scores(m)[index]
            }
            let next: Int? = index < count - 1 ? index + 1 : nil
            if allSaved && !changed {
                action = next.map { .next(title: "Neste hull → hull \(holeNumber($0))", hole: $0) } ?? .scorecard
            } else {
                var text = allSaved ? "Lagre endringen · hull \(holeNumber(index))" : "Lagre hull \(holeNumber(index))"
                if all, let next { text += " → hull \(holeNumber(next))" }
                let missing = editable.filter { !confirmed.contains($0) }.map(name)
                let blocker = all ? nil
                    : "Bekreft \(HoleMath.list(missing)) først · \(confirmed.count) av \(editable.count) klare"
                action = .save(title: text, enabled: all, blocker: blocker)
            }
        } else {
            action = .none
            if hasBays, let marker = bay(of: viewer.memberID)?.marker {
                viewerHint = "Feil tall? Si det til \(name(marker))."
            }
        }

        return HoleCard(
            holeIndex: index,
            title: title,
            detail: detail.joined(separator: " · "),
            isLongestDrive: index == longestDriveHole,
            isClosestToPin: index == closestToPinHole,
            header: header,
            strokesLabel: round.hcpExtern ? "Slag · netto" : "Slag · brutto",
            rows: rows,
            mustConfirm: mustConfirm,
            showsParHint: mustConfirm && editable.contains { !isConfirmed($0) },
            outsideTruncation: outside,
            action: action,
            viewerHint: viewerHint
        )
    }

    // MARK: Linjene over kortet

    /// `renderMarkorLinje`. Nil uten båsoppsett.
    func markerLine(for viewer: Viewer) -> String? {
        guard hasBays else { return nil }
        let me = viewer.memberID
        guard let bay = bay(of: me) else {
            return "Du står ikke i noen bås i denne runden. Si fra til arrangøren."
        }
        let others = bay.players.filter { $0 != me }.map(name)
        if bay.marker == me {
            return "Du er markør i bås \(bay.number)" + (others.isEmpty ? "" : " · \(others.joined(separator: ", ")) og deg")
        }
        if let marker = bay.marker {
            return "Bås \(bay.number) · \(name(marker)) fører · du ser det live"
        }
        return "Bås \(bay.number) · ingen markør satt · du fører din egen"
    }

    /// `renderBaasStripe`: står du på et annet hull enn båsen? Nil når du er der.
    func bayStripe(currentHole: Int, viewer: Viewer) -> (text: String, button: String, hole: Int)? {
        guard hasBays, bay(of: viewer.memberID) != nil, status == .active else { return nil }
        let bh = bayHole(for: viewer)
        guard currentHole != bh else { return nil }
        return ("Du ser på hull \(holeNumber(currentHole)). Båsen er på hull \(holeNumber(bh)).",
                "Til hull \(holeNumber(bh)) →", bh)
    }
}

/// Tekst og tall til hullkortet.
nonisolated enum HoleMath {
    /// Regnestykket: «5 brutto − 1 = 4 netto».
    static func calculation(gross: Int, received: Int) -> String {
        "\(gross) brutto − \(received) = \(gross - received) netto"
    }

    /// Meter uten desimaler når de er hele.
    static func meters(_ m: Double) -> String {
        m.rounded() == m ? String(Int(m)) : JS.norwegianString(m)
    }

    /// «A», «A og B», «A, B og C».
    static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " og " + names.last!
    }
}

// MARK: - Hullprikkene

nonisolated struct HoleDot: Equatable, Identifiable, Sendable {
    enum State: Equatable, Sendable { case done, partial, upcoming }

    let index: Int
    let number: Int
    let state: State
    let isCurrent: Bool
    let isPending: Bool
    let isLongestDrive: Bool
    let isClosestToPin: Bool
    let isBayHole: Bool
    var id: Int { index }

    var accessibilityLabel: String {
        var parts = ["Hull \(number)"]
        switch state {
        case .done: parts.append("lagret")
        case .partial: parts.append("delvis lagret")
        case .upcoming: parts.append("ikke lagret")
        }
        if isPending { parts.append("ikke sendt ennå") }
        if isLongestDrive { parts.append("longest drive") }
        if isClosestToPin { parts.append("nærmest pinnen") }
        if isBayHole { parts.append("båsens hull") }
        return parts.joined(separator: ", ")
    }
}

nonisolated extension RoundGame {
    /// `renderHullprikker`: et hull er ført når alle på kortet har score der.
    func dots(currentHole: Int, viewer: Viewer, pending: Set<Int>) -> [HoleDot] {
        var players = cardPlayers(for: viewer)
        if players.isEmpty { players = snapshot.players.map(\.memberID) }
        let bh: Int? = (hasBays && bay(of: viewer.memberID) != nil) ? bayHole(for: viewer) : nil
        return (0..<holeCount).map { i in
            let done = isComplete(hole: i, for: players)
            let partial = !done && players.contains { scores($0)[i] != nil }
            return HoleDot(index: i, number: holeNumber(i), state: done ? .done : (partial ? .partial : .upcoming),
                           isCurrent: i == currentHole, isPending: pending.contains(i),
                           isLongestDrive: i == longestDriveHole, isClosestToPin: i == closestToPinHole,
                           isBayHole: i == bh)
        }
    }
}

// MARK: - Bayen nå

nonisolated struct StandingRow: Equatable, Identifiable, Sendable {
    let memberID: UUID
    let name: String
    let total: Int
    let thru: Int
    let bay: Int?
    let isMe: Bool
    var id: UUID { memberID }
}

nonisolated extension RoundGame {
    /// Stablefordsummen i runden for spilleren (`roundNetTotalForPlayer`), med rundens handicap.
    func total(_ member: UUID) -> Int {
        Scoring.points(from: scores(member), in: round, handicap: handicap(member), rules: rules)
    }

    /// «Bayen nå»: alle i runden, flest poeng først. Likt: norsk navnesortering.
    func standings(viewer: Viewer) -> [StandingRow] {
        snapshot.players
            .map { p in
                StandingRow(memberID: p.memberID, name: name(p.memberID), total: total(p.memberID),
                            thru: scores(p.memberID).count, bay: p.bayNo, isMe: p.memberID == viewer.memberID)
            }
            .sorted { a, b in
                a.total != b.total ? a.total > b.total : NorwegianSort.areInIncreasingOrder(a.name, b.name)
            }
    }
}

// MARK: - Scorekortet

nonisolated struct Scorecard: Equatable, Sendable {
    struct Line: Equatable, Identifiable, Sendable {
        let index: Int
        let number: Int
        let par: Int
        let strokes: Int?
        let points: Int?
        let scoreName: ScoreName?
        var id: Int { index }
    }

    let name: String
    let inward: Bool
    let lines: [Line]
    var sumPar: Int { lines.reduce(0) { $0 + $1.par } }
    var sumStrokes: Int { lines.reduce(0) { $0 + ($1.strokes ?? 0) } }
    var sumPoints: Int { lines.reduce(0) { $0 + ($1.points ?? 0) } }
}

nonisolated extension RoundGame {
    /// Har runden en «Inn»-side? Ni hull har ikke.
    var hasInward: Bool { holeCount > 9 }

    /// `renderScorekort`: Ut (1–9) eller Inn (10–18), par, slag og poeng per hull.
    func scorecard(for member: UUID, inward: Bool) -> Scorecard {
        let from = (hasInward && inward) ? 9 : 0
        let hcp = handicap(member)
        let mine = scores(member)
        let lines = (from..<min(from + 9, holeCount)).map { i -> Scorecard.Line in
            let h = holes[i]
            guard let gross = mine[i] else {
                return Scorecard.Line(index: i, number: holeNumber(i), par: h.par, strokes: nil, points: nil, scoreName: nil)
            }
            return Scorecard.Line(
                index: i, number: holeNumber(i), par: h.par, strokes: gross,
                points: Scoring.points(par: h.par, gross: gross, handicap: hcp, strokeIndex: h.strokeIndex,
                                       holes: holeCount, rules: rules),
                scoreName: Scoring.scoreName(par: h.par, gross: gross, handicap: hcp, strokeIndex: h.strokeIndex,
                                             holes: holeCount))
        }
        return Scorecard(name: name(member), inward: from == 9, lines: lines)
    }
}

// MARK: - Feiringen

nonisolated enum CelebrationLevel: Int, Comparable, Sendable {
    case birdie = 1, eagle, albatross, ace

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// Hvor lenge feiringen står (`CELEBRATIONS.ms`).
    var duration: Duration {
        switch self {
        case .birdie: .milliseconds(1500)
        case .eagle: .milliseconds(2300)
        case .albatross: .milliseconds(2900)
        case .ace: .milliseconds(5200)
        }
    }

    var title: String {
        switch self {
        case .birdie: "Birdie"
        case .eagle: "Eagle"
        case .albatross: "Albatross"
        case .ace: "HOLE IN ONE"
        }
    }

    /// Konfettimengden (`partikler`). Birdie har ingen.
    var particles: Int {
        switch self {
        case .birdie: 0
        case .eagle: 70
        case .albatross: 110
        case .ace: 200
        }
    }

    /// `celebrationFor`: hole in one er brutto 1; resten er netto mot par.
    static func level(gross: Int, net: Int, par: Int) -> CelebrationLevel? {
        if gross == 1 { return .ace }
        switch net - par {
        case ...(-3): return .albatross
        case -2: return .eagle
        case -1: return .birdie
        default: return nil
        }
    }
}

nonisolated struct Celebration: Equatable, Identifiable, Sendable {
    let id = UUID()
    let level: CelebrationLevel
    let eyebrow: String
    let text: String
    let points: Int?
    let place: Int?
    /// Neste hull (banens nummer), eller nil på siste hull.
    let nextHole: Int?
    /// I en match: stillingen etter hullet («1 opp etter 1») i stedet for poeng og plass.
    var matchText: String? = nil

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

nonisolated extension RoundGame {
    /// `samletFeiring`: én feiring per hull. Høyeste nivå i båsen vinner. Én mann: personlig
    /// tekst, poeng og plass. Flere: alle som fikk birdie eller bedre.
    /// - Parameter saved: hulltallene som nettopp ble lagret, i en runde der de står inne.
    ///   Rettinger (hullet var lagret fra før) tas ikke med av den som kaller.
    func celebration(hole index: Int, saved: [(member: UUID, strokes: Int)]) -> Celebration? {
        let hole = holes[index]
        let hits: [(level: CelebrationLevel, member: UUID, strokes: Int)] = saved.compactMap { s in
            let net = Scoring.netStrokes(gross: s.strokes, handicap: handicap(s.member),
                                         strokeIndex: hole.strokeIndex, holes: holeCount)
            return CelebrationLevel.level(gross: s.strokes, net: net, par: hole.par).map { ($0, s.member, s.strokes) }
        }
        guard let best = hits.max(by: { $0.level < $1.level }) else { return nil }
        let eyebrow = "HULL \(holeNumber(index)) · PAR \(hole.par)"
        let next = index < holeCount - 1 ? holeNumber(index + 1) : nil

        if hits.count > 1 {
            let text = hits.sorted { $0.level > $1.level }.map { h in
                name(h.member) + " " + (h.level == .ace ? "hole in one" : h.level.title.lowercased())
            }.joined(separator: " · ")
            return Celebration(level: best.level, eyebrow: eyebrow, text: text, points: nil, place: nil, nextHole: next)
        }

        let who = name(best.member)
        let text = switch best.level {
        case .ace: "\(who) slo den rett i koppen."
        case .albatross: "Tre under par netto, \(who). Det skjer ikke igjen."
        case .eagle: "To under par. Ikke for å bruse med fjæra, men det var pent."
        case .birdie: "Bra jobba, \(who)!"
        }
        if MatchPlay.holeMatch(for: best.member.uuidString, in: round) != nil {
            let standing = holeMatchStanding(best.member).map(MatchPlay.text)
            return Celebration(level: best.level, eyebrow: eyebrow, text: text, points: nil, place: nil, nextHole: next,
                               matchText: standing.flatMap { $0.isEmpty ? nil : $0 })
        }
        let points = Scoring.points(par: hole.par, gross: best.strokes, handicap: handicap(best.member),
                                    strokeIndex: hole.strokeIndex, holes: holeCount, rules: rules)
        let place = standings(viewer: Viewer(memberID: best.member, isOrganizer: false))
            .firstIndex { $0.memberID == best.member }.map { $0 + 1 }
        return Celebration(level: best.level, eyebrow: eyebrow, text: text, points: points, place: place, nextHole: next)
    }
}
