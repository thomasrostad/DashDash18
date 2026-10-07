import Foundation
import GolfgutuCore

/// Paritetssjekken: regner sesongen med GolfgutuCore fra de importerte radene (slik appen ser dem)
/// og sammenligner rundepoengene med PWA-ens lagrede `round_points`.
public struct ParityReport: Sendable {
    public struct PointsMismatch: Sendable, Equatable {
        public var roundID: UUID
        public var memberID: UUID
        public var name: String
        public var pwa: Int
        public var app: Int?
    }

    public var jacket: [Season.JacketRow]
    public var stableford: [Season.StablefordRow]
    /// Runder som teller (ikke kladd), i rekkefølge.
    public var roundCount: Int
    public var eveningCount: Int
    /// Antall lagrede rundepoeng i PWA-en som er sammenlignet.
    public var comparedPoints: Int
    public var mismatches: [PointsMismatch]
    /// Spillere med regnede poeng i en runde der PWA-en ikke har lagret noe.
    public var missingInPWA: Int

    public var isOK: Bool { mismatches.isEmpty }
}

public enum Parity {
    /// Bygger regelmotorens sesong av planen. Kladder tas ikke med (spillerne ser dem ikke i appen).
    public static func season(_ plan: ImportPlan, ruleset: Ruleset = .golfgutu) -> Season {
        let players = plan.members.map { m in
            Player(id: m.id.uuidString, name: m.displayName, handicap: m.handicapIndex, seedGroup: m.seedGroup)
        }
        let eventDate = Dictionary(uniqueKeysWithValues: plan.events.map { ($0.id, $0.eventDate) })
        let holesByCourse = Dictionary(grouping: plan.courseHoles, by: \.courseID)
        let coursesByID = Dictionary(uniqueKeysWithValues: plan.courses.map { ($0.id, $0) })
        let playersByRound = Dictionary(grouping: plan.roundPlayers, by: \.roundID)
        let scoresByRound = Dictionary(grouping: plan.scores, by: \.roundID)
        let matchesByRound = Dictionary(grouping: plan.matches, by: \.roundID)
        let holesByRound = Dictionary(grouping: plan.roundHoles, by: \.roundID)

        let rounds = plan.rounds.filter { $0.status != "draft" }.map { r -> Round in
            var course: Course?
            if let cid = r.courseID, let c = coursesByID[cid] {
                let rows = (holesByCourse[cid] ?? []).map {
                    CourseHoleRow(courseId: cid.uuidString, holeNumber: $0.holeNumber, par: $0.par,
                                  hcpIndex: $0.strokeIndex, distanceMeters: $0.lengthM.map(Double.init))
                }
                let holes = Course.holesFromRows(rows)[cid.uuidString] ?? nil
                course = Course(id: cid.uuidString, name: c.name, par: holes.map { $0.reduce(0) { $0 + ($1.par ?? 0) } },
                                courseRating: c.courseRating, slopeRating: c.slopeRating.map(Double.init), holes: holes)
            }
            var scores: [String: HoleScores] = [:]
            for s in scoresByRound[r.id] ?? [] { scores[s.memberID.uuidString, default: [:]][s.holeIndex] = s.strokes }
            var teams: [String: Int] = [:]
            for p in playersByRound[r.id] ?? [] { if let t = p.teamNo { teams[p.memberID.uuidString] = t } }
            let overrides = Dictionary((holesByRound[r.id] ?? []).map {
                ($0.holeIndex, RoundHole(par: $0.par, strokeIndex: $0.strokeIndex, meters: $0.lengthM.map(Double.init)))
            }, uniquingKeysWith: { a, _ in a })
            let rule: String? = switch r.cutRule {
            case "common": "felles"
            case "net_par": "nettopar"
            case "zero": "null"
            default: nil
            }
            return Round(
                id: r.id.uuidString, gameType: r.format, holeCount: r.holeCount, holeStart: r.firstHole == 10 ? 9 : 0,
                course: course, holes: overrides.isEmpty ? nil : overrides, hcpAllowance: r.handicapAllowance,
                hcpExtern: r.externalHandicap, teams: teams, holeScores: scores,
                avkortRegel: rule, avkortetEtter: r.cutAfter.map(Double.init),
                matches: (matchesByRound[r.id] ?? []).sorted { $0.matchNo < $1.matchNo }.map { m in
                    Match(matchNo: m.matchNo, playerA: m.playerA?.uuidString, playerB: m.playerB?.uuidString,
                          playerC: m.playerC?.uuidString, teamA: m.teamA, teamB: m.teamB, result: Match.Result(stored: m.result))
                },
                ldEnabled: r.ldEnabled, kpEnabled: r.kpEnabled, ldHoleIndex: r.ldHoleIndex, kpHoleIndex: r.kpHoleIndex,
                weight: r.weight, date: eventDate[r.eventID], locked: r.status == "locked")
        }
        let claims = plan.sideClaims.map { c in
            SideClaim(id: c.id.uuidString, kind: c.kind == "kp" ? .kp : .drive, playerId: c.memberID.uuidString,
                      roundId: c.roundID.uuidString, meters: c.meters, holeIndex: c.holeIndex, ts: c.createdAt)
        }
        return Season(players: players, rounds: rounds, claims: claims, ruleset: ruleset)
    }

