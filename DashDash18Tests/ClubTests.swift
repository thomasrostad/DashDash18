import Foundation
import Supabase
import Testing
@testable import DashDash18

struct ClubInputTests {
    @Test(arguments: [
        ("a1b2c3d4e5", "A1B2C3D4E5"),
        (" A1B2 C3D4-E5 ", "A1B2C3D4E5"),
        ("ABC123", "ABC123"),
    ])
    func gyldigKode(_ input: String, _ forventet: String) {
        #expect(ClubInput.normalizedJoinCode(input) == forventet)
    }

    @Test(arguments: ["", "ABC12", "ÆØÅ123", "ABC!23", String(repeating: "A", count: 17)])
    func ugyldigKode(_ input: String) {
        #expect(ClubInput.normalizedJoinCode(input) == nil)
    }

    @Test func navn() {
        #expect(ClubInput.normalizedName("  Thomas  ") == "Thomas")
        #expect(ClubInput.normalizedName("   ") == nil)
        #expect(ClubInput.normalizedName(String(repeating: "x", count: 41)) == nil)
        #expect(ClubInput.normalizedName(String(repeating: "x", count: 60), maxLength: 60) != nil)
    }

    @Test(arguments: [
        ("", nil as Double?),
        ("18,4", 18.4),
        ("18.4", 18.4),
        (" 54 ", 54.0),
        ("0", 0.0),
        ("+2", -2.0),
        ("+2,3", -2.3),
        ("12,34", 12.3),
        ("12, 4", 12.4),
        ("+ 2,3", -2.3),
        ("\u{00A0}7,0\u{00A0}", 7.0),
        ("12,", 12.0),
        (",5", 0.5),
        ("+0", 0.0),
    ])
    func gyldigHandicap(_ input: String, _ forventet: Double?) throws {
        #expect(try ClubInput.handicapIndex(input).get() == forventet)
    }

    @Test(arguments: ["abc", "54,1", "+10,1", "-3", "\u{2212}3", "1e1", "0x1A", "12,4,1", "+", ",", "inf", "nan", "++2"])
    func ugyldigHandicap(_ input: String) {
        // «-3» er ugyldig fordi plusshandicap skrives med «+», ikke minus.
        if case .success = ClubInput.handicapIndex(input) {
            Issue.record("\(input) skulle vært avvist")
        }
    }
}

struct ClubErrorTests {
    @Test func sqlStateTilNorsk() {
        #expect(ClubError.from(sqlState: "P0002", message: "") == .notFound)
        #expect(ClubError.from(sqlState: "55000", message: "") == .nameTaken)
        #expect(ClubError.from(sqlState: "23505", message: "") == .duplicateName)
        #expect(ClubError.from(sqlState: "22023", message: "Skriv inn et navn") == .invalidInput("Skriv inn et navn"))
        #expect(ClubError.from(sqlState: "42501", message: "") == .notAllowed)
        #expect(ClubError.from(sqlState: nil, message: "x") == .unknown("x"))
    }
}

struct MembershipTests {
    private func medlem(_ klubb: UUID, _ status: MemberStatus) -> Membership {
        Membership(id: UUID(), clubID: klubb, displayName: "T", status: status,
                   isOrganizer: false, isTreasurer: false, club: .init(name: "K", joinCode: nil))
    }

    @Test func velgerHusketAktivKlubb() {
        let a = UUID(), b = UUID()
        let valgt = Membership.choose(from: [medlem(a, .active), medlem(b, .active)], remembered: b)
        #expect(valgt?.clubID == b)
    }

    @Test func fallerTilbakeTilForsteAktive() {
        let a = UUID(), b = UUID()
        let valgt = Membership.choose(from: [medlem(a, .pending), medlem(b, .active)], remembered: a)
        #expect(valgt?.clubID == b)
    }

    @Test func venterHvisIngenAktive() {
        let a = UUID()
        #expect(Membership.choose(from: [medlem(a, .archived), medlem(a, .pending)], remembered: nil)?.status == .pending)
        #expect(Membership.choose(from: [medlem(a, .archived)], remembered: nil) == nil)
        #expect(Membership.choose(from: [], remembered: nil) == nil)
    }

    @Test func dekoderRadFraSupabase() throws {
        let json = """
        {"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b",
         "display_name":"Thomas","status":"active","is_organizer":true,"is_treasurer":false,
         "clubs":{"name":"Golfgutu Invitational","join_code":"A1B2C3D4E5"}}
        """
        let m = try JSONDecoder().decode(Membership.self, from: Data(json.utf8))
        #expect(m.displayName == "Thomas")
        #expect(m.club.joinCode == "A1B2C3D4E5")
        #expect(m.roleText == "Arrangør")
    }

    @Test func dekoderForhandsvisning() throws {
        let json = """
        {"club_id":"1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b","name":"Golfgutu","my_status":null,
         "open_members":[{"id":"7d6c8a51-2f0e-4a5b-9a1c-0d2b3c4e5f60","display_name":"Per"}]}
        """
        let p = try JSONDecoder().decode(ClubPreview.self, from: Data(json.utf8))
        #expect(p.openMembers.map(\.displayName) == ["Per"])
        #expect(p.myStatus == nil)
    }

