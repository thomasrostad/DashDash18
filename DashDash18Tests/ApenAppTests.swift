import Foundation
import Testing
@testable import DashDash18

// Fase 17, åpent for alle: onboarding uten klubb, sletting av konto, rapporter og blokker,
// kjøp for å kjøre turnering og «Del regningen».

struct ApenOnboardingTests {
    private let membership = Membership.preview
    private let pending = Membership(id: UUID(), clubID: UUID(), displayName: "Dag", status: .pending, isOrganizer: false,
                                     isTreasurer: false, club: .init(name: "Golfgutu", joinCode: nil))

    @Test func flaggetAvGirDagensFlyt() {
        #expect(OpenAppGate.home(club: .noClub, choice: nil, openApp: false) == .clubOnboarding)
        #expect(OpenAppGate.home(club: .noClub, choice: .friends, openApp: false) == .clubOnboarding)
        #expect(OpenAppGate.home(club: .pending(pending), choice: .friends, openApp: false) == .pending(pending))
        #expect(OpenAppGate.home(club: .active(membership), choice: nil, openApp: false) == .club(membership))
        #expect(OpenAppGate.home(club: .loading, choice: nil, openApp: false) == .loading)
        #expect(OpenAppGate.home(club: .failed(.offline), choice: nil, openApp: false) == .failed(.offline))
    }

    @Test func utenKlubbVelgerManForsteGang() {
        #expect(OpenAppGate.home(club: .noClub, choice: nil, openApp: true) == .chooser)
        #expect(OpenAppGate.home(club: .noClub, choice: .friends, openApp: true) == .friends)
        #expect(OpenAppGate.home(club: .noClub, choice: .club, openApp: true) == .clubOnboarding)
    }

    @Test func aktivKlubbVinnerOgVentendeKanSpilleMedVenner() {
        #expect(OpenAppGate.home(club: .active(membership), choice: .friends, openApp: true) == .club(membership))
        #expect(OpenAppGate.home(club: .pending(pending), choice: .friends, openApp: true) == .friends)
        #expect(OpenAppGate.home(club: .pending(pending), choice: nil, openApp: true) == .pending(pending))
    }

    @Test func fanerUtenKlubbErSpillOgDeg() {
        #expect(AppTab.tabsWithoutClub() == [.spill, .deg])
    }

    @Test func valgetLagresPerInnlogging() throws {
        let defaults = try #require(UserDefaults(suiteName: "ApenOnboardingTests"))
        defaults.removePersistentDomain(forName: "ApenOnboardingTests")
        let store = AppHomeChoiceStore(defaults: defaults)
        let a = UUID(), b = UUID()
        store.save(.friends, userID: a)
        #expect(store.load(userID: a) == .friends)
        #expect(store.load(userID: b) == nil)
        store.save(nil, userID: a)
        #expect(store.load(userID: a) == nil)
    }

    /// 08.10.2026: 019 kjørt og `delete-account` deployet på test, så sletting, moderering og
    /// «Del regningen» er på. 09.10: onboarding uten klubb på. Google og kjøp venter på oppsett.
    @Test func flaggeneEtterGodkjenning() {
        #expect(OpenAppFeature.isEnabled)
        #expect(AccountDeletionFeature.isEnabled)
        #expect(ModerationFeature.isEnabled)
        #expect(!GoogleLoginFeature.isEnabled)
        #expect(!PurchaseFeature.isEnabled)
        #expect(BillSplitFeature.isEnabled)
        // Med onboarding på vises personvern og vilkår (teksten «publiseres før lansering» til lenkene finnes).
        #expect(LegalLinks.isVisible)
        #expect(!LoginMethod.google.isAvailable)
    }
}

struct ApenKontoTests {
    @Test func bekreftelsenErOrdetSlett() {
        #expect(AccountDeletion.isConfirmed("SLETT"))
        #expect(AccountDeletion.isConfirmed(" slett "))
        #expect(!AccountDeletion.isConfirmed("SLETTE"))
        #expect(!AccountDeletion.isConfirmed(""))
    }

    @Test func advarslerForArrangorOgHullIKo() {
        #expect(AccountDeletion.organizerWarning(clubs: []) == nil)
        #expect(AccountDeletion.organizerWarning(clubs: ["Golfgutu"])?.contains("Golfgutu") == true)
        #expect(AccountDeletion.pendingWarning(pending: 0) == nil)
        #expect(AccountDeletion.pendingWarning(pending: 1) == "1 hull er ikke sendt ennå og går tapt.")
        #expect(AccountDeletion.pendingWarning(pending: 3) == "3 hull er ikke sendt ennå og går tapt.")
    }

