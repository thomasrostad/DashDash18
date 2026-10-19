import Foundation
import Testing
@testable import DashDash18

/// Invitasjonslenken (runde, konkurranse, følg) huskes på telefonen til den er brukt, så den ikke
/// glemmes når iOS lukker appen mens en ny bruker henter innloggingskoden i Mail.
struct PendingLinkStoreTests {
    private func store(_ key: String = PendingLinkStore.appLinkKey) -> PendingLinkStore {
        PendingLinkStore(key: key, defaults: UserDefaults(suiteName: "test.ventende.\(UUID().uuidString)")!)
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let url = URL(string: "https://dashdash18.com/runde/ABCDEFGH23")!

    @Test func lenkenHuskesGjennomInnloggingen() {
        let store = store()
        store.save(url, now: now)
        #expect(store.load(now: now.addingTimeInterval(600)) == url)
    }

    @Test func glemmesEtterEtDogn() {
        let store = store()
        store.save(url, now: now)
        #expect(store.load(now: now.addingTimeInterval(PendingLinkStore.maxAge + 1)) == nil)
        #expect(store.load(now: now) == nil)
    }

    @Test func slettesNaarDenErBrukt() {
        let store = store()
        store.save(url, now: now)
        store.clear()
        #expect(store.load(now: now) == nil)
    }

    @Test func nyLenkeErstatterDenGamle() {
        let store = store()
        store.save(url, now: now)
        let other = URL(string: "dashdash://konkurranse/ZZZZZZZZZZ")!
        store.save(other, now: now)
        #expect(store.load(now: now) == other)
    }

    /// Rundelenken og følgelenken huskes hver for seg.
    @Test func hverSinNokkel() {
        let defaults = UserDefaults(suiteName: "test.ventende.\(UUID().uuidString)")!
        let links = PendingLinkStore(key: PendingLinkStore.appLinkKey, defaults: defaults)
        let follow = PendingLinkStore(key: PendingLinkStore.followKey, defaults: defaults)
        links.save(url, now: now)
        #expect(follow.load(now: now) == nil)
        #expect(links.load(now: now) == url)
    }
}
