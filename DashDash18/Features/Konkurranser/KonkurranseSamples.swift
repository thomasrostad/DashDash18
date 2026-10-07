#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// Oppdiktede konkurranser for skjermprøvene `konktavla`, `konkliste`, `konkliga`, `konkcup`,
/// `konkny`, `konkteller` og `konkkveld` (DesignScreenSamples).
enum KonkurranseSamples {
    static func id(_ n: Int) -> UUID { TavlaSamples.id(n) }

    static let club = TavlaSamples.club
    static let me = id(880)
    static let access = CompetitionAccess(profileID: me, memberships: [
        .init(clubID: club, memberID: TavlaSamples.me, isOrganizer: true, isActive: true),
    ])

    static func competition(_ n: Int, _ kind: CompetitionKind, _ name: String, entry: CompetitionEntry = .listed,
                            status: SeasonStatus = .active, club: UUID? = KonkurranseSamples.club,
                            owner: UUID? = nil, starts: String? = nil, ends: String? = nil, signup: Bool = true,
                            main: Bool = false) -> CompetitionRow {
        CompetitionRow(id: id(n), kind: kind, name: name, clubID: club, ownerID: owner, seasonID: main ? id(9002) : nil,
                       status: status, entry: entry, rules: .golfgutu, startsOn: starts, endsOn: ends, isMain: main,
                       requiresPurchase: false, entitlementID: nil, signupOpen: signup)
    }

    static let jakkeracet = competition(7000, .season, "Jakkeracet 2026", entry: .club, signup: false, main: true)
    static let morro = competition(7001, .fun, "Oktobermorro", starts: "2026-10-01", ends: "2026-10-31")
    static let liga = competition(7002, .league, "Torsdagsligaen", starts: "2026-09-01", ends: "2026-12-17")
    static let cup = competition(7003, .cup, "Høstcupen", signup: false)
    static let vinter = competition(7004, .cup, "Vintercupen", status: .planned, starts: "2026-12-01")
    static let privat = competition(7005, .fun, "Gutta på tur", club: nil, owner: me, starts: "2026-06-12",
                                    ends: "2026-06-14", signup: false)
    static let ferdig = competition(7006, .league, "Vårligaen", status: .finished, starts: "2026-04-01",
                                    ends: "2026-06-30", signup: false)

    static var overview: CompetitionQueries.Overview {
        let members = TavlaSamples.members
        var parts: [CompetitionParticipantRow] = []
        for (i, m) in members.prefix(6).enumerated() {
            parts.append(CompetitionParticipantRow(id: id(7100 + i), competitionID: liga.id, memberID: m.id, profileID: nil,
                                                   status: .active))
        }
        for (i, m) in members.enumerated() {
            parts.append(CompetitionParticipantRow(id: id(7200 + i), competitionID: cup.id, memberID: m.id, profileID: nil,
                                                   status: .active))
        }
        parts.append(CompetitionParticipantRow(id: id(7300), competitionID: privat.id, memberID: nil, profileID: me,
                                               status: .active))
        return CompetitionQueries.Overview(competitions: [jakkeracet, morro, liga, cup, vinter, privat, ferdig],
                                           participants: parts, drawn: [cup.id])
    }

    static func list() -> CompetitionsModel {
        CompetitionsModel(preview: overview, access: access, clubID: club, clubName: "Golfgutu Invitational")
    }

    // MARK: Liga

    static func league() -> CompetitionDetailModel {
        let rounds = (1...4).map { TavlaSamples.round($0, date: "2026-10-0\($0 + 1)") }
        let links = rounds.map { CompetitionRoundRow(competitionID: liga.id, roundID: $0.round.id, source: .manual) }
        let parts = overview.participants.filter { $0.competitionID == liga.id }
        let scope = CompetitionScope(competition: liga, links: links, participants: parts)
        let input = scope.input(candidates: rounds, directory: PersonDirectory(members: TavlaSamples.members))
        return CompetitionDetailModel(preview: liga, content: .league(LeagueStandings(input, me: access.myEntrants)),
                                      access: access)
    }

    // MARK: Cup

