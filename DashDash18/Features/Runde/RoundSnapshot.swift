import Foundation
import GolfgutuCore

/// Alt som er hentet for runden som går, slik databasen leverer det. Rene rader, ingen poeng:
/// `RoundGame` bygger regelmotorens domene av dette.
nonisolated struct RoundSnapshot: Equatable, Sendable {
    var round: RoundRow
    var roundHoles: [RoundHoleRow] = []
    var players: [RoundPlayerRow] = []
    var matches: [RoundMatchRow] = []
    var scores: [HoleScoreRow] = []
    var sideClaims: [SideClaimRow] = []
    var course: CourseRow?
    var courseHoles: [CourseHoleRecord] = []
    /// Kveldens dato (`YYYY-MM-DD`), fra `events`.
    var eventDate: String?
    /// Regelsettet til sesongen kvelden hører til. Mangler det, gjelder Golfgutu-oppsettet.
    var rules: Ruleset = .golfgutu
    /// Navn fra troppen (klubbrunde) eller deltakerne (løs runde).
    var names: [UUID: String] = [:]
    /// Eieren og deltakerne i en løs runde (sql/017). Tom for klubbrunder.
    var loose: LooseRoundInfo?

    /// En runde uten klubb og kveld.
    var isLoose: Bool { round.clubID == nil }
}

/// Bås-oppsettet for runden (`baaserForRunde`).
nonisolated struct Bay: Equatable, Sendable {
    let number: Int
    /// Spillerne i båsen, sortert på navn (norsk).
    let players: [UUID]
    /// Markøren, eller nil når båsen ikke har en.
    let marker: UUID?
}

