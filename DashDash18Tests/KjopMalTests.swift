import Foundation
import Synchronization
import Testing
@testable import DashDash18

// Fase 17, kodegjennomgangen 08.10.2026: bare transaksjonen fra `purchase()` får turneringen
// kjøpsarket ble åpnet for. Fornyelser, «Gjenopprett» og `Transaction.updates` kobles ikke til den.

/// Serveren uten nett: husker hvilke kall `verify-purchase` fikk.
nonisolated private final class RecordingPurchaseBackend: PurchaseBackend {
    struct Call: Equatable {
        let transactionID: UInt64
        let competitionID: UUID?
        let clubID: UUID?
    }

    private let state = Mutex<(calls: [Call], failing: Bool)>(([], false))

    var calls: [Call] { state.withLock { $0.calls } }

    func setFailing(_ failing: Bool) { state.withLock { $0.failing = failing } }

    func verify(transactionID: UInt64, competitionID: UUID?, clubID: UUID?) async throws -> EntitlementRow {
        let failing = state.withLock { s in
            s.calls.append(Call(transactionID: transactionID, competitionID: competitionID, clubID: clubID))
            return s.failing
        }
        if failing { throw URLError(.notConnectedToInternet) }
        return EntitlementRow(id: UUID(), profileID: nil, clubID: clubID, competitionID: competitionID,
                              productID: PurchaseProduct.tournament.rawValue, productKind: "consumable",
                              status: .active, expiresAt: nil)
    }

    func entitlements() async throws -> [EntitlementRow] { [] }
    func assign(entitlementID: UUID, competitionID: UUID) async throws {}
    func isUnlocked(competitionID: UUID) async throws -> Bool { false }
}

struct KjopMalTests {
    static let me = UUID(uuidString: "0A0A0A0A-0000-4000-8000-0000000000AA")!
    static let start = Date(timeIntervalSince1970: 1_800_000_000)
    static let cup = PurchaseTarget(competitionID: UUID(uuidString: "0C0C0C0C-0000-4000-8000-0000000000CC")!)
    static let tournament = PurchaseProduct.tournament.rawValue
    static let yearly = PurchaseProduct.yearly.rawValue

    static func store() -> PendingPurchaseStore {
        PendingPurchaseStore(defaults: UserDefaults(suiteName: "kjopmal.\(UUID().uuidString)")!)
    }

    static func pending(_ product: String = tournament, target: PurchaseTarget = cup) -> PendingPurchaseStore.Pending {
        .init(productID: product, target: target, profileID: me, createdAt: start)
    }

    static func transaction(_ id: UInt64, original: UInt64? = nil, product: String = tournament,
                            after seconds: TimeInterval = 10, token: UUID? = me) -> PurchaseTransactionInfo {
        PurchaseTransactionInfo(id: id, originalID: original ?? id, productID: product,
                                purchaseDate: start.addingTimeInterval(seconds), appAccountToken: token)
    }

    // MARK: Regelen

    @Test func sammeKjopFarMalet() {
        #expect(PendingPurchaseStore.matches(Self.pending(), Self.transaction(1)))
        // Klokkene går litt ulikt.
        #expect(PendingPurchaseStore.matches(Self.pending(), Self.transaction(1, after: -60)))
        // Kjøpsforespørsel godkjent dagen etter.
        #expect(PendingPurchaseStore.matches(Self.pending(), Self.transaction(1, after: 24 * 3600)))
    }

    @Test func andreTransaksjonerFarIkkeMalet() {
        // Fornyelse av abonnementet.
        #expect(!PendingPurchaseStore.matches(Self.pending(Self.yearly), Self.transaction(9, original: 3, product: Self.yearly)))
        // Annet produkt.
        #expect(!PendingPurchaseStore.matches(Self.pending(), Self.transaction(1, product: Self.yearly)))
        // En annen konto, eller uten konto (kjøpt utenom appen).
        #expect(!PendingPurchaseStore.matches(Self.pending(), Self.transaction(1, token: UUID())))
        #expect(!PendingPurchaseStore.matches(Self.pending(), Self.transaction(1, token: nil)))
        // Et eldre kjøp (uferdig fra før, eller «Gjenopprett»).
        #expect(!PendingPurchaseStore.matches(Self.pending(), Self.transaction(1, after: -3600)))
        // For lenge etter.
        #expect(!PendingPurchaseStore.matches(Self.pending(), Self.transaction(1, after: 3 * 24 * 3600)))
    }

    // MARK: Lageret

