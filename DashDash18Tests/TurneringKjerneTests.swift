import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Fase 23 (sql/032): turneringsvelger, påmelding med venteliste og tilbud, innstillingene for
/// påmeldingen, stab, startliste og minste appbygg.
private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(1)
private let oslo = TimeZone(identifier: "Europe/Oslo")!

private func competition(_ n: Int, _ name: String, kind: CompetitionKind = .fun, clubID: UUID? = club,
                         status: SeasonStatus = .active, isMain: Bool = false, seasonID: UUID? = nil,
                         entry: CompetitionEntry = .listed) -> CompetitionRow {
    CompetitionRow(id: id(n), kind: kind, name: name, clubID: clubID, ownerID: nil, seasonID: seasonID,
                   status: status, entry: entry, rules: .golfgutu, startsOn: nil, endsOn: nil, isMain: isMain,
                   requiresPurchase: false, entitlementID: nil, signupOpen: true)
}

private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

struct TurneringsvelgerTests {
    @Test func mainFirstThenActiveThenPlannedByName() {
        let rows = [
            competition(10, "Vintercup", kind: .cup, status: .planned),
            competition(11, "Øl-turnering"),
            competition(12, "Jakkeracet", kind: .season, isMain: true, seasonID: id(500), entry: .club),
            competition(13, "Avslutning"),
            competition(14, "Ferdig liga", kind: .league, status: .finished),
            competition(15, "Skins", kind: .game),
            competition(16, "Annen klubb", clubID: id(2)),
        ]
        let options = TournamentPicker.options(rows, clubID: club)
        #expect(options.map(\.name) == ["Jakkeracet", "Avslutning", "Øl-turnering", "Vintercup"])
        #expect(options[0].subtitle == "Hovedturnering · Serie")
        #expect(options[3].subtitle == "Cup · planlagt")
        #expect(options[0].hasEvenings)
        #expect(!options[1].hasEvenings)
        #expect(TournamentPicker.showsPicker(options))
    }

    /// Golfgutu har én turnering: ingen velger, og arrangørsiden er som før.
    @Test func oneTournamentShowsNoPicker() {
        let options = TournamentPicker.options([competition(12, "Jakkeracet", kind: .season, isMain: true,
                                                            seasonID: id(500), entry: .club)], clubID: club)
        #expect(!TournamentPicker.showsPicker(options))
        #expect(!TournamentPicker.showsPicker([]))
    }

    @Test func initialFollowsSeasonOrMain() {
        let options = TournamentPicker.options([
            competition(12, "Jakkeracet", kind: .season, isMain: true, seasonID: id(500), entry: .club),
            competition(13, "Høstserie", kind: .season, status: .planned, seasonID: id(501), entry: .club),
        ], clubID: club)
        #expect(TournamentPicker.initial(options, seasonID: nil)?.name == "Jakkeracet")
        #expect(TournamentPicker.initial(options, seasonID: id(501))?.name == "Høstserie")
        #expect(TournamentPicker.initial(options, seasonID: id(999))?.name == "Jakkeracet")
    }

    /// En klubb uten serie med kvelder får tidslinja og «Kom i gang» som før, ikke en liga.
    @Test func noEveningsSelectsNothing() {
        let options = TournamentPicker.options([competition(10, "Liga", kind: .league), competition(11, "Cup", kind: .cup)],
                                               clubID: club)
        #expect(TournamentPicker.showsPicker(options))
        #expect(TournamentPicker.initial(options, seasonID: nil) == nil)
    }
}

struct PameldingTests {
    private func status(_ state: CompetitionSignupStatus.State, entrants: Int = 10, max: Int? = 16, waitlist: Int = 0,
                        waitlistEnabled: Bool = true, open: Bool = true, position: Int? = nil,
                        expires: Date? = nil, opens: Date? = nil, closes: Date? = nil) -> CompetitionSignupStatus {
        CompetitionSignupStatus(competitionID: id(10), state: state, waitlistPosition: position, offerExpiresAt: expires,
                     entrants: entrants, maxEntrants: max, waitlist: waitlist, signupOpen: open,
                     waitlistEnabled: waitlistEnabled, signupOpensAt: opens, signupClosesAt: closes)
    }

    private let now = date("2026-10-09T12:00:00Z")

