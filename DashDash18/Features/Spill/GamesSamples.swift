#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// Oppdiktede spill for skjermprøvene `spill`, `spillnytt` og `spillresultat` (DesignScreenSamples).
enum GamesSamples {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0014-%012d", n))! }

    static let roundID = id(900)
    static let club = id(901)
    static let course = id(902)
    static let thomas = id(1), kare = id(2), ola = id(3), per = id(4)
    static let names = [thomas: "Thomas", kare: "Kåre", ola: "Ola", per: "Per"]
    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    static let viewer = Viewer(memberID: thomas, isOrganizer: true)
    /// Brutto skins, så prøven viser vinnere uten å regne slag.
    static let grossSkins: GameSettings = .skins({ var r = SkinsRules.standard; r.handicap = .gross; return r }())

    /// Brutto per spiller, hull 1–18.
    static let gross: [UUID: [Int]] = [
        thomas: [5, 5, 3, 4, 5, 3, 6, 4, 5, 4, 3, 6, 4, 5, 3, 4, 5, 5],
        kare: [4, 6, 4, 4, 4, 3, 5, 5, 4, 5, 4, 5, 4, 4, 4, 5, 5, 4],
        ola: [4, 5, 3, 5, 4, 4, 5, 4, 4, 4, 3, 5, 5, 4, 3, 4, 6, 4],
        per: [6, 5, 4, 4, 5, 3, 5, 4, 5, 5, 3, 5, 4, 4, 3, 5, 5, 4],
    ]

    static func game(holesPlayed: Int, locked: Bool) -> RoundGame {
        let round = RoundRow(id: roundID, clubID: club, eventID: id(903), courseID: course, roundNo: 1, name: nil,
                             status: locked ? .locked : .active, holeCount: 18, firstHole: 1, teeTime: nil,
                             format: "stableford", handicapAllowance: 1, externalHandicap: false, weight: 1,
                             ldEnabled: false, ldHoleIndex: nil, kpEnabled: false, kpHoleIndex: nil,
                             cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: .now,
                             startedAt: nil, lockedAt: nil)
        var s = RoundSnapshot(round: round)
        let playing = [thomas: 12, kare: 6, ola: 3, per: 9]
        s.players = [thomas, kare, ola, per].map { m in
            RoundPlayerRow(roundID: roundID, memberID: m, clubID: club, handicapIndex: Double(playing[m]!),
                           seedGroup: nil, playingHandicap: playing[m], bayNo: 1, isMarker: m == thomas, teamNo: nil)
        }
        s.names = names
        s.course = CourseRow(id: course, clubID: club, name: "Marco Simone", externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map {
            CourseHoleRecord(courseID: course, holeNumber: $0 + 1, par: par[$0], strokeIndex: [7, 1, 15, 3, 11, 17, 5, 9, 13,
                                                                                              8, 18, 2, 10, 4, 16, 6, 12, 14][$0],
                             lengthM: nil)
        }
        s.scores = gross.flatMap { member, strokes in
            strokes.prefix(holesPlayed).enumerated().map { h, g in
                HoleScoreRow(roundID: roundID, memberID: member, holeIndex: h, strokes: g, recordedAt: nil,
                             updatedBy: nil, updatedAt: nil)
            }
        }
        return RoundGame(s)
    }

    private static func players(_ game: UUID, _ ids: [UUID], sides: [Int?]? = nil) -> [RoundGamePlayerRow] {
        ids.enumerated().map { i, p in
            RoundGamePlayerRow(gameID: game, roundID: roundID, playerID: p, seat: i + 1, side: sides?[i] ?? nil)
        }
    }

    /// Under runden: skins, Wolf og Nassau etter sju hull. Wolf venter på valget på hull 8.
    static var underway: GamesInput {
        let skins = id(100), wolf = id(101), nassau = id(102)
        var input = GamesInput()
        input.games = [
            RoundGameRow(id: skins, roundID: roundID, settings: grossSkins, createdBy: thomas),
            RoundGameRow(id: wolf, roundID: roundID, settings: .wolf(.standard), createdBy: thomas),
            RoundGameRow(id: nassau, roundID: roundID, settings: .nassau({ var r = NassauRules.standard; r.press = true; return r }()),
                         createdBy: thomas),
        ]
        input.players = players(skins, [thomas, kare, ola, per])
            + players(wolf, [kare, ola, per, thomas])
            + players(nassau, [thomas, kare, ola, per], sides: [1, 1, 2, 2])
        let choices: [(Int, String?, WolfChoice.Mode)] = [
            (0, ola.uuidString, .partner), (1, nil, .alone), (2, kare.uuidString, .partner),
            (3, per.uuidString, .partner), (4, thomas.uuidString, .partner), (5, nil, .blind), (6, kare.uuidString, .partner),
        ]
        input.marks = choices.map { h, p, mode in
            RoundGameMarkRow(gameID: wolf, roundID: roundID, holeIndex: h, award: .wolf,
                             playerID: p.flatMap(UUID.init(uuidString:)), wolfMode: mode)
        }
        return input
    }

    /// Ferdig runde: skins er gjort opp, best ball er klar til oppgjør.
    static var finished: GamesInput {
        let skins = id(110), bestBall = id(111)
        var input = GamesInput()
        input.games = [
            RoundGameRow(id: skins, roundID: roundID, settings: grossSkins, status: .settled, createdBy: thomas,
                         settledAt: "2026-10-07T20:15:00Z"),
            RoundGameRow(id: bestBall, roundID: roundID, settings: .bestBall(.standard), createdBy: thomas),
        ]
        input.players = players(skins, [thomas, kare, ola, per])
            + players(bestBall, [thomas, ola, kare, per], sides: [1, 1, 2, 2])
        let result = Games.evaluate(input.setup(for: input.games[0]), round: game(holesPlayed: 18, locked: true).round,
                                    roster: game(holesPlayed: 18, locked: true).roster)
        input.results = [thomas, kare, ola, per].map {
            RoundGameResultRow(gameID: skins, roundID: roundID, playerID: $0, points: result.settlement[$0.uuidString] ?? 0)
        }
        return input
    }
}

/// Skjermprøve: kortene under føringen, eller sluttresultatet.
struct SpillSampleScreen: View {
    let finished: Bool

