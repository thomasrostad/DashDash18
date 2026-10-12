import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Veddemål overalt (steg 11, sql/052): bank per turnering eller runde, personer som medlem eller
/// profil (`person_key`), på/av (`bets_enabled`) og serverens oppgjør (feiingen er bare reserve).
struct VeddOverallTests {
    typealias F = ForingFixture
    typealias V = VeddTests

    static let competition = F.id(960)
    /// Profilene bak deltakerne i en løs runde (deltaker-id F.id(1…3)).
    static let annaProfil = F.id(101)
    static let bjarteProfil = F.id(102)

    static func looseRound(status: RoundStatus = .active, lockedAt: Date? = nil) -> RoundRow {
        RoundRow(id: F.roundID, clubID: nil, eventID: nil, courseID: F.courseID, roundNo: 1, name: nil,
                 status: status, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                 handicapAllowance: 1, externalHandicap: false, weight: 1,
                 ldEnabled: true, ldHoleIndex: nil, kpEnabled: true, kpHoleIndex: nil,
                 cutRule: nil, cutAfter: nil, parConfirmedBy: nil, parConfirmedAt: Date(timeIntervalSince1970: 0),
                 startedAt: nil, lockedAt: lockedAt)
    }

    /// Løs runde: Anna og Bjarte med profil, Gjest uten.
    static func looseSnapshot(status: RoundStatus = .active, lockedAt: Date? = nil,
                              scores: [(Int, Int, Int)] = []) -> RoundSnapshot {
        var s = F.snapshot([F.P(n: 1, name: "Anna"), F.P(n: 2, name: "Bjarte"), F.P(n: 3, name: "Gjest")],
                           round: looseRound(status: status, lockedAt: lockedAt), scores: scores)
        s.loose = LooseRoundInfo(ownerID: annaProfil, roster: [
            RoundRosterRow(roundID: F.roundID, playerID: F.id(1), clubID: nil, displayName: "Anna", profileID: annaProfil, isGuest: false),
            RoundRosterRow(roundID: F.roundID, playerID: F.id(2), clubID: nil, displayName: "Bjarte", profileID: bjarteProfil, isGuest: false),
            RoundRosterRow(roundID: F.roundID, playerID: F.id(3), clubID: nil, displayName: "Gjest", profileID: nil, isGuest: true),
        ])
        return s
    }

    static func profileStake(_ n: Int, _ bet: Int, _ profile: UUID, _ side: BetSide, _ points: Int) -> BetStakeRow {
        BetStakeRow(id: F.id(n), betID: F.id(bet), clubID: nil, memberID: nil, side: side, points: points,
                    createdAt: "2026-10-12T18:0\(n % 10):00Z", profileID: profile, personKey: profile)
    }

    static func roundBet(_ n: Int, creator: UUID, against: UUID? = nil, condition: BetConditionRecord? = nil,
                         status: Bet.Status = .open, resolution: BetSide? = nil) -> BetRow {
        BetRow(id: F.id(n), clubID: nil, seasonID: nil, eventID: nil, roundID: F.roundID, creatorID: nil, againstID: nil,
               question: "Påstanden", condition: condition, status: status, resolution: resolution, closedAt: nil,
               resolvedBy: nil, resolvedAt: status == .open ? nil : "2026-10-12T20:00:00Z", createdAt: "2026-10-12T18:00:00Z",
               roundScope: F.roundID, creatorProfileID: creator, againstProfileID: against)
    }

    // MARK: Lasting og bank

    @Test func bankenSendesSomTurneringEllerRunde() throws {
        func json(_ value: some Encodable) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        }
        let c = try json(BetScopeParams(.competition(Self.competition)))
        #expect(c["p_competition_id"] as? String == Self.competition.uuidString)
        #expect(c["p_round_id"] is NSNull)
        let r = try json(BetScopeParams(.round(F.roundID)))
        #expect(r["p_competition_id"] is NSNull)
        #expect(r["p_round_id"] as? String == F.roundID.uuidString)

        let on = try json(BetsSetEnabledParams(scope: .round(F.roundID), enabled: true))
        #expect(Set(on.keys) == ["p_competition_id", "p_round_id", "p_enabled"])
        #expect(on["p_enabled"] as? Bool == true)

