import Foundation
import Testing
@testable import DashDash18

// Steg 10 (sql/051): «Del regningen» lagret (delene, status, tilbake fra Vipps) og kalenderlenken.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

struct RegningDelingTests {
    @Test func mottakerensDelStaarForSegOgSummenStemmer() {
        let plan = BillSplit.plan(total: NOK(ore: 100_000), people: ["Thomas", "Anders", "Bjørn", "Carl"], payer: "Thomas")
        #expect(plan.payeeShare.ore == 25_000)
        #expect(plan.shares.map(\.name) == ["Anders", "Bjørn", "Carl"])
        #expect(plan.shares.map(\.amount.ore) == [25_000, 25_000, 25_000])
        #expect(plan.sum == 100_000)
    }

    @Test func restOreFraToppenOgSammeSomVisningen() {
        // 1000,01 kr på tre: én øre til den første.
        let plan = BillSplit.plan(total: NOK(ore: 100_001), people: ["A", "B", "C"], payer: "A")
        #expect(plan.payeeShare.ore == 33_334)
        #expect(plan.shares.map(\.amount.ore) == [33_334, 33_333])
        #expect(plan.sum == 100_001)
        // Delene de andre ser, er de samme som i lista «Hver betaler».
        #expect(plan.shares == BillSplit.shares(total: NOK(ore: 100_001), people: ["A", "B", "C"], payer: "A"))
        // Mottakeren sist: hen får ingen ekstra øre.
        let last = BillSplit.plan(total: NOK(ore: 1_000), people: ["A", "B", "C"], payer: "C")
        #expect(last.shares.map(\.amount.ore) == [334, 333])
        #expect(last.payeeShare.ore == 333)
    }

    @Test func mottakerSomIkkeDelerFaarNull() {
        let plan = BillSplit.plan(total: NOK(ore: 999), people: ["B", "C"], payer: "A")
        #expect(plan.payeeShare.ore == 0)
        #expect(plan.shares.map(\.amount.ore) == [500, 499])
        #expect(plan.sum == 999)
    }

    @Test(arguments: [1, 2, 7, 99, 100, 101, 12_345, 100_000_000])
    func summenErAltidEksaktIOre(_ ore: Int) {
        for count in 1...13 {
            let people = (0..<count).map { "P\($0)" }
            let payers: [String] = [people[0], people[count - 1], "Utenfor"]
            for payer in payers {
                let plan = BillSplit.plan(total: NOK(ore: ore), people: people, payer: payer)
                #expect(plan.sum == ore)
                let payee: [Int] = people.contains(payer) ? [plan.payeeShare.ore] : []
                let amounts: [Int] = plan.shares.map { $0.amount.ore } + payee
                #expect((amounts.max() ?? 0) - (amounts.min() ?? 0) <= 1)
            }
        }
    }

    @Test func ingenSomDelerGirIngenDeler() {
        let plan = BillSplit.plan(total: NOK(ore: 500), people: [], payer: "A")
        #expect(plan.shares.isEmpty)
        #expect(plan.payeeShare.ore == 0)
    }

    @Test func tittelOgNavnInnenforGrensene() {
        #expect(BillSplit.title(purpose: .greenfee, note: "ignoreres") == "Greenfee")
        #expect(BillSplit.title(purpose: .other, note: "  Pizza  ") == "Pizza")
        #expect(BillSplit.title(purpose: .other, note: " ") == "Annet")
        #expect(BillSplit.title(purpose: .other, note: String(repeating: "x", count: 80)).count == 60)
        #expect(BillSplit.storedName(" " + String(repeating: "y", count: 50)).count == 40)
    }
}

struct RegningStatusTests {
    @Test func statusFraDatabasen() {
        #expect(BillShareStatus(raw: "open") == .open)
        #expect(BillShareStatus(raw: "sent") == .sent)
        #expect(BillShareStatus(raw: "confirmed") == .confirmed)
        #expect(BillShareStatus(raw: "disputed") == .disputed)
        #expect(BillShareStatus(raw: "noe_nytt") == .open)
        #expect(BillShareStatus(raw: nil) == .open)
    }

