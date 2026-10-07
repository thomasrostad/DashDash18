#if DEBUG
import Foundation
import GolfgutuCore
import Supabase
import SwiftUI

/// Løse runder med oppdiktede data, uten nett (`-DDDesignScreen losspill`, `losny`, `losbane`,
/// `losinviter`, `losblimed`, `losrunde` og `losresultat`).
enum SpillSamples {
    static let me = UUID()
    static let client = SupabaseClient(supabaseURL: URL(string: "https://forhandsvisning.supabase.co")!,
                                       supabaseKey: "sb_publishable_forhandsvisning")
    static let profile = ProfileRow(id: me, displayName: "Thomas", handicapIndex: 14.2, avatarPath: nil)
    static let friends = [
        ProfileRow(id: UUID(), displayName: "Anders", handicapIndex: 9.8, avatarPath: nil),
        ProfileRow(id: UUID(), displayName: "Bjørn", handicapIndex: 20.1, avatarPath: nil),
        ProfileRow(id: UUID(), displayName: "Cato", handicapIndex: nil, avatarPath: nil),
    ]

    static func course(_ name: String, kind: CourseKind, pars: [Int], createdBy: UUID? = nil) -> CourseListItem {
        let id = UUID()
        let row = CourseRow(id: id, clubID: nil, name: name, externalName: nil, courseRating: 71.2, slopeRating: 128,
                            inUse: true, confirmedBy: nil, confirmedAt: nil, createdByProfile: createdBy)
        let holes = pars.enumerated().map { i, par in
            CourseHoleRecord(courseID: id, holeNumber: i + 1, par: par, strokeIndex: (i * 7) % pars.count + 1,
                             lengthM: 120 + 25 * par * (i % 3 + 1))
        }
        return CourseListItem(course: row, holes: holes, storedKind: kind)
    }

    static let losby = course("Losby Golfklubb", kind: .course, pars: Course.defaultPar, createdBy: me)
    static var courses: [CourseListItem] {
        [
            losby,
            course("Oslo Golfklubb", kind: .course, pars: Course.defaultPar),
            course("Pebble Beach Golf Links", kind: .simulator, pars: Course.defaultPar),
            course("Grini 9-hulls", kind: .course, pars: Array(Course.defaultPar.prefix(9))),
            course("Lofoten Links", kind: .course, pars: []),
        ]
    }

    static var library: CourseLibraryModel {
        CourseLibraryModel(previewShared: courses, client: client, userID: me)
    }

    static var nyRunde: NyRundeModel {
        var draft = LooseRoundDraft.new()
        draft.courseID = losby.id
        draft.friends = [friends[0].id]
        draft.guests = [.init(name: "Per", handicapText: "18,4")]
        let library = CourseLibraryModel(previewShared: [losby], client: client, userID: me)
        return NyRundeModel(preview: library, friends: friends, me: profile, draft: draft)
    }

    // MARK: Runden

    static let roundID = UUID()
    static let ids = (0..<4).map { _ in UUID() }

    static func snapshot(locked: Bool) -> RoundSnapshot {
        let started = Date.now.addingTimeInterval(-2 * 3600)
        let round = RoundRow(id: roundID, clubID: nil, eventID: nil, courseID: losby.id, roundNo: 1, name: nil,
                             status: locked ? .locked : .active, holeCount: 18, firstHole: 1, teeTime: nil,
                             format: "stableford", handicapAllowance: 0.95, externalHandicap: false, weight: 1,
                             ldEnabled: true, ldHoleIndex: nil, kpEnabled: true, kpHoleIndex: nil, cutRule: nil,
                             cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: started, startedAt: started,
                             lockedAt: locked ? .now : nil, venue: "course")
        let seats: [(String, UUID?, Double?)] = [("Thomas", me, 14.2), ("Anders", friends[0].id, 9.8),
                                                  ("Per", nil, 18.4), ("Kari", nil, nil)]
        var s = RoundSnapshot(round: round)
        s.players = seats.indices.map { i in
            RoundPlayerRow(roundID: roundID, memberID: ids[i], clubID: nil, handicapIndex: seats[i].2, seedGroup: nil,
                           playingHandicap: nil, bayNo: 1, isMarker: i == 0, teamNo: nil)
        }
        let info = LooseRoundInfo(ownerID: me, roster: seats.indices.map { i in
            RoundRosterRow(roundID: roundID, playerID: ids[i], clubID: nil, displayName: seats[i].0,
                           profileID: seats[i].1, isGuest: seats[i].1 == nil)
        })
        s.loose = info
        s.names = info.names
        s.eventDate = LooseRoundInfo.day(started)
        s.rules = LooseRoundRules.template
        s.course = losby.course
        s.courseHoles = losby.holes
        let played = locked ? 18 : 6
        let strokes = [[4, 5, 3, 4, 5, 4], [5, 4, 4, 4, 4, 3], [6, 6, 4, 5, 5, 4], [5, 7, 4, 6, 5, 5]]
        for (i, member) in ids.enumerated() {
            for hole in 0..<played {
                s.scores.append(HoleScoreRow(roundID: roundID, memberID: member, holeIndex: hole,
                                             strokes: strokes[i][hole % 6], recordedAt: nil, updatedBy: nil, updatedAt: nil))
            }
        }
        return s
    }

