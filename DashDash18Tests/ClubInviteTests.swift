import Foundation
import Testing
@testable import DashDash18

// Invitasjon til klubb (fiks/invitasjon, 09.10.2026): lenken `dashdash://klubb/KODE`, det som limes
// inn, delingsteksten, Hjem-kortet og hva som skjer i hver innloggingstilstand.

struct ClubInviteLinkTests {
    @Test func lagerLenkeMedKoden() {
        #expect(ClubInvite(code: "02e5172c87")?.url.absoluteString == "dashdash://klubb/02E5172C87")
    }

    @Test func leserLenken() throws {
        let url = try #require(URL(string: "dashdash://klubb/02E5172C87"))
        #expect(ClubInvite(url: url)?.code == "02E5172C87")
        let query = try #require(URL(string: "dashdash://klubb?kode=abc-def-2345"))
        #expect(ClubInvite(url: query)?.code == "ABCDEF2345")
        let upper = try #require(URL(string: "DASHDASH://KLUBB/02E5172C87"))
        #expect(ClubInvite(url: upper)?.code == "02E5172C87")
    }

    @Test func andreLenkerErIkkeKlubb() throws {
        #expect(ClubInvite(url: try #require(URL(string: "dashdash://runde/ABCDEFGHJK"))) == nil)
        #expect(ClubInvite(url: try #require(URL(string: "dashdash://konkurranse/ABCDEFGHJK"))) == nil)
        #expect(ClubInvite(url: try #require(URL(string: "https://dashdash18.com/klubb/02E5172C87"))) == nil)
        #expect(ClubInvite(url: try #require(URL(string: "dashdash://klubb/"))) == nil)
    }

    @Test func kodenNormaliseresSomIBliMed() {
        #expect(ClubInvite(code: " 02e5-172c 87 ")?.code == "02E5172C87")
        #expect(ClubInvite(code: "ABC") == nil)
        #expect(ClubInvite(code: "ÆØÅ123") == nil)
        #expect(ClubInvite(code: "A1B2C3D4E5F6G7H8I") == nil)
    }

    @Test func klubblenkerErIkkeRundelenker() throws {
        let link = try #require(URL(string: "dashdash://klubb/02E5172C87"))
        #expect(AppLink.parse(link, rounds: true, competitions: true) == nil)
    }
}

struct ClubInvitePasteTests {
    @Test func kodeAlene() {
        #expect(ClubInvite.parse("  02e5172c87\n")?.code == "02E5172C87")
    }

    @Test func lenkeAlene() {
        #expect(ClubInvite.parse("dashdash://klubb/02E5172C87")?.code == "02E5172C87")
    }

    @Test func heleMeldingen() {
        let text = "Bli med i Golfgutu Invitational i Atten: dashdash://klubb/7KQ2MZ9PXA4R · Koden er 7KQ2MZ9PXA4R"
        #expect(ClubInvite.parse(text)?.code == "7KQ2MZ9PXA4R")
    }

    @Test func lenkeMedPunktumEtter() {
        #expect(ClubInvite.parse("Her: dashdash://klubb/02E5172C87.")?.code == "02E5172C87")
    }

    @Test func gammelMeldingMedBareKode() {
        #expect(ClubInvite.parse("Bli med i Golfgutu Invitational i Atten. Invitasjonskode: 02E5172C87")?.code
            == "02E5172C87")
    }

    @Test func vanligTekstErIkkeEnKode() {
        #expect(ClubInvite.parse("Bli med i Golfgutu Invitational") == nil)
        #expect(ClubInvite.parse("") == nil)
        #expect(ClubInvite.parse("dashdash://runde/ABCDEFGHJK") == nil)
    }

    @Test func delingstekstenKanLimesInnIgjen() throws {
        let invite = try #require(ClubInvite(code: "02E5172C87"))
        let text = invite.shareText(clubName: "Golfgutu Invitational")
        #expect(text == "Bli med i Golfgutu Invitational i Atten: dashdash://klubb/02E5172C87 · Koden er 02E5172C87")
        #expect(ClubInvite.parse(text) == invite)
    }
}

struct ClubInviteHomeCardTests {
    @Test func liteTroppGirKort() {
        #expect(ClubInvite.homeCardRosterLimit == 4)
        #expect(ClubInvite.showsHomeCard(isOrganizer: true, activeMembers: 1, hasCode: true))
        #expect(ClubInvite.showsHomeCard(isOrganizer: true, activeMembers: 3, hasCode: true))
        #expect(!ClubInvite.showsHomeCard(isOrganizer: true, activeMembers: 4, hasCode: true))
    }

    @Test func bareArrangorMedKodeOgKjentTropp() {
        #expect(!ClubInvite.showsHomeCard(isOrganizer: false, activeMembers: 1, hasCode: true))
        #expect(!ClubInvite.showsHomeCard(isOrganizer: true, activeMembers: 1, hasCode: false))
        #expect(!ClubInvite.showsHomeCard(isOrganizer: true, activeMembers: nil, hasCode: true))
    }