    @Test func teksterOgHandlinger() {
        #expect(BillShareStatus.sent.payeeText == "Sendt. Sjekk Vipps")
        #expect(BillShareStatus.confirmed.payeeText == "Fikk den")
        #expect(BillShareStatus.disputed.payeeText == "Kom ikke")
        #expect(BillShareStatus.sent.debtorText(payee: "Thomas") == "Sendt. Venter på Thomas")
        #expect(BillShareStatus.disputed.debtorText(payee: "Thomas") == "Thomas sier den ikke kom")
        #expect(BillShareStatus.confirmed.debtorText(payee: "Thomas") == "Betalt")
        // Betal: åpen eller etter «kom ikke». «Kom ikke» bare når den er sendt. «Fikk den» også kontant.
        #expect(BillShareStatus.allCases.filter(\.canPay) == [.open, .disputed])
        #expect(BillShareStatus.allCases.filter(\.canDispute) == [.sent])
        #expect(BillShareStatus.allCases.filter(\.canConfirm) == [.open, .sent, .disputed])
    }

    private let me = id(1), anders = id(2), bjorn = id(3)

    private func split(createdBy: UUID?, payee: UUID?) -> BillSplitRow {
        BillSplitRow(id: id(100), clubID: nil, roundID: id(200), createdBy: createdBy, payeeProfileID: payee,
                     payeeName: "Thomas", payeeVipps: nil, title: "Greenfee", totalOre: 900,
                     createdAt: Date(timeIntervalSince1970: 1_000))
    }

    private func share(_ n: Int, profile: UUID?, payee: Bool = false, status: String) -> BillShareRow {
        BillShareRow(id: id(n), splitID: id(100), profileID: profile, name: "P\(n)", amountOre: 300, isPayee: payee,
                     statusRaw: status, createdAt: Date(timeIntervalSince1970: Double(n)))
    }

    @Test func rollerOgSletting() throws {
        let rows = [share(13, profile: bjorn, status: "sent"), share(11, profile: me, payee: true, status: "confirmed"),
                    share(12, profile: anders, status: "open")]
        let settlement = try #require(BillSettlement.group(splits: [split(createdBy: me, payee: me)], shares: rows).first)
        #expect(settlement.shares.first?.isPayee == true)
        #expect(settlement.owed.map(\.id) == [id(12), id(13)])
        #expect(settlement.isPayee(me))
        #expect(!settlement.isPayee(anders))
        #expect(settlement.myShare(anders)?.id == id(12))
        #expect(settlement.myShare(me) == nil)
        // Mottakerens egen del er bekreftet, men teller ikke: regningen kan slettes.
        #expect(settlement.canDelete(me))
        #expect(!settlement.canDelete(anders))
        #expect(settlement.progressText == "0 av 2 betalt")
        #expect(!settlement.isSettled)

        let confirmed = BillSettlement(split: settlement.split,
                                       shares: [share(12, profile: anders, status: "confirmed"), share(13, profile: bjorn, status: "sent")])
        #expect(!confirmed.canDelete(me))
        #expect(confirmed.progressText == "1 av 2 betalt")
    }

    @Test func mottakerUtenInnloggingFolgesOppAvDenSomLagetDen() {
        let settlement = BillSettlement(split: split(createdBy: me, payee: nil), shares: [])
        #expect(settlement.isPayee(me))
        #expect(!settlement.isPayee(anders))
    }

    @Test func leserRaderFraServeren() throws {
        let json = #"""
        [{"id":"00000000-0000-0000-0000-000000000011","split_id":"00000000-0000-0000-0000-000000000100",
          "profile_id":null,"name":"Gjest","amount_ore":250,"is_payee":false,"status":"disputed",
          "created_at":"2026-10-12T18:00:00Z"}]
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([BillShareRow].self, from: Data(json.utf8))
        #expect(rows.first?.status == .disputed)
        #expect(rows.first?.amount.text == "2,50 kr")
        #expect(rows.first?.profileID == nil)
    }
}

struct VippsReturTests {
    private let share = id(42)

    @Test func merkesSendtNaarDuKommerTilbake() {
        var tracker = VippsReturnTracker()
        tracker.opened(share: share)
        #expect(tracker.phaseChanged(to: .inactive) == nil)
        #expect(tracker.phaseChanged(to: .background) == nil)
        #expect(tracker.state == .away(share))
        #expect(tracker.phaseChanged(to: .inactive) == nil)
        #expect(tracker.phaseChanged(to: .active) == share)
        #expect(tracker.state == .idle)
        // Bare én gang.
        #expect(tracker.phaseChanged(to: .background) == nil)
        #expect(tracker.phaseChanged(to: .active) == nil)
    }

