#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// Oppdiktet Hjem for skjermprøver (`-DDDesignScreen hjem`, `hjemmidt`, `hjembunn`, `hjemlos`, `hjemtom`, `hjemarrangor`,
/// `hjembjelle`, `hjeminviter`): Golfgutu Invitational med jakkeracet, Morrocupen og en løs runde, som i designet.
enum HjemSamples {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let club = id(9100)
    static let profile = id(9101)
    static let me = id(1), anders = id(2), bjorn = id(3), kari = id(4), even = id(5), kristian = id(6), ola = id(7)
    static let viewer = HomeViewer(profileID: profile, memberships: [club: me])
    static let clubs = [HomeClub(id: club, name: "Golfgutu Invitational")]

    static let jakke = CompetitionRow(id: id(7000), kind: .season, name: "Jakkeracet", clubID: club, ownerID: nil,
                                      seasonID: id(7001), status: .active, entry: .club, rules: .golfgutu,
                                      startsOn: nil, endsOn: nil, isMain: true, requiresPurchase: false,
                                      entitlementID: nil)
    static let morro = CompetitionRow(id: id(7100), kind: .fun, name: "Morrocupen", clubID: nil, ownerID: profile,
                                      seasonID: nil, status: .active, entry: .open, rules: .golfgutu,
                                      startsOn: nil, endsOn: nil, isMain: false, requiresPurchase: false,
                                      entitlementID: nil)

