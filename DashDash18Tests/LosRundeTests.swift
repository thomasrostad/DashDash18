import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 13: løse runder med venner. Oppsett, invitasjonskode, gjesteplass og kobling, rettighet til å
// føre og «Mine runder». Reglene i databasen er prøvd i sql/lokal/018_prove.sql; her er appens side.

private enum L {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static let me = id(1)
    static let friendA = id(2)
    static let friendB = id(3)
    static let courseID = id(50)
    static let roundID = id(60)

    static func course(kind: CourseKind = .course, holes: Int = 18, ready: Bool = true,
                       name: String = "Losby", createdBy: UUID? = nil, id: UUID = courseID) -> CourseListItem {
        let row = CourseRow(id: id, clubID: nil, name: name, externalName: nil, courseRating: nil, slopeRating: nil,
                            inUse: true, confirmedBy: nil, confirmedAt: nil, createdByProfile: createdBy)
        let records = (1...holes).map { n in
            CourseHoleRecord(courseID: id, holeNumber: n, par: (ready || n > 1) ? (n % 6 == 0 ? 3 : 4) : 0,
                             strokeIndex: n, lengthM: nil)
        }
        return CourseListItem(course: row, holes: ready ? records : Array(records.dropFirst()), storedKind: kind)
    }

    static func looseRound(status: RoundStatus = .active, format: String = "stableford",
                           startedAt: Date = Date(timeIntervalSince1970: 1_800_000_000), id: UUID = roundID) -> RoundRow {
        RoundRow(id: id, clubID: nil, eventID: nil, courseID: courseID, roundNo: 1, name: nil, status: status,
                 holeCount: 18, firstHole: 1, teeTime: nil, format: format, handicapAllowance: 1,
                 externalHandicap: false, weight: 1, ldEnabled: false, ldHoleIndex: nil, kpEnabled: false,
                 kpHoleIndex: nil, cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
                 parConfirmedAt: Date(timeIntervalSince1970: 0), startedAt: startedAt,
                 lockedAt: status == .locked ? startedAt.addingTimeInterval(3600) : nil, venue: "course")
    }

    struct Seat {
        let player: Int
        let name: String
        var profile: UUID?
        var bay: Int?
        var marker = false
    }

    /// En løs runde slik databasen gir den: deltakere (profil eller gjest), flight og markør.
    static func snapshot(_ seats: [Seat], owner: UUID? = me, round: RoundRow = looseRound(),
                         scores: [(Int, Int, Int)] = []) -> RoundSnapshot {
        var s = RoundSnapshot(round: round)
        s.players = seats.map { seat in
            RoundPlayerRow(roundID: round.id, memberID: id(seat.player), clubID: nil, handicapIndex: 10,
                           seedGroup: nil, playingHandicap: nil, bayNo: seat.bay, isMarker: seat.marker, teamNo: nil)
        }
        let info = LooseRoundInfo(ownerID: owner, roster: seats.map { seat in
            RoundRosterRow(roundID: round.id, playerID: id(seat.player), clubID: nil, displayName: seat.name,
                           profileID: seat.profile, isGuest: seat.profile == nil)
        })
        s.loose = info
        s.names = info.names
        s.eventDate = round.startedAt.map(LooseRoundInfo.day)
        s.rules = LooseRoundRules.template
        let course = L.course()
        s.course = course.course
        s.courseHoles = course.holes
        s.scores = scores.map { player, hole, strokes in
            HoleScoreRow(roundID: round.id, memberID: id(player), holeIndex: hole, strokes: strokes,
                         recordedAt: nil, updatedBy: nil, updatedAt: nil)
        }
        return s
    }
}

// MARK: - Invitasjonskoden

struct LosRundeKodeTests {
    @Test func kodenNormaliseresSomIDatabasen() {
        // round_invite_normalize: store bokstaver, uten mellomrom og bindestrek, O → 0, I/L → 1.
        #expect(InviteCode(" abcde-fgh23 ")?.value == "ABCDEFGH23")
        #expect(InviteCode("abcde fghil")?.value == "ABCDEFGH11")
        #expect(InviteCode("OOOOO-00000")?.value == "0000000000")
        #expect(InviteCode("ABCDE-FGH23")?.display == "ABCDE-FGH23")
    }