    @Test func kortInaktivUtenBakgrunnTellerIkke() {
        var tracker = VippsReturnTracker()
        tracker.opened(share: share)
        #expect(tracker.phaseChanged(to: .inactive) == nil)
        #expect(tracker.phaseChanged(to: .active) == nil)
        #expect(tracker.state == .opening(share))
    }

    @Test func ingenDelUtenAtVippsBleAapnet() {
        var tracker = VippsReturnTracker()
        #expect(tracker.phaseChanged(to: .background) == nil)
        #expect(tracker.phaseChanged(to: .active) == nil)
    }

    @Test func vippsKunneIkkeAapnes() {
        var tracker = VippsReturnTracker()
        tracker.opened(share: share)
        tracker.openFailed()
        #expect(tracker.phaseChanged(to: .background) == nil)
        #expect(tracker.phaseChanged(to: .active) == nil)
    }

    @Test func sisteDelenGjelder() {
        var tracker = VippsReturnTracker()
        tracker.opened(share: id(1))
        tracker.opened(share: share)
        _ = tracker.phaseChanged(to: .background)
        #expect(tracker.phaseChanged(to: .active) == share)
    }
}

struct KalenderLenkeTests {
    private let token = "abcdefghijklmnopqrstuvwxyz234567"

    @Test func webcalOgHttps() {
        #expect(CalendarLink.subscribeURL(token: token)?.absoluteString
                == "webcal://dashdash18.com/kalender/abcdefghijklmnopqrstuvwxyz234567.ics")
        #expect(CalendarLink.webURL(token: token)?.absoluteString
                == "https://dashdash18.com/kalender/abcdefghijklmnopqrstuvwxyz234567.ics")
    }

    @Test func ugyldigTokenGirIngenLenke() {
        #expect(CalendarLink.subscribeURL(token: "") == nil)
        #expect(CalendarLink.subscribeURL(token: String(token.dropLast())) == nil)
        #expect(CalendarLink.subscribeURL(token: token.uppercased()) == nil)
        #expect(CalendarLink.subscribeURL(token: String(token.dropLast()) + "8") == nil)
        #expect(CalendarLink.subscribeURL(token: String(token.dropLast()) + "/") == nil)
    }
}

struct RegningAktivitetTests {
    @Test func tekstForSendtOgKomIkke() {
        let sent = ActivityEvent.billShareSent(title: "Simulatorleie", name: "Anders")
        let disputed = ActivityEvent.billShareDisputed(title: "Simulatorleie", name: "Thomas")
        #expect(ActivityText.display(sent, actor: nil, name: { _ in nil }).text == "Anders har sendt sin del for Simulatorleie")
        #expect(ActivityText.display(disputed, actor: nil, name: { _ in nil }).text
                == "Thomas sier at din del for Simulatorleie ikke kom")
        #expect(ActivityText.billShareSent(title: nil, name: " ") == "Noen har sendt sin del for regningen")
        #expect(ActivityText.billShareDisputed(title: nil, name: nil) == "Mottakeren sier at din del for regningen ikke kom")
        #expect(sent.category == .social)
        #expect(PushGroup.of(category: sent.category.rawValue, kind: sent.kind) == .social)
    }

    @Test func leserRadenSlikServerenSkriverDen() throws {
        // private.bill_activity i 051.
        let json = #"{"split_id":"00000000-0000-0000-0000-000000000100","share_id":"00000000-0000-0000-0000-000000000011","title":"Greenfee","name":"Anders"}"#
        let data = try JSONDecoder().decode(ActivityData.self, from: Data(json.utf8))
        #expect(ActivityEvent(kind: "bill_share_sent", data: data) == .billShareSent(title: "Greenfee", name: "Anders"))
        #expect(ActivityEvent(kind: "bill_share_disputed", data: data) == .billShareDisputed(title: "Greenfee", name: "Anders"))
    }

    @Test func bjellaNaarDetGjelderDeg() {
        let toMe = H.row(1, club: H.clubA, .billShareSent(title: "Greenfee", name: "Anders"), actor: H.anders,
                         round: nil, at: H.now, recipients: [H.me])
        let toOther = H.row(2, club: H.clubA, .billShareDisputed(title: "Greenfee", name: "Thomas"), actor: H.anders,
                            round: nil, at: H.now, recipients: [H.bjorn])
        #expect(HomeBell.reason(toMe, viewer: H.viewer) == .bill)
        #expect(HomeBell.reason(toOther, viewer: H.viewer) == nil)
    }
}