    @Test func komIGangHarInviterUnderTroppen() {
        let steps = GettingStarted.steps(.init(hasActiveSeason: true, readyCourses: 0, activeMembers: 1,
                                               upcomingEvenings: 0))
        #expect(steps.filter(GettingStarted.showsInvite(after:)).map(\.item) == [.roster])
    }

    @Test func undertekst() {
        #expect(ClubInvite.organizerSubtitle(activeMembers: 1) == "Bare deg i troppen så langt. Send lenken til gjengen.")
        #expect(ClubInvite.organizerSubtitle(activeMembers: 3) == "3 i troppen. Send lenken til resten av gjengen.")
    }
}

struct ClubInviteFlowTests {
    static let invite = ClubInvite(code: "02E5172C87")!

    static func membership(code: String?, status: MemberStatus, name: String = "Klubben") -> Membership {
        Membership(id: UUID(), clubID: UUID(), displayName: "Thomas", status: status, isOrganizer: false,
                   isTreasurer: false, club: .init(name: name, joinCode: code))
    }

    @Test func ikkeInnloggetHuskes() {
        #expect(ClubInviteFlow.step(isSignedIn: false, club: .loading, memberships: [], invite: Self.invite)
            == .waitForSignIn)
    }

    @Test func venterPaaKlubbene() {
        #expect(ClubInviteFlow.step(isSignedIn: true, club: .loading, memberships: [], invite: Self.invite)
            == .waitForClubs)
        #expect(ClubInviteFlow.step(isSignedIn: true, club: .failed(.offline), memberships: [], invite: Self.invite)
            == .waitForClubs)
    }

    @Test func utenKlubbRettTilBliMed() {
        #expect(ClubInviteFlow.step(isSignedIn: true, club: .noClub, memberships: [], invite: Self.invite) == .join)
    }

    @Test func arkivertTellerIkkeSomKlubb() {
        let archived = Self.membership(code: "02E5172C87", status: .archived)
        #expect(ClubInviteFlow.step(isSignedIn: true, club: .noClub, memberships: [archived], invite: Self.invite)
            == .join)
    }

    @Test func medIAnnenKlubbSporFoerst() {
        let other = Self.membership(code: "ZZZZZZZZZZ", status: .active)
        #expect(ClubInviteFlow.step(isSignedIn: true, club: .active(other), memberships: [other], invite: Self.invite)
            == .confirmJoin)
    }

    @Test func alleredeMed() {
        let other = Self.membership(code: "ZZZZZZZZZZ", status: .active)
        let mine = Self.membership(code: "02e5172c87", status: .active, name: "Golfgutu")
        #expect(ClubInviteFlow.step(isSignedIn: true, club: .active(other), memberships: [other, mine],
                                    invite: Self.invite) == .alreadyMember(mine))
        #expect(ClubInviteFlow.alreadyMemberText(mine) == "Du er allerede med i Golfgutu.")
    }

    @Test func venterPaaGodkjenning() {
        let pending = Self.membership(code: "02E5172C87", status: .pending, name: "Golfgutu")
        #expect(ClubInviteFlow.step(isSignedIn: true, club: .pending(pending), memberships: [pending],
                                    invite: Self.invite) == .alreadyMember(pending))
        #expect(ClubInviteFlow.alreadyMemberText(pending).contains("må godkjenne"))
    }

    @Test func tekstEtterBliMed() {
        #expect(ClubInviteFlow.joinedText(clubName: "Golfgutu", status: .active) == "Du er med i Golfgutu.")
        #expect(ClubInviteFlow.joinedText(clubName: "Golfgutu", status: .pending).contains("godkjenne"))
    }
}

struct PendingClubInviteStoreTests {
    private func store() -> PendingClubInviteStore {
        PendingClubInviteStore(defaults: UserDefaults(suiteName: "test.klubbinvitasjon.\(UUID().uuidString)")!)
    }

    @Test func kodenHuskesGjennomInnloggingen() {
        let store = store()
        let now = Date(timeIntervalSince1970: 1_000_000)
        store.save(ClubInviteFlowTests.invite, now: now)
        #expect(store.load(now: now.addingTimeInterval(600)) == ClubInviteFlowTests.invite)
    }

    @Test func glemmesEtterEnDag() {
        let store = store()
        let now = Date(timeIntervalSince1970: 1_000_000)
        store.save(ClubInviteFlowTests.invite, now: now)
        #expect(store.load(now: now.addingTimeInterval(PendingClubInviteStore.maxAge + 1)) == nil)
        #expect(store.load(now: now) == nil)
    }

    @Test func slettes() {
        let store = store()
        store.save(ClubInviteFlowTests.invite)
        store.clear()
        #expect(store.load() == nil)
    }
}