    static let liveRound = id(800), yesterdayRound = id(801), morroRound = id(802), looseRound = id(803)
    static let names: [(UUID, String)] = [(me, "Thomas"), (anders, "Anders Berg"), (bjorn, "Bjørn Dahl"),
                                          (kari, "Kari"), (even, "Even Lie"), (kristian, "Kristian"), (ola, "Ola")]
    static let par = [4, 5, 3, 4, 5, 3, 4, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    // MARK: Modellen

    /// Hele feeden: oppsummering, «Pågår nå», «Neste kveld» og alle korttypene.
    static func model(now: Date = .now, live: Bool = true, organizer: Bool = false, empty: Bool = false)
        -> HomeFeedModel {
        let model = HomeFeedModel(preview: empty ? HomeFeedQueries.Raw() : raw(now: now), viewer: viewer,
                                  clubs: clubs, lastSeen: empty ? nil : now.addingTimeInterval(-2 * 86_400),
                                  now: { now })
        if live, !empty {
            model.live = HomeLiveInput(snapshot: liveSnapshot(now: now), viewer: Viewer(memberID: me, isOrganizer: organizer))
        }
        if !empty {
            model.evening = evening(now: now, organizer: organizer)
        }
        return model
    }

    static func evening(now: Date, organizer: Bool) -> HomeEveningInput {
        let today = EveningDates.dateString(from: now)
        let date = EveningDates.dateString(from: now.addingTimeInterval(8 * 86_400))
        return HomeEveningInput(clubID: club, clubName: "Golfgutu Invitational",
                                event: EventRow(id: id(950), clubID: club, seasonID: id(7001), eventDate: date,
                                                startTime: "18:00:00", venue: "Golfstudio Bryn", note: nil),
                                today: today, answer: .yes, coming: 6, isOrganizer: organizer)
    }

    static func raw(now: Date) -> HomeFeedQueries.Raw {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let startOfToday = Calendar.current.startOfDay(for: now)
        let yesterday2014 = startOfToday.addingTimeInterval(-(3 * 3600 + 46 * 60))
        let yesterday2240 = startOfToday.addingTimeInterval(-(80 * 60))

        var raw = HomeFeedQueries.Raw()
        raw.competitions = [jakke, morro]
        raw.links = [
            CompetitionRoundRow(competitionID: jakke.id, roundID: liveRound, source: .season),
            CompetitionRoundRow(competitionID: morro.id, roundID: liveRound, source: .manual),
            CompetitionRoundRow(competitionID: jakke.id, roundID: yesterdayRound, source: .season),
            CompetitionRoundRow(competitionID: morro.id, roundID: morroRound, source: .manual),
        ]
        raw.members = names.map { id, name in
            ClubMemberRow(id: id, clubID: club, userID: nil, displayName: name, handicapIndex: nil, seedGroup: nil,
                          isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
        }
        raw.roundLabels = [liveRound: HomeRoundLabel(courseName: "Losby", roundNo: 4),
                           yesterdayRound: HomeRoundLabel(courseName: "Losby", roundNo: 3),
                           morroRound: HomeRoundLabel(courseName: "Bærum GK", roundNo: 1)]
        let eagle = row(1, .bigScore(member: anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5),
                        actor: anders, round: liveRound, at: ago(3))
        raw.activity = [
            eagle,
            row(2, .tableChanged(competition: morro.id, competitionName: "Morrocupen", roundNo: 2,
                                 table: [ActivityTableSpot(member: bjorn, place: 1, from: 2, points: 41),
                                         ActivityTableSpot(member: anders, place: 2, from: 1, points: 39),
                                         ActivityTableSpot(member: me, place: 3, from: 4, points: 36)]),
                at: ago(12)),
            row(3, .sidePrize(kind: .drive, member: bjorn, hole: 7, meters: 245, passed: anders, passedMeters: 231),
                actor: bjorn, round: yesterdayRound, at: yesterday2014),
            row(4, .tipsKing(members: [kristian], correct: 9, possible: 12,
                             eventDate: EveningDates.dateString(from: yesterday2014)),
                at: yesterday2240),
            row(5, .tableChanged(competition: jakke.id, competitionName: "Jakkeracet", roundNo: 3,
                                 table: [ActivityTableSpot(member: anders, place: 1, from: 1, points: 58),
                                         ActivityTableSpot(member: bjorn, place: 2, from: 2, points: 55),
                                         ActivityTableSpot(member: me, place: 3, from: 5, points: 49)]),
                at: ago(4 * 1440)),
            row(6, .bigScore(member: even, hole: 12, holeIndex: 11, name: .holeInOne, strokes: 1, par: 3),
                actor: even, round: morroRound, at: ago(5 * 1440)),
            row(7, .announcement(text: "Vi starter 17:00 torsdag, husk sko."), actor: me, at: ago(6 * 1440)),
            row(8, .signup(member: bjorn, status: .yes, eventDate: EveningDates.dateString(from: now.addingTimeInterval(8 * 86_400))),
                actor: bjorn, at: ago(6 * 1440 + 30)),
        ]
        raw.reactions = [
            ActivityReactionRow(activityID: eagle.id, memberID: me, clubID: club, emoji: .fire),
            ActivityReactionRow(activityID: eagle.id, memberID: bjorn, clubID: club, emoji: .fire),
            ActivityReactionRow(activityID: eagle.id, memberID: kari, clubID: club, emoji: .thumbsUp),
            ActivityReactionRow(activityID: id(10_006), memberID: anders, clubID: club, emoji: .laugh),
            ActivityReactionRow(activityID: id(10_006), memberID: bjorn, clubID: club, emoji: .laugh),
            ActivityReactionRow(activityID: id(10_006), memberID: kari, clubID: club, emoji: .laugh),
        ]
        raw.rounds = [looseSnapshot(lockedAt: startOfToday.addingTimeInterval(-6 * 3600))]
        return raw
    }

    static func row(_ n: Int, _ event: ActivityEvent, actor: UUID? = nil, round: UUID? = nil, at date: Date)
        -> ActivityRow {
        ActivityRow(id: id(10_000 + n), clubID: club, kind: event.kind, category: event.category, data: event.data,
                    actorMemberID: actor, eventID: nil, roundID: round, recipients: nil, createdAt: date)
    }

    // MARK: Runder

    static func roundRow(_ rid: UUID, club: UUID?, status: RoundStatus, roundNo: Int, started: Date?, locked: Date?)
        -> RoundRow {
        RoundRow(id: rid, clubID: club, eventID: club == nil ? nil : id(950), courseID: id(960), roundNo: roundNo,
                 name: nil, status: status, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                 handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: false, ldHoleIndex: nil,
                 kpEnabled: false, kpHoleIndex: nil, cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
                 parConfirmedAt: Date(timeIntervalSince1970: 0), startedAt: started, lockedAt: locked)
    }

    /// `players`: (id, navn, bås, brutto per hull).
    static func snapshot(_ row: RoundRow, course: String, players: [(UUID, String, Int, [Int])]) -> RoundSnapshot {
        var s = RoundSnapshot(round: row)
        s.players = players.map { p in
            RoundPlayerRow(roundID: row.id, memberID: p.0, clubID: row.clubID, handicapIndex: 0, seedGroup: nil,
                           playingHandicap: nil, bayNo: p.2, isMarker: false, teamNo: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: players.map { ($0.0, $0.1) })
        s.course = CourseRow(id: id(960), clubID: row.clubID, name: course, externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map { i in
            CourseHoleRecord(courseID: id(960), holeNumber: i + 1, par: par[i], strokeIndex: i + 1, lengthM: nil)
        }
        s.scores = players.flatMap { p in
            p.3.enumerated().map { hole, strokes in
                HoleScoreRow(roundID: row.id, memberID: p.0, holeIndex: hole, strokes: strokes, recordedAt: nil,
                             updatedBy: nil, updatedAt: nil)
            }
        }
        return s
    }

    /// Brutto fra par og et mønster: −1 birdie, 0 par, 1 bogey, 2 dobbel.
    static func strokes(_ pattern: [Int]) -> [Int] {
        pattern.enumerated().map { par[$0.offset] + $0.element }
    }

    /// Runden som går: Losby, runde 4, ni hull spilt. Bjørn 23, Anders 22, Thomas 21.
    static func liveSnapshot(now: Date) -> RoundSnapshot {
        let row = roundRow(liveRound, club: club, status: .active, roundNo: 4, started: now.addingTimeInterval(-7200),
                           locked: nil)
        return snapshot(row, course: "Losby", players: [
            (bjorn, "Bjørn", 1, strokes([-1, -1, 0, -1, 0, -1, 0, -1, 0])),
            (anders, "Anders", 1, strokes([-1, -1, 0, 0, -1, 0, -1, 0, 0])),
            (me, "Thomas", 2, strokes([-1, 0, 0, -1, 0, 0, -1, 0, 0])),
            (kari, "Kari", 2, strokes([0, 0, 0, 0, 0, 0, 0, 0, 0])),
            (ola, "Ola", 2, strokes([0, 1, 0, 0, 1, 0, 0, 0, 0])),
        ])
    }

    /// Din løse runde i går: Oslo GK med Per og Even. Per 36, Thomas 33 (2. plass), Even 31.
    static func looseSnapshot(lockedAt: Date) -> RoundSnapshot {
        let myPart = id(980), per = id(981), evenSeat = id(982)
        let row = roundRow(looseRound, club: nil, status: .locked, roundNo: 0,
                           started: lockedAt.addingTimeInterval(-4 * 3600), locked: lockedAt)
        var s = snapshot(row, course: "Oslo GK", players: [
            (myPart, "Thomas", 1, strokes([-1, 0, 0, 1, -1, 0, 0, 2, 0, 1, 0, -1, 0, 1, 0, 0, 1, 0])),
            (per, "Per", 1, strokes(Array(repeating: 0, count: 18))),
            (evenSeat, "Even", 1, strokes([0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0])),
        ])
        s.loose = LooseRoundInfo(ownerID: profile, roster: [
            RoundRosterRow(roundID: looseRound, playerID: myPart, clubID: nil, displayName: "Thomas", profileID: profile,
                           isGuest: false),
            RoundRosterRow(roundID: looseRound, playerID: per, clubID: nil, displayName: "Per", profileID: nil,
                           isGuest: true),
            RoundRosterRow(roundID: looseRound, playerID: evenSeat, clubID: nil, displayName: "Even", profileID: nil,
                           isGuest: true),
        ])
        s.rules = LooseRoundRules.template
        s.eventDate = LooseRoundInfo.day(row.startedAt ?? lockedAt)
        return s
    }
}

/// Hjem som skjermprøve: feeden i fanens ramme med bjella.
struct HjemSampleScreen: View {
    enum Variant {
        case full, middle, bottom, empty, organizer, bell
        /// Arrangør i en ny klubb med to i troppen: «Inviter spillere» øverst (`hjeminviter`).
        case invite
        /// Filteret «Løse runder»: «Din runde» øverst.
        case loose
    }

    let variant: Variant
    @State private var model: HomeFeedModel

    init(variant: Variant) {
        self.variant = variant
        let organizer = variant == .organizer || variant == .invite
        let model = HjemSamples.model(live: !organizer, organizer: organizer,
                                      empty: variant == .empty)
        if variant == .loose { model.filter = .loose }
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Group {
                if variant == .bell {
                    HjemVarslerView(model: model)
                } else {
                    HjemFeedView(feed: model.feed, pendingAnswer: variant == .organizer ? "Svaret ditt: Kommer" : nil,
                                 actions: HjemActions(select: { model.filter = $0 },
                                                      toggle: { r, t in Task { await model.toggle(r, on: t) } },
                                                      hasReacted: { model.hasReacted($0, on: $1) },
                                                      share: { model.share(round: $0) },
                                                      organizer: variant == .organizer
                                                        ? HjemOrganizerStep(title: TonightAction.setUp.buttonTitle() ?? "",
                                                                            hint: "", perform: {})
                                                        : nil,
                                                      invite: variant == .invite
                                                        ? HjemInvite(clubName: "Golfgutu Invitational",
                                                                     invite: ClubInvite(code: "A1B2C3D4E5")!,
                                                                     activeMembers: 2)
                                                        : nil),
                                 scrollAnchor: variant == .bottom ? .bottom : variant == .middle ? .center : nil)
                        .navigationTitle("Hjem")
                        .ddNavigationChrome()
                }
            }
            .toolbar {
                if variant != .bell {
                    ToolbarItem(placement: .topBarTrailing) {
                        HjemBell(model: model).tint(Color.ddOnDark)
                    }
                }
            }
        }
        .tint(Color.ddForestInk)
        .ddScreenBackground()
    }
}

#Preview("Hjem") { HjemSampleScreen(variant: .full) }
#Preview("Hjem tom") { HjemSampleScreen(variant: .empty) }
#Preview("Hjem arrangør") { HjemSampleScreen(variant: .organizer) }
#Preview("Hjem mørk") { HjemSampleScreen(variant: .full).preferredColorScheme(.dark) }
#endif
