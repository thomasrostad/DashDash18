import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Fase 17: låst konkurranse (besluttet 08.10.2026). En liga eller cup som krever kjøp, men der
/// kjøpet ikke ble koblet, får en betalingsknapp for den som styrer den, «Bruk kjøpet ditt» når et
/// kjøp står ubrukt, og en kort tekst for de andre (`CompetitionLock`).
@MainActor private enum L {
    static func id(_ n: Int) -> UUID { TavlaSamples.id(n) }

    static let club = TavlaSamples.club
    static let me = id(820)
    static let other = id(821)

    static func competition(kind: CompetitionKind = .league, club: UUID? = L.club, owner: UUID? = nil,
                            status: SeasonStatus = .active, requiresPurchase: Bool = true,
                            entitlementID: UUID? = nil) -> CompetitionRow {
        CompetitionRow(id: id(8300), kind: kind, name: "Høstligaen", clubID: club, ownerID: owner, seasonID: nil,
                       status: status, entry: .listed, rules: .golfgutu, startsOn: nil, endsOn: nil, isMain: false,
                       requiresPurchase: requiresPurchase, entitlementID: entitlementID, signupOpen: true)
    }

    static func access(organizer: Bool) -> CompetitionAccess {
        CompetitionAccess(profileID: me, memberships: [.init(clubID: club, memberID: id(1), isOrganizer: organizer,
                                                             isActive: true)])
    }

    static func entitlement(profile: UUID = L.me, club: UUID? = nil, competition: UUID? = nil,
                            kind: String = "consumable", status: EntitlementRow.Status = .active) -> EntitlementRow {
        EntitlementRow(id: UUID(), profileID: profile, clubID: club, competitionID: competition,
                       productID: PurchaseProduct.tournament.rawValue, productKind: kind, status: status, expiresAt: nil)
    }
}

@MainActor
struct KonkurranseLaastTests {
    // MARK: Regelen