    @Test func ugyldigeKoder() {
        #expect(InviteCode("ABCDEFGH2") == nil)      // 9 tegn
        #expect(InviteCode("ABCDEFGH234") == nil)    // 11 tegn
        #expect(InviteCode("ABCDEFGHU2") == nil)     // U er ikke i Crockford base32
        #expect(InviteCode("ABCDE!FGH2") == nil)
        #expect(InviteCode("") == nil)
    }

    @Test func lenkenTilOgFra() throws {
        let code = try #require(InviteCode("ABCDEFGH23"))
        #expect(code.url.absoluteString == "dashdash://runde/ABCDEFGH23")
        #expect(InviteCode(url: code.url) == code)
        #expect(InviteCode(url: URL(string: "DashDash://Runde/abcde-fgh23")!) == code)
        #expect(InviteCode(url: URL(string: "dashdash://runde?kode=ABCDEFGH23")!) == code)
        #expect(InviteCode(url: URL(string: "dashdash://klubb/ABCDEFGH23")!) == nil)
        #expect(InviteCode(url: URL(string: "https://runde/ABCDEFGH23")!) == nil)
        #expect(InviteCode.parse("  dashdash://runde/ABCDEFGH23 ") == code)
        #expect(InviteCode.parse("abcde-fgh23") == code)
    }

    @Test func delingsteksten() throws {
        let text = try #require(InviteCode("ABCDEFGH23")).shareText(courseName: "Losby")
        #expect(text.contains("Losby") && text.contains("dashdash://runde/ABCDEFGH23") && text.contains("ABCDE-FGH23"))
        #expect(text.contains("i Atten.") && !text.contains("DashDash"))
    }
}

// MARK: - Oppsettet

struct LosRundeOppsettTests {
    @Test func nyRundeFraRegelsettet() {
        let rules = LooseRoundRules.template
        let draft = LooseRoundDraft.new(rules: rules)
        #expect(draft.formID == rules.formats.defaultFormID)
        #expect(draft.sidePrizes == (rules.sidePrizes.longestDrive.enabled || rules.sidePrizes.closestToPin.enabled))
        #expect(draft.playerCount == 1 && draft.scoring == .oneCard)
    }

    @Test func formeneErIndividuelleOgRegnbare() {
        let forms = LooseRoundRules.forms()
        #expect(forms.map(\.id).contains("stableford"))
        #expect(forms.map(\.id).contains("slag-netto"))
        #expect(forms.map(\.id).contains("match"))
        #expect(forms.allSatisfy { !$0.isTeamForm && $0.support != .missing })
        // Et regelsett som bare tillater slagspill, gir bare det.
        var rules = Ruleset.golfgutu
        rules.formats.allowedFormIDs = ["slag-brutto", "fourball"]
        rules.formats.defaultFormID = "fourball"
        #expect(LooseRoundRules.forms(rules).map(\.id) == ["slag-brutto"])
        #expect(LooseRoundDraft.new(rules: rules).formID == "slag-brutto")
    }

    @Test func mangler() {
        var draft = LooseRoundDraft.new()
        #expect(LooseRoundSetup.issues(draft, course: nil) == [.noCourse])
        #expect(LooseRoundSetup.issues(draft, course: L.course(ready: false)) == [.courseNotReady("Losby")])
        draft.guests = [.init(name: "  "), .init(name: "Per", handicapText: "tolv")]
        let issues = LooseRoundSetup.issues(draft, course: L.course())
        #expect(issues.first == .guestWithoutName)
        #expect(issues.contains { if case .guestHandicap(name: "Per", _) = $0 { true } else { false } })
        draft.guests = [.init(name: "Per", handicapText: "+2,3")]
        #expect(LooseRoundSetup.issues(draft, course: L.course()).isEmpty)
    }