    public static func check(_ plan: ImportPlan, ruleset: Ruleset = .golfgutu) -> ParityReport {
        let season = season(plan, ruleset: ruleset)
        let names = Dictionary(uniqueKeysWithValues: plan.members.map { ($0.id, $0.displayName) })
        let indexByRound = Dictionary(uniqueKeysWithValues: season.rounds.enumerated().compactMap { i, r in
            r.id.flatMap(UUID.init(uuidString:)).map { ($0, i) }
        })
        var mismatches: [ParityReport.PointsMismatch] = []
        var compared = 0
        var storedKeys = Set<String>()
        for p in plan.storedPoints {
            guard let i = indexByRound[p.roundID] else { continue }
            compared += 1
            storedKeys.insert("\(p.roundID)|\(p.memberID)")
            let app = season.roundPoints(i)[p.memberID.uuidString]
            if app != p.points {
                mismatches.append(.init(roundID: p.roundID, memberID: p.memberID, name: names[p.memberID] ?? "?", pwa: p.points, app: app))
            }
        }
        var missing = 0
        for (i, r) in season.rounds.enumerated() {
            for pid in season.roundPoints(i).keys where !storedKeys.contains("\(r.id ?? "")|\(pid)") { missing += 1 }
        }
        return ParityReport(jacket: season.jacketBoard(), stableford: season.stablefordBoard(),
                            roundCount: season.rounds.count, eveningCount: Season.eveningCount(season.rounds),
                            comparedPoints: compared, mismatches: mismatches, missingInPWA: missing)
    }

    /// Tabellene som tekst, i Tavlas rekkefølge.
    public static func render(_ report: ParityReport) -> String {
        var lines: [String] = []
        lines.append("Jakkeracet (Golfgutu-oppsettet): \(report.roundCount) runder, \(report.eveningCount) kvelder")
        lines.append(row(["#", "Spiller", "Poeng", "Duell", "Side", "Matcher", "Hull", "Stbf"]))
        for (i, r) in report.jacket.enumerated() {
            lines.append(row([String(i + 1), r.player.name, Season.formatPoints(r.total), Season.formatPoints(r.duel),
                              Season.formatPoints(r.side), "\(r.matches)", signed(r.holes), "\(r.stableford)"]))
        }
        lines.append("")
        lines.append("Stablefordsummen")
        lines.append(row(["#", "Spiller", "Sum", "Spilt", "Teller", "Strøket"]))
        for (i, r) in report.stableford.enumerated() {
            lines.append(row([String(i + 1), r.player.name, "\(r.total)", "\(r.played)", "\(r.counting)", "\(r.dropped)"]))
        }
        lines.append("")
        lines.append("Rundepoeng mot PWA-ens round_points: \(report.comparedPoints) sammenlignet, \(report.mismatches.count) avvik"
                     + (report.missingInPWA > 0 ? ", \(report.missingInPWA) uten lagret tall i PWA-en" : ""))
        for m in report.mismatches {
            lines.append("  AVVIK runde \(m.roundID.uuidString.lowercased().prefix(8)) \(m.name): PWA \(m.pwa), app \(m.app.map(String.init) ?? "–")")
        }
        lines.append(report.isOK ? "OK: rundepoengene stemmer." : "IKKE OK: se avvikene over.")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func signed(_ x: Int) -> String { x > 0 ? "+\(x)" : "\(x)" }

    private static func row(_ cells: [String]) -> String {
        let widths = [3, 26, 6, 6, 5, 8, 5, 5]
        return cells.enumerated().map { i, c in
            let w = i < widths.count ? widths[i] : 6
            let pad = max(0, w - c.count)
            return i == 1 ? c + String(repeating: " ", count: pad) : String(repeating: " ", count: pad) + c
        }.joined(separator: " ")
    }
}