    @Test func tilstandForRadene() {
        let a = UUID()
        let aktiv = medlem(a, .active), venter = medlem(a, .pending)
        #expect(Membership.state(for: [aktiv], remembered: nil) == .active(aktiv))
        #expect(Membership.state(for: [venter], remembered: nil) == .pending(venter))
        #expect(Membership.state(for: [medlem(a, .archived)], remembered: nil) == .noClub)
        #expect(Membership.state(for: [], remembered: nil) == .noClub)
    }
}

/// Sist kjente medlemskap, så appen starter uten nett.
struct MembershipCacheTests {
    private func lager() -> (MembershipCache, UserDefaults) {
        let suite = "klubbcache-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (MembershipCache(defaults: defaults), defaults)
    }

    private let rad = Membership(
        id: UUID(), clubID: UUID(), displayName: "Øyvind", status: .active,
        isOrganizer: true, isTreasurer: false, club: .init(name: "Golfgutu Invitational", joinCode: "A1B2C3D4E5")
    )

    @Test func tarVarePaaPerBruker() {
        let (cache, _) = lager()
        let meg = UUID(), annen = UUID()
        #expect(cache.load(userID: meg) == nil)
        cache.save([rad], userID: meg)
        #expect(cache.load(userID: meg) == [rad])
        #expect(cache.load(userID: annen) == nil)
        cache.save([], userID: annen)
        #expect(cache.load(userID: annen) == [])
    }

    @Test func utloggingSletterAlt() {
        let (cache, defaults) = lager()
        let meg = UUID()
        defaults.set("x", forKey: "valgtKlubb")
        cache.save([rad], userID: meg)
        cache.clear()
        #expect(cache.load(userID: meg) == nil)
        // Andre innstillinger røres ikke.
        #expect(defaults.string(forKey: "valgtKlubb") == "x")
    }
}

/// Bli med: ledige navn og navn som er tatt (PWA: `handleAddSelfAndJoin`).
struct JoinNameTests {
    private func ledig(_ navn: String) -> ClubPreview.OpenMember {
        ClubPreview.OpenMember(id: UUID(), displayName: navn)
    }

    @Test func nyttNavnSomStaarLedig() {
        let ledige = [ledig("Per"), ledig("Åse")]
        #expect(ClubInput.openNameConflict("  per ", openMembers: ledige) != nil)
        #expect(ClubInput.openNameConflict("ÅSE", openMembers: ledige) != nil)
        #expect(ClubInput.openNameConflict("Pål", openMembers: ledige) == nil)
        #expect(ClubInput.openNameConflict("Per", openMembers: []) == nil)
    }

    @Test func meldingenPekerPaaNavnet() {
        guard case .invalidInput(let tekst) = ClubInput.openNameConflict("per", openMembers: [ledig("Per")]) else {
            Issue.record("forventet invalidInput")
            return
        }
        #expect(tekst.contains("«Per»"))
        guard case .invalidInput(let tatt) = ClubInput.nameTakenByOtherLogin("Per") else {
            Issue.record("forventet invalidInput")
            return
        }
        #expect(tatt.contains("annen e-post"))
    }

    @Test func ledigeNavnINorskRekkefolge() {
        let p = ClubPreview(clubID: UUID(), name: "K", myStatus: nil,
                            openMembers: [ledig("Åse"), ledig("Øyvind"), ledig("Ærlige"), ledig("Bjørn"), ledig("Zorro")])
        #expect(p.sortedOpenMembers.map(\.displayName) == ["Bjørn", "Zorro", "Ærlige", "Øyvind", "Åse"])
    }
}

/// Oppstarten prøver på nytt ved nettverksfeil, men bare mens ingenting vises.
struct ClubStartupRetryTests {
    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost])
    func nettverksfeilProvesPaaNytt(code: URLError.Code) {
        #expect(ClubModel.shouldRetry(URLError(code), attempt: 0, retries: 3, state: .loading))
        #expect(ClubModel.shouldRetry(URLError(code), attempt: 2, retries: 3, state: .loading))
    }

    @Test func stopperEtterSisteForsok() {
        #expect(!ClubModel.shouldRetry(URLError(.timedOut), attempt: 3, retries: 3, state: .loading))
    }

    @Test func avbruttEllerAnnenFeilProvesIkke() {
        #expect(!ClubModel.shouldRetry(URLError(.cancelled), attempt: 0, retries: 3, state: .loading))
        #expect(!ClubModel.shouldRetry(ClubError.notAllowed, attempt: 0, retries: 3, state: .loading))
    }

    @Test func ikkeNaarNoeVisesEllerFraFeilskjermen() {
        #expect(!ClubModel.shouldRetry(URLError(.timedOut), attempt: 0, retries: 3, state: .noClub))
        #expect(!ClubModel.shouldRetry(URLError(.timedOut), attempt: 0, retries: 3, state: .failed(.offline)))
    }
}