    static func rundeModel(locked: Bool) -> RundeModel {
        RundeModel(previewLoose: snapshot(locked: locked),
                   context: LooseRoundContext(client: client, userID: me, roundID: roundID))
    }

    // MARK: Lister

    static var spill: SpillModel {
        let finished = [snapshot(locked: true)]
        var other = snapshot(locked: true)
        other.round = RoundRow(id: UUID(), clubID: nil, eventID: nil, courseID: other.round.courseID, roundNo: 1,
                               name: nil, status: .locked, holeCount: 9, firstHole: 1, teeTime: nil, format: "match",
                               handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: false,
                               ldHoleIndex: nil, kpEnabled: false, kpHoleIndex: nil, cutRule: nil, cutAfter: nil,
                               parConfirmedBy: nil, parConfirmedAt: nil, startedAt: .now.addingTimeInterval(-8 * 86_400),
                               lockedAt: .now.addingTimeInterval(-8 * 86_400 + 7200), venue: "course")
        other.eventDate = LooseRoundInfo.day(other.round.startedAt!)
        let lists = MyRounds.lists([snapshot(locked: false)] + finished + [other], userID: me)
        return SpillModel(preview: profile, ongoing: lists.ongoing, finished: lists.finished)
    }

    static var invitePreview: InvitePreview {
        let json = """
        {"round_id": "\(roundID.uuidString)", "status": "active", "hole_count": 18, "first_hole": 1,
         "format": "stableford", "venue": "course", "course_name": "Losby Golfklubb", "owner_name": "Thomas",
         "my_participant_id": null,
         "players": [
           {"participant_id": "\(ids[0].uuidString)", "display_name": "Thomas", "is_guest": false},
           {"participant_id": "\(ids[1].uuidString)", "display_name": "Anders", "is_guest": false},
           {"participant_id": "\(ids[3].uuidString)", "display_name": "Kari", "is_guest": true},
           {"participant_id": "\(ids[2].uuidString)", "display_name": "Per", "is_guest": true}]}
        """
        return try! JSONDecoder().decode(InvitePreview.self, from: Data(json.utf8))
    }

    static let code = InviteCode("K7QM2-XR4TD")!
}

struct SpillSampleScreen: View {
    let screen: DesignScreenSamples.Screen

    var body: some View {
        NavigationStack {
            switch screen {
            case .losny:
                NyRundeView(model: SpillSamples.nyRunde) { _ in }
            case .losbane:
                CoursePickerView(model: SpillSamples.library, selected: SpillSamples.losby.id) { _ in }
            case .losinviter:
                InviteView(model: InviteModel(preview: SpillSamples.code, courseName: "Losby Golfklubb"))
            case .losblimed:
                JoinRoundView(model: JoinRoundModel(preview: SpillSamples.invitePreview, code: SpillSamples.code,
                                                    myName: "Per")) { _ in }
            case .losrunde, .losresultat:
                RundeView(model: SpillSamples.rundeModel(locked: screen == .losresultat))
            default:
                SpillView(model: SpillSamples.spill)
                    .navigationTitle("Spill")
                    .ddNavigationChrome()
            }
        }
        .tint(Color.ddForestInk)
    }
}
#endif
