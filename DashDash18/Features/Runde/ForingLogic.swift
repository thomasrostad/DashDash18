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

    /// Som `clamp`, og aldri over regelsettets maks slag på hullet (`play.maxStrokes`, nil: ingen).
    static func clamp(_ value: Int, max limit: Int?) -> Int {
        guard let limit else { return clamp(value) }
        return Swift.min(clamp(value), Swift.max(range.lowerBound, limit))
    }
}

/// Et trykk på «Lagre» rett etter at kortet byttet hull, var ment for hullet før: andre halvdel
/// av et dobbelttrykk på «Lagre hull N → hull N+1» eller «Neste hull», eller kortet som flyttet
/// seg under fingeren. Uten sperra lagres neste hull med par uten at noen har tastet det.
/// En inndatagrense for skjermen, ikke en spilleregel.
nonisolated enum SaveTapGuard {
    static let interval: TimeInterval = 0.6

    static func allows(now: Date, holeChangedAt: Date) -> Bool {
        now.timeIntervalSince(holeChangedAt) >= interval
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
    /// Levert kort (sql/057): bare arrangøren. `ignoringSubmission`: som om kortet ikke var levert.
    func canScore(_ viewer: Viewer, for target: UUID, ignoringSubmission: Bool = false) -> Bool {
        if viewer.isOrganizer { return true }
        guard status == .active else { return false }
        if !ignoringSubmission, isCardSubmitted(target) { return false }
        if let marker = bay(of: target)?.marker { return marker == viewer.memberID }
        return viewer.memberID == target
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

    /// Radene på hullkortet. I en form med ett kort per lag (scramble, foursome …) står hvert lag
    /// én gang, med den første fra laget på kortet. Tallet skrives på hele laget (`recipients`).
    /// Ellers én rad per spiller, som `cardPlayers`.
    func cardRows(for viewer: Viewer) -> [UUID] {
        let players = cardPlayers(for: viewer)
        guard round.form.card == .perTeam else { return players }
        var seen: Set<UUID> = []
        return players.filter { member in
            guard !seen.contains(member) else { return false }
            seen.formUnion(recipients(for: member))
            return true
        }
    }

    /// Navnet på raden: hele laget («Anders, Bjørn og Cato») når laget spiller én ball, ellers spilleren.
    func rowName(_ member: UUID) -> String {
        let team = recipients(for: member)
        guard team.count > 1 else { return name(member) }
        let names = team.map(name).sorted { NorwegianSort.areInIncreasingOrder($0, $1) }
        return names.dropLast().joined(separator: ", ") + " og " + names.last!
    }

    /// `hullkortRadKanFores`: får jeg føre raden på kortet? Strengere enn `canScore`:
    /// en arrangør i en bås med markør fører ikke på kortet (han retter i stedet).
    func cardRowEditable(_ member: UUID, for viewer: Viewer, ignoringSubmission: Bool = false) -> Bool {
        if status != .active && !viewer.isOrganizer { return false }
        let me = viewer.memberID
        let skip = ignoringSubmission
        guard let bay = bay(of: me) else { return member == me && canScore(viewer, for: me, ignoringSubmission: skip) }
        if let marker = bay.marker { return marker == me && canScore(viewer, for: member, ignoringSubmission: skip) }
        return member == me && canScore(viewer, for: me, ignoringSubmission: skip)
    }

    /// Hullet er ført for alle disse spillerne.
    func isComplete(hole: Int, for players: [UUID]) -> Bool {
        !players.isEmpty && players.allSatisfy { scores($0)[hole] != nil }
    }

    /// Synkstatus over «Lagre» (utbedringsplanen K6). Nil når ingenting er ført ennå.
    /// `pending`: hull som ligger i køen på telefonen.
    func syncStatus(viewer: Viewer, pending: Set<Int>) -> SyncStatus? {
        let players = cardRows(for: viewer).filter { cardRowEditable($0, for: viewer) }
        guard !players.isEmpty else { return nil }
        if !pending.isEmpty {
            return SyncStatus(text: "Lagret på telefonen · sendes når du får dekning", isPending: true)
        }
        let synced = (0..<holeCount).filter { isComplete(hole: $0, for: players) }
        guard let last = synced.last else { return nil }
        if synced.count == 1 {
            return SyncStatus(text: "Hull \(holeNumber(last)) er synket", isPending: false)
        }
        if synced == Array(synced.first!...last) {
            return SyncStatus(text: "Hull \(holeNumber(synced.first!))–\(holeNumber(last)) er synket", isPending: false)
        }
        return SyncStatus(text: "\(synced.count) hull er synket", isPending: false)
    }

    /// `baasensHull`: første hull der ikke alle på kortet er ført, regnet fra gruppas starthull og
    /// rundt (gunstart på hull 10: 10–18, så 1–9). Alle ført: det siste i rekka.
    func bayHole(for viewer: Viewer) -> Int {
        let players = cardPlayers(for: viewer)
        guard !players.isEmpty else { return 0 }
        let order = holeOrder(for: viewer)
        return order.first { !isComplete(hole: $0, for: players) } ?? order.last ?? 0
    }

    /// Indeksen til starthullet for gruppa på kortet (startlista, sql/031). 0 uten startliste,
    /// og når starthullet ikke er i runden. Nummeret er banens hullnummer; finnes det ikke i runden
    /// (9 hull fra hull 10, starthull 3), er det plassen i runden.
    func startHoleIndex(for viewer: Viewer) -> Int {
        guard let first = cardPlayers(for: viewer).first, let group = bay(of: first)?.number,
              let start = snapshot.startHoles[group] else { return 0 }
        if let index = (0..<holeCount).first(where: { holeNumber($0) == start }) { return index }
        return (1...max(holeCount, 1)).contains(start) ? start - 1 : 0
    }

    /// Hullene i den rekkefølgen gruppa spiller dem: fra starthullet og rundt.
    func holeOrder(for viewer: Viewer) -> [Int] {
        let start = startHoleIndex(for: viewer)
        return (0..<holeCount).map { (start + $0) % holeCount }
    }

    /// Hullet etter `index` for gruppa: fra 18 til 1 når gruppa startet midt i runden.
    /// nil etter gruppas siste hull.
    func nextHole(after index: Int, for viewer: Viewer) -> Int? {
        let order = holeOrder(for: viewer)
        guard let position = order.firstIndex(of: index), position + 1 < order.count else { return nil }
        return order[position + 1]
    }

    // MARK: Lagring

    /// Det «Lagre hull» sender: radene `viewer` får føre på kortet, med tallet som står
    /// (utkastet, ellers det lagrede, ellers par). Bare rader som er endret mot serveren.
    /// I en form med ett kort per lag har laget én rad, og tallet skrives på hele laget (`saveHoleScore`).
    /// `nil` når ingenting er endret.
    func submission(hole: Int, drafts: HoleDrafts, viewer: Viewer, recordedAt: Date) -> HoleSubmission? {
        guard holes.indices.contains(hole) else { return nil }
        let par = holes[hole].par
        var entries: [HoleSubmission.Entry] = []
        var seen: Set<UUID> = []
        for member in cardRows(for: viewer) where cardRowEditable(member, for: viewer) {
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

nonisolated extension QueuedHole {
    init(_ submission: HoleSubmission) {
        self.init(hole: submission.holeIndex, entries: submission.entries)
    }
}

/// Linja som sier om førte hull er sendt (K6).
nonisolated struct SyncStatus: Equatable, Sendable {
    let text: String
    /// Ligger i køen på telefonen (rust-ikon).
    let isPending: Bool
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

// MARK: - Par-bekreftelsen

nonisolated extension RoundGame {
    /// Kan `viewer` bekrefte parene? Samme regel som `confirm_round_par` (sql/014): arrangøren alltid, ellers en
    /// spiller i runden mens den går, så lenge båsen hans ikke har en annen markør
    /// (PWA: `kanBekrefteBaneoppsett`).
    func canConfirmPar(_ viewer: Viewer) -> Bool {
        if viewer.isOrganizer { return true }
        guard status == .active,
              let me = snapshot.players.first(where: { $0.memberID == viewer.memberID }) else { return false }
        guard let bay = me.bayNo, bay >= 1 else { return true }
        let marker = snapshot.players.last { $0.bayNo == bay && $0.isMarker }?.memberID
        return marker == nil || marker == viewer.memberID
    }
}

/// Feilene fra `confirm_round_par` på norsk.
nonisolated enum ParConfirmation {
    static func error(_ error: DataError) -> DataError {
        // 55000 («Runden er ikke i gang») kommer med serverens tekst som `.invalid`.
        error == .notAllowed ? .invalid("Bare arrangøren eller en markør kan bekrefte parene.") : error
    }

    /// Teksten under knappen. Feil som kan gå over av seg selv, sier «Prøv igjen»
    /// (nett-teksten sier det allerede).
    static func message(_ error: DataError) -> String {
        if case .unknown = error { return error.message + " Prøv igjen." }
        return error.message
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
        /// Rørt av markøren, lagret, eller alene på kortet. Urørt forvalg (par) vises dempet
        /// med «forvalgt par» (utbedringsplanen K1).
        let confirmed: Bool
        /// Lagret på serveren (eller i kø).
        let saved: Int?
        /// Tallet som står: utkastet, ellers det lagrede, ellers par.
        let value: Int
        let strokesReceived: Int
        /// «5 brutto − 1 = 4 netto». Nil med eksternt handicap.
        let calculation: String?
        /// Nil når det ikke er noe å vise (ikke ført i seer-modus).
        let scoreName: ScoreName?
        /// Nil i en match (der er det hullet som vinnes, ikke poengene) og i par/bogey.
        let points: Int?
        /// Par/bogey (regel 21.3): «+» vunnet, «0» delt, «−» tapt hull mot banen. Nil i andre former.
        var parBogey: String? = nil
        /// Regelsettets maks slag på hullet for spilleren (`play.maxStrokes`). Nil: ingen grense.
        var maxStrokes: Int? = nil
        var id: UUID { memberID }
        /// Stepperen står på grensen (+ er av).
        var isAtMax: Bool { maxStrokes.map { value >= $0 } ?? false }
        /// Står på forvalget (par) uten at markøren har rørt det.
        var isDefault: Bool { editable && !confirmed }
    }

    enum Action: Equatable, Sendable {
        /// «Lagre hull N og gå videre». Alltid aktiv: urørte rader lagres som par (K1).
        /// `status` er linja over knappen, f.eks. «1 av 4 endret fra par».
        case save(title: String, enabled: Bool, status: String?)
        /// Lagret og urørt: videre uten å lagre.
        case next(title: String, hole: Int)
        /// Alt er lagret på siste hull.
        case scorecard
        /// Seer: ingen knapp.
        case none
    }

    let holeIndex: Int
    /// Banens nummer på hullet (hero-kortet).
    let number: Int
    let par: Int
    /// «155», eller nil uten lengde.
    let meters: String?
    /// Indeksen på scorekortet, eller nil med eksternt handicap.
    let strokeIndex: Int?
    /// Hull i runden, så ‹ › vet hvor langt de kan gå.
    let holeCount: Int
    let title: String
    let detail: String
    let isLongestDrive: Bool
    let isClosestToPin: Bool
    let header: String
    let strokesLabel: String
    let rows: [Row]
    /// Flere rader å føre (båsen). Da viser kortet hvor mange som er endret fra par.
    let mustConfirm: Bool
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
        let players = cardRows(for: viewer)
        let editable = players.filter { cardRowEditable($0, for: viewer) }
        let canEdit = !editable.isEmpty
        let mustConfirm = editable.count > 1
        let isParBogey = round.form.axes.scoring == .parBogey

        func isConfirmed(_ member: UUID) -> Bool {
            !mustConfirm || drafts[index, member] != nil || scores(member)[index] != nil
        }

        let rows = players.map { member -> HoleCard.Row in
            let saved = scores(member)[index]
            let isEditable = editable.contains(member)
            let confirmed = isEditable ? isConfirmed(member) : saved != nil
            let hcp = handicap(member)
            let received = round.hcpExtern ? 0
                : Scoring.handicapStrokes(handicap: hcp, strokeIndex: hole.strokeIndex, holes: count)
            // Maks slag per hull (`play.maxStrokes`): stepperen stopper der, og forvalget går ikke over.
            let limit = rules.play.maxStrokes.limit(par: hole.par, strokesReceived: received)
            let value = StrokeInput.clamp(drafts[index, member] ?? saved ?? hole.par, max: limit)
            let show = isEditable || saved != nil
            let inMatch = MatchPlay.holeMatch(for: member.uuidString, in: round) != nil
            let parBogey = isParBogey && show ? HoleMath.parBogeyMark(net: value - received, par: hole.par) : nil
            return HoleCard.Row(
                memberID: member,
                name: rowName(member),
                isMe: member == viewer.memberID,
                editable: isEditable,
                confirmed: confirmed,
                saved: saved,
                value: value,
                strokesReceived: received,
                calculation: (isEditable && !round.hcpExtern)
                    ? HoleMath.calculation(gross: value, received: received) : nil,
                scoreName: show ? Scoring.scoreName(par: hole.par, gross: value, handicap: hcp,
                                                    strokeIndex: hole.strokeIndex, holes: count) : nil,
                points: (show && !inMatch && !isParBogey) ? Scoring.points(par: hole.par, gross: value, handicap: hcp,
                                                            strokeIndex: hole.strokeIndex, holes: count, rules: rules) : nil,
                parBogey: parBogey,
                maxStrokes: limit
            )
        }

        var detail = ["Par \(hole.par)"]
        if let m = hole.meters { detail.append("\(HoleMath.meters(m)) m") }
        if !round.hcpExtern { detail.append("indeks \(hole.cardIndex)") }

        let title = count == 18
            ? "Hull \(holeNumber(index)) av 18"
            : "Hull \(holeNumber(index)) · \(index + 1) av \(count) i runden"

        let header: String
        if players.count > 1 { header = groupTerm.definiteTitle }
        else if let only = players.first { header = only == viewer.memberID ? "Ditt kort" : name(only) }
        else { header = "" }

        let outside = index >= Truncation.countingHoles(round)
            ? "Hull \(holeNumber(index)) er utenfor avkortingen og teller ikke. Du kan fortsatt føre det. Det står på scorekortet, men ikke i poengsummen."
            : nil

        let action: HoleCard.Action
        var viewerHint: String?
        if canEdit {
            let allSaved = editable.allSatisfy { scores($0)[index] != nil }
            let changed = editable.contains { m in
                guard let d = drafts[index, m] else { return false }
                return d != scores(m)[index]
            }
            let next = nextHole(after: index, for: viewer)
            if allSaved && !changed {
                action = next.map { .next(title: "Neste hull → hull \(holeNumber($0))", hole: $0) } ?? .scorecard
            } else {
                let text = allSaved
                    ? "Lagre endringen · hull \(holeNumber(index))"
                    : (next == nil ? "Lagre hull \(holeNumber(index))" : "Lagre hull \(holeNumber(index)) og gå videre")
                // Ett trykk per hull når alle går par: urørte rader lagres som par (K1).
                let changedFromPar = editable.filter { m in
                    (drafts[index, m] ?? scores(m)[index]).map { $0 != hole.par } ?? false
                }.count
                let status = mustConfirm ? "\(changedFromPar) av \(editable.count) endret fra par" : nil
                action = .save(title: text, enabled: true, status: status)
            }
        } else {
            action = .none
            if hasBays, let marker = bay(of: viewer.memberID)?.marker {
                viewerHint = "Feil tall? Si det til \(name(marker))."
            }
        }

        return HoleCard(
            holeIndex: index,
            number: holeNumber(index),
            par: hole.par,
            meters: hole.meters.map(HoleMath.meters),
            strokeIndex: round.hcpExtern ? nil : hole.cardIndex,
            holeCount: count,
            title: title,
            detail: detail.joined(separator: " · "),
            isLongestDrive: index == longestDriveHole,
            isClosestToPin: index == closestToPinHole,
            header: header,
            strokesLabel: round.hcpExtern ? "Slag · netto" : "Slag · brutto",
            rows: rows,
            mustConfirm: mustConfirm,
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
            return "Du står ikke i noen \(groupTerm.singular) i denne runden. Si fra til arrangøren."
        }
        let others = bay.players.filter { $0 != me }.map(name)
        if bay.marker == me {
            return "Du er markør i \(groupTerm.numberedLower(bay.number))" + (others.isEmpty ? "" : " · \(others.joined(separator: ", ")) og deg")
        }
        if let marker = bay.marker {
            return "\(groupTerm.numbered(bay.number)) · \(name(marker)) fører · du ser det live"
        }
        return "\(groupTerm.numbered(bay.number)) · ingen markør satt · du fører din egen"
    }

    /// `renderBaasStripe`: står du på et annet hull enn båsen? Nil når du er der.
    func bayStripe(currentHole: Int, viewer: Viewer) -> (text: String, button: String, hole: Int)? {
        guard hasBays, bay(of: viewer.memberID) != nil, status == .active else { return nil }
        let bh = bayHole(for: viewer)
        guard currentHole != bh else { return nil }
        return ("Du ser på hull \(holeNumber(currentHole)). \(groupTerm.definiteTitle) er på hull \(holeNumber(bh)).",
                "Til hull \(holeNumber(bh)) →", bh)
    }
}

nonisolated extension HoleCard {
    /// «Par 3 · 155 m» under hullnummeret.
    var parLine: String {
        meters.map { "Par \(par) · \($0) m" } ?? "Par \(par)"
    }

    /// «Indeks 17», eller nil med eksternt handicap.
    var indexLine: String? { strokeIndex.map { "Indeks \($0)" } }

    var hasPrevious: Bool { holeIndex > 0 }
    var hasNext: Bool { holeIndex < holeCount - 1 }

    /// «Lagre hull 7 og gå videre» får en pil (planen 4.2).
    var actionAdvances: Bool {
        if case .save(let title, _, _) = action { return title.hasSuffix("og gå videre") }
        return false
    }
}

// MARK: - Føringen som egen skjerm (planen 4.2)

/// Tittelen i verktøylinja: «Losby · runde 4» og «Du fører for bås 2» under.
nonisolated struct ScoringTitle: Equatable, Sendable {
    let title: String
    let subtitle: String?
}

/// Segmentene i føringen: «Føring | Stilling | Spill i runden».
nonisolated enum RundeSegment: Hashable, Sendable {
    case scoring, standing, extras

    /// Segmentet skjermen åpner på: føringen når det er noe å føre, ellers stillingen.
    static func initial(isLocked: Bool, hasCard: Bool) -> RundeSegment {
        (isLocked || !hasCard) ? .standing : .scoring
    }

    /// «Spill · 2». Kort nok til tre like brede segmenter på 375 pt.
    static func extrasTitle(count: Int) -> String {
        count > 0 ? "Spill · \(count)" : "Spill"
    }
}

nonisolated extension RoundGame {
    /// Banen (uten «Golfklubb») og runden i klubben. En løs runde har ikke rundenummer.
    func scoringTitle(viewer: Viewer) -> ScoringTitle {
        let course = snapshot.course.map { Self.shortCourseName($0.name) } ?? "Runden"
        let title = snapshot.loose == nil ? "\(course) · runde \(snapshot.round.roundNo)" : course
        return ScoringTitle(title: title, subtitle: scoringSubtitle(viewer: viewer))
    }

    /// «Du fører for bås 2», «Bås 2 · Kåre fører», «Du fører ditt eget kort» eller «Runden er ferdig».
    private func scoringSubtitle(viewer: Viewer) -> String? {
        if status == .locked { return "Runden er ferdig" }
        let me = viewer.memberID
        guard isPlaying(me) else { return viewer.isOrganizer ? "Du ser på som arrangør" : "Du ser på" }
        if hasBays, let bay = bay(of: me) {
            if bay.marker == me { return "Du fører for \(groupTerm.numberedLower(bay.number))" }
            if let marker = bay.marker { return "\(groupTerm.numbered(bay.number)) · \(name(marker)) fører" }
        }
        return cardRowEditable(me, for: viewer) ? "Du fører ditt eget kort" : nil
    }

    /// «Losby Golfklubb» → «Losby». Andre navn står som de er.
    static func shortCourseName(_ name: String) -> String {
        for suffix in [" Golfklubb", " golfklubb", " GK", " Golfbane", " golfbane"] where name.hasSuffix(suffix) {
            let short = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            return short.isEmpty ? name : short
        }
        return name
    }
}

/// Tekst og tall til hullkortet.
nonisolated enum HoleMath {
    /// Regnestykket: «5 brutto − 1 = 4 netto».
    /// Par/bogey-tegnet på hullet (regel 21.3): «+» under par netto, «0» på par, «−» over.
    static func parBogeyMark(net: Int, par: Int) -> String {
        net < par ? "+" : net == par ? "0" : "−"
    }

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
    /// Ordet for gruppa i «båsens hull» / «flightens hull».
    var groupTerm: GroupTerm = .bay
    var id: Int { index }

    /// Hullbrikken (V15): nåværende er fylt, førte har chip-bakgrunn, kommende har strek.
    enum ChipStyle: Equatable, Sendable { case current, saved, partial, upcoming }

    var chipStyle: ChipStyle {
        if isCurrent { return .current }
        switch state {
        case .done: return .saved
        case .partial: return .partial
        case .upcoming: return .upcoming
        }
    }

    /// Longest drive eller nærmest pinnen: liten gull-prikk på brikken.
    var hasSidePrize: Bool { isLongestDrive || isClosestToPin }

    /// «Hull 7, nåværende, nærmest pinnen».
    var accessibilityLabel: String {
        var parts = ["Hull \(number)"]
        if isCurrent { parts.append("nåværende") }
        switch state {
        case .done: parts.append("lagret")
        case .partial: parts.append("delvis lagret")
        case .upcoming: if !isCurrent { parts.append("ikke lagret") }
        }
        if isPending { parts.append("ikke sendt ennå") }
        if isLongestDrive { parts.append("longest drive") }
        if isClosestToPin { parts.append("nærmest pinnen") }
        if isBayHole { parts.append("\(groupTerm.definiteGenitive) hull") }
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
                           isBayHole: i == bh, groupTerm: groupTerm)
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
        /// Par/bogey (regel 21.3): «+», «0» eller «−» mot banen. Nil i andre former.
        var parBogey: String? = nil
        var id: Int { index }
    }

    let name: String
    let inward: Bool
    let lines: [Line]
    /// Par/bogey: summen for siden med regelsettets verdier (`formPlay.parBogey`). Nil i andre former.
    var parBogeySum: Double? = nil
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
        let isParBogey = round.form.axes.scoring == .parBogey
        var parBogeySum = 0.0
        let lines = (from..<min(from + 9, holeCount)).map { i -> Scorecard.Line in
            let h = holes[i]
            guard let gross = mine[i] else {
                return Scorecard.Line(index: i, number: holeNumber(i), par: h.par, strokes: nil, points: nil, scoreName: nil)
            }
            var mark: String?
            if isParBogey {
                let received = round.hcpExtern ? 0
                    : Scoring.handicapStrokes(handicap: hcp, strokeIndex: h.strokeIndex, holes: holeCount)
                mark = HoleMath.parBogeyMark(net: gross - received, par: h.par)
                parBogeySum += ParBogey.holeValue(net: gross - received, par: h.par, rules: rules.formPlay.parBogey)
            }
            return Scorecard.Line(
                index: i, number: holeNumber(i), par: h.par, strokes: gross,
                points: isParBogey ? nil : Scoring.points(par: h.par, gross: gross, handicap: hcp, strokeIndex: h.strokeIndex,
                                                          holes: holeCount, rules: rules),
                scoreName: Scoring.scoreName(par: h.par, gross: gross, handicap: hcp, strokeIndex: h.strokeIndex,
                                             holes: holeCount),
                parBogey: mark)
        }
        return Scorecard(name: name(member), inward: from == 9, lines: lines,
                         parBogeySum: isParBogey ? parBogeySum : nil)
    }

    /// «Totalt i runden»: «24 poeng», eller par/bogey-summen med fortegn («+2 mot banen», som «Bayen nå»).
    func scorecardTotal(for member: UUID) -> String {
        guard round.form.axes.scoring == .parBogey else { return "\(total(member)) poeng" }
        let sum = FormPlay.tablePoints(round, roster: roster, rules: rules)[member.uuidString] ?? 0
        return RoundCompetitionBoard.signedText(sum.rounded()) + " mot banen"
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
    /// - Parameter viewer: med den går «Videre til hull N» rundt fra gruppas starthull (gunstart).
    func celebration(hole index: Int, saved: [(member: UUID, strokes: Int)], viewer: Viewer? = nil) -> Celebration? {
        let hole = holes[index]
        let hits: [(level: CelebrationLevel, member: UUID, strokes: Int)] = saved.compactMap { s in
            let net = Scoring.netStrokes(gross: s.strokes, handicap: handicap(s.member),
                                         strokeIndex: hole.strokeIndex, holes: holeCount)
            return CelebrationLevel.level(gross: s.strokes, net: net, par: hole.par).map { ($0, s.member, s.strokes) }
        }
        guard let best = hits.max(by: { $0.level < $1.level }) else { return nil }
        let eyebrow = "HULL \(holeNumber(index)) · PAR \(hole.par)"
        let following = viewer.map { nextHole(after: index, for: $0) } ?? (index < holeCount - 1 ? index + 1 : nil)
        let next = following.map(holeNumber)

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
