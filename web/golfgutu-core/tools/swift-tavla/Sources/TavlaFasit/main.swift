import Foundation
import GolfgutuCore

// Leser test/fixtures/tavla.json, regner Tavla og liga/morro med appens kode, og skriver fasiten som JSON
// (UUID-er med små bokstaver, som i databasen).

struct Fixture: Decodable {
    let me: UUID
    let tavlaData: TavlaData
    let sesonger: [SeasonRow]
}

func u(_ id: UUID) -> String { id.uuidString.lowercased() }
func u(_ id: String) -> String { id.lowercased() }
func n<T>(_ x: T?) -> Any { x.map { $0 as Any } ?? NSNull() }

func grid(_ g: RoundsGrid) -> [String: Any] {
    [
        "columns": g.columns.map { c -> [String: Any] in
            ["roundID": u(c.roundID), "label": c.label, "date": n(c.date), "title": c.title, "isOngoing": c.isOngoing]
        },
        "rows": g.rows.map { r -> [String: Any] in
            ["playerID": u(r.playerID), "name": r.name, "place": r.place, "isMe": r.isMe,
             "points": r.points.map { n($0) }, "strokes": r.strokes.map { n($0) }, "toPar": r.toPar.map { n($0) },
             "counted": n(r.counted), "pointsTotal": r.pointsTotal, "strokesTotal": r.strokesTotal,
             "toParTotal": r.toParTotal]
        },
        "bestPoints": g.bestPoints.map { n($0) },
        "bestStrokes": g.bestStrokes.map { n($0) },
    ]
}

func tavla(_ t: TavlaStandings) -> [String: Any] {
    [
        "seasonName": t.seasonName,
        "status": t.status.rawValue,
        "countsStableford": t.countsStableford,
        "hasResults": t.hasResults,
        "eveningsPlayed": t.eveningsPlayed,
        "eveningsTotal": t.eveningsTotal,
        "roundColumns": t.roundColumns,
        "rows": t.rows.map { r -> [String: Any] in
            ["memberID": u(r.memberID), "name": r.name, "place": r.place, "total": r.total, "duel": r.duel,
             "side": r.side, "matches": r.matches, "holes": r.holes, "stableford": r.stableford,
             "evenings": r.evenings, "isMe": r.isMe, "roundPoints": r.roundPoints, "played": r.played,
             "placeText": t.placeText(r), "totalText": t.points(r.total), "duelText": t.points(r.duel),
             "sideText": t.points(r.side), "detail": t.detail(r), "basis": n(t.basis(r))]
        },
        "rounds": grid(t.roundGrid),
        "roundTitles": t.snapshots.indices.map(t.roundTitle),
        "birdies": Dictionary(uniqueKeysWithValues: t.rows.map { (u($0.memberID), t.birdies($0.memberID)) }),
        "longestDrive": Dictionary(uniqueKeysWithValues: t.rows.map { (u($0.memberID), n(t.longestDrive($0.memberID))) }),
    ]
}

func league(_ l: LeagueStandings) -> [String: Any] {
    [
        "rulesSummary": l.rulesSummary,
        "hasResults": l.hasResults,
        "roundCount": l.roundCount,
        "roundTitles": Dictionary(uniqueKeysWithValues: l.roundTitles.map { (u($0.key), $0.value) }),
        "rows": l.rows.map { r -> [String: Any] in
            ["entrant": u(r.entrant.id), "name": r.name, "place": r.place, "total": r.total, "played": r.played,
             "wins": r.wins, "bestRound": n(r.bestRound), "stableford": r.stableford, "isMe": r.isMe,
             "placeText": l.placeText(r), "totalText": LeagueStandings.points(r.total), "detail": l.detail(r),
             "results": r.results.map { x -> [String: Any] in
                 ["roundID": u(x.roundID), "place": x.place, "stableford": x.stableford, "points": x.points,
                  "counted": x.counted]
             }]
        },
        "rounds": grid(l.roundGrid),
    ]
}

let path = CommandLine.arguments[1]
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let fixture = try decoder.decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
let data = fixture.tavlaData

var seasons: [[String: Any]] = []
for season in fixture.sesonger {
    let input = data.input(season: season)
    seasons.append(tavla(TavlaStandings(input, me: fixture.me)))
}