/// Henting med falske svar: hva `load` gjør med forsøk, ventetid, tidsgrense og avbrudd.
@MainActor
@Suite(.serialized)
struct ClubLoadTests {
    /// Svarene i rekkefølge. `nil` betyr tom liste (ingen klubb). Tomt for svar: henger.
    @MainActor
    final class Script {
        var replies: [(any Error)?]
        private(set) var calls = 0
        init(_ replies: [(any Error)?]) { self.replies = replies }

        func next() async throws -> [Membership] {
            calls += 1
            guard !replies.isEmpty else {
                try await Task.sleep(for: .seconds(30))
                return []
            }
            if let error = replies.removeFirst() { throw error }
            return []
        }
    }

    /// Klokke som ikke venter, men husker ventetidene. Avbrutt oppgave gir `CancellationError`.
    @MainActor
    final class InstantClock: OutboxClock {
        var now = Date()
        private(set) var sleeps: [Duration] = []
        var onSleep: (() -> Void)?
        func sleep(for duration: Duration) async throws {
            sleeps.append(duration)
            onSleep?()
            try Task.checkCancellation()
        }
    }

    let userID = UUID()
    let client = SupabaseClient(supabaseURL: URL(string: "https://example.invalid")!, supabaseKey: "sb_publishable_test")
    let defaults = UserDefaults(suiteName: "ClubLoadTests.\(UUID().uuidString)")!

    func model(_ script: Script, clock: InstantClock = InstantClock(), network: FakeNetwork = FakeNetwork(),
               timeout: Duration = .seconds(5)) -> ClubModel {
        ClubModel(client: client, cache: MembershipCache(defaults: defaults), network: network, clock: clock,
                  attemptTimeout: timeout, fetchRows: { _ in try await script.next() })
    }

    @Test func provesPaaNyttMedOkendeVentetid() async {
        let script = Script([URLError(.notConnectedToInternet), URLError(.timedOut), nil])
        let clock = InstantClock()
        let club = model(script, clock: clock)
        #expect(await club.load(userID: userID) == nil)
        #expect(club.state == .noClub)
        #expect(script.calls == 3)
        #expect(clock.sleeps == [.seconds(1), .seconds(2)])
        #expect(!club.isRefreshing)
        #expect(!club.isWaitingForNetwork)
    }

    @Test func girOppEtterTreNyeForsok() async {
        let script = Script(Array(repeating: URLError(.notConnectedToInternet), count: 5))
        let clock = InstantClock()
        let club = model(script, clock: clock)
        #expect(await club.load(userID: userID) == .offline)
        #expect(club.state == .failed(.offline))
        #expect(script.calls == 4)
        #expect(clock.sleeps == [.seconds(1), .seconds(2), .seconds(4)])
    }

    @Test func fraFeilskjermenBareEttForsok() async {
        let script = Script(Array(repeating: URLError(.notConnectedToInternet), count: 5))
        let clock = InstantClock()
        let club = model(script, clock: clock)
        await club.load(userID: userID)
        await club.refresh(userID: userID)
        #expect(script.calls == 5)
        #expect(clock.sleeps.count == 3)
    }

    @Test func forsokSomHengerFaarTidsgrense() async {
        let script = Script([])
        let club = model(script, timeout: .milliseconds(50))
        #expect(await club.load(userID: userID) == .offline)
        #expect(script.calls == 4)
    }

    @Test func avbruttUnderVentetidRorIkkeTilstanden() async {
        let script = Script([URLError(.notConnectedToInternet)])
        let clock = InstantClock()
        let club = model(script, clock: clock)
        let task = Task { await club.load(userID: userID) }
        clock.onSleep = { task.cancel() }
        #expect(await task.value == nil)
        #expect(club.state == .loading)
        #expect(!club.isRefreshing)
    }

    @Test func provIgjenMensHentingPaagarStarterIngenNy() async {
        let script = Script([])
        let club = model(script)
        let first = Task { await club.load(userID: userID) }
        while script.calls == 0 { await Task.yield() }
        #expect(club.isRefreshing)
        await club.refresh(userID: userID)
        #expect(script.calls == 1)
        first.cancel()
        _ = await first.value
        #expect(!club.isRefreshing)
    }

    @Test func henterNaarNettetKommerTilbake() async {
        let script = Script(Array(repeating: URLError(.notConnectedToInternet), count: 4) + [nil])
        let network = FakeNetwork()
        let club = model(script, network: network)
        await club.load(userID: userID)
        #expect(club.state == .failed(.offline))

        let watcher = Task { await club.reloadWhenOnline(userID: userID) }
        network.send(true)
        await settle()
        #expect(script.calls == 4)

        network.send(false)
        network.send(true)
        await settle()
        #expect(script.calls == 5)
        #expect(club.state == .noClub)
        watcher.cancel()
    }

    @Test func henterIkkeNaarFeilenIkkeErNett() async {
        let script = Script([ClubError.notAllowed])
        let network = FakeNetwork()
        let club = model(script, network: network)
        await club.load(userID: userID)
        let watcher = Task { await club.reloadWhenOnline(userID: userID) }
        network.send(false)
        network.send(true)
        await settle()
        #expect(script.calls == 1)
        watcher.cancel()
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
