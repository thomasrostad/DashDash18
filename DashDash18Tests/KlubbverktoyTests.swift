import Foundation
import Testing
@testable import DashDash18

// Klubbverktøyene på arrangørsiden (fase 11): «Varsler til troppen», «Rapporter» og invitasjonskoden i Troppen.

struct ClubToolsTests {
    @Test func meldingTilAlleVirkerOgsaaUtenPush() {
        #expect(ClubTools.noticeRows(pushEnabled: false) == [.announcement])
    }

    @Test func pushRadeneKommerNaarFlaggetErPaa() {
        #expect(ClubTools.noticeRows(pushEnabled: true) == [.announcement, .pushSettings, .pushStatus])
    }

    @Test func rapporterBakModereringsflagget() {
        #expect(ClubTools.hubRows(moderationEnabled: true) == [.notices, .reports])
        #expect(ClubTools.hubRows(moderationEnabled: false) == [.notices])
    }

    @Test func underteksterNevnerBarePushNaarDetErPaa() {
        #expect(ClubTools.noticesSubtitle(pushEnabled: true).contains("push"))
        #expect(!ClubTools.noticesSubtitle(pushEnabled: false).contains("push"))
    }
}

struct TroppInviteTests {
    @Test func delingstekstMedKlubbOgKode() {
        #expect(TroppInvite.shareText(clubName: "Golfgutu Invitational", code: "A1B2C3D4E5")
            == "Bli med i Golfgutu Invitational i Atten: https://dashdash18.com/klubb/A1B2C3D4E5 · Koden er A1B2C3D4E5")
    }

    @Test func ingenKodeGirIngenInvitasjon() {
        #expect(TroppInvite.shareText(clubName: "Klubb", code: nil) == nil)
        #expect(TroppInvite.shareText(clubName: "Klubb", code: "  ") == nil)
    }
}