    @Test func matchspillTrengerToSpillere() {
        var draft = LooseRoundDraft.new()
        draft.formID = "match"
        let issues = LooseRoundSetup.issues(draft, course: L.course())
        #expect(issues.count == 1)
        if case .form = issues.first {} else { Issue.record("forventet .form, fikk \(issues)") }
        draft.addGuest(name: "Per")
        #expect(LooseRoundSetup.issues(draft, course: L.course()).isEmpty)
        // Stableford kan spilles alene.
        #expect(LooseRoundSetup.issues(.new(), course: L.course()).isEmpty)
    }

    @Test func forMangeFlighterNarHverForerSelv() {
        var draft = LooseRoundDraft.new()
        draft.friends = (0..<LooseRoundLimits.maxGroups).map { L.id(100 + $0) }
        draft.scoring = .ownCards
        #expect(LooseRoundSetup.issues(draft, course: L.course()) == [.tooManyGroups(max: LooseRoundLimits.maxGroups)])
        draft.scoring = .oneCard
        #expect(LooseRoundSetup.issues(draft, course: L.course()).isEmpty)
    }

    @Test func startOgBane() {
        var draft = LooseRoundDraft.new()
        draft.setStart(QuickStartStart(firstHole: 10, holeCount: 9), courseHoles: 18)
        #expect(draft.firstHole == 10 && draft.holeCount == 9)
        draft.setCourse(L.id(51), courseHoles: 9)
        #expect(draft.holeCount == 9 && draft.firstHole == 1)
        draft.setStart(QuickStartStart(firstHole: 10, holeCount: 9), courseHoles: 9)
        #expect(draft.firstHole == 1)
    }

    @Test func venner() {
        var draft = LooseRoundDraft.new()
        draft.toggleFriend(L.friendA)
        draft.toggleFriend(L.friendB)
        draft.toggleFriend(L.friendA)
        #expect(draft.friends == [L.friendB])
        let blank = draft.addGuest(name: "   ")
        let kari = draft.addGuest(name: " Kari ")
        #expect(!blank && kari && draft.guests.map(\.trimmedName) == ["Kari"])
        draft.removeGuest(draft.guests[0].id)
        #expect(draft.guests.isEmpty)
    }
}

// MARK: - Flight, markør og matcher

struct LosRundePlanTests {
    private func draft(friends: Int, guests: Int, scoring: LooseRoundDraft.Scoring, form: String = "stableford") -> LooseRoundDraft {
        var d = LooseRoundDraft.new()
        d.friends = (0..<friends).map { L.id(100 + $0) }
        d.guests = (0..<guests).map { .init(name: "Gjest \($0)") }
        d.scoring = scoring
        d.formID = form
        return d
    }

    @Test func jegForerForAlle() {
        let plan = LooseRoundPlan.make(draft(friends: 2, guests: 1, scoring: .oneCard), names: [])
        #expect(plan.seats.map(\.bay) == [1, 1, 1, 1])
        #expect(plan.seats.map(\.isMarker) == [true, false, false, false])
        #expect(plan.matches.isEmpty)
    }

    @Test func hverForerSittEgetKort() {
        let plan = LooseRoundPlan.make(draft(friends: 2, guests: 2, scoring: .ownCards), names: [])
        // Deg + gjestene i flight 1 med deg som markør; vennene i hver sin flight uten markør.
        #expect(plan.seats.map(\.bay) == [1, 2, 3, 1, 1])
        #expect(plan.seats.map(\.isMarker) == [true, false, false, false, false])
        // Uten gjester trenger du ingen markør.
        let alone = LooseRoundPlan.make(draft(friends: 1, guests: 0, scoring: .ownCards), names: [])
        #expect(alone.seats.map(\.bay) == [1, 2] && alone.seats.map(\.isMarker) == [false, false])
    }

