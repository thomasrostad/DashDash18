import Foundation
import GolfgutuCore

/// Valg for importen.
public struct ImportOptions: Sendable, Equatable {
    /// Importer inn i en klubb som finnes fra før. `nil`: en ny klubb med stabil id.
    public var clubID: UUID?
    /// Navnet på en ny klubb. `nil`: `settings.name` fra PWA-en.
    public var clubName: String?
    /// Regelsettet sesongen får. Golfgutu-oppsettet gjengir PWA-en.
    public var ruleset: Ruleset

    public init(clubID: UUID? = nil, clubName: String? = nil, ruleset: Ruleset = .golfgutu) {
        self.clubID = clubID
        self.clubName = clubName
        self.ruleset = ruleset
    }
}

/// Feil som stopper importen. Da skrives ingen SQL.
public enum ImportError: Error, Equatable, CustomStringConvertible {
    case duplicateMemberName(String)
    case duplicateEventDate(String)
    case severalActiveRounds([String])
    case emptyRoster

    public var description: String {
        switch self {
        case .duplicateMemberName(let ids):
            "To spillere har samme navn (store/små bokstaver og mellomrom teller ikke): \(ids). Navnet må være unikt i troppen."
        case .duplicateEventDate(let date):
            "To kvelder i terminlista har samme dato: \(date)."
        case .severalActiveRounds(let ids):
            "Mer enn én runde pågår i PWA-en (\(ids.joined(separator: ", "))). Appen tillater bare én. Lås eller slett i PWA-en først."
        case .emptyRoster:
            "Øyeblikksbildet har ingen spillere. Er det riktig fil?"
        }
    }
}