    @Test func kjopsflytenTarMaletSelvForFornyelser() {
        let store = Self.store()
        store.prepare(Self.pending())
        // En transaksjon som kommer mens kjøpsarket er åpent, tar ikke målet.
        #expect(store.claimForBackground(Self.transaction(1), mayClaim: false) == nil)
        #expect(store.next != nil)
        #expect(store.claimForPurchase(Self.transaction(2)) == Self.cup)
        #expect(store.next == nil)
        // Den samme transaksjonen igjen (fra `updates`) får målet den alt har.
        #expect(store.claimForBackground(Self.transaction(2)) == Self.cup)
        #expect(store.claimForBackground(Self.transaction(3)) == nil)
    }

    @Test func avbruttKjopGirIkkeMal() {
        let store = Self.store()
        store.prepare(Self.pending())
        store.cancel()
        #expect(store.claimForBackground(Self.transaction(1)) == nil)
        #expect(store.claimForPurchase(Self.transaction(1)) == nil)
    }

    @Test func krasjEtterKjopetFinnerMaletIgjen() throws {
        let name = "kjopmal.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        PendingPurchaseStore(defaults: defaults).prepare(Self.pending())
        // Appen starter på nytt: den uferdige transaksjonen kommer i `Transaction.unfinished`.
        let restarted = PendingPurchaseStore(defaults: defaults)
        #expect(restarted.claimForBackground(Self.transaction(7)) == Self.cup)
        // Serveren svarte ikke: neste forsøk får samme mål.
        #expect(PendingPurchaseStore(defaults: defaults).claimForBackground(Self.transaction(7)) == Self.cup)
        restarted.done(transactionID: 7)
        #expect(restarted.target(for: 7) == nil)
        #expect(defaults.object(forKey: "ventendeKjop") == nil)
    }

    // MARK: Tjenesten

    @MainActor @Test func fornyelseUnderKjopetVerifiseresUtenTurnering() async {
        let backend = RecordingPurchaseBackend()
        let service = PurchaseService(backend: backend, profileID: Self.me, pending: Self.store(), now: { Self.start })
        service.beginPurchase(.tournament, target: Self.cup)
        var finished = 0
        // Abonnementet fornyes mens kjøpsarket er åpent.
        await service.register(Self.transaction(20, original: 5, product: Self.yearly), source: .background) { finished += 1 }
        // Den samme forbrukbare transaksjonen kommer i `updates` før `purchase()` har svart.
        await service.register(Self.transaction(21), source: .background) { finished += 1 }
        await service.register(Self.transaction(21), source: .purchase) { finished += 1 }
        #expect(backend.calls == [
            .init(transactionID: 20, competitionID: nil, clubID: nil),
            .init(transactionID: 21, competitionID: nil, clubID: nil),
            .init(transactionID: 21, competitionID: Self.cup.competitionID, clubID: nil),
        ])
        #expect(finished == 3)
        #expect(service.lastUnlocked == Self.cup.competitionID)
    }

    @MainActor @Test func gjenopprettEtterKjopetKoblerIkkeTilTurneringen() async {
        let backend = RecordingPurchaseBackend()
        let store = Self.store()
        let service = PurchaseService(backend: backend, profileID: Self.me, pending: store, now: { Self.start })
        service.beginPurchase(.yearly, target: .init(clubID: Self.cup.competitionID))
        await service.register(Self.transaction(30, product: Self.yearly), source: .purchase) {}
        // «Gjenopprett» og en senere fornyelse.
        await service.register(Self.transaction(30, product: Self.yearly), source: .background) {}
        await service.register(Self.transaction(31, original: 30, product: Self.yearly, after: 365 * 24 * 3600),
                               source: .background) {}
        #expect(backend.calls == [
            .init(transactionID: 30, competitionID: nil, clubID: Self.cup.competitionID),
            .init(transactionID: 30, competitionID: nil, clubID: nil),
            .init(transactionID: 31, competitionID: nil, clubID: nil),
        ])
    }

    @MainActor @Test func krasjOgKjopsforesporselFarMaletEtterpa() async {
        let backend = RecordingPurchaseBackend()
        let store = Self.store()
        let crashed = PurchaseService(backend: backend, profileID: Self.me, pending: store, now: { Self.start })
        crashed.beginPurchase(.tournament, target: Self.cup)
        // Ny økt (krasj, eller en godkjent Kjøpsforespørsel i `updates`), uten nett første gang.
        let service = PurchaseService(backend: backend, profileID: Self.me, pending: store, now: { Self.start })
        backend.setFailing(true)
        var finished = 0
        await service.register(Self.transaction(40), source: .background) { finished += 1 }
        #expect(service.state == .failed(.offline))
        #expect(finished == 0)
        backend.setFailing(false)
        await service.register(Self.transaction(40), source: .background) { finished += 1 }
        #expect(finished == 1)
        // Et senere kjøp utenom (annen enhet) får ingenting.
        await service.register(Self.transaction(41, after: 600), source: .background) {}
        #expect(backend.calls.map(\.competitionID) == [Self.cup.competitionID, Self.cup.competitionID, nil])
    }
}
