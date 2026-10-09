#if DEBUG
import Foundation
import GolfgutuCore
import SwiftUI

/// Oppdiktede data for skjermprøvene i fase 23 (DesignScreenSamples): `turneringvelger`,
/// `pamelding`, `pameldingvente`, `pameldinginnstillinger`, `startliste`, `stab`, `mingruppe`
/// og `oppdater`.
enum TournamentCoreSamples {
    static func id(_ n: Int) -> UUID { KonkurranseSamples.id(n) }

    static let club = KonkurranseSamples.club

    /// Simulatorsenteret med flere turneringer samtidig.
    static var pickerRows: [CompetitionRow] {
        [KonkurranseSamples.jakkeracet, KonkurranseSamples.liga, KonkurranseSamples.morro, KonkurranseSamples.vinter]
    }

    static func picker() -> TournamentPickerModel {
        TournamentPickerModel(preview: pickerRows, clubID: club)
    }

    static var league: CompetitionRow {
        var liga = KonkurranseSamples.liga
        liga.name = "Tirsdagsligaen"
        return liga
    }

    private static func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text) ?? .now }

    static func status(_ state: CompetitionSignupStatus.State) -> CompetitionSignupStatus {
        CompetitionSignupStatus(competitionID: league.id, state: state, waitlistPosition: state == .waitlisted ? 3 : 1,
                                offerExpiresAt: state == .offered ? Date.now.addingTimeInterval(22 * 3600) : nil,
                                entrants: state == .offered ? 31 : 32, maxEntrants: 32, waitlist: 4, signupOpen: true,
                                openToAnyone: true, waitlistEnabled: true, signupOpensAt: nil,
                                signupClosesAt: date("2026-10-20T16:00:00Z"))
    }

    static func settings() -> SignupSettingsModel {
        let settings = CompetitionSignupSettings(signupOpen: true, signupAudience: "anyone", listed: true,
                                                 maxEntrants: 32, waitlistEnabled: true,
                                                 signupOpensAt: date("2026-09-01T08:00:00Z"),
                                                 signupClosesAt: date("2026-10-20T16:00:00Z"))
        let names = ["Kari Nordmann", "Per Hansen", "Ingrid Berg", "Ola Dahl"]
        let waitlist = names.enumerated().map { i, name in
            WaitlistEntryRow(id: id(9100 + i), position: i + 1, displayName: name,
                             offeredAt: i == 0 ? Date.now.addingTimeInterval(-2 * 3600) : nil,
                             offerExpiresAt: i == 0 ? Date.now.addingTimeInterval(22 * 3600) : nil)
        }
        return SignupSettingsModel(preview: league, settings: settings, status: status(.none), waitlist: waitlist)
    }

    static let staffNames: [UUID: String] = [id(9201): "Anders", id(9202): "Bjørn", id(9203): "Cato",
                                             id(9204): "Dag", id(9205): "Erik"]

    static func staff() -> StaffModel {
        let staff = [CompetitionStaffRow(competitionID: league.id, profileID: id(9201), role: .organizer),
                     CompetitionStaffRow(competitionID: league.id, profileID: id(9202), role: .scorer),
                     CompetitionStaffRow(competitionID: league.id, profileID: id(9203), role: .scorer)]
        return StaffModel(preview: league, staff: staff, names: staffNames,
                          people: staffNames.map { (profileID: $0.key, name: $0.value) })
    }

    static func startList() -> StartListModel {
        let names = ["Anders", "Bjørn", "Cato", "Dag", "Erik", "Frode", "Gunnar", "Halvor", "Ivar", "Jon", "Kåre", "Lars"]
        let members = names.enumerated().map { (id(9300 + $0.offset), $0.element) }
        let memberNames = Dictionary(members, uniquingKeysWith: { first, _ in first })
        let event = EventRow(id: id(9400), clubID: club, seasonID: nil, eventDate: EveningDates.today(),
                             startTime: "18:00:00", venue: "Golfstudio Bryn", note: nil)
        func round(_ no: Int) -> RoundRow {
            var r = RoundRow(id: id(9410 + no), clubID: club, eventID: event.id, courseID: nil, roundNo: no, name: nil,
                             status: .draft, holeCount: 18, firstHole: 1, teeTime: "18:00:00", format: "stableford",
                             handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: false,
                             ldHoleIndex: nil, kpEnabled: false, kpHoleIndex: nil, cutRule: nil, cutAfter: nil,
                             parConfirmedBy: nil, parConfirmedAt: nil, startedAt: nil, lockedAt: nil)
            r.venue = "simulator"
            return r
        }
        func groups(_ ids: ArraySlice<(UUID, String)>, startBay: Int, time: Int, scorer: UUID?) -> [StartGroupDraft] {
            stride(from: ids.startIndex, to: ids.endIndex, by: 3).enumerated().map { i, start in
                let members = ids[start..<min(start + 3, ids.endIndex)].map(\.0)
                return StartGroupDraft(groupNo: startBay + i, startsAt: StartList.clock(time + i * 10), startHole: 1,
                                       resourceLabel: "Bås \(startBay + i)", scorerID: i == 1 ? scorer : nil,
                                       memberIDs: members)
            }
        }
        let first = StartListModel.RoundStart(round: round(1), title: "Runde 1 · Pebble Beach", wave: 1,
                                              groups: groups(members[0..<6], startBay: 1, time: 18 * 60, scorer: id(9202)))
        let second = StartListModel.RoundStart(round: round(2), title: "Runde 2 · St Andrews Old Course", wave: 2,
                                               groups: groups(members[6..<12], startBay: 3, time: 20 * 60, scorer: nil))
        let staff = [CompetitionStaffRow(competitionID: league.id, profileID: id(9202), role: .scorer)]
        return StartListModel(preview: event, rounds: [first, second], memberNames: memberNames, staff: staff,
                              staffNames: staffNames)
    }
}

/// `pamelding` / `pameldingvente`: turneringssiden med påmeldingskortet.
struct SignupSampleScreen: View {
    let state: CompetitionSignupStatus.State

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                    CompetitionHeaderCard(competition: TournamentCoreSamples.league, clubName: "Golfstudio Bryn")
                    CompetitionSignupCard(presentation: SignupCard.presentation(TournamentCoreSamples.status(state)),
                                          competitionName: TournamentCoreSamples.league.name) { _ in }
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .navigationTitle(TournamentCoreSamples.league.name)
            .ddNavigationChrome()
        }
        .tint(Color.ddForestInk)
    }
}

/// `mingruppe`: Kveld med gruppa mi øverst.
struct MyGroupSampleScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                    DDSectionLabel("Neste kveld")
                    MyStartGroupCard(model: MyStartGroupModel(preview: .init(summary: "Bås 3 · 18:10 · pulje 2",
                                                                             mates: "med Anders og Bjørn")))
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .navigationTitle("Kvelden")
            .ddNavigationChrome()
        }
        .tint(Color.ddForestInk)
    }
}
#endif