/// PWA-øyeblikksbilde → appens rader. Ren funksjon: samme input gir samme plan.
public enum Mapper {
    public static func plan(_ s: PWASnapshot, options: ImportOptions = ImportOptions()) throws -> ImportPlan {
        var warnings: [String] = []
        func warn(_ text: String) { warnings.append(text) }
        let settings = s.settings.first

        guard !s.players.isEmpty else { throw ImportError.emptyRoster }

        // --- Klubb og sesong ----------------------------------------------
        let clubName = clip(options.clubName ?? settings?.name ?? "Golfgutu Invitational", 60, "klubbnavn", warn)
        let club = ImportPlan.Club(id: options.clubID ?? StableID.club("golfgutu"), name: clubName)
        let year = settings?.year.map(String.init) ?? "uten år"
        let seasonName = clip("\(settings?.name ?? "Golfgutu Invitational") \(year)", 60, "sesongnavn", warn)
        let season = ImportPlan.Season(
            id: StableID.season("\(club.id.uuidString.lowercased()):\(year)"),
            name: seasonName,
            status: (settings?.finished ?? false) ? "finished" : "active",
            rulesJSON: rulesJSON(options.ruleset))

        // --- Troppen --------------------------------------------------------
        var memberByPWA: [String: UUID] = [:]
        var members: [ImportPlan.Member] = []
        var seenNames: [String: String] = [:]
        let treasurer = settings?.treasurerId?.lowercased()
        for p in s.players.sorted(by: { ($0.joinedAt ?? "", $0.id) < ($1.joinedAt ?? "", $1.id) }) {
            let key = p.id.lowercased()
            let name = clip(p.name.trimmingCharacters(in: .whitespacesAndNewlines), 40, "spillernavn \(p.id)", warn)
            let folded = name.lowercased()
            if let other = seenNames[folded] { throw ImportError.duplicateMemberName("\(other) og \(p.id)") }
            seenNames[folded] = p.id
            var hcp = p.handicap.map { ($0 * 10).rounded() / 10 }
            if let h = hcp, !(-10...54).contains(h) {
                warn("Spiller \(p.id): handicap \(h) er utenfor −10…54 og er satt til tomt.")
                hcp = nil
            }
            var seed = p.seedGroup
            if let g = seed, !(1...9).contains(g) {
                warn("Spiller \(p.id): seedet gruppe \(g) er utenfor 1…9 og er tatt bort.")
                seed = nil
            }
            let id = StableID.member(key)
            memberByPWA[key] = id
            members.append(ImportPlan.Member(id: id, pwaID: p.id, displayName: name, handicapIndex: hcp, seedGroup: seed,
                                             isOrganizer: p.commissioner, isTreasurer: key == treasurer,
                                             createdAt: p.joinedAt))
        }
        func member(_ pwa: String?) -> UUID? {
            guard let pwa, !pwa.isEmpty else { return nil }
            return memberByPWA[pwa.lowercased()]
        }
        let memberRow = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })

        // --- Baner ----------------------------------------------------------
        var courseByPWA: [String: UUID] = [:]
        var courses: [ImportPlan.Course] = []
        var courseHoles: [ImportPlan.CourseHole] = []
        let holeRowsByCourse = Dictionary(grouping: s.courseHoles, by: \.courseId)
        for c in s.courses.sorted(by: { $0.id < $1.id }) {
            let id = StableID.course(c.id)
            courseByPWA[c.id] = id
            var cr = c.courseRating
            if let x = cr, !(20...90).contains(x) { warn("Bane \(c.id): CR \(x) er utenfor 20…90."); cr = nil }
            var slope = c.slopeRating.map { Int($0.rounded()) }
            if let x = slope, !(55...155).contains(x) { warn("Bane \(c.id): slope \(x) er utenfor 55…155."); slope = nil }
            courses.append(ImportPlan.Course(
                id: id, pwaID: c.id, name: clip(c.name.trimmingCharacters(in: .whitespaces), 80, "banenavn \(c.id)", warn),
                externalName: c.trackmanName.map { clip($0, 80, "Trackman-navn \(c.id)", warn) },
                courseRating: cr.map { ($0 * 10).rounded() / 10 }, slopeRating: slope, inUse: c.inUse,
                confirmedBy: member(c.confirmedBy), confirmedAt: c.confirmedBy == nil ? nil : c.confirmedAt,
                createdAt: c.createdAt))
            courseHoles += holes(for: c, rows: holeRowsByCourse[c.id] ?? [], courseID: id, warn: warn)
        }

        // --- Terminlista ----------------------------------------------------
        var eventByPWA: [String: UUID] = [:]
        var eventByDate: [String: UUID] = [:]
        var events: [ImportPlan.Event] = []
        var committee: [ImportPlan.Committee] = []
        for row in s.schedule.sorted(by: { ($0.date, $0.id) < ($1.date, $1.id) }) {
            let date = String(row.date.prefix(10))
            if eventByDate[date] != nil { throw ImportError.duplicateEventDate(date) }
            let id = StableID.event(row.id)
            eventByPWA[row.id.lowercased()] = id
            eventByDate[date] = id
            var line = row.tipsLinje
            if let l = line, !(l >= -9.5 && l <= 18.5 && l - l.rounded(.down) == 0.5) {
                warn("Kveld \(date): tipslinja \(l) passer ikke appen (x,5 mellom −9,5 og 18,5) og er tatt bort.")
                line = nil
            }
            events.append(ImportPlan.Event(id: id, eventDate: date, startTime: firstClockTime(row.time),
                                           tipsLine: line, tipsStakePoints: stakePoints(row.tipsInnsats, date: date, warn: warn)))
            var seen = Set<UUID>()
            for social in [row.social1, row.social2] {
                guard let m = member(social), seen.insert(m).inserted else { continue }
                committee.append(ImportPlan.Committee(eventID: id, memberID: m))
            }
        }

        // --- Påmeldinger ----------------------------------------------------
        var signups: [ImportPlan.Signup] = []
        for row in s.signups {
            guard let event = eventByPWA[row.scheduleId.lowercased()], let m = member(row.playerId) else {
                warn("Påmelding uten kjent kveld eller spiller er hoppet over.")
                continue
            }
            let status: String = switch row.status {
            case "usikker": "maybe"
            case "kommer_ikke": "no"
            default: "yes"   // PWA: ukjent status leses som «kommer».
            }
            let comment = row.kommentar?.trimmingCharacters(in: .whitespacesAndNewlines)
            signups.append(ImportPlan.Signup(eventID: event, memberID: m, status: status,
                                             comment: (comment?.isEmpty ?? true) ? nil : clip(comment!, 80, "påmeldingskommentar", warn),
                                             createdAt: row.createdAt))
        }

        // --- Runder ---------------------------------------------------------
        let sortedRounds = s.rounds.sorted { ($0.createdAt ?? "", $0.id) < ($1.createdAt ?? "", $1.id) }
        let active = sortedRounds.filter { !$0.locked && !$0.kladd }
        if active.count > 1 { throw ImportError.severalActiveRounds(active.map(\.id)) }

        var rounds: [ImportPlan.Round] = []
        var roundByPWA: [String: ImportPlan.Round] = [:]
        var roundNoByEvent: [UUID: Int] = [:]
        for r in sortedRounds {
            let id = StableID.round(r.id)
            let date = r.date.map { String($0.prefix(10)) } ?? ""
            let eventID: UUID
            if let e = eventByDate[date] {
                eventID = e
            } else {
                let dateForEvent = date.isEmpty ? String((r.createdAt ?? "1970-01-01").prefix(10)) : date
                if let e = eventByDate[dateForEvent] {
                    eventID = e
                } else {
                    eventID = StableID.eventForDate(dateForEvent)
                    eventByDate[dateForEvent] = eventID
                    events.append(ImportPlan.Event(id: eventID, eventDate: dateForEvent, startTime: nil, tipsLine: nil, tipsStakePoints: nil))
                    warn("Runde \(r.id): datoen \(dateForEvent) står ikke i terminlista. Kvelden er laget.")
                }
            }
            let roundNo = (roundNoByEvent[eventID] ?? 0) + 1
            roundNoByEvent[eventID] = roundNo
            if roundNo > 9 { warn("Runde \(r.id): mer enn 9 runder samme kveld.") }

            let holeCount = r.holeCount == 9 ? 9 : 18
            var firstHole = 1
            if r.holeStart == 9 {
                if holeCount == 9 { firstHole = 10 } else { warn("Runde \(r.id): «siste ni» på en 18-hullsrunde er ignorert, som i PWA-en.") }
            }
            let status = r.locked ? "locked" : (r.kladd ? "draft" : "active")
            var format = (r.gameType ?? "stableford").trimmingCharacters(in: .whitespaces).lowercased()
            if format.range(of: "^[a-z0-9-]{1,40}$", options: .regularExpression) == nil {
                warn("Runde \(r.id): formen «\(format)» passer ikke appen og er satt til stableford.")
                format = "stableford"
            }
            var allowance = r.hcpAllowance ?? 1
            if !(0...1).contains(allowance) { warn("Runde \(r.id): handicapandel \(allowance) er klemt til 0…1."); allowance = min(1, max(0, allowance)) }
            var weight = r.multiplier ?? 1
            if !(0...5).contains(weight) { warn("Runde \(r.id): vekt \(weight) er klemt til 0…5."); weight = min(5, max(0, weight)) }
            func holeIndex(_ x: Int?, _ what: String) -> Int? {
                guard let x else { return nil }
                if x >= 0 && x < holeCount { return x }
                warn("Runde \(r.id): \(what)-hull \(x) finnes ikke i runden og er tatt bort.")
                return nil
            }
            let cutRule: String? = switch r.cutRule {
            case "felles": "common"
            case "nettopar": "net_par"
            case "null": "zero"
            default: nil
            }
            let cutAfter = cutRule == nil ? nil : min(holeCount, max(1, r.cutAfter ?? holeCount))
            let lockedAt = status == "locked" ? (lastScoreTime(s, r.id) ?? r.createdAt) : nil
            let round = ImportPlan.Round(
                id: id, pwaID: r.id, eventID: eventID, courseID: r.courseId.flatMap { courseByPWA[$0] },
                roundNo: min(roundNo, 9), name: r.name.map { clip($0, 60, "rundenavn \(r.id)", warn) },
                status: status, holeCount: holeCount, firstHole: firstHole,
                teeTime: firstClockTime(r.teeTime), format: format, handicapAllowance: allowance,
                externalHandicap: r.hcpExtern, weight: weight,
                ldEnabled: r.ldActive, ldHoleIndex: holeIndex(r.ldHoleIndex, "LD"),
                kpEnabled: r.kpActive, kpHoleIndex: holeIndex(r.kpHoleIndex, "KP"),
                cutRule: cutRule, cutAfter: cutAfter,
                cutBy: cutRule == nil ? nil : member(r.cutBy), cutAt: cutRule == nil ? nil : r.cutAt,
                parConfirmedBy: member(r.parConfirmedBy), parConfirmedAt: r.parConfirmedAt,
                startedAt: status == "draft" ? nil : r.createdAt, lockedAt: lockedAt, createdAt: r.createdAt)
            if r.courseId != nil && round.courseID == nil { warn("Runde \(r.id): banen \(r.courseId!) finnes ikke. Runden er uten bane.") }
            rounds.append(round)
            roundByPWA[r.id.lowercased()] = round
        }

        // --- Rundens hull ---------------------------------------------------
        var roundHoles: [ImportPlan.RoundHole] = []
        for h in s.roundHoles {
            guard let round = roundByPWA[h.roundId.lowercased()] else { continue }
            guard h.holeIndex >= 0 && h.holeIndex < round.holeCount else {
                warn("Runde \(h.roundId): rundehull \(h.holeIndex) er utenfor runden og er hoppet over.")
                continue
            }
            roundHoles.append(ImportPlan.RoundHole(
                roundID: round.id, holeIndex: h.holeIndex,
                par: h.par.flatMap { (3...6).contains($0) ? $0 : nil },
                strokeIndex: h.strokeIndex.flatMap { (1...18).contains($0) ? $0 : nil },
                lengthM: h.meters.flatMap(length)))
        }

        // --- Deltakere, båser, lag ------------------------------------------
        struct Slot { var bay: Int?; var marker = false; var team: Int? }
        var slots: [UUID: [UUID: Slot]] = [:]   // runde → spiller → plass
        var order: [UUID: [UUID]] = [:]
        func touch(_ round: UUID, _ m: UUID) {
            if slots[round]?[m] == nil {
                slots[round, default: [:]][m] = Slot()
                order[round, default: []].append(m)
            }
        }
        for b in s.roundBays.sorted(by: { ($0.roundId, $0.bayNo, $0.playerId) < ($1.roundId, $1.bayNo, $1.playerId) }) {
            guard let round = roundByPWA[b.roundId.lowercased()], let m = member(b.playerId) else { continue }
            touch(round.id, m)
            if (1...12).contains(b.bayNo) {
                slots[round.id]![m]!.bay = b.bayNo
                slots[round.id]![m]!.marker = b.isMarker
            } else {
                warn("Runde \(b.roundId): bås \(b.bayNo) er utenfor 1…12 og er tatt bort.")
            }
        }
        for t in s.roundTeams {
            guard let round = roundByPWA[t.roundId.lowercased()], let m = member(t.playerId) else { continue }
            touch(round.id, m)
            if (1...20).contains(t.teamNo) { slots[round.id]![m]!.team = t.teamNo }
            else { warn("Runde \(t.roundId): lag \(t.teamNo) er utenfor 1…20 og er tatt bort.") }
        }
        for sc in s.holeScores {
            guard let round = roundByPWA[sc.roundId.lowercased()], let m = member(sc.playerId) else { continue }
            touch(round.id, m)
        }
        for mt in s.roundMatches {
            guard let round = roundByPWA[mt.roundId.lowercased()] else { continue }
            for p in [mt.playerA, mt.playerB, mt.playerC] { if let m = member(p) { touch(round.id, m) } }
        }
        for c in s.sideClaims {
            guard let rid = c.roundId, let round = roundByPWA[rid.lowercased()], let m = member(c.playerId) else { continue }
            touch(round.id, m)
        }
        var roundPlayers: [ImportPlan.RoundPlayer] = []
        for round in rounds {
            var markerInBay = Set<Int>()
            for m in order[round.id] ?? [] {
                var slot = slots[round.id]![m]!
                if slot.marker, let bay = slot.bay {
                    if !markerInBay.insert(bay).inserted {
                        warn("Runde \(round.pwaID): to markører i bås \(bay). Bare den første beholdes.")
                        slot.marker = false
                    }
                } else {
                    slot.marker = false
                }
                // Frosset handicap (B16): PWA-en regnet alltid med dagens tall, så dagens tall fryses.
                let mem = memberRow[m]
                roundPlayers.append(ImportPlan.RoundPlayer(roundID: round.id, memberID: m,
                                                           handicapIndex: mem?.handicapIndex, seedGroup: mem?.seedGroup,
                                                           bayNo: slot.bay, isMarker: slot.marker, teamNo: slot.team))
            }
        }

        // --- Matcher ----------------------------------------------------------
        var matches: [ImportPlan.Match] = []
        for mt in s.roundMatches.sorted(by: { ($0.roundId, $0.matchNo) < ($1.roundId, $1.matchNo) }) {
            guard let round = roundByPWA[mt.roundId.lowercased()] else { continue }
            guard (1...40).contains(mt.matchNo) else { warn("Runde \(mt.roundId): match \(mt.matchNo) er utenfor 1…40."); continue }
            let a = member(mt.playerA), b = member(mt.playerB), c = member(mt.playerC)
            let isPlayers = a != nil && b != nil && a != b && mt.teamA == nil && mt.teamB == nil && (c == nil || (c != a && c != b))
            let isTeams = a == nil && b == nil && c == nil && mt.teamA != nil && mt.teamB != nil && mt.teamA != mt.teamB
                && (1...20).contains(mt.teamA!) && (1...20).contains(mt.teamB!)
            guard isPlayers || isTeams else {
                warn("Runde \(mt.roundId): match \(mt.matchNo) har ugyldige sider og er hoppet over.")
                continue
            }
            var result: String? = Match.Result(stored: mt.result).map { r in
                switch r { case .a: "a"; case .b: "b"; case .halved: "halved" }
            }
            if c != nil && result != nil {
                warn("Runde \(mt.roundId): trekant \(mt.matchNo) hadde manuelt resultat. Det er tatt bort (trekanten avgjøres på poeng).")
                result = nil
            }
            matches.append(ImportPlan.Match(roundID: round.id, matchNo: mt.matchNo, playerA: a, playerB: b, playerC: c,
                                            teamA: isTeams ? mt.teamA : nil, teamB: isTeams ? mt.teamB : nil, result: result))
        }

        // --- Scorer -----------------------------------------------------------
        var scores: [ImportPlan.Score] = []
        for sc in s.holeScores {
            guard let round = roundByPWA[sc.roundId.lowercased()], let m = member(sc.playerId) else {
                warn("Score uten kjent runde eller spiller er hoppet over.")
                continue
            }
            guard sc.holeIndex >= 0 && sc.holeIndex < round.holeCount else {
                warn("Runde \(sc.roundId): score på hull \(sc.holeIndex + 1) i en \(round.holeCount)-hullsrunde er hoppet over.")
                continue
            }
            guard (1...20).contains(sc.strokes) else {
                warn("Runde \(sc.roundId): \(sc.strokes) slag på hull \(sc.holeIndex + 1) er utenfor 1…20 og er hoppet over.")
                continue
            }
            scores.append(ImportPlan.Score(roundID: round.id, memberID: m, holeIndex: sc.holeIndex,
                                           strokes: sc.strokes, recordedAt: sc.updatedAt))
        }
        scores.sort { ($0.roundID.uuidString, $0.memberID.uuidString, $0.holeIndex) < ($1.roundID.uuidString, $1.memberID.uuidString, $1.holeIndex) }

        // --- Sidepremier ------------------------------------------------------
        var claimByKey: [String: ImportPlan.SideClaim] = [:]
        for c in s.sideClaims.sorted(by: { ($0.createdAt ?? "", $0.id) < ($1.createdAt ?? "", $1.id) }) {
            guard let rid = c.roundId, let round = roundByPWA[rid.lowercased()] else {
                warn("Sidepremie \(c.id) uten runde er hoppet over (appen knytter dem til en runde).")
                continue
            }
            guard let m = member(c.playerId), c.type == "drive" || c.type == "kp" else { continue }
            guard c.meters > 0 && c.meters <= 500 else { warn("Sidepremie \(c.id): \(c.meters) m er utenfor 0…500."); continue }
            let claim = ImportPlan.SideClaim(id: StableID.sideClaim(c.id), roundID: round.id, memberID: m, kind: c.type,
                                             meters: (c.meters * 10).rounded() / 10,
                                             holeIndex: c.holeIndex.flatMap { (0...17).contains($0) ? $0 : nil },
                                             createdAt: c.createdAt)
            // Én per spiller, runde og type: den siste vinner (PWA-en sletter før den setter inn).
            claimByKey["\(round.id)|\(m)|\(c.type)"] = claim
        }
        let sideClaims = claimByKey.values.sorted { $0.id.uuidString < $1.id.uuidString }

        // --- Tippekupong ------------------------------------------------------
        var tips: [ImportPlan.Tip] = []
        for t in s.tips {
            guard let event = eventByPWA[t.scheduleId.lowercased()], let m = member(t.playerId) else { continue }
            tips.append(ImportPlan.Tip(eventID: event, memberID: m, winner: member(t.vinner), frontNine: member(t.forsteNi),
                                       mostPars: member(t.flestPar), birdie: t.birdie, overLine: t.overLinja))
        }

        // --- Kveldens tråd ----------------------------------------------------
        var thread: [ImportPlan.ThreadMessage] = []
        for msg in s.meldinger.sorted(by: { ($0.createdAt ?? "", $0.id) < ($1.createdAt ?? "", $1.id) }) {
            guard let event = eventByPWA[msg.scheduleId.lowercased()], let m = member(msg.playerId) else { continue }
            var body = msg.tekst
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard msg.hasImage else { continue }
                body = "(Bilde fra PWA-en, ikke flyttet)"
            }
            if msg.hasImage { warn("Melding \(msg.id): bildet er ikke flyttet, bare teksten.") }
            var seen = Set<UUID>()
            let mentions = msg.nevnt.compactMap(member).filter { seen.insert($0).inserted }
            thread.append(ImportPlan.ThreadMessage(id: StableID.threadMessage(msg.id), eventID: event, memberID: m,
                                                   body: clip(body, 500, "melding \(msg.id)", warn),
                                                   mentions: Array(mentions.prefix(50)), createdAt: msg.createdAt))
        }

        // --- Lagrede poeng (bare paritet) -------------------------------------
        let stored = s.roundPoints.compactMap { p -> ImportPlan.StoredPoints? in
            guard let round = roundByPWA[p.roundId.lowercased()], let m = member(p.playerId), let pts = p.points else { return nil }
            return ImportPlan.StoredPoints(roundID: round.id, memberID: m, points: pts)
        }

        // Fast rekkefølge uansett rekkefølgen i fila: samme data gir samme SQL.
        events.sort { ($0.eventDate, $0.id.uuidString) < ($1.eventDate, $1.id.uuidString) }
        signups.sort { ($0.eventID.uuidString, $0.memberID.uuidString) < ($1.eventID.uuidString, $1.memberID.uuidString) }
        committee.sort { ($0.eventID.uuidString, $0.memberID.uuidString) < ($1.eventID.uuidString, $1.memberID.uuidString) }
        roundHoles.sort { ($0.roundID.uuidString, $0.holeIndex) < ($1.roundID.uuidString, $1.holeIndex) }
        roundPlayers.sort { ($0.roundID.uuidString, $0.memberID.uuidString) < ($1.roundID.uuidString, $1.memberID.uuidString) }
        matches.sort { ($0.roundID.uuidString, $0.matchNo) < ($1.roundID.uuidString, $1.matchNo) }
        tips.sort { ($0.eventID.uuidString, $0.memberID.uuidString) < ($1.eventID.uuidString, $1.memberID.uuidString) }
        let storedSorted = stored.sorted { ($0.roundID.uuidString, $0.memberID.uuidString) < ($1.roundID.uuidString, $1.memberID.uuidString) }
        return ImportPlan(club: club, clubExists: options.clubID != nil, members: members, season: season,
                          courses: courses, courseHoles: courseHoles, events: events, committee: committee,
                          signups: signups, rounds: rounds, roundHoles: roundHoles, roundPlayers: roundPlayers,
                          matches: matches, scores: scores, sideClaims: sideClaims, tips: tips,
                          threadMessages: thread, storedPoints: storedSorted, warnings: warnings)
    }

    // MARK: Hjelpere

    /// Regelsettet som sortert JSON, så samme regelsett alltid gir samme tekst.
    static func rulesJSON(_ rules: Ruleset) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(rules)) ?? Data("{\"version\":2}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// Tippeinnsatsen: kroner i PWA-en blir poeng 1:1 (beslutning 07.10.2026, B10). Som `tipsInnsats`:
    /// tom eller negativ verdi gir regelsettets standard (null), ellers `Math.round`. 0 = for æra.
    /// Over databasens tak (`Tips.stakeLimits`) blir den også null, med merknad.
    static func stakePoints(_ kroner: Double?, date: String, warn: (String) -> Void) -> Int? {
        guard let k = kroner, k.isFinite, k >= 0 else { return nil }
        let points = (k + 0.5).rounded(.down)
        guard points <= Double(Tips.stakeLimits.upperBound) else {
            warn("Kveld \(date): tippeinnsatsen \(Int(min(points, 1e9))) er over \(Tips.stakeLimits.upperBound) poeng. Kvelden bruker regelsettets standard.")
            return nil
        }
        return Int(points)
    }

    /// Første klokkeslett i teksten («18:00–22:00» → «18:00»). `nil` når det ikke finnes.
    static func firstClockTime(_ text: String?) -> String? {
        guard let text, let r = text.range(of: #"\b([01]?\d|2[0-3])[:.]([0-5]\d)\b"#, options: .regularExpression) else { return nil }
        let parts = text[r].split(whereSeparator: { $0 == ":" || $0 == "." })
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    static func length(_ meters: Double) -> Int? {
        let m = Int(meters.rounded())
        return (50...700).contains(m) ? m : nil
    }

    static func clip(_ text: String, _ max: Int, _ what: String, _ warn: (String) -> Void) -> String {
        guard text.count > max else { return text }
        warn("\(what.prefix(1).uppercased() + what.dropFirst()) er kortet ned til \(max) tegn.")
        return String(text.prefix(max))
    }

    static func lastScoreTime(_ s: PWASnapshot, _ roundID: String) -> String? {
        s.holeScores.filter { $0.roundId.lowercased() == roundID.lowercased() }.compactMap(\.updatedAt).max()
    }

    /// Banens hull, som PWA-en leser dem: `course_holes` når de er 9 eller 18 sammenhengende fra 1
    /// (`banehullFraRader`), ellers `courses.holes`.
    static func holes(for c: PWASnapshot.Course, rows: [PWASnapshot.CourseHole], courseID: UUID,
                      warn: (String) -> Void) -> [ImportPlan.CourseHole] {
        let sorted = rows.sorted { $0.holeNumber < $1.holeNumber }
        let complete = (sorted.count == 9 || sorted.count == 18)
            && sorted.enumerated().allSatisfy { $0.element.holeNumber == $0.offset + 1 }
        var source: [(number: Int, par: Int?, si: Int?, meters: Double?)]
        if complete || (c.holes == nil && !sorted.isEmpty) {
            if !complete { warn("Bane \(c.id): hullene i course_holes er ikke 9 eller 18 sammenhengende. De tas med som de er.") }
            source = sorted.map { ($0.holeNumber, $0.par, $0.hcpIndex, $0.distanceMeters) }
        } else if let json = c.holes, json.count == 9 || json.count == 18 {
            source = json.enumerated().map { ($0.offset + 1, $0.element.par, $0.element.si, $0.element.meters) }
        } else {
            if !(c.holes ?? []).isEmpty { warn("Bane \(c.id): courses.holes har \(c.holes!.count) hull og er ikke tatt med.") }
            source = []
        }
        var usedIndex = Set<Int>()
        var out: [ImportPlan.CourseHole] = []
        for h in source {
            guard (1...18).contains(h.number), let par = h.par, (3...6).contains(par) else {
                warn("Bane \(c.id): hull \(h.number) har par \(h.par.map(String.init) ?? "tomt") og er hoppet over.")
                continue
            }
            var si = h.si.flatMap { (1...18).contains($0) ? $0 : nil }
            if let x = si, !usedIndex.insert(x).inserted {
                warn("Bane \(c.id): indeks \(x) står to ganger. Den andre er tatt bort.")
                si = nil
            }
            out.append(ImportPlan.CourseHole(courseID: courseID, holeNumber: h.number, par: par, strokeIndex: si,
                                             lengthM: h.meters.flatMap(length)))
        }
        return out
    }
}