    @Test func matchspillTrekkerMatcherSomRegelmotoren() {
        let two = LooseRoundPlan.make(draft(friends: 0, guests: 1, scoring: .oneCard, form: "match"), names: ["Thomas", "Per"])
        #expect(two.matches.count == 1 && Set(two.matches[0]) == [0, 1])
        let names = ["Thomas", "Per", "Anders"]
        let three = LooseRoundPlan.make(draft(friends: 0, guests: 2, scoring: .oneCard, form: "match"), names: names)
        let expected = Triangle.drawMatches(names.enumerated().map { Player(id: String($0.offset), name: $0.element) },
                                            round: 0, standing: [:])
        #expect(three.matches == expected.map { $0.compactMap { Int($0) } })
        #expect(three.matches.count == 1 && three.matches[0].count == 3)
    }

    @Test func kalletTilStartLooseRound() throws {
        var d = draft(friends: 1, guests: 1, scoring: .ownCards)
        d.guests = [.init(name: " Per ", handicapText: "+2,3")]
        let rules = LooseRoundRules.template
        let start = try #require(LooseRoundStart.make(d, course: L.course(kind: .course), names: [], rules: rules))
        #expect(start.courseID == L.courseID && start.venue == "course" && start.start)
        #expect(start.handicapAllowance == rules.allowance(for: d.form))
        #expect(start.externalHandicap == false)
        #expect(start.me == .init(bayNo: 1, isMarker: true))
        #expect(start.players == [
            .init(profileID: L.id(100), guestName: nil, handicapIndex: nil, bayNo: 2, isMarker: false),
            .init(profileID: nil, guestName: "Per", handicapIndex: -2.3, bayNo: 1, isMarker: false),
        ])
        #expect(start.ldEnabled == rules.sidePrizes.longestDrive.enabled)
        // Ikke klar: ingen kall.
        #expect(LooseRoundStart.make(d, course: nil, names: []) == nil)
    }

    @Test func regelverdieneKommerFraRegelsettet() throws {
        var rules = Ruleset.golfgutu
        rules.handicap.allowanceOverride = 0.8
        rules.handicap.externalHandicap = true
        rules.sidePrizes.longestDrive.enabled = false
        var d = LooseRoundDraft.new(rules: rules)
        d.sidePrizes = true
        let sim = try #require(LooseRoundStart.make(d, course: L.course(kind: .simulator), names: [], rules: rules))
        #expect(sim.handicapAllowance == 0.8 && sim.externalHandicap && sim.venue == "simulator")
        #expect(!sim.ldEnabled && sim.kpEnabled == rules.sidePrizes.closestToPin.enabled)
        // Trackman deler bare ut slag i simulatoren.
        let real = try #require(LooseRoundStart.make(d, course: L.course(kind: .course), names: [], rules: rules))
        #expect(!real.externalHandicap)
        d.sidePrizes = false
        let none = try #require(LooseRoundStart.make(d, course: L.course(), names: [], rules: rules))
        #expect(!none.ldEnabled && !none.kpEnabled)
    }

    @Test func jsonSomServerenLeser() throws {
        var d = draft(friends: 0, guests: 2, scoring: .oneCard, form: "match")
        d.guests = [.init(name: "Per", handicapText: "12,4"), .init(name: "Kari")]
        let start = try #require(LooseRoundStart.make(d, course: L.course(), names: ["Thomas", "Per", "Kari"]))
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(start)) as? [String: Any])
        #expect(json["course_id"] as? String == L.courseID.uuidString)
        #expect(json["format"] as? String == "match" && json["start"] as? Bool == true)
        let players = try #require(json["players"] as? [[String: Any]])
        #expect(players[0]["guest_name"] as? String == "Per" && players[0]["handicap_index"] as? Double == 12.4)
        #expect(players[1]["handicap_index"] == nil && players[1]["profile_id"] == nil)
        #expect(players[1]["bay_no"] as? Int == 1 && players[1]["is_marker"] as? Bool == false)
        let me = try #require(json["me"] as? [String: Any])
        #expect(me["bay_no"] as? Int == 1 && me["is_marker"] as? Bool == true)
        let matches = try #require(json["matches"] as? [[String: Any]])
        #expect(matches.count == 1 && matches[0]["c"] as? Int != nil)
    }
}