    @Test func decodesRpcAnswer() throws {
        let json = """
        {"competition_id": "00000000-0000-0000-0000-000000000010", "state": "waitlisted", "waitlist_position": 3,
         "offer_expires_at": null, "entrants": 16, "max_entrants": 16, "waitlist": 4, "signup_open": true,
         "signup_audience": "anyone", "waitlist_enabled": true, "signup_opens_at": null,
         "signup_closes_at": "2026-10-20T16:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let s = try decoder.decode(CompetitionSignupStatus.self, from: Data(json.utf8))
        #expect(s.state == .waitlisted)
        #expect(s.waitlistPosition == 3)
        #expect(s.openToAnyone)
        #expect(s.isFull)
        #expect(s.signupClosesAt == date("2026-10-20T16:00:00Z"))
    }

    /// Svaret uten tall (turneringen kan ikke leses lenger) og en ukjent tilstand gir «none».
    @Test func decodesMinimalAndUnknownState() throws {
        let json = #"{"competition_id": "00000000-0000-0000-0000-000000000010", "state": "promoted"}"#
        let s = try JSONDecoder().decode(CompetitionSignupStatus.self, from: Data(json.utf8))
        #expect(s.state == .none)
        #expect(s.entrants == 0)
        #expect(!s.signupOpen)
    }

    @Test func entered() {
        let p = SignupCard.presentation(status(.entered, entrants: 12), now: now, timeZone: oslo)
        #expect(p.headline == "Du er påmeldt")
        #expect(p.capacity == "12 av 16 plasser")
        #expect(p.primary == nil)
        #expect(p.secondary == .leave)
    }

    @Test func offerWithDeadline() {
        let p = SignupCard.presentation(status(.offered, entrants: 15, waitlist: 2, position: 1,
                                               expires: date("2026-10-10T16:30:00Z")), now: now, timeZone: oslo)
        #expect(p.headline == "Du har fått plass")
        #expect(p.detail == "Svar innen lørdag 10. oktober kl. 18:30, ellers går plassen videre.")
        #expect(p.primary == .accept)
        #expect(p.secondary == .decline)
        #expect(p.capacity == "15 av 16 plasser · 2 på venteliste")
        #expect(p.tone == .urgent)
    }

    @Test func waitlistPosition() {
        let p = SignupCard.presentation(status(.waitlisted, entrants: 16, waitlist: 4, position: 3), now: now)
        #expect(p.headline == "Du står som nr. 3 på ventelista")
        #expect(p.secondary == .leaveWaitlist)
        #expect(p.primary == nil)
    }

    @Test func expiredOfferCanJoinAgain() {
        let p = SignupCard.presentation(status(.expired, entrants: 16, waitlist: 1, position: 1), now: now)
        #expect(p.headline == "Tilbudet gikk ut")
        #expect(p.primary == .joinWaitlist)
        #expect(p.detail?.hasSuffix("Du kan melde deg på igjen.") == true)
    }

    @Test func fullWithAndWithoutWaitlist() {
        let full = SignupCard.presentation(status(.none, entrants: 16), now: now)
        #expect(full.primary == .joinWaitlist)
        #expect(full.headline == "Turneringen er full")
        let noQueue = SignupCard.presentation(status(.none, entrants: 16, waitlistEnabled: false), now: now)
        #expect(noQueue.primary == nil)
        #expect(noQueue.tone == .closed)
        // Noen venter allerede: en ny påmelding havner bak dem, selv om taket ikke er nådd.
        let queue = SignupCard.presentation(status(.none, entrants: 15, waitlist: 1), now: now)
        #expect(queue.primary == .joinWaitlist)
    }

    @Test func openWithFreePlaces() {
        let p = SignupCard.presentation(status(.none, entrants: 15), now: now)
        #expect(p.headline == "1 ledig plass")
        #expect(p.primary == .join)
        let many = SignupCard.presentation(status(.withdrawn, entrants: 10, closes: date("2026-10-20T16:00:00Z")),
                                           now: now, timeZone: oslo)
        #expect(many.headline == "6 ledige plasser")
        #expect(many.detail == "Påmeldingen stenger tirsdag 20. oktober kl. 18:00.")
        let noCap = SignupCard.presentation(status(.none, entrants: 1, max: nil, waitlistEnabled: false), now: now)
        #expect(noCap.headline == "Påmeldingen er åpen")
        #expect(noCap.capacity == "1 påmeldt")
    }

    @Test func windowAndClosed() {
        let notYet = SignupCard.presentation(status(.none, opens: date("2026-10-12T06:00:00Z")), now: now, timeZone: oslo)
        #expect(notYet.headline == "Påmeldingen åpner mandag 12. oktober kl. 08:00")
        #expect(notYet.primary == nil)
        let past = SignupCard.presentation(status(.none, closes: date("2026-10-08T06:00:00Z")), now: now)
        #expect(past.headline == "Påmeldingen er stengt")
        let shut = SignupCard.presentation(status(.none, open: false), now: now)
        #expect(shut.headline == "Påmeldingen er stengt")
        #expect(shut.primary == nil)
    }

    @Test func waitlistEntryStatus() {
        let offered = WaitlistEntryRow(id: id(1), position: 1, displayName: "Ola", offeredAt: now,
                                       offerExpiresAt: date("2026-10-10T12:00:00Z"))
        #expect(offered.status(now: now, timeZone: oslo) == "Tilbudt plass, frist lørdag 10. oktober kl. 14:00")
        #expect(offered.status(now: date("2026-10-10T13:00:00Z")) == "Tilbudet har gått ut")
        let waiting = WaitlistEntryRow(id: id(2), position: 2, displayName: "Dag", offeredAt: nil, offerExpiresAt: nil)
        #expect(waiting.status(now: now) == nil)
    }
}

struct PameldingInnstillingerTests {
    private func draft(entry: CompetitionEntry = .listed, hasClub: Bool = true) -> SignupSettingsDraft {
        SignupSettingsDraft(.closed, entry: entry, hasClub: hasClub, now: date("2026-10-09T12:00:00Z"))
    }

    @Test func fromClosedDefaults() {
        let d = draft()
        #expect(!d.isOpen)
        #expect(!d.hasCap)
        #expect(d.maxEntrants == SignupSettingsDraft.defaultCap)
        #expect(d.issues().isEmpty)
    }

    @Test func checksMatchServer() {
        var d = draft()
        d.waitlistEnabled = true
        #expect(d.issues() == ["Venteliste krever et tak på antall påmeldte."])
        d.hasCap = true
        d.maxEntrants = 1
        #expect(d.issues() == ["Taket må være mellom 2 og 5000."])
        d.maxEntrants = 32
        d.hasOpensAt = true
        d.hasClosesAt = true
        d.closesAt = d.opensAt.addingTimeInterval(-60)
        #expect(d.issues() == ["Påmeldingen må stenge etter at den åpner."])
        #expect(draft(entry: .club).issues().count == 1)
        var noClub = draft(hasClub: false)
        noClub.openToAnyone = true
        noClub.listed = true
        #expect(noClub.issues() == ["Bare en klubb eller et senter har en offentlig liste."])
    }

    /// Den offentlige lista gjelder bare åpne turneringer, og venteliste bare med tak.
    @Test func paramsNormalize() throws {
        var d = draft()
        d.isOpen = true
        d.listed = true
        d.waitlistEnabled = true
        var p = d.params(competitionID: id(10))
        #expect(p.p_audience == "members")
        #expect(!p.p_listed)
        #expect(!p.p_waitlist_enabled)
        #expect(p.p_max_entrants == nil)
        d.openToAnyone = true
        d.hasCap = true
        d.maxEntrants = 24
        p = d.params(competitionID: id(10))
        #expect(p.p_audience == "anyone" && p.p_listed && p.p_waitlist_enabled && p.p_max_entrants == 24)
        // Tomme verdier sendes som null, ikke utelatt (RPC-en har ingen standardverdier).
        let json = String(decoding: try JSONEncoder().encode(p), as: UTF8.self)
        #expect(json.contains("\"p_opens_at\":null"))
        #expect(json.contains("\"p_closes_at\":null"))
    }
}

struct StabTests {
    @Test func organizersFirstThenByName() {
        let names = [id(1): "Øystein", id(2): "Anne", id(3): "Bjørn"]
        let staff = [CompetitionStaffRow(competitionID: id(9), profileID: id(1), role: .scorer),
                     CompetitionStaffRow(competitionID: id(9), profileID: id(2), role: .scorer),
                     CompetitionStaffRow(competitionID: id(9), profileID: id(3), role: .organizer)]
        #expect(StaffList.sorted(staff) { names[$0] ?? "" }.map(\.profileID) == [id(3), id(2), id(1)])
    }

    @Test func candidatesSkipStaffAndDuplicates() {
        let staff = [CompetitionStaffRow(competitionID: id(9), profileID: id(1), role: .scorer)]
        let people = [(profileID: id(1), name: "Anne"), (profileID: id(2), name: "Øyvind"),
                      (profileID: id(3), name: "Bjørn"), (profileID: id(3), name: "Bjørn")]
        #expect(StaffList.candidates(people, staff: staff).map(\.name) == ["Bjørn", "Øyvind"])
    }

    @Test func roleTexts() {
        #expect(StaffRole.organizer.title == "Arrangør")
        #expect(StaffRole.scorer.title == "Funksjonær")
        #expect(StaffRole(rawValue: "scorer") == .scorer)
    }
}

struct StartlisteTests {
    private let round = id(600)

    private func player(_ n: Int, bay: Int?) -> RoundPlayerRow {
        RoundPlayerRow(roundID: round, memberID: id(n), clubID: club, handicapIndex: nil, seedGroup: nil,
                       playingHandicap: nil, bayNo: bay, isMarker: false, teamNo: nil)
    }

    private var players: [RoundPlayerRow] {
        [player(1, bay: 1), player(2, bay: 1), player(3, bay: 2), player(4, bay: 3), player(5, bay: nil)]
    }

    /// Gruppene er båsene fra runde-oppsettet. Det som er lagret, legges på.
    @Test func groupsFromBays() {
        let saved = [RoundStartGroupRow(roundID: round, groupNo: 2, startsAt: "18:10:00", startHole: 10,
                                        resourceLabel: "Trackman 2", scorerID: id(77))]
        let groups = StartList.groups(players: players, saved: saved, venue: "simulator")
        #expect(groups.map(\.groupNo) == [1, 2, 3])
        #expect(groups[0].memberIDs == [id(1), id(2)])
        #expect(groups[0].resourceLabel == "Bås 1")
        #expect(groups[1].startsAt == "18:10")
        #expect(groups[1].resourceLabel == "Trackman 2")
        #expect(groups[1].scorerID == id(77))
        #expect(StartList.groups(players: players, saved: [], venue: "course")[0].resourceLabel == "")
        // Uten båser er det ingen grupper.
        #expect(StartList.groups(players: [player(1, bay: nil)], saved: [], venue: nil).isEmpty)
    }

    @Test func teeTimesWithInterval() {
        let groups = StartList.groups(players: players, saved: [], venue: "course")
        let timed = StartList.fillTimes(groups, first: "23:50", intervalMinutes: 10)
        #expect(timed.map(\.startsAt) == ["23:50", "00:00", "00:10"])
        #expect(StartList.fillTimes(groups, first: "kl 18", intervalMinutes: 10) == groups)
    }

    @Test func shotgunStart() {
        var groups = StartList.groups(players: players, saved: [], venue: "course")
        groups[0].startsAt = "09:00"
        let shot = StartList.shotgun(groups, holeCount: 2)
        #expect(shot.map(\.startHole) == [1, 2, 1])
        #expect(shot.map(\.startsAt) == ["09:00", "09:00", "09:00"])
    }

    @Test func checksMatchServer() {
        var groups = StartList.groups(players: players, saved: [], venue: "simulator")
        #expect(StartList.issues(groups, wave: 1, holeCount: 18, staffIDs: []).isEmpty)
        #expect(StartList.issues(groups, wave: 0, holeCount: 18, staffIDs: []) == ["Puljen må være mellom 1 og 20."])
        groups[0].startHole = 10
        #expect(StartList.issues(groups, wave: 1, holeCount: 9, staffIDs: []) == ["Starthullet må være mellom 1 og 9."])
        groups[0].startHole = nil
        groups[1].scorerID = id(77)
        #expect(StartList.issues(groups, wave: 1, holeCount: 18, staffIDs: []) == ["En funksjonær er ikke lenger i staben."])
        #expect(StartList.issues(groups, wave: 1, holeCount: 18, staffIDs: [id(77)]).isEmpty)
        groups[2].startsAt = "25:00"
        #expect(StartList.issues(groups, wave: 1, holeCount: 18, staffIDs: [id(77)]) == ["Starttiden må være på formen TT:MM."])
    }

    @Test func paramsTrimAndNull() throws {
        var groups = StartList.groups(players: players, saved: [], venue: "course")
        groups[0].resourceLabel = "  Tee 10 "
        let p = StartList.params(roundID: round, wave: 2, groups: groups)
        #expect(p.p_wave_no == 2)
        #expect(p.p_groups[0].resource_label == "Tee 10")
        #expect(p.p_groups[1].resource_label == nil)
        let json = String(decoding: try JSONEncoder().encode(p.p_groups[1]), as: UTF8.self)
        #expect(json.contains("\"scorer_id\":null"))
    }

    @Test func myGroupAndSummary() {
        let saved = [RoundStartGroupRow(roundID: round, groupNo: 1, startsAt: "18:00:00", startHole: 1,
                                        resourceLabel: "Bås 1", scorerID: nil)]
        let mine = StartList.myGroup(memberID: id(2), players: players, saved: saved)
        #expect(mine?.groupNo == 1)
        #expect(mine?.mates == [id(1)])
        #expect(StartList.summary(groupNo: 1, saved: mine?.saved, venue: "simulator") == "Bås 1 · 18:00")
        #expect(StartList.myGroup(memberID: id(5), players: players, saved: saved) == nil)
        let shot = RoundStartGroupRow(roundID: round, groupNo: 3, startsAt: "09:00:00", startHole: 10,
                                      resourceLabel: nil, scorerID: nil)
        #expect(StartList.summary(groupNo: 3, saved: shot, wave: 2, venue: "course")
                == "Flight 3 · 09:00 · starter på hull 10 · pulje 2")
        #expect(StartList.summary(groupNo: 2, saved: nil, venue: nil) == "Bås 2")
    }

    @Test func matesAndNames() {
        #expect(StartList.matesText([]) == nil)
        #expect(StartList.matesText(["Anders"]) == "med Anders")
        #expect(StartList.matesText(["Anders", "Bjørn", "Cato"]) == "med Anders, Bjørn og Cato")
        #expect(StartList.namesText([]) == "Ingen spillere")
        #expect(StartList.namesText(["Anders", "Bjørn"]) == "Anders, Bjørn")
    }

    @Test func clockMath() {
        #expect(StartList.minutes("18:10") == 1090)
        #expect(StartList.minutes("18:10:00") == 1090)
        #expect(StartList.minutes("24:00") == nil)
        #expect(StartList.clock(1090) == "18:10")
        #expect(StartList.clock(1440 + 5) == "00:05")
        #expect(StartList.timeText("07:05:00") == "07:05")
    }
}

struct MinsteByggTests {
    @Test func currentBuildFromBundle() {
        #expect(MinimumBuild.currentBuild(["CFBundleVersion": "42"]) == 42)
        #expect(MinimumBuild.currentBuild(["CFBundleVersion": "1.2"]) == nil)
        #expect(MinimumBuild.currentBuild([:]) == nil)
        #expect(MinimumBuild.currentBuild(nil) == nil)
    }

    @Test func outdatedOnlyWhenBothKnown() {
        #expect(MinimumBuild.isOutdated(current: 41, required: 42))
        #expect(!MinimumBuild.isOutdated(current: 42, required: 42))
        #expect(!MinimumBuild.isOutdated(current: 50, required: 42))
        // 0 (031) betyr ingen sperre. Ukjent bygg eller ukjent krav sperrer aldri.
        #expect(!MinimumBuild.isOutdated(current: 1, required: 0))
        #expect(!MinimumBuild.isOutdated(current: nil, required: 42))
        #expect(!MinimumBuild.isOutdated(current: 41, required: nil))
    }

    @Test func decodesConfigValue() throws {
        func build(_ json: String) throws -> Int? {
            try JSONDecoder().decode(AppConfigMinBuildRow.self, from: Data(json.utf8)).value?.build
        }
        #expect(try build(#"{"value": {"build": 0}}"#) == 0)
        #expect(try build(#"{"value": {"build": 57}}"#) == 57)
        #expect(try build(#"{"value": {"build": "58"}}"#) == 58)
        #expect(try build(#"{"value": {"build": "neste"}}"#) == nil)
        #expect(try build(#"{"value": {}}"#) == nil)
        #expect(try build(#"{"value": null}"#) == nil)
    }
}