    @Test func svaretFraServerenBlirTilFeil() throws {
        let decoder = JSONDecoder()
        let ok = try decoder.decode(AccountDeletionResponse.self, from: Data(#"{"ok":true,"removedFiles":2,"summary":{}}"#.utf8))
        #expect(AccountDeletionError.from(ok) == nil)
        let stopped = try decoder.decode(AccountDeletionResponse.self,
                                         from: Data(#"{"ok":false,"removedFiles":0,"failedAt":"anonymize","error":"500"}"#.utf8))
        #expect(AccountDeletionError.from(stopped) == .partial(step: "anonymize"))
        #expect(AccountDeletionError.partial(step: "anonymize").message.contains("navn og innhold"))
        let unknown = AccountDeletionResponse(ok: false, removedFiles: nil, failedAt: nil, error: "nei")
        #expect(AccountDeletionError.from(unknown) == .unknown("nei"))
    }

    @Test func konsekvenseneNevnerSlettetSpillerOgScorer() {
        let text = AccountDeletion.consequences.joined(separator: " ")
        #expect(text.contains("Slettet spiller"))
        #expect(text.contains("Scorene står"))
    }
}

struct ApenModereringTests {
    @Test func grunnenePasserInnholdet() {
        #expect(!ReportReason.options(for: .message).contains(.inappropriateImage))
        #expect(ReportReason.options(for: .image).contains(.inappropriateImage))
        #expect(ReportReason.options(for: .member).contains(.impersonation))
        #expect(!ReportReason.options(for: .message).contains(.impersonation))
        #expect(ReportReason.options(for: .message).last == .other)
    }

    @Test func blokkerteOgRapporterteSkjules() {
        let blocked = UUID(), member = UUID(), other = UUID(), message = UUID()
        var filter = ModerationFilter()
        let users = [member: blocked]
        #expect(filter.shows(messageID: message, memberID: member, userForMember: users))
        filter.blockedUsers.insert(blocked)
        #expect(!filter.shows(messageID: message, memberID: member, userForMember: users))
        #expect(filter.shows(messageID: UUID(), memberID: other, userForMember: users))
        filter.reportedMessages.insert(message)
        #expect(!filter.shows(messageID: message, memberID: other, userForMember: users))
    }

    @Test func rapporterOmSammeMeldingErEnSak() {
        let message = UUID()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func row(_ kind: ReportKind, _ target: UUID, _ reason: ReportReason, _ minutes: Double, _ status: ReportStatus = .open) -> ContentReportRow {
            ContentReportRow(id: UUID(), kind: kind, targetID: target, clubID: nil, reason: reason, note: nil,
                             snapshot: nil, status: status, createdAt: t0.addingTimeInterval(minutes * 60))
        }
        let rows = [
            row(.message, message, .offensive, 10),
            row(.image, message, .inappropriateImage, 20),
            row(.member, UUID(), .impersonation, 5),
            row(.message, message, .offensive, 30),
            row(.message, UUID(), .spam, 1, .dismissed),
        ]
        let cases = ReportCase.open(rows)
        #expect(cases.count == 2)
        #expect(cases[0].first.kind == .member)
        #expect(cases[1].count == 3)
        #expect(cases[1].reasons == [.offensive, .inappropriateImage])
        #expect(cases[1].hoursOpen(now: t0.addingTimeInterval(25 * 3600)) == 24)
    }

    @Test func rapportRadenLesesFraDatabasen() throws {
        let json = #"""
        [{"id":"0a000000-0000-0000-0000-00000000000a","kind":"image","target_id":"0b000000-0000-0000-0000-00000000000b",
          "club_id":null,"reason":"inappropriate_image","note":null,"snapshot":"x/y.jpg","status":"open",
          "created_at":"2026-10-08T12:00:00Z"}]
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([ContentReportRow].self, from: Data(json.utf8))
        #expect(rows.first?.reason == .inappropriateImage)
        #expect(rows.first?.kind == .image)
    }
}

struct ApenKjopTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let me = UUID()
    private let club = UUID()

    private func entitlement(kind: String = "consumable", status: EntitlementRow.Status = .active, competition: UUID? = nil,
                             club: UUID? = nil, expires: Date? = nil) -> EntitlementRow {
        EntitlementRow(id: UUID(), profileID: me, clubID: club, competitionID: competition,
                       productID: kind == "consumable" ? PurchaseProduct.tournament.rawValue : PurchaseProduct.yearly.rawValue,
                       productKind: kind, status: status, expiresAt: expires)
    }

    @Test func produkteneErForbrukbarOgAbonnement() {
        #expect(PurchaseProduct.tournament.rawValue == "no.atten.turnering.sesong")
        #expect(PurchaseProduct.tournament.kind == .consumable)
        #expect(PurchaseProduct.yearly.kind == .subscription)
        #expect(PurchaseProduct.ids.count == 2)
    }

    @Test func gratisTurneringErLastOpp() {
        let free = CompetitionPurchaseInfo(id: UUID(), requiresPurchase: false)
        #expect(CompetitionUnlock.isUnlocked(free, entitlements: [], now: now))
    }

    @Test func kjopKobletTilTurneringenLaserOpp() {
        let cup = CompetitionPurchaseInfo(id: UUID(), requiresPurchase: true, ownerID: me)
        #expect(!CompetitionUnlock.isUnlocked(cup, entitlements: [], now: now))
        #expect(CompetitionUnlock.isUnlocked(cup, entitlements: [entitlement(competition: cup.id)], now: now))
        #expect(!CompetitionUnlock.isUnlocked(cup, entitlements: [entitlement(status: .refunded, competition: cup.id)], now: now))
        #expect(!CompetitionUnlock.isUnlocked(cup, entitlements: [entitlement(competition: UUID())], now: now))
        let pointed = entitlement()
        var viaPointer = cup
        viaPointer.entitlementID = pointed.id
        #expect(CompetitionUnlock.isUnlocked(viaPointer, entitlements: [pointed], now: now))
    }

    @Test func abonnementLaserOppEierensOgKlubbens() {
        let mine = CompetitionPurchaseInfo(id: UUID(), requiresPurchase: true, ownerID: me)
        let clubs = CompetitionPurchaseInfo(id: UUID(), requiresPurchase: true, clubID: club)
        let personal = entitlement(kind: "subscription", expires: now.addingTimeInterval(3600))
        let forClub = entitlement(kind: "subscription", club: club, expires: now.addingTimeInterval(3600))
        let expired = entitlement(kind: "subscription", expires: now.addingTimeInterval(-1))
        #expect(CompetitionUnlock.isUnlocked(mine, entitlements: [personal], now: now))
        #expect(!CompetitionUnlock.isUnlocked(clubs, entitlements: [personal], now: now))
        #expect(CompetitionUnlock.isUnlocked(clubs, entitlements: [forClub], now: now))
        #expect(!CompetitionUnlock.isUnlocked(mine, entitlements: [forClub], now: now))
        #expect(!CompetitionUnlock.isUnlocked(mine, entitlements: [expired], now: now))
    }

    @Test func ledigKredittFinnes() {
        let used = entitlement(competition: UUID())
        let free = entitlement()
        #expect(CompetitionUnlock.unusedCredit(in: [used], owner: me) == nil)
        #expect(CompetitionUnlock.unusedCredit(in: [used, free], owner: me)?.id == free.id)
        #expect(CompetitionUnlock.unusedCredit(in: [entitlement(kind: "subscription")], owner: me) == nil)
        // En annen arrangørs ledige kjøp i klubben kan ikke kobles (`assign_purchase`), så det teller ikke.
        var others = entitlement()
        others.profileID = UUID()
        #expect(CompetitionUnlock.unusedCredit(in: [others], owner: me) == nil)
        #expect(CompetitionUnlock.unusedCredit(in: [others, free], owner: me)?.id == free.id)
        #expect(CompetitionUnlock.unusedCredit(in: [free], owner: nil) == nil)
    }

    @Test func ventendeKjopHuskerTurneringen() throws {
        let defaults = try #require(UserDefaults(suiteName: "ApenKjopTests"))
        defaults.removePersistentDomain(forName: "ApenKjopTests")
        let store = PendingPurchaseStore(defaults: defaults)
        let cup = PurchaseTarget(competitionID: UUID())
        let product = PurchaseProduct.tournament.rawValue
        store.prepare(.init(productID: product, target: cup, profileID: me, createdAt: .now))
        let first = PurchaseTransactionInfo(id: 42, originalID: 42, productID: product, purchaseDate: .now,
                                            appAccountToken: me)
        #expect(store.claimForPurchase(first) == cup)
        let second = PurchaseTransactionInfo(id: 43, originalID: 43, productID: product, purchaseDate: .now,
                                             appAccountToken: me)
        #expect(store.claimForPurchase(second) == nil)
        store.done(transactionID: 42)
        #expect(store.target(for: 42) == nil)
    }

    @Test func kjopsradenLesesFraDatabasen() throws {
        let json = #"""
        [{"id":"0a000000-0000-0000-0000-00000000000a","profile_id":null,"club_id":null,"competition_id":null,
          "product_id":"no.atten.turnering.sesong","product_kind":"consumable","status":"active","expires_at":null}]
        """#
        let rows = try JSONDecoder().decode([EntitlementRow].self, from: Data(json.utf8))
        #expect(rows.first?.isUnusedCredit == true)
    }
}

struct ApenRegningTests {
    @Test func belopLesesSomNorskeKroner() {
        #expect(NOK(parsing: "1250")?.ore == 125_000)
        #expect(NOK(parsing: "1 250")?.ore == 125_000)
        #expect(NOK(parsing: "249,5")?.ore == 24_950)
        #expect(NOK(parsing: "249.50 kr")?.ore == 24_950)
        #expect(NOK(parsing: "kr 300")?.ore == 30_000)
        #expect(NOK(parsing: "300,-")?.ore == 30_000)
        #expect(NOK(parsing: "0") == nil)
        #expect(NOK(parsing: "-5") == nil)
        #expect(NOK(parsing: "12,345") == nil)
        #expect(NOK(parsing: "abc") == nil)
        #expect(NOK(parsing: "") == nil)
    }

    @Test func belopVisesMedTusenskilleOgKomma() {
        #expect(NOK(ore: 125_000).text == "1\u{00A0}250 kr")
        #expect(NOK(ore: 31_250).text == "312,50 kr")
        #expect(NOK(ore: 31_250).plain == "312,50")
        #expect(NOK(ore: 30_000).plain == "300")
    }

    @Test func likDelingDerOrenGaarOpp() {
        let shares = BillSplit.shares(total: NOK(ore: 100_000), people: ["Thomas", "Anders", "Bjørn", "Carl"], payer: "Thomas")
        #expect(shares.map(\.name) == ["Anders", "Bjørn", "Carl"])
        #expect(shares.map(\.amount.ore) == [25_000, 25_000, 25_000])
    }

    @Test func restOreFordelesFraToppenOgSummenStemmer() {
        let total = NOK(ore: 100_001)
        let people = ["A", "B", "C"]
        let all = BillSplit.shares(total: total, people: people, payer: nil)
        #expect(all.map(\.amount.ore) == [33_334, 33_334, 33_333])
        #expect(all.reduce(0) { $0 + $1.amount.ore } == total.ore)
    }

    @Test func navnRyddesOgDegForst() {
        #expect(BillSplit.unique([" Thomas ", "thomas", "", "Anders"]) == ["Thomas", "Anders"])
        let me = UUID(), a = UUID(), b = UUID()
        #expect(BillSplit.names(players: [a, me, b], names: [a: "Anders", me: "Thomas", b: "Bjørn"], me: me)
                == ["Thomas", "Anders", "Bjørn"])
    }

    @Test func mobilnummerOgTekstTilVipps() {
        #expect(VippsRecipient.normalizedPhone("987 65 432") == "98765432")
        #expect(VippsRecipient.normalizedPhone("+47 412 34 567") == "41234567")
        #expect(VippsRecipient.normalizedPhone("0047 98765432") == "98765432")
        #expect(VippsRecipient.normalizedPhone("22 33 44 55") == nil)
        #expect(VippsRecipient.formatted("98765432") == "987 65 432")
        let share = BillShare(name: "Anders", amount: NOK(ore: 31_250))
        let summary = VippsLink.summary(shares: [share], total: NOK(ore: 125_000), recipientName: "Thomas",
                                        phone: nil, purpose: .greenfee)
        #expect(summary == "Greenfee: 1\u{00A0}250 kr. Vipps til Thomas:\n• Anders: 312,50 kr")
        #expect(VippsLink.app.scheme == "vipps")
    }
}