/// Regelmotorens syn på runden, bygd av radene. Ren, uten nettverk og SwiftUI.
nonisolated struct RoundGame: Sendable {
    let snapshot: RoundSnapshot
    /// GolfgutuCore-runden (bane, hull, lag, scorer, matcher, avkorting).
    let round: Round
    /// Spillerne i runden med frosset indeks og seedet gruppe.
    let roster: [Player]
    /// `courseForRound`.
    let holes: [PlayedHole]
    let rules: Ruleset

    init(_ snapshot: RoundSnapshot) {
        self.snapshot = snapshot
        rules = snapshot.rules
        roster = snapshot.players.map { row in
            Player(id: row.memberID.uuidString, name: snapshot.names[row.memberID] ?? "",
                   handicap: row.handicapIndex, seedGroup: row.seedGroup)
        }
        round = RoundGame.makeRound(snapshot)
        holes = round.courseHoles()
    }

    // MARK: Mapping rader → GolfgutuCore

    static func makeRound(_ s: RoundSnapshot) -> Round {
        let r = s.round
        var holeScores: [String: HoleScores] = [:]
        for row in s.scores {
            holeScores[row.memberID.uuidString, default: [:]][row.holeIndex] = row.strokes
        }
        var teams: [String: Int] = [:]
        for p in s.players {
            if let team = p.teamNo { teams[p.memberID.uuidString] = team }
        }
        let overrides = Dictionary(s.roundHoles.map { h in
            (h.holeIndex, RoundHole(par: h.par, strokeIndex: h.strokeIndex, meters: h.lengthM.map(Double.init)))
        }, uniquingKeysWith: { first, _ in first })

        return Round(
            id: r.id.uuidString,
            gameType: r.format,
            holeCount: r.holeCount,
            // Skjemaet lagrer banens første hull (1 eller 10), regelmotoren PWA-ens 0/9.
            holeStart: r.firstHole == 10 ? 9 : 0,
            course: makeCourse(s.course, holes: s.courseHoles, round: r),
            holes: overrides.isEmpty ? nil : overrides,
            hcpAllowance: r.handicapAllowance,
            hcpExtern: r.externalHandicap,
            teams: teams,
            holeScores: holeScores,
            avkortRegel: cutRule(r.cutRule)?.rawValue,
            avkortetEtter: r.cutAfter.map(Double.init),
            matches: s.matches.sorted { $0.matchNo < $1.matchNo }.map { m in
                Match(matchNo: m.matchNo, playerA: m.playerA?.uuidString, playerB: m.playerB?.uuidString,
                      playerC: m.playerC?.uuidString, teamA: m.teamA, teamB: m.teamB,
                      result: Match.Result(stored: m.result))
            },
            ldEnabled: r.ldEnabled,
            kpEnabled: r.kpEnabled,
            ldHoleIndex: r.ldHoleIndex,
            kpHoleIndex: r.kpHoleIndex,
            weight: r.weight,
            date: s.eventDate,
            locked: r.status == .locked,
            playingHandicaps: frozenHandicaps(s)
        )
    }

    /// Spillehandicapet som ble frosset ved start (`round_players.playing_handicap`), per spiller.
    /// Samme regel som `handicap(_:)`: lagret verdi er fasiten, og spillere uten får
    /// `effectiveHandicap`. Da bruker match, trekant, avkorting og føringen samme tall.
    static func frozenHandicaps(_ s: RoundSnapshot) -> [String: Double] {
        Dictionary(s.players.compactMap { p in p.playingHandicap.map { (p.memberID.uuidString, Double($0)) } },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Banen med hull fra `course_holes`. Hullene tas bare med når de er 9 eller 18
    /// sammenhengende fra 1 (`banehullFraRader`). Par er summen av hullene.
    /// Er runden spilt fra en tee (sql/029), gjelder CR og slope slik de var da runden startet. Har teen
    /// egne hull (sql/030), gjelder også teens par fra start (`tee_par`); hullene selv er frosset i
    /// `round_holes` og kommer inn som rundens overstyringer.
    static func makeCourse(_ row: CourseRow?, holes: [CourseHoleRecord], round: RoundRow? = nil) -> Course? {
        guard let row else { return nil }
        let mine = holes.filter { $0.courseID == row.id }.map { h in
            CourseHoleRow(courseId: row.id.uuidString, holeNumber: h.holeNumber, par: h.par,
                          hcpIndex: h.strokeIndex, distanceMeters: h.lengthM.map(Double.init))
        }
        let played = Course.holesFromRows(mine)[row.id.uuidString] ?? nil
        let par = played.map { $0.reduce(0) { $0 + ($1.par ?? 0) } }
        return Course(id: row.id.uuidString, name: row.name, par: TeeHoles.coursePar(holesPar: par, teePar: round?.teePar),
                      courseRating: round?.courseRating ?? row.courseRating,
                      slopeRating: (round?.slopeRating ?? row.slopeRating).map(Double.init),
                      holes: played)
    }

    /// `rounds.cut_rule` (skjemaets navn) → regelmotorens avkortingsregel.
    static func cutRule(_ raw: String?) -> Truncation.Rule? {
        switch raw {
        case "common": .common
        case "net_par": .netPar
        case "zero": .zero
        default: nil
        }
    }

    // MARK: Spillere og båser

    /// «bås» i simulatoren, «flight» på ekte bane (`rounds.venue`).
    var groupTerm: GroupTerm { .for(stored: snapshot.round.venue) }

    var roundID: UUID { snapshot.round.id }
    var holeCount: Int { round.numberOfHoles }
    var status: RoundStatus { snapshot.round.status }

    func name(_ member: UUID) -> String {
        snapshot.names[member] ?? "Ukjent"
    }

    func isPlaying(_ member: UUID) -> Bool {
        snapshot.players.contains { $0.memberID == member }
    }

    func player(_ member: UUID) -> Player? {
        roster.first { $0.id == member.uuidString }
    }

    /// Spillerens handicap i runden, i hele slag. Simulatoren deler ut slagene → 0.
    /// `playing_handicap` er fasiten når den er lagret; ellers `effectiveHandicap` med regelsettet.
    func handicap(_ member: UUID) -> Double {
        if round.hcpExtern { return 0 }
        if let stored = snapshot.players.first(where: { $0.memberID == member })?.playingHandicap {
            return Double(stored)
        }
        return Handicap.effective(for: player(member), in: round, roster: roster, rules: rules)
    }

    /// Spillerens førte hull: rundens 0-baserte hull → brutto.
    func scores(_ member: UUID) -> HoleScores {
        round.holeScores[member.uuidString] ?? [:]
    }

    /// Båsene, nummer → bås. Spillere uten bås er ikke med.
    var bays: [Int: Bay] {
        var grouped: [Int: [RoundPlayerRow]] = [:]
        for p in snapshot.players {
            guard let bay = p.bayNo, bay >= 1 else { continue }
            grouped[bay, default: []].append(p)
        }
        return grouped.reduce(into: [:]) { out, entry in
            let sorted = entry.value
                .map(\.memberID)
                .sorted { NorwegianSort.areInIncreasingOrder(name($0), name($1)) }
            out[entry.key] = Bay(number: entry.key, players: sorted,
                                 marker: entry.value.last(where: \.isMarker)?.memberID)
        }
    }

    /// `harBaaser`.
    var hasBays: Bool { !bays.isEmpty }

    /// `baasFor`: båsen spilleren står i.
    func bay(of member: UUID) -> Bay? {
        guard let number = snapshot.players.first(where: { $0.memberID == member })?.bayNo else { return nil }
        return bays[number]
    }

    /// `hullNr`: banens hullnummer. Siste ni heter 10–18, slik simulatoren sier det.
    func holeNumber(_ index: Int) -> Int {
        index + 1 + (round.holeStart == 9 ? 9 : 0)
    }

    var longestDriveHole: Int? { SidePrizes.longestDriveHole(round) }
    var closestToPinHole: Int? { SidePrizes.closestToPinHole(round) }
}
