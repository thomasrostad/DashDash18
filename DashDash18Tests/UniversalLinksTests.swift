import Foundation
import Testing
@testable import DashDash18

// Universelle lenker (fiks/universelle-lenker): `https://dashdash18.com/<type>/KODE` leses av de samme
// parserne som `dashdash://<type>/KODE`, og deles i stedet for dem når flagget er på.

struct UniversalLinkParsingTests {
    private func url(_ string: String) throws -> URL { try #require(URL(string: string)) }

    @Test func flaggetErPå() {
        #expect(UniversalLinksFeature.isEnabled == true)
    }

    @Test func oversetterTilAppLenken() throws {
        #expect(UniversalLink.appURL(try url("https://dashdash18.com/runde/ABCDEFGH23"))?.absoluteString
            == "dashdash://runde/ABCDEFGH23")
        #expect(UniversalLink.appURL(try url("https://www.dashdash18.com/klubb/02E5172C87/"))?.absoluteString
            == "dashdash://klubb/02E5172C87")
        #expect(UniversalLink.appURL(try url("HTTPS://DashDash18.com/konkurranse/ABCDEFGH23"))?.absoluteString
            == "dashdash://konkurranse/ABCDEFGH23")
    }

    @Test func andreAdresserOversettesIkke() throws {
        for string in [
            "http://dashdash18.com/runde/ABCDEFGH23",
            "https://example.com/runde/ABCDEFGH23",
            "https://dashdash18.com.example.com/runde/ABCDEFGH23",
            "https://dashdash18.com/",
            "https://dashdash18.com/runde",
            "https://dashdash18.com/runde/ABCDEFGH23/mer",
            "https://dashdash18.com/annet/ABCDEFGH23",
            "https://dashdash18.com/Runde/ABCDEFGH23",
            "dashdash://runde/ABCDEFGH23",
        ] {
            #expect(UniversalLink.appURL(try url(string)) == nil, "\(string)")
        }
    }

    @Test func rundeOgKonkurranse() throws {
        let round = try url("https://dashdash18.com/runde/abcde-fgh23")
        #expect(InviteCode(url: round)?.value == "ABCDEFGH23")
        #expect(AppLink.parse(round, rounds: true, competitions: true) == .round(try #require(InviteCode("ABCDEFGH23"))))
        let competition = try url("https://www.dashdash18.com/konkurranse/ABCDEFGH23")
        #expect(InviteCode(url: competition) == nil)
        #expect(AppLink.parse(competition, rounds: true, competitions: true)
            == .competition(try #require(InviteCode("ABCDEFGH23"))))
        #expect(AppLink.parse(competition, rounds: true, competitions: false) == nil)
        #expect(InviteCode(url: try url("https://dashdash18.com/runde/KORT")) == nil)
        #expect(InviteCode(url: try url("https://dashdash18.com/klubb/ABCDEFGH23")) == nil)
    }

    @Test func klubb() throws {
        #expect(ClubInvite(url: try url("https://dashdash18.com/klubb/02e5172c87"))?.code == "02E5172C87")
        #expect(ClubInvite(url: try url("https://dashdash18.com/runde/ABCDEFGH23")) == nil)
        #expect(ClubInvite(url: try url("https://dashdash18.com/klubb/ABC")) == nil)
    }

    @Test func limtInn() {
        #expect(InviteCode.parse("https://dashdash18.com/runde/ABCDEFGH23")?.value == "ABCDEFGH23")
        #expect(InviteCode.parse(" https://dashdash18.com/konkurranse/ABCDEFGH23 ", host: InviteTarget.competitionHost)?
            .value == "ABCDEFGH23")
        #expect(InviteCode.parse("https://example.com/runde/ABCDEFGH23") == nil)
        let message = "Bli med i Golfgutu Invitational i Atten: https://dashdash18.com/klubb/02E5172C87 · Koden er 02E5172C87"
        #expect(ClubInvite.parse(message)?.code == "02E5172C87")
        #expect(ClubInvite.parse("https://www.dashdash18.com/klubb/02e5172c87")?.code == "02E5172C87")
    }
}

struct UniversalLinkSharingTests {
    @Test func klubb() throws {
        let invite = try #require(ClubInvite(code: "02E5172C87"))
        #expect(invite.shareURL(universal: true).absoluteString == "https://dashdash18.com/klubb/02E5172C87")
        #expect(invite.shareURL(universal: false) == invite.url)
        #expect(invite.shareText(clubName: "Golfgutu Invitational", universal: true)
            == "Bli med i Golfgutu Invitational i Atten: https://dashdash18.com/klubb/02E5172C87 · Koden er 02E5172C87")
        #expect(invite.shareText(clubName: "Golfgutu Invitational", universal: false)
            == "Bli med i Golfgutu Invitational i Atten: dashdash://klubb/02E5172C87 · Koden er 02E5172C87")
        // Flagget er av: som før.
        #expect(invite.shareText(clubName: "Golfgutu Invitational") == invite.shareText(clubName: "Golfgutu Invitational", universal: true))
    }

    @Test func runde() throws {
        let code = try #require(InviteCode("ABCDEFGH23"))
        #expect(code.shareText(courseName: "Losby", universal: true)
            == "Bli med på runden på Losby i Atten.\nhttps://dashdash18.com/runde/ABCDEFGH23\n"
            + "Eller skriv inn koden ABCDE-FGH23 under Spill → Bli med.")
        #expect(code.shareText(courseName: "Losby", universal: false)
            == "Bli med på runden på Losby i Atten.\ndashdash://runde/ABCDEFGH23\n"
            + "Eller skriv inn koden ABCDE-FGH23 under Spill → Bli med.")
        #expect(InviteTarget.round(courseName: nil).shareText(code, universal: true)
            == code.shareText(courseName: nil, universal: true))
    }

    @Test func konkurranse() throws {
        let code = try #require(InviteCode("ABCDEFGH23"))
        let target = InviteTarget.competition(name: "Vårcupen")
        #expect(target.shareText(code, universal: true)
            == "Bli med i Vårcupen i Atten.\nhttps://dashdash18.com/konkurranse/ABCDEFGH23\n"
            + "Eller skriv inn koden ABCDE-FGH23 under Turneringer → Bli med med kode.")
        #expect(target.shareText(code, universal: false).contains("dashdash://konkurranse/ABCDEFGH23"))
        #expect(target.shareText(code) == target.shareText(code, universal: true))
    }

    /// Den delte lenken leses tilbake til samme kode.
    @Test func rundtur() throws {
        let code = try #require(InviteCode("ABCDEFGH23"))
        #expect(InviteCode(url: code.shareURL(host: InviteCode.host, universal: true)) == code)
        #expect(InviteCode(url: code.shareURL(host: InviteTarget.competitionHost, universal: true),
                           host: InviteTarget.competitionHost) == code)
        let invite = try #require(ClubInvite(code: "02E5172C87"))
        #expect(ClubInvite(url: invite.shareURL(universal: true)) == invite)
    }
}