    static func cupModel() -> CompetitionDetailModel {
        let parts = overview.participants.filter { $0.competitionID == cup.id }
        func p(_ n: Int) -> UUID { parts[n - 1].id }
        // Åtte påmeldte, seedet 1–8 = Bjørn … Thomas; kvartfinalene er spilt, én semifinale.
        func m(_ r: Int, _ s: Int, _ a: Int, _ b: Int, _ w: Int?, _ text: String? = nil, walkover: Bool = false)
            -> CompetitionMatchRow {
            CompetitionMatchRow(id: id(7400 + r * 10 + s), competitionID: cup.id, roundNo: r, slot: s, playerA: p(a),
                                playerB: p(b), winner: w.map(p), walkover: walkover, result: text, roundID: nil)
        }
        let matches = [
            m(1, 0, 1, 8, 8, "2&1"), m(1, 1, 4, 5, 4, "1 opp"), m(1, 2, 2, 7, 2, walkover: true), m(1, 3, 3, 6, 3, "4&3"),
            m(2, 0, 8, 4, 8, "3&2"),
        ]
        let names = Dictionary(uniqueKeysWithValues: parts.enumerated().map { ($1.id, TavlaSamples.names[$0]) })
        let mine = Set(parts.filter(access.isMine).map(\.id))
        let standings = CupStandings(participants: parts, matches: matches, names: names, me: mine)
        return CompetitionDetailModel(preview: cup, content: .cup(standings), access: access)
    }

    // MARK: Ny konkurranse

    static func new(list: CompetitionsModel) -> NewCompetitionModel {
        var draft = CompetitionDraft(clubID: club, today: "2026-10-07")
        draft.name = "Høstcupen"
        draft.kind = .cup
        draft.hasPeriod = true
        draft.endsOn = "2026-11-26"
        draft.memberIDs = Set(TavlaSamples.members.prefix(6).map(\.id))
        return NewCompetitionModel(preview: list, draft: draft, members: TavlaSamples.members, friends: [])
    }

    // MARK: «Teller også i …» i hurtigstarten

    static func links(for model: RundeAdminModel) -> CompetitionLinkModel {
        let context = model.clubContext
        let access = context.competitionAccess
        let club = context.clubID
        let morro = CompetitionRow(id: id(7501), kind: .fun, name: "Oktobermorro", clubID: club, ownerID: nil,
                                   seasonID: nil, status: .active, entry: .listed, rules: .golfgutu,
                                   startsOn: "2026-10-01", endsOn: "2026-10-31", isMain: false, requiresPurchase: false,
                                   entitlementID: nil, signupOpen: true)
        let liga = CompetitionRow(id: id(7502), kind: .league, name: "Torsdagsligaen", clubID: club, ownerID: nil,
                              seasonID: nil, status: .active, entry: .open, rules: .golfgutu, startsOn: nil, endsOn: nil,
                              isMain: false, requiresPurchase: false, entitlementID: nil, signupOpen: false)
        let parts = model.members.prefix(5).enumerated().map { i, m in
            CompetitionParticipantRow(id: id(7600 + i), competitionID: morro.id, memberID: m.id, profileID: nil,
                                      status: .active)
        }
        return CompetitionLinkModel(preview: .init(competitions: [morro, liga], participants: Array(parts)),
                                    members: model.members, access: access, selected: [morro.id])
    }
}

/// Skjermprøvene for fase 15.
struct KonkurranseSampleScreen: View {
    let screen: DesignScreenSamples.Screen

    var body: some View {
        NavigationStack {
            switch screen {
            case .konkliste:
                CompetitionsListView(model: KonkurranseSamples.list())
            case .konkliga:
                CompetitionDetailView(model: KonkurranseSamples.league(), list: KonkurranseSamples.list())
            case .konkcup:
                CompetitionDetailView(model: KonkurranseSamples.cupModel(), list: KonkurranseSamples.list())
            case .konkny:
                NewCompetitionView(prepared: KonkurranseSamples.new(list: KonkurranseSamples.list())) {}
            case .konkteller:
                let model = RundeAdminModel.sample()
                RundeQuickStartView(model: model, draft: model.newDraft()!, onDone: { _ in },
                                    links: KonkurranseSamples.links(for: model))
            case .konkkveld:
                ScrollView {
                    VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                        DDSectionLabel("Neste kveld")
                        NextEveningCard(event: EventRow(id: UUID(), clubID: KonkurranseSamples.club, seasonID: nil,
                                                        eventDate: "2026-10-15", startTime: "18:00:00",
                                                        venue: "Golfstudio Bryn", note: nil),
                                        committee: ["Kåre", "Ola"], daysUntil: 8, referenceYear: 2026,
                                        funCompetitions: ["Oktobermorro"])
                            .ddCard(.large)
                    }
                    .padding(.horizontal, DDSpacing.gutter)
                    .padding(.vertical, DDSpacing.l)
                }
                .navigationTitle("Kveld")
                .ddNavigationChrome()
            default:
                TavlaCompetitions(model: KonkurranseSamples.list()) {
                    TavlaList(standings: TavlaSamples.standings())
                }
                .navigationTitle("Tavla")
                .ddNavigationChrome()
            }
        }
        .tint(Color.ddForestInk)
    }
}
#endif