// MARK: - Gjesteplass og kobling

struct LosRundeBliMedTests {
    static let previewJSON = """
    {"round_id": "00000000-0000-0000-0000-000000000060", "status": "active", "hole_count": 18, "first_hole": 1,
     "format": "stableford", "venue": "course", "started_at": "2026-10-07T10:00:00+00:00",
     "course_name": "Losby", "owner_name": "Frida", "my_participant_id": null,
     "players": [
       {"participant_id": "00000000-0000-0000-0000-000000000011", "display_name": "Frida", "is_guest": false},
       {"participant_id": "00000000-0000-0000-0000-000000000012", "display_name": "Kari", "is_guest": true},
       {"participant_id": "00000000-0000-0000-0000-000000000013", "display_name": "Per", "is_guest": true}]}
    """

    static func preview(mine: UUID? = nil) throws -> InvitePreview {
        var p = try JSONDecoder().decode(InvitePreview.self, from: Data(previewJSON.utf8))
        p.myParticipantID = mine
        return p
    }

    @Test func forhandsvisningenLesesFraServeren() throws {
        let p = try Self.preview()
        #expect(p.roundID == L.roundID && p.status == .active && p.courseName == "Losby" && p.ownerName == "Frida")
        #expect(p.players.map(\.displayName) == ["Frida", "Kari", "Per"])
        #expect(p.players.filter(\.isGuest).count == 2)
        #expect(p.summary == "18 hull · Stableford (netto)")
    }

    @Test func erDuEnAvGjestene() throws {
        let p = try Self.preview()
        #expect(JoinChoice.options(p) == [.guest(L.id(12)), .guest(L.id(13)), .newPlayer])
        #expect(JoinChoice.guest(L.id(13)).title(in: p) == "Jeg er Per")
        #expect(JoinChoice.guest(L.id(13)).participantID == L.id(13))
        #expect(JoinChoice.newPlayer.participantID == nil)
    }

    @Test func gjestenMedSammeNavnForeslas() throws {
        let p = try Self.preview()
        #expect(JoinChoice.suggested(p, myName: " per ") == .guest(L.id(13)))
        #expect(JoinChoice.suggested(p, myName: "Gunnar") == .newPlayer)
        #expect(JoinChoice.suggested(p, myName: nil) == .newPlayer)
        // En profil (ikke gjest) med samme navn tas ikke.
        #expect(JoinChoice.suggested(p, myName: "Frida") == .newPlayer)
    }

    @Test func medFraFor() throws {
        let p = try Self.preview(mine: L.id(11))
        #expect(JoinChoice.options(p) == [.alreadyIn(L.id(11))])
        #expect(JoinChoice.suggested(p, myName: "Per") == .alreadyIn(L.id(11)))
        #expect(JoinChoice.alreadyIn(L.id(11)).participantID == nil)
    }

    @Test func svaretFraClaim() throws {
        let json = #"{"round_id": "00000000-0000-0000-0000-000000000060", "participant_id": "00000000-0000-0000-0000-000000000013", "joined": "guest"}"#
        let result = try JSONDecoder().decode(ClaimResult.self, from: Data(json.utf8))
        #expect(result.roundID == L.roundID && result.participantID == L.id(13) && result.joined == .guest)
    }

    /// Etter koblingen er plassen profilen: den som tok den, er den som ser på.
    @Test func koblingGjorPlassenTilDeg() {
        let before = L.snapshot([L.Seat(player: 11, name: "Frida", profile: L.me, bay: 1, marker: true),
                                 L.Seat(player: 13, name: "Per", profile: nil, bay: 1)])
        let gunnar = L.id(8)
        #expect(LooseRoundRights.viewer(info: before.loose, userID: gunnar).memberID == gunnar)
        #expect(RoundGame(before).cardPlayers(for: LooseRoundRights.viewer(info: before.loose, userID: gunnar)).isEmpty)
        let after = L.snapshot([L.Seat(player: 11, name: "Frida", profile: L.me, bay: 1, marker: true),
                                L.Seat(player: 13, name: "Gunnar", profile: gunnar, bay: 1)])
        let viewer = LooseRoundRights.viewer(info: after.loose, userID: gunnar)
        #expect(viewer == Viewer(memberID: L.id(13), isOrganizer: false))
        #expect(after.names[L.id(13)] == "Gunnar")
    }
}

