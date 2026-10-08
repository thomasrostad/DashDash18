import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Veddemål i appen: radene, mappingen til regelmotoren, tekstene (PWA-ens ordlyd fra
/// kveld-test.js, lockout-test.js og status-del-test.js), tavla for kortene og vedd-arket.
/// Regnestykket selv er testet i GolfgutuCore (BetsTests).
struct VeddTests {
    typealias F = ForingFixture

    static let seasonID = F.id(950)
    static let me = F.id(F.anders)
    static let bjorn = F.id(F.bjorn)
    static let cato = F.id(F.cato)

    static func member(_ n: Int, _ name: String, organizer: Bool = false) -> ClubMemberRow {
        ClubMemberRow(id: F.id(n), clubID: F.club, userID: nil, displayName: name, handicapIndex: 0, seedGroup: nil,
                      isOrganizer: organizer, isTreasurer: false, status: .active, avatarPath: nil)
    }

    static let members = [member(F.anders, "Anders"), member(F.bjorn, "Bjørn"), member(F.cato, "Cato")]
    static let players = [F.P(n: F.anders, name: "Anders"), F.P(n: F.bjorn, name: "Bjørn"), F.P(n: F.cato, name: "Cato")]

    static func bet(_ n: Int, question: String = "Påstanden", condition: BetConditionRecord? = nil, round: Bool = false,
                    creator: UUID = bjorn, against: UUID? = nil, status: Bet.Status = .open, resolution: BetSide? = nil,
                    created: String = "2026-10-08T18:00:00Z", resolvedAt: String? = nil) -> BetRow {
        BetRow(id: F.id(n), clubID: F.club, seasonID: seasonID, eventID: F.eventID,
               roundID: (round || condition != nil) ? F.roundID : nil, creatorID: creator, againstID: against,
               question: question, condition: condition, status: status, resolution: resolution, closedAt: nil,
               resolvedBy: status == .open ? nil : F.id(F.cato), resolvedAt: resolvedAt, createdAt: created)
    }

    static func stake(_ n: Int, _ bet: Int, _ member: UUID, _ side: BetSide, _ points: Int) -> BetStakeRow {
        BetStakeRow(id: F.id(n), betID: F.id(bet), clubID: F.club, memberID: member, side: side, points: points,
                    createdAt: "2026-10-08T18:0\(n % 10):00Z")
    }

    /// Runden: Anders har ført hull 1–2, Bjørn hull 1 (som kveld-test.js §3).
    static func input(bets: [BetRow] = [], stakes: [BetStakeRow] = [], rules: Ruleset = .golfgutu,
                      scores: [(Int, Int, Int)] = [(F.anders, 0, 4), (F.anders, 1, 5), (F.bjorn, 0, 5)]) -> BetsInput {
        var snapshot = F.snapshot(players, scores: scores)
        snapshot.rules = rules
        snapshot.eventDate = "2026-10-08"
        let season = SeasonRow(id: seasonID, clubID: F.club, name: "Sesong 2026", status: .active, rules: rules)
        return BetsInput(tavla: TavlaInput(season: season, members: members, rounds: [snapshot]), bets: bets, stakes: stakes)
    }

    /// 012 er kjørt på test (07.10.2026), så veddemål er slått på.
    @Test func slaattPaaEtter012() {
        #expect(BetsFeature.isEnabled)
    }

    // MARK: Radene og mappingen

    @Test func radTilRegelmotoren() {
        let row = Self.bet(1, condition: BetConditionRecord(kind: .hole, hole: 2, a: Self.bjorn, b: Self.me), against: Self.bjorn)
        let b = BetMapping.bet(row, stakes: [Self.stake(12, 1, Self.cato, .yes, 50), Self.stake(11, 1, Self.me, .no, 100),
                                             Self.stake(13, 2, Self.me, .no, 100)])
        #expect(b.id == F.id(1).uuidString)
        #expect(b.condition == BetCondition(kind: .hole, round: F.roundID.uuidString, hole: 2,
                                            a: Self.bjorn.uuidString, b: Self.me.uuidString))
        #expect(b.against == Self.bjorn.uuidString)
        // Bare innsatsene på dette veddemålet, i tidsrekkefølge.
        #expect(b.stakes.map(\.playerID) == [Self.me.uuidString, Self.cato.uuidString])
        #expect(b.stakes.map(\.points) == [100, 50])
        // Uten runde blir det ikke noe vilkår.
        #expect(BetMapping.condition(BetConditionRecord(kind: .par, hole: 1, player: Self.me), roundID: nil) == nil)
        let tilbake = BetMapping.record(b.condition!)
        #expect(tilbake == row.condition)
    }

    @Test func radeneLesesFraDatabasen() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","club_id":"00000000-0000-0000-0000-000000000900",
         "season_id":"00000000-0000-0000-0000-000000000950","event_id":null,"round_id":"00000000-0000-0000-0000-000000000901",
         "creator_id":"00000000-0000-0000-0000-000000000002","against_id":null,"question":"Bjørn holder par",
         "condition":{"kind":"par","hole":4,"player":"00000000-0000-0000-0000-000000000002"},
         "status":"void","resolution":null,"closed_at":"2026-10-08T18:00:00+00:00","resolved_by":null,
         "resolved_at":null,"created_at":"2026-10-08T17:00:00+00:00"}
        """
        let row = try JSONDecoder().decode(BetRow.self, from: Data(json.utf8))
        #expect(row.status == .void)
        #expect(row.condition == BetConditionRecord(kind: .par, hole: 4, player: Self.bjorn))
        let stake = try JSONDecoder().decode(BetStakeRow.self, from: Data("""
        {"id":"00000000-0000-0000-0000-000000000011","bet_id":"00000000-0000-0000-0000-000000000001",
         "club_id":"00000000-0000-0000-0000-000000000900","member_id":"00000000-0000-0000-0000-000000000001",
         "side":"no","points":100,"created_at":"2026-10-08T17:00:00+00:00"}
        """.utf8))
        #expect(stake.side == .no && stake.points == 100)
    }

    /// Vilkåret skrives uten tomme nøkler (databasen skiller på om nøkkelen finnes), og
    /// `create_bet` får alle argumentene, også de tomme.
    @Test func rpcParametrene() throws {
        let record = BetConditionRecord(kind: .birdie, hole: 4)
        let c = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any]
        #expect(Set(c?.keys.map { $0 } ?? []) == ["kind", "hole"])
        let par = BetConditionRecord(kind: .par, hole: 4, player: Self.bjorn)
        let p = try JSONSerialization.jsonObject(with: JSONEncoder().encode(par)) as? [String: Any]
        #expect(p?["player"] as? String == Self.bjorn.uuidString.lowercased())

        let params = CreateBetParams(clubID: F.club, roundID: nil, eventID: nil, question: "Bjørn kommer på pallen",
                                     condition: nil, against: Self.bjorn, side: .no, points: 100)
        let o = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any]
        #expect(Set(o?.keys.map { $0 } ?? []) == ["p_club_id", "p_round_id", "p_event_id", "p_question", "p_condition",
                                                  "p_against", "p_side", "p_points"])
        #expect(o?["p_round_id"] is NSNull)
        #expect(o?["p_condition"] is NSNull)
        #expect(o?["p_side"] as? String == "no")
        #expect(o?["p_points"] as? Int == 100)
    }

    // MARK: Tekstene

    /// Malene med PWA-ens ordlyd (kveld-test.js §4, README «Vedd på de andre»).
    @Test func malteksteneErSomPWA() {
        let duel = BetTemplate(kind: .holeDuel, condition: BetCondition(kind: .hole, round: "r", hole: 2, a: "b", b: "a"), side: .no)
        #expect(BetTexts.template(duel, me: "Anders", him: "Bjørn", roundName: "Runde 1") == "Bjørn slår Anders netto på hull 3")
        let par = BetTemplate(kind: .par, condition: BetCondition(kind: .par, round: "r", hole: 9, player: "b"), side: .no)
        #expect(BetTexts.template(par, me: "Anders", him: "Bjørn", roundName: nil) == "Bjørn holder par eller bedre på hull 10")
        let beats = BetTemplate(kind: .beats, condition: nil, side: .no)
        #expect(BetTexts.template(beats, me: "Anders", him: "Bjørn", roundName: "Runde 6") == "Bjørn slår Anders netto i Runde 6")
        #expect(BetTexts.template(beats, me: "Anders", him: "Bjørn", roundName: nil) == "Bjørn slår Anders netto i neste runde")
        let podium = BetTemplate(kind: .podium, condition: nil, side: .no)
        #expect(BetTexts.template(podium, me: "Anders", him: "Bjørn", roundName: nil) == "Bjørn kommer på pallen i neste runde")
        let any = BetTemplate(kind: .anyBirdie, condition: BetCondition(kind: .birdie, round: "r", hole: 6), side: .yes)
        #expect(BetTexts.template(any, me: "Anders", him: nil, roundName: nil) == "Noen får birdie på hull 7")
        #expect(BetTexts.template(BetTemplate(kind: .seasonPodium, condition: nil, side: .yes), me: "Anders", him: nil,
                                  roundName: nil) == "Anders kommer på pallen i turneringen")
        #expect(BetTexts.side(.yes, against: "Bjørn Berg") == "Ja, Bjørn gjør det")
        #expect(BetTexts.side(.yes, against: nil) == "Ja, det skjer")
        #expect(BetTexts.side(.no, against: "Bjørn") == "Nei, jeg vinner")
    }

    /// status-del-test.js C7: én betydning per pille, aldri «Lukket».
    @Test func statuspillene() {
        #expect(BetTexts.phase(.open) == "Åpent")
        #expect(BetTexts.phase(.closed) == "Stengt")
        #expect(BetTexts.phase(.resolvedYes) == "Avgjort · JA")
        #expect(BetTexts.phase(.resolvedNo) == "Avgjort · NEI")
        #expect(BetTexts.phase(.void) == "Annullert")
    }

    /// lockout-test.js §6: meldingen sier hvilket hull som er neste.
    @Test func hvorforDetErStengt() {
        let round = Round(id: "r1", holeCount: 18, holeScores: ["a": [0: 4, 1: 4, 2: 4, 3: 4, 4: 4, 5: 4]])
        let bet = Bet(condition: BetCondition(kind: .par, round: "r1", hole: 6, player: "a"))
        #expect(BetTexts.closedReason(bet, round: round, rules: .golfgutu)
                == "Hull 7 spilles nå. Neste hull du kan satse på er hull 8.")
        let slaar = Bet(condition: BetCondition(kind: .beats, round: "r1", a: "a", b: "b"))
        #expect(BetTexts.closedReason(slaar, round: round, rules: .golfgutu) == "Runden er i gang – det er ikke lenger en spådom.")
        var laast = round
        laast.locked = true
        #expect(BetTexts.closedReason(bet, round: laast, rules: .golfgutu) == "Runden er ferdig – veddemålet gjøres opp.")
        #expect(BetTexts.closedReason(Bet(status: .resolved, resolution: .yes), round: nil, rules: .golfgutu) == "Veddemålet er avgjort.")
        #expect(BetTexts.problem(.overCap(max: 200, already: 150), closedReason: "") == "Maks 200 poeng per veddemål. Du har 150 på det fra før.")
        #expect(BetTexts.problem(.overCap(max: 200, already: 0), closedReason: "") == "Maks 200 poeng per veddemål.")
        #expect(BetTexts.problem(.insufficient(available: 30), closedReason: "") == "Du har 30 ledige poeng.")
        #expect(BetTexts.problem(.otherSide(.no), closedReason: "") == "Du har alt satset NEI på dette.")
        #expect(BetTexts.signed(33.333) == "+33,33")
        #expect(BetTexts.signed(-50) == "−50")
        #expect(BetTexts.signed(0) == "0")
    }

    // MARK: Tavla for kortene

    @Test func kortenesRekkefolgeOgResultat() throws {
        let bets = [
            // Rettet mot meg, fri tekst, uten innsats fra meg: øverst.
            Self.bet(1, question: "Anders kommer på pallen", against: Self.me, created: "2026-10-08T18:01:00Z"),
            // Mitt: jeg har satset.
            Self.bet(2, question: "Cato vinner runden", creator: Self.cato, created: "2026-10-08T18:02:00Z"),
            // Andres, hullveddemål som er stengt (Bjørn står på hull 2, hull 2 er stengt).
            Self.bet(3, question: "Bjørn holder par på hull 2", condition: BetConditionRecord(kind: .par, hole: 1, player: Self.bjorn),
                     created: "2026-10-08T18:03:00Z"),
            // Avgjort: jeg vant 50 fra Cato.
            Self.bet(4, question: "Bjørn slår Cato", round: true, status: .resolved, resolution: .yes,
                     resolvedAt: "2026-10-08T19:00:00Z"),
        ]
        let stakes = [
            Self.stake(11, 1, Self.bjorn, .yes, 100),
            Self.stake(12, 2, Self.me, .no, 100), Self.stake(13, 2, Self.cato, .yes, 50),
            Self.stake(14, 3, Self.cato, .no, 50),
            Self.stake(15, 4, Self.me, .yes, 100), Self.stake(16, 4, Self.cato, .no, 50),
        ]
        let board = BetsBoard(Self.input(bets: bets, stakes: stakes), me: Self.me, isOrganizer: false)
        #expect(board.challenged.map(\.id) == [F.id(1)])
        #expect(board.mine.map(\.id) == [F.id(2)])
        #expect(board.others.map(\.id) == [F.id(3)])
        #expect(board.settled.map(\.id) == [F.id(4)])
        #expect(board.openCount == 3)

        let mine = try #require(board.item(F.id(2)))
        #expect(mine.mySide == BetSide.no && mine.myPoints == 100)
        #expect(mine.yesPool == 50 && mine.noPool == 100)
        #expect(mine.phase == .open)

        let closed = try #require(board.item(F.id(3)))
        #expect(closed.phase == .closed)
        #expect(closed.closedReason == "Hull 2 spilles nå. Neste hull du kan satse på er hull 3.")

        let settled = try #require(board.item(F.id(4)))
        #expect(settled.myResult == 50)
        #expect(settled.phase == .resolvedYes)
        #expect(settled.resolvedByName == "Cato")
        #expect(settled.stakers.map(\.name) == ["Anders", "Cato"])

        // Poengtabellen: start 1000. Anders +50, 200 ute. Cato −50, 100 ute. Bjørn 100 ute.
        #expect(board.table.map(\.row.name) == ["Anders", "Bjørn", "Cato"])
        let anders = try #require(board.myRow)
        #expect(anders.balance == 1050 && anders.atStake == 100 && anders.available == 950)
        #expect(board.table[0].isMe)
        #expect(board.table.last?.row.balance == 950)
        // Ingen feiing for en spiller.
        #expect(board.sweepPlan.isEmpty)
    }

    /// Arrangørens telefon avgjør det vilkårene gir svar på, og ingenting annet.
    @Test func feiingenPaaArrangorensTelefon() {
        let bets = [
            // Anders har ført hull 2 med 5 slag på par 5: par → JA.
            Self.bet(1, condition: BetConditionRecord(kind: .par, hole: 1, player: Self.me)),
            // Hull 6 er ikke ført: ingen svar ennå.
            Self.bet(2, condition: BetConditionRecord(kind: .par, hole: 5, player: Self.me)),
            // Fri tekst: arrangøren tar den for hånd.
            Self.bet(3),
        ]
        let board = BetsBoard(Self.input(bets: bets), me: Self.cato, isOrganizer: true)
        #expect(board.sweepPlan.map(\.betID) == [F.id(1)])
        #expect(board.sweepPlan.map(\.verdict) == [.yes])
        #expect(board.item(F.id(3))?.needsOrganizer == true)
        #expect(board.item(F.id(2))?.needsOrganizer == false)
    }

    /// Delt hull annulleres av feiingen (besluttet 07.10.2026), også når arrangøren selv har
    /// satset: det er scorene som avgjør. Med PWA-ens regler venter det på arrangøren.
    @Test func deltHullAnnulleresAvFeiingen() {
        let bets = [Self.bet(1, condition: BetConditionRecord(kind: .hole, hole: 0, a: Self.bjorn, b: Self.me))]
        let stakes = [Self.stake(11, 1, Self.cato, .yes, 50), Self.stake(12, 1, Self.me, .no, 50)]
        let scores = [(F.anders, 0, 4), (F.bjorn, 0, 4)]
        let board = BetsBoard(Self.input(bets: bets, stakes: stakes, scores: scores), me: Self.cato, isOrganizer: true)
        #expect(board.sweepPlan.map(\.betID) == [F.id(1)])
        #expect(board.sweepPlan.map(\.verdict) == [.void])
        #expect(board.item(F.id(1))?.needsOrganizer == false)
        var pwa = Ruleset.golfgutu
        pwa.bets = .pwa
        let manuell = BetsBoard(Self.input(bets: bets, stakes: stakes, rules: pwa, scores: scores), me: Self.cato, isOrganizer: true)
        #expect(manuell.sweepPlan.isEmpty)
        #expect(manuell.item(F.id(1))?.needsOrganizer == true)
    }

    /// Den som avgjør, vedder ikke: «Avgjør» bare for en arrangør uten innsats.
    @Test func arrangorenMedInnsatsKanIkkeAvgjore() throws {
        let bets = [Self.bet(1), Self.bet(2)]
        let stakes = [Self.stake(11, 1, Self.cato, .yes, 50), Self.stake(12, 2, Self.me, .no, 50)]
        let cato = BetsBoard(Self.input(bets: bets, stakes: stakes), me: Self.cato, isOrganizer: true)
        let medInnsats = try #require(cato.item(F.id(1)))
        #expect(!medInnsats.canResolve && medInnsats.resolverHasStake)
        let utenInnsats = try #require(cato.item(F.id(2)))
        #expect(utenInnsats.canResolve && !utenInnsats.resolverHasStake)
        // En spiller avgjør aldri, med eller uten innsats.
        let anders = BetsBoard(Self.input(bets: bets, stakes: stakes), me: Self.me, isOrganizer: false)
        #expect(anders.item(F.id(1))?.canResolve == false && anders.item(F.id(2))?.canResolve == false)
        #expect(anders.item(F.id(2))?.resolverHasStake == false)
        #expect(BetTexts.resolverHasStake.contains("En annen arrangør"))
        #expect(BetTexts.resolvedBy("Cato") == "avgjort av Cato")
        #expect(BetTexts.resolvedBy(nil) == "avgjort av scorene")
    }

    /// Hele poeng: Bjørns 100 delt på Anders (100) og Cato (50) blir hele tall, og
    /// summen i poengtabellen er startbeholdningen ganger antall spillere.
    @Test func helePoengITabellen() throws {
        let bets = [Self.bet(1, status: .resolved, resolution: .yes, resolvedAt: "2026-10-08T19:00:00Z")]
        let stakes = [Self.stake(11, 1, Self.me, .yes, 100), Self.stake(12, 1, Self.cato, .yes, 50),
                      Self.stake(13, 1, Self.bjorn, .no, 100)]
        let board = BetsBoard(Self.input(bets: bets, stakes: stakes), me: Self.me, isOrganizer: false)
        // 100 · 100/150 = 66,67 → 67, 100 · 50/150 = 33,33 → 33.
        #expect(board.item(F.id(1))?.myResult == 67)
        #expect(board.table.map(\.row.net) == [67, 33, -100])
        #expect(board.table.reduce(0) { $0 + ($1.row.balance ?? 0) } == 3000)
    }

    // MARK: Vedd-arket

    /// kveld-test.js §4: mot Bjørn midt i runden er første mal duellen på hull 3, så par, så pallen.
    @Test func arketMotEnSpiller() {
        let board = BetsBoard(Self.input(scores: [(F.anders, 0, 4), (F.bjorn, 0, 5)]), me: Self.me, isOrganizer: false)
        var draft = BetSheetDraft(board: board, against: Self.bjorn, game: board.activeGame)
        #expect(draft.title == "Vedd på Bjørn")
        #expect(draft.options.map(\.template.kind) == [.holeDuel, .par, .podium])
        #expect(draft.options.map(\.text) == ["Bjørn slår Anders netto på hull 3", "Bjørn holder par eller bedre på hull 3",
                                              "Bjørn kommer på pallen i Runde 1"])
        #expect(draft.side == .no)
        #expect(draft.points == 100)
        #expect(draft.buttonTitle == "Sats 100 poeng på NEI")
        #expect(draft.problem(board: board) == nil)

        let params = draft.params(clubID: F.club)
        #expect(params.roundID == F.roundID)
        #expect(params.eventID == nil)
        #expect(params.against == Self.bjorn)
        #expect(params.condition == BetConditionRecord(kind: .hole, hole: 2, a: Self.bjorn, b: Self.me))
        #expect(params.question == "Bjørn slår Anders netto på hull 3")

        draft.points = 250
        #expect(draft.problem(board: board) == "Maks 200 poeng per veddemål.")
        draft.points = 50
        draft.select(nil)
        draft.customText = " ja "
        #expect(draft.problem(board: board) == "Skriv en tydelig påstand.")
        draft.customText = "Bjørn bommer på greenen på hull 4"
        #expect(draft.problem(board: board) == nil)
        #expect(draft.params(clubID: F.club).condition == nil)
        draft.select(2)
        #expect(draft.side == .no)
    }

    @Test func arketOmDegSelvOgUtenBank() {
        var rules = Ruleset.golfgutu
        rules.bets.startingPoints = 120
        let board = BetsBoard(Self.input(stakes: [], rules: rules), me: Self.me, isOrganizer: false)
        var draft = BetSheetDraft(board: board, against: nil, game: board.activeGame)
        #expect(draft.title == "Vedd på deg selv")
        #expect(draft.options.map(\.template.kind) == [.myBirdie, .anyBirdie, .myPar])
        #expect(draft.options.first?.text == "Anders får birdie på hull 4")
        #expect(draft.side == .yes)
        draft.points = 200
        #expect(draft.problem(board: board) == "Du har 120 ledige poeng.")
        draft.points = 100
        #expect(draft.problem(board: board) == nil)
    }

    @Test func innsatsPaaEtKort() throws {
        let bets = [Self.bet(1, question: "Cato vinner runden", creator: Self.cato)]
        let board = BetsBoard(Self.input(bets: bets, stakes: [Self.stake(11, 1, Self.me, .no, 150)]), me: Self.me,
                              isOrganizer: false)
        let item = try #require(board.item(F.id(1)))
        #expect(BetStakeCheck.problem(item, side: .no, points: 50, board: board) == nil)
        #expect(BetStakeCheck.problem(item, side: .no, points: 100, board: board)
                == "Maks 200 poeng per veddemål. Du har 150 på det fra før.")
        #expect(BetStakeCheck.problem(item, side: .yes, points: 50, board: board) == "Du har alt satset NEI på dette.")
    }
}