// Liga (klubbens tropp, beste 3 runder) og morro (privat, alle som spilte) over de samme rundene.
let candidates = data.input(season: fixture.sesonger[0]).rounds
let directory = PersonDirectory(members: data.members)
let leagueRules = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 2, "competition": {"league": {"bestRounds": 3}}}"#.utf8))
let club = data.members[0].clubID
func competition(_ kind: CompetitionKind, club: UUID?, entry: CompetitionEntry, rules: Ruleset) -> CompetitionRow {
    CompetitionRow(id: UUID(uuidString: "00000000-0000-0000-0000-000000009100")!, kind: kind, name: "Konkurranse",
                   clubID: club, ownerID: nil, seasonID: nil, status: .active, entry: entry, rules: rules,
                   startsOn: nil, endsOn: nil, isMain: false, requiresPurchase: false, entitlementID: nil)
}
var competitions: [[String: Any]] = []
for c in [competition(.league, club: club, entry: .club, rules: leagueRules),
          competition(.fun, club: nil, entry: .open, rules: RulesetTemplate.fun.rules)] {
    let links = data.rounds.map { CompetitionRoundRow(competitionID: c.id, roundID: $0.id, source: .manual) }
    let scope = CompetitionScope(competition: c, links: links)
    let input = scope.input(candidates: candidates, directory: directory)
    let me = Set(input.entrants.filter { $0.id == fixture.me })
    competitions.append(["kind": c.kind.rawValue, "entry": c.entry.rawValue, "standings": league(LeagueStandings(input, me: me))])
}

// Cup: seks påmeldte seedet på handicap, første runde fra trekningen, to resultater og en walkover.
func pid(_ i: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 500 + i))! }
let cupID = UUID(uuidString: "00000000-0000-0000-0000-000000009200")!
let entrants = (0..<6).map { CompetitionParticipantRow(id: pid($0), competitionID: cupID, memberID: data.members[$0].id, profileID: nil, status: .active) }
let cupNames = Dictionary(uniqueKeysWithValues: (0..<6).map { (pid($0), data.members[$0].displayName) })
let cupHandicaps = Dictionary(uniqueKeysWithValues: (0..<6).compactMap { i in data.members[i].handicapIndex.map { (pid(i), $0) } })
let pairings = CupStandings.pairings(participants: entrants, names: cupNames, handicaps: cupHandicaps, ranks: [:],
                                     rules: CupRules(seeding: .handicap, tie: .countback), seed: 0)
var cupRows = pairings.map { p in
    CompetitionMatchRow(id: UUID(), competitionID: cupID, roundNo: 1, slot: p.slot, playerA: p.a, playerB: p.b,
                        winner: p.b == nil ? p.a : nil, walkover: false, result: nil, roundID: nil)
}
let firstReal = cupRows.firstIndex { $0.playerB != nil }!
cupRows[firstReal].winner = cupRows[firstReal].playerB
cupRows[firstReal].result = "3&2"
let secondReal = cupRows.lastIndex { $0.playerB != nil }!
cupRows[secondReal].winner = cupRows[secondReal].playerA
cupRows[secondReal].walkover = true
let cup = CupStandings(participants: entrants, matches: cupRows, names: cupNames, me: [pid(5)])
func side(_ s: CupStandings.Side?) -> Any {
    guard let s else { return NSNull() }
    return ["participantID": u(s.participantID), "name": s.name, "seed": n(s.seed), "isMe": s.isMe]
}
func game(_ g: CupStandings.Game) -> [String: Any] {
    ["round": g.round, "slot": g.slot, "a": side(g.a), "b": side(g.b), "winner": n(g.winner.map(u)), "isBye": g.isBye,
     "walkover": g.walkover, "result": n(g.result), "state": g.state.rawValue]
}
let cupOut: [String: Any] = [
    "pairings": pairings.map { ["slot": $0.slot, "a": u($0.a), "b": n($0.b.map(u))] as [String: Any] },
    "rounds": cup.rounds.map { $0.map(game) },
    "roundTitles": cup.roundTitles,
    "champion": side(cup.champion),
    "myNext": cup.myNext.map(game) ?? NSNull(),
]

let out: [String: Any] = ["tavla": seasons, "konkurranser": competitions, "cup": cupOut]
let json = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data("\n".utf8))