// MARK: - Rettighet til å føre

struct LosRundeForingTests {
    static let gunnar = L.id(8), hege = L.id(9)

    /// Frida (eier, markør i flight 1) med gjesten Kari og Gunnar (profil) i flighten, og Hege i egen flight.
    static var round: RoundSnapshot {
        L.snapshot([
            L.Seat(player: 11, name: "Frida", profile: L.me, bay: 1, marker: true),
            L.Seat(player: 12, name: "Kari", profile: nil, bay: 1),
            L.Seat(player: 13, name: "Gunnar", profile: gunnar, bay: 1),
            L.Seat(player: 14, name: "Hege", profile: hege, bay: 2),
        ])
    }

    @Test func hvemSerPa() {
        let info = Self.round.loose
        #expect(LooseRoundRights.viewer(info: info, userID: L.me) == Viewer(memberID: L.id(11), isOrganizer: true))
        #expect(LooseRoundRights.viewer(info: info, userID: Self.hege) == Viewer(memberID: L.id(14), isOrganizer: false))
        // Eier uten å spille selv: arrangørens rett, men ikke på kortet.
        let ownerOnly = L.snapshot([L.Seat(player: 12, name: "Kari", profile: nil)])
        let viewer = LooseRoundRights.viewer(info: ownerOnly.loose, userID: L.me)
        #expect(viewer.isOrganizer && RoundGame(ownerOnly).cardPlayers(for: viewer).isEmpty)
    }

    @Test func markorenForerFlighten() {
        let game = RoundGame(Self.round)
        let frida = LooseRoundRights.viewer(info: Self.round.loose, userID: L.me)
        #expect(game.cardPlayers(for: frida) == [L.id(11), L.id(13), L.id(12)])
        #expect([L.id(11), L.id(12), L.id(13)].allSatisfy { game.cardRowEditable($0, for: frida) })
    }

    @Test func profilIFlightMedMarkorForerIkkeSelv() {
        let game = RoundGame(Self.round)
        let gunnar = LooseRoundRights.viewer(info: Self.round.loose, userID: Self.gunnar)
        #expect(!game.canScore(gunnar, for: L.id(13)))
        #expect(!game.cardRowEditable(L.id(13), for: gunnar))
        #expect(game.markerLine(for: gunnar)?.contains("Frida fører") == true)
    }

    @Test func egenFlightUtenMarkorForerSelv() {
        let game = RoundGame(Self.round)
        let hege = LooseRoundRights.viewer(info: Self.round.loose, userID: Self.hege)
        #expect(game.cardPlayers(for: hege) == [L.id(14)])
        #expect(game.canScore(hege, for: L.id(14)) && game.cardRowEditable(L.id(14), for: hege))
        #expect(!game.canScore(hege, for: L.id(12)))
        // Eieren kan rette alle (som arrangøren i en klubbrunde, og can_score i 017).
        let frida = LooseRoundRights.viewer(info: Self.round.loose, userID: L.me)
        #expect(game.canScore(frida, for: L.id(14)))
    }

    @Test func lagringSenderBareDetDuForer() throws {
        let game = RoundGame(Self.round)
        let hege = LooseRoundRights.viewer(info: Self.round.loose, userID: Self.hege)
        let submission = try #require(game.submission(hole: 0, drafts: HoleDrafts(), viewer: hege, recordedAt: .now))
        #expect(submission.entries.map(\.memberID) == [L.id(14)] && submission.roundID == L.roundID)
    }

