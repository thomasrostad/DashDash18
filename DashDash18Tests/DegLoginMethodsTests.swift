import Foundation
import Testing
@testable import DashDash18

struct DegLoginMethodsTests {
    @Test func ePostkontoViserEPostKobletOgAppleIkkeKoblet() {
        let rows = LoginMethods.rows(identities: [LinkedIdentity(provider: "email", email: "thomas@example.com")],
                                     appleLinkingEnabled: false)
        #expect(rows.map(\.method) == [.apple, .email, .google])
        #expect(rows[0].status == .notLinked(canLink: false))
        #expect(rows[1].status == .linked(detail: "thomas@example.com"))
        #expect(rows[2].status == .comingSoon)
        #expect(rows.map(\.trailingText) == ["Ikke koblet", "Koblet", "Kommer"])
    }

    @Test func appleKanKoblesNaarDetErSlaattPaa() {
        let rows = LoginMethods.rows(identities: [LinkedIdentity(provider: "email")], appleLinkingEnabled: true)
        #expect(rows[0].status == .notLinked(canLink: true))
        // E-post kobles ved å logge inn med kode, ikke med en knapp her.
        let appleOnly = LoginMethods.rows(identities: [LinkedIdentity(provider: "apple")], appleLinkingEnabled: true)
        #expect(appleOnly[1].status == .notLinked(canLink: false))
    }

    @Test func appleSkjultEPostVisesSomSkjult() {
        let rows = LoginMethods.rows(identities: [
            LinkedIdentity(provider: "apple", email: "abc123@privaterelay.appleid.com"),
            LinkedIdentity(provider: "email", email: "thomas@example.com"),
        ])
        #expect(rows[0].status == .linked(detail: "Skjult e-post"))
        #expect(rows[1].status == .linked(detail: "thomas@example.com"))
    }

    @Test func appleUtenEPostHarIngenDetalj() {
        let rows = LoginMethods.rows(identities: [LinkedIdentity(provider: "Apple", email: "")])
        #expect(rows[0].status == .linked(detail: nil))
    }

    @Test func googleVisesSomKoblet() {
        // Om Google blir satt opp og kontoen har den, vises den som koblet.
        let rows = LoginMethods.rows(identities: [LinkedIdentity(provider: "google", email: "t@gmail.com")])
        #expect(rows[2].status == .linked(detail: "t@gmail.com"))
    }

    @Test func ukjenteMaaterVisesIkke() {
        let rows = LoginMethods.rows(identities: [LinkedIdentity(provider: "github")])
        #expect(rows.count == 3)
        #expect(!rows.contains { if case .linked = $0.status { true } else { false } })
    }

    @Test func koblingErAvTilSupabaseErSattOpp() {
        #expect(AccountLinkingFeature.appleEnabled == false)
    }
}

struct DegSignOutTests {
    @Test func bekreftelsenSierHvordanDuKommerInnIgjen() {
        #expect(LoginMethods.signOutMessage(identities: []) == "Du trenger en ny kode på e-post for å logge inn igjen.")
        #expect(LoginMethods.signOutMessage(identities: [LinkedIdentity(provider: "email")])
            == "Du trenger en ny kode på e-post for å logge inn igjen.")
        #expect(LoginMethods.signOutMessage(identities: [LinkedIdentity(provider: "apple")]) == "Du logger inn igjen med Apple.")
        #expect(LoginMethods.signOutMessage(identities: [LinkedIdentity(provider: "apple"), LinkedIdentity(provider: "email")])
            == "Du logger inn igjen med Apple eller en ny kode på e-post.")
        // Google (før GoogleLoginFeature slås på): bare Google skal ikke få beskjed om e-postkode.
        #expect(LoginMethods.signOutMessage(identities: [LinkedIdentity(provider: "google")]) == "Du logger inn igjen med Google.")
        #expect(LoginMethods.signOutMessage(identities: [LinkedIdentity(provider: "google"), LinkedIdentity(provider: "email")])
            == "Du logger inn igjen med Google eller en ny kode på e-post.")
        #expect(LoginMethods.signOutMessage(identities: [LinkedIdentity(provider: "apple"), LinkedIdentity(provider: "google"),
                                                         LinkedIdentity(provider: "email")])
            == "Du logger inn igjen med Apple, Google eller en ny kode på e-post.")
        #expect(LoginMethods.signOutMessage(identities: [LinkedIdentity(provider: "apple"), LinkedIdentity(provider: "google")])
            == "Du logger inn igjen med Apple eller Google.")
    }

    @Test func hullIKoeNevnesFoerst() {
        let hint = "Du logger inn igjen med Apple."
        #expect(SignOutButton.confirmation(pending: 0, loginHint: hint) == hint)
        #expect(SignOutButton.confirmation(pending: 2, loginHint: hint)
            == "2 hull er ikke sendt ennå. De sendes neste gang du logger inn på denne telefonen. Du logger inn igjen med Apple.")
    }
}

struct LinkIdentityErrorTests {
    @Test func feilkoderTilNorsk() {
        #expect(LinkIdentityError.from(errorCode: "identity_already_exists", fallback: "") == .alreadyUsed)
        #expect(LinkIdentityError.from(errorCode: "manual_linking_disabled", fallback: "") == .notEnabled)
        #expect(LinkIdentityError.from(errorCode: "bad_jwt", fallback: "") == .appleFailed)
        #expect(LinkIdentityError.from(errorCode: nil, fallback: "x") == .unknown("x"))
        #expect(LinkIdentityError.alreadyUsed.message.contains("annen konto"))
    }
}