        let v2 = try json(CreateBetV2Params(competitionID: nil, roundID: F.roundID, question: "Q", condition: nil,
                                            againstMember: nil, againstProfile: Self.bjarteProfil, side: .no, points: 50))
        #expect(Set(v2.keys) == ["p_competition_id", "p_round_id", "p_question", "p_condition", "p_against_member",
                                 "p_against_profile", "p_side", "p_points"])
        #expect(v2["p_against_profile"] as? String == Self.bjarteProfil.uuidString)
        #expect(v2["p_against_member"] is NSNull)
    }

    @Test func radeneMed052() throws {
        let row = try JSONDecoder().decode(BetRow.self, from: Data("""
        {"id":"00000000-0000-0000-0000-000000000001","club_id":null,"season_id":null,"event_id":null,
         "round_id":"00000000-0000-0000-0000-000000000901","creator_id":null,"against_id":null,"question":"Q",
         "condition":null,"status":"resolved","resolution":"yes","closed_at":null,"resolved_by":null,
         "resolved_at":"2026-10-12T20:00:00+00:00","created_at":"2026-10-12T18:00:00+00:00",
         "competition_id":null,"round_scope":"00000000-0000-0000-0000-000000000901",
         "creator_profile_id":"00000000-0000-0000-0000-000000000101","against_profile_id":"00000000-0000-0000-0000-000000000102",
         "resolved_by_profile":null}
        """.utf8))
        #expect(row.clubID == nil && row.seasonID == nil)
        #expect(row.roundScope == F.roundID)
        #expect(row.creator == Self.annaProfil)
        #expect(row.against == Self.bjarteProfil)
        #expect(row.resolver == nil)

        // person_key går foran; den blir stående når kontoen er slettet (profile_id tom).
        let deleted = BetStakeRow(id: F.id(11), betID: F.id(1), clubID: nil, memberID: nil, side: .yes, points: 10,
                                  createdAt: "x", profileID: nil, personKey: Self.annaProfil)
        #expect(deleted.person == Self.annaProfil)
        let old = BetStakeRow(id: F.id(12), betID: F.id(1), clubID: F.club, memberID: V.me, side: .yes, points: 10, createdAt: "x")
        #expect(old.person == V.me)
        #expect(BetStakeRow.columnsV2.hasSuffix("profile_id, person_key"))
        #expect(BetRow.columnsV2.contains("round_scope"))
    }

    @Test func bankeneEnRundeKanVeddeI() {
        let options = BetScopeChoice.options(
            competitions: [.init(id: F.id(1), name: "Sommerligaen", enabled: true),
                           .init(id: F.id(2), name: "Morro", enabled: false),
                           .init(id: F.id(3), name: "Høstcupen", enabled: true),
                           .init(id: F.id(1), name: "Sommerligaen", enabled: true)],
            roundID: F.roundID, roundEnabled: true, roundName: "Testbanen")
        #expect(options.map(\.name) == ["Høstcupen", "Sommerligaen", "Testbanen"])
        #expect(options.last?.scope == .round(F.roundID))
        #expect(BetScopeChoice.options(competitions: [.init(id: F.id(2), name: "Morro", enabled: false)],
                                       roundID: F.roundID, roundEnabled: false, roundName: "R").isEmpty)
    }

    // MARK: Personer (person_key)

    @Test func duErMedlemmetIKlubbenEllersProfilen() {
        let me = F.id(77)
        #expect(BetIdentity.me(clubID: F.club, memberships: [F.club: V.me], userID: me) == V.me)
        #expect(BetIdentity.me(clubID: F.id(999), memberships: [F.club: V.me], userID: me) == me)
        #expect(BetIdentity.me(clubID: nil, memberships: [F.club: V.me], userID: me) == me)
    }

    @Test func losRundeNoklerPaaProfilen() throws {
        let bets = [Self.roundBet(1, creator: Self.bjarteProfil, against: Self.annaProfil, status: .resolved, resolution: .no)]
        let stakes = [Self.profileStake(11, 1, Self.annaProfil, .no, 100), Self.profileStake(12, 1, Self.bjarteProfil, .yes, 100)]
        let input = BetsAssembly.round(Self.looseSnapshot(), bets: bets, stakes: stakes)
        #expect(input.scope == .round(F.roundID))
        #expect(input.people.map(\.id) == [Self.annaProfil, Self.bjarteProfil])
        #expect(input.people.allSatisfy { $0.kind == .profile })
        #expect(input.person(ofPlayer: F.id(2)) == Self.bjarteProfil)
        #expect(input.ownerID == Self.annaProfil && input.clubID == nil)

        let viewer = BetViewer(userID: Self.annaProfil)
        let board = BetsBoard(input, me: viewer.me(in: input), isOrganizer: viewer.canResolve(input))
        #expect(board.me == Self.annaProfil)
        #expect(board.isOrganizer)
        let item = try #require(board.item(F.id(1)))
        #expect(item.creatorName == "Bjarte")
        #expect(item.againstName == "Anna")
        #expect(item.myResult == 100)
        #expect(item.stakers.map(\.name).sorted() == ["Anna", "Bjarte"])
        #expect(board.table.map(\.row.name) == ["Anna", "Bjarte"])
        #expect(board.table.map(\.row.net) == [100, -100])
        #expect(board.table.first?.isMe == true)
        // Bjarte vedder på Anna: vilkåret bruker deltaker-id-ene i runden, motparten er profilen.
        #expect(board.opponents(in: board.activeGame) == [Self.bjarteProfil])
        let bjarteBoard = BetsBoard(input, me: Self.bjarteProfil, isOrganizer: false)
        let draft = BetSheetDraft(board: bjarteBoard, against: Self.annaProfil, game: bjarteBoard.activeGame)
        #expect(draft.title == "Vedd på Anna")
        let params = draft.params(scope: .round(F.roundID))
        #expect(params.competitionID == nil && params.roundID == F.roundID)
        #expect(params.againstProfile == Self.annaProfil && params.againstMember == nil)
        #expect(params.condition?.a == F.id(1))
        #expect(params.condition?.b == F.id(2))
    }

    @Test func turneringMedProfilerOgMedlemmer() {
        let comp = CompetitionRow(id: Self.competition, kind: .league, name: "Høstligaen", clubID: F.club, ownerID: nil,
                                  seasonID: nil, status: .active, entry: .listed, rules: .golfgutu, startsOn: nil,
                                  endsOn: nil, isMain: false, requiresPurchase: false, entitlementID: nil)
        // Anders er medlem; Bjarte er påmeldt som profil fra en løs runde.
        let directory = PersonDirectory(members: [V.member(F.anders, "Anders")],
                                        participants: [RoundParticipantRow(id: F.id(2), roundID: F.roundID,
                                                                           profileID: Self.bjarteProfil,
                                                                           displayName: "Bjarte", handicapIndex: 0)],
                                        profiles: [ProfileRow(id: Self.bjarteProfil, displayName: "Bjarte B",
                                                              handicapIndex: 0, avatarPath: nil)])
        let snapshot = F.snapshot([F.P(n: F.anders, name: "Anders"), F.P(n: 2, name: "Bjarte")])
        let input = BetsAssembly.competition(comp, rounds: [snapshot],
                                             entrants: [.member(V.me), .profile(Self.bjarteProfil), .guest(F.id(3))],
                                             directory: directory)
        #expect(input.scope == .competition(Self.competition))
        #expect(input.people.map(\.kind) == [.member, .profile])
        #expect(input.people.map(\.name) == ["Anders", "Bjarte B"])
        #expect(input.person(ofPlayer: F.id(2)) == Self.bjarteProfil)
        #expect(input.person(ofPlayer: V.me) == V.me)
        let board = BetsBoard(input, me: V.me, isOrganizer: false)
        let draft = BetSheetDraft(board: board, against: Self.bjarteProfil, game: board.activeGame)
        let params = draft.params(scope: .competition(Self.competition))
        #expect(params.competitionID == Self.competition && params.roundID == F.roundID)
        #expect(params.againstProfile == Self.bjarteProfil)
    }

    // MARK: På og av

    @Test func avSomStandardStopperNyeVeddemaal() {
        var input = BetsAssembly.round(Self.looseSnapshot(), enabled: false)
        let board = BetsBoard(input, me: Self.annaProfil, isOrganizer: true)
        #expect(!board.enabled)
        let draft = BetSheetDraft(board: board, against: nil, game: board.activeGame)
        #expect(draft.problem(board: board) == BetTexts.notEnabled)
        input.enabled = true
        let on = BetsBoard(input, me: Self.annaProfil, isOrganizer: true)
        #expect(BetSheetDraft(board: on, against: nil, game: on.activeGame).problem(board: on) == nil)
    }

    @Test func hvemSlaarPaaOgAvgjor() {
        let me = F.id(77)
        let loose = BetsAssembly.round(Self.looseSnapshot())
        #expect(BetViewer(userID: Self.annaProfil).canToggle(loose))
        #expect(!BetViewer(userID: me).canToggle(loose))
        #expect(!BetViewer(userID: me).canResolve(loose))

        let season = BetsInput(tavla: V.input().tavlaInput, scope: .competition(Self.competition))
        let organizer = BetViewer(userID: me, memberships: [F.club: V.cato], moneyClubs: [F.club], organizerClubs: [F.club])
        let player = BetViewer(userID: me, memberships: [F.club: V.me])
        #expect(organizer.canToggle(season) && organizer.canResolve(season))
        #expect(!player.canToggle(season) && !player.canResolve(season))
        #expect(player.me(in: season) == V.me)
        // Før 052 er det ingen bryter.
        let legacy = BetsInput(tavla: V.input().tavlaInput)
        #expect(!organizer.canToggle(legacy) && organizer.canResolve(legacy))
    }

    // MARK: Oppgjøret på serveren

    @Test func hjemFeierIkkeNaarServerenGjorOpp() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(BetSweep.isDue(last: nil, now: now))
        #expect(!BetSweep.isDue(last: nil, now: now, serverSettles: true))
        #expect(!BetSweep.isDue(last: now.addingTimeInterval(-60), now: now))
        #expect(BetSweep.phoneMaySettle(roundLocked: false, lockedAt: nil, now: now, serverSettles: false))
        #expect(!BetSweep.phoneMaySettle(roundLocked: false, lockedAt: nil, now: now, serverSettles: true))
        #expect(!BetSweep.phoneMaySettle(roundLocked: true, lockedAt: now.addingTimeInterval(-60), now: now, serverSettles: true))
        #expect(BetSweep.phoneMaySettle(roundLocked: true, lockedAt: now.addingTimeInterval(-31 * 60), now: now, serverSettles: true))
    }

    /// Anna fikk birdie på hull 1 (par 4, 3 slag): vilkåret er avgjort. Telefonen avgjør bare når
    /// serveren skulle vært ferdig.
    @Test func feiingenErBareReserve() {
        let bet = Self.roundBet(1, creator: Self.bjarteProfil, condition: BetConditionRecord(kind: .birdie, hole: 0, player: F.id(1)))
        let now = Date()
        func plan(_ status: RoundStatus, lockedAt: Date?, server: Bool) -> [UUID] {
            var input = BetsAssembly.round(Self.looseSnapshot(status: status, lockedAt: lockedAt, scores: [(1, 0, 3), (2, 0, 4)]),
                                           bets: [bet])
            if !server { input.scope = nil }
            return BetsBoard(input, me: Self.annaProfil, isOrganizer: true).sweepPlan(now: now).map(\.betID)
        }
        #expect(plan(.active, lockedAt: nil, server: false) == [F.id(1)])
        #expect(plan(.active, lockedAt: nil, server: true).isEmpty)
        #expect(plan(.locked, lockedAt: now.addingTimeInterval(-60), server: true).isEmpty)
        #expect(plan(.locked, lockedAt: now.addingTimeInterval(-3600), server: true) == [F.id(1)])
    }

    @Test func avgjortAvScorene() throws {
        let data = try JSONDecoder().decode(ActivityData.self, from: Data(#"{"question":"Q","resolution":"yes","auto":true,"server":true}"#.utf8))
        let event = ActivityEvent(kind: "bet_resolved", data: data)
        #expect(event == .betResolved(question: "Q", resolution: "yes", server: true))
        #expect(event.data.server == true)
        #expect(ActivityEvent.betResolved(question: "Q", resolution: "no").data.server == nil)
        func text(_ e: ActivityEvent) -> String { ActivityText.display(e, actor: nil, name: { _ in nil }).text }
        #expect(text(event) == "Avgjort av scorene: «Q» → JA")
        #expect(text(.betResolved(question: "Q", resolution: "void", server: true)) == "Annullert av scorene: «Q»")
        #expect(text(.betResolved(question: "Q", resolution: "no")) == "Veddemål avgjort: «Q» → NEI")
    }
}

extension BetsInput {
    /// Sesongen tilbake som Tavla-grunnlag (bare for testene).
    fileprivate var tavlaInput: TavlaInput {
        TavlaInput(season: SeasonRow(id: VeddTests.seasonID, clubID: clubID ?? ForingFixture.club, name: title,
                                     status: .active, rules: rules),
                   members: VeddTests.members, rounds: rounds)
    }
}