    @Test func avsluttetRundeKanIngenForeUtenomEieren() {
        var s = Self.round
        s.round.status = .locked
        let game = RoundGame(s)
        let hege = LooseRoundRights.viewer(info: s.loose, userID: Self.hege)
        #expect(!game.canScore(hege, for: L.id(14)))
        #expect(game.canScore(LooseRoundRights.viewer(info: s.loose, userID: L.me), for: L.id(14)))
    }

    @Test func invitereOgAvslutte() {
        let info = Self.round.loose
        #expect(LooseRoundRights.canInvite(info: info, userID: L.me, status: .active))
        #expect(LooseRoundRights.canInvite(info: info, userID: Self.hege, status: .active))
        #expect(!LooseRoundRights.canInvite(info: info, userID: L.id(99), status: .active))
        #expect(!LooseRoundRights.canInvite(info: info, userID: L.me, status: .locked))
        #expect(LooseRoundRights.canFinish(info: info, userID: L.me, status: .active))
        #expect(!LooseRoundRights.canFinish(info: info, userID: Self.hege, status: .active))
        #expect(!LooseRoundRights.canFinish(info: info, userID: L.me, status: .locked))
        #expect(!LooseRoundRights.canInvite(info: nil, userID: L.me, status: .active))
    }
}

// MARK: - Mine runder

struct LosRundeMineRunderTests {
    @Test func pagaendeOgFerdigeNyesteForst() {
        let a = L.snapshot([L.Seat(player: 11, name: "Frida", profile: L.me)],
                           round: L.looseRound(status: .locked, startedAt: Date(timeIntervalSince1970: 1_000), id: L.id(61)))
        let b = L.snapshot([L.Seat(player: 21, name: "Frida", profile: L.me)],
                           round: L.looseRound(status: .locked, startedAt: Date(timeIntervalSince1970: 9_000), id: L.id(62)))
        let c = L.snapshot([L.Seat(player: 31, name: "Frida", profile: L.me)],
                           round: L.looseRound(status: .active, id: L.id(63)))
        let draft = L.snapshot([L.Seat(player: 41, name: "Frida", profile: L.me)],
                               round: L.looseRound(status: .draft, id: L.id(64)))
        let lists = MyRounds.lists([a, b, c, draft], userID: L.me)
        #expect(lists.ongoing.map(\.id) == [L.id(63)])
        #expect(lists.finished.map(\.id) == [L.id(62), L.id(61)])
    }

    @Test func resultatlinjene() {
        // To spillere, hull 1: Frida 4 (par 4, hcp 10 → 1 slag → 3 p), Per 6 (2 over netto → 0 p).
        let s = L.snapshot([L.Seat(player: 11, name: "Frida", profile: L.me, bay: 1, marker: true),
                            L.Seat(player: 12, name: "Per", profile: nil, bay: 1)],
                           round: L.looseRound(status: .locked), scores: [(11, 0, 4), (12, 0, 6)])
        let game = RoundGame(s)
        let rows = game.bayenNaa(viewer: LooseRoundRights.viewer(info: s.loose, userID: L.me))
        let item = MyRounds.item(s, userID: L.me, referenceYear: 2027)
        #expect(item.title == "Losby")
        #expect(item.mine == "Du: 1. plass · \(rows[0].total) p")
        #expect(item.leader == "Vinner: Frida · \(rows[0].total) p")
        #expect(item.subtitle.hasSuffix("18 hull · 2 spillere"))
        // Pågår: «Leder … etter 1».
        var active = s
        active.round.status = .active
        #expect(MyRounds.item(active, userID: L.me).leader == "Leder: Frida · \(rows[0].total) p etter 1")
        // Ingen har ført: ingen leder.
        var empty = s
        empty.scores = []
        #expect(MyRounds.item(empty, userID: L.me).leader == nil)
    }