    var body: some View {
        let game = GamesSamples.game(holesPlayed: finished ? 18 : 7, locked: finished)
        NavigationStack {
            ScrollView {
                SpillSeksjon(model: GamesModel(sample: finished ? GamesSamples.finished : GamesSamples.underway,
                                               roundID: GamesSamples.roundID),
                             game: game, hole: finished ? 17 : 7, viewer: GamesSamples.viewer, me: nil)
                    .padding(.horizontal, DDSpacing.gutter)
                    .padding(.vertical, DDSpacing.l)
            }
            .navigationTitle(finished ? "Runden er ferdig" : "Hull 8")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
        }
        .tint(Color.ddForestInk)
    }
}

/// Skjermprøve: arket for et nytt spill (Wolf, fire spillere).
struct SpillNyttSampleScreen: View {
    var body: some View {
        let draft = GameDraft(kind: .wolf, roundPlayers: [GamesSamples.kare, GamesSamples.ola, GamesSamples.per,
                                                          GamesSamples.thomas],
                              preferred: [GamesSamples.thomas])
        NyttSpillArk(model: GamesModel(sample: GamesInput(), roundID: GamesSamples.roundID), draft: draft,
                     name: { GamesSamples.names[$0] ?? "?" })
            .tint(Color.ddForestInk)
    }
}

#Preview("Spill under runden") { SpillSampleScreen(finished: false) }
#Preview("Spill: sluttresultat") { SpillSampleScreen(finished: true) }
#Preview("Nytt spill") { SpillNyttSampleScreen() }
#endif