    @Test func ingentingNarKjopErAv() {
        let notice = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: true, isClub: true,
                                            serverUnlocked: false, localUnlocked: false, hasOwnCredit: false,
                                            enabled: false)
        #expect(notice == .hidden)
    }

    @Test func ingentingNarDenErGratis() {
        let notice = CompetitionLock.notice(requiresPurchase: false, isFinished: false, isAdmin: true, isClub: true,
                                            serverUnlocked: false, localUnlocked: false, hasOwnCredit: false,
                                            enabled: true)
        #expect(notice == .hidden)
    }

    @Test func ingentingNarDenErFerdig() {
        let notice = CompetitionLock.notice(requiresPurchase: true, isFinished: true, isAdmin: true, isClub: true,
                                            serverUnlocked: false, localUnlocked: false, hasOwnCredit: true,
                                            enabled: true)
        #expect(notice == .hidden)
    }

    @Test func ingentingNarServerenSierUlast() {
        let notice = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: true, isClub: true,
                                            serverUnlocked: true, localUnlocked: false, hasOwnCredit: false,
                                            enabled: true)
        #expect(notice == .hidden)
    }

    @Test func serverenErFasitOgsaNarAppenTrorDenErUlast() {
        let notice = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: true, isClub: true,
                                            serverUnlocked: false, localUnlocked: true, hasOwnCredit: false,
                                            enabled: true)
        #expect(notice == .purchase)
    }

    @Test func utenSvarFraServerenVisesIngenting() {
        // Deltakerne ser ikke eierens kjøp (RLS), så et lokalt «låst» er ikke nok.
        for admin in [true, false] {
            let notice = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: admin, isClub: true,
                                                serverUnlocked: nil, localUnlocked: false, hasOwnCredit: true,
                                                enabled: true)
            #expect(notice == .hidden)
        }
    }

    @Test func eierenUtenKredittFarKjop() {
        let notice = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: true, isClub: false,
                                            serverUnlocked: false, localUnlocked: false, hasOwnCredit: false,
                                            enabled: true)
        #expect(notice == .purchase)
        #expect(notice.buttonTitle == "Lås opp konkurransen")
    }

    @Test func eierenMedKredittKoblerDen() {
        let notice = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: true, isClub: true,
                                            serverUnlocked: false, localUnlocked: false, hasOwnCredit: true,
                                            enabled: true)
        #expect(notice == .useCredit)
        #expect(notice.buttonTitle == "Bruk kjøpet ditt")
    }

    @Test func deltakerenFarBareTekst() {
        let club = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: false, isClub: true,
                                          serverUnlocked: false, localUnlocked: false, hasOwnCredit: true,
                                          enabled: true)
        #expect(club == .waitForOrganizer(isClub: true))
        #expect(club.buttonTitle == nil)
        #expect(club.message == "Arrangøren må låse den opp med et kjøp i appen.")
        let privat = CompetitionLock.notice(requiresPurchase: true, isFinished: false, isAdmin: false, isClub: false,
                                            serverUnlocked: false, localUnlocked: false, hasOwnCredit: false,
                                            enabled: true)
        #expect(privat.message == "Eieren må låse den opp med et kjøp i appen.")
    }

    @Test func skjultHarIngenTekst() {
        #expect(CompetitionLockNotice.hidden.title == nil)
        #expect(CompetitionLockNotice.hidden.message == nil)
        #expect(CompetitionLockNotice.hidden.buttonTitle == nil)
        #expect(CompetitionLockNotice.purchase.title == "Ikke låst opp ennå")
    }

    // MARK: Fra konkurransen og kjøpene

    @Test func arrangorenIKlubbenStyrerDen() {
        let notice = CompetitionLock.notice(for: L.competition(), access: L.access(organizer: true),
                                            serverUnlocked: false, entitlements: [], enabled: true)
        #expect(notice == .purchase)
    }

    @Test func vanligMedlemVenterPaArrangoren() {
        let notice = CompetitionLock.notice(for: L.competition(), access: L.access(organizer: false),
                                            serverUnlocked: false, entitlements: [], enabled: true)
        #expect(notice == .waitForOrganizer(isClub: true))
    }

    @Test func eierenAvEnPrivatStyrerDen() {
        let mine = L.competition(kind: .cup, club: nil, owner: L.me)
        let notice = CompetitionLock.notice(for: mine, access: L.access(organizer: false), serverUnlocked: false,
                                            entitlements: [], enabled: true)
        #expect(notice == .purchase)
        let others = L.competition(kind: .cup, club: nil, owner: L.other)
        #expect(CompetitionLock.notice(for: others, access: L.access(organizer: true), serverUnlocked: false,
                                       entitlements: [], enabled: true) == .waitForOrganizer(isClub: false))
    }

    @Test func egenLedigKredittGirBrukKjopet() {
        let notice = CompetitionLock.notice(for: L.competition(), access: L.access(organizer: true),
                                            serverUnlocked: false, entitlements: [L.entitlement(club: L.club)],
                                            enabled: true)
        #expect(notice == .useCredit)
    }

    @Test func andresBrukteOgUtlopteKjopErIkkeKreditt() {
        let entitlements = [
            L.entitlement(profile: L.other, club: L.club),            // en annen arrangørs kjøp
            L.entitlement(competition: L.id(8999)),                    // brukt på en annen turnering
            L.entitlement(status: .refunded),                          // refundert
            L.entitlement(kind: "subscription"),                       // abonnement, ikke kreditt
        ]
        #expect(CompetitionLock.credit(in: entitlements, profileID: L.me) == nil)
        #expect(CompetitionLock.notice(for: L.competition(), access: L.access(organizer: true), serverUnlocked: false,
                                       entitlements: entitlements, enabled: true) == .purchase)
        #expect(CompetitionLock.credit(in: [L.entitlement()], profileID: nil) == nil)
    }

    @Test func kjopKobletTilDenneGjorDenUlastUtenNett() {
        let c = L.competition()
        let notice = CompetitionLock.notice(for: c, access: L.access(organizer: true), serverUnlocked: nil,
                                            entitlements: [L.entitlement(competition: c.id)], enabled: true)
        #expect(notice == .hidden)
    }

    @Test func morroOgSesongKreverIkkeKjop() {
        let fun = L.competition(kind: .fun, requiresPurchase: false)
        #expect(CompetitionLock.notice(for: fun, access: L.access(organizer: true), serverUnlocked: false,
                                       entitlements: [], enabled: true) == .hidden)
    }

    @Test func ferdigKonkurranseViserIngenting() {
        let done = L.competition(status: .finished)
        #expect(CompetitionLock.notice(for: done, access: L.access(organizer: true), serverUnlocked: false,
                                       entitlements: [], enabled: true) == .hidden)
    }

    @Test func standardFolgerKjopsflagget() {
        let notice = CompetitionLock.notice(for: L.competition(), access: L.access(organizer: true),
                                            serverUnlocked: false, entitlements: [])
        #expect((notice == .hidden) == !PurchaseFeature.isEnabled)
    }
}