    @Test func sattSammenAvRadene() {
        let round = L.looseRound()
        let course = L.course()
        let snapshots = LooseRoundQueries.assemble(
            [LooseRoundRecord(round: round, ownerID: L.me)],
            players: [RoundPlayerRow(roundID: round.id, memberID: L.id(11), clubID: nil, handicapIndex: 3, seedGroup: nil,
                                     playingHandicap: nil, bayNo: nil, isMarker: false, teamNo: nil),
                      RoundPlayerRow(roundID: L.id(99), memberID: L.id(12), clubID: nil, handicapIndex: 3, seedGroup: nil,
                                     playingHandicap: nil, bayNo: nil, isMarker: false, teamNo: nil)],
            scores: [], matches: [], holes: [],
            roster: [RoundRosterRow(roundID: round.id, playerID: L.id(11), clubID: nil, displayName: nil,
                                    profileID: L.me, isGuest: false)],
            courses: [course.course], courseHoles: course.holes)
        #expect(snapshots.count == 1)
        let s = snapshots[0]
        #expect(s.isLoose && s.players.count == 1 && s.loose?.ownerID == L.me)
        #expect(s.names[L.id(11)] == "Spiller")
        #expect(s.course?.name == "Losby" && s.courseHoles.count == 18)
        #expect(s.eventDate == LooseRoundInfo.day(round.startedAt!))
        #expect(s.rules == LooseRoundRules.template)
    }

    @Test func delingenHeterRunden() {
        let s = L.snapshot([L.Seat(player: 11, name: "Frida", profile: L.me)])
        let share = RoundGame(s).share(viewer: LooseRoundRights.viewer(info: s.loose, userID: L.me))
        #expect(share.eyebrow == "Runden" && share.title == "Losby")
    }
}

// MARK: - Rader uten klubb og banesøk

struct LosRundeRaderTests {
    @Test func losRundeUtenKlubbOgKveld() throws {
        let json = """
        {"id": "00000000-0000-0000-0000-000000000060", "club_id": null, "event_id": null, "course_id": null,
         "round_no": 1, "name": null, "status": "active", "hole_count": 18, "first_hole": 1, "tee_time": null,
         "format": "stableford", "handicap_allowance": 0.95, "external_handicap": false, "weight": 1,
         "ld_enabled": true, "ld_hole_index": null, "kp_enabled": true, "kp_hole_index": null, "cut_rule": null,
         "cut_after": null, "par_confirmed_by": null, "par_confirmed_at": null, "started_at": null, "locked_at": null,
         "owner_id": "00000000-0000-0000-0000-000000000001"}
        """
        let record = try JSONDecoder().decode(LooseRoundRecord.self, from: Data(json.utf8))
        #expect(record.round.clubID == nil && record.round.eventID == nil && record.ownerID == L.me)
        #expect(RoundSnapshot(round: record.round).isLoose)
        let player = try JSONDecoder().decode(RoundPlayerRow.self, from: Data("""
        {"round_id": "00000000-0000-0000-0000-000000000060", "member_id": "00000000-0000-0000-0000-000000000011",
         "club_id": null, "handicap_index": null, "seed_group": null, "playing_handicap": null, "bay_no": null,
         "is_marker": false, "team_no": null}
        """.utf8))
        #expect(player.clubID == nil)
    }

    @Test func klubbrundenErIkkeLos() {
        #expect(!ForingFixture.snapshot([]).isLoose)
    }

    @Test func banesokUtenStoreBokstaverOgAksenter() {
        let items = [L.course(name: "Losby Golfklubb", id: L.id(70)), L.course(name: "Bærum GK", id: L.id(71)),
                     L.course(name: "Oslo Golfklubb", id: L.id(72))]
        #expect(CourseSearch.filter(items, query: "").count == 3)
        #expect(CourseSearch.filter(items, query: "golfklubb").map(\.course.name) == ["Losby Golfklubb", "Oslo Golfklubb"])
        #expect(CourseSearch.filter(items, query: "losby golf").map(\.course.name) == ["Losby Golfklubb"])
        #expect(CourseSearch.filter(items, query: "BÆRUM").map(\.course.name) == ["Bærum GK"])
    }
}
