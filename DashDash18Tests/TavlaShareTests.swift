import Foundation
import Testing
@testable import DashDash18

/// «Del tavla» (sql/056): lenken og hva arket viser.
struct TavlaShareTests {
    @Test func flaggetErAvTil056ErKjørt() {
        #expect(TavlaShareFeature.isEnabled == false)
    }

    @Test func lenken() {
        #expect(TavlaShare.url("ABCDEFGHJK").absoluteString == "https://dashdash18.com/tavla/ABCDEFGHJK")
        // Samme domene som TV-koden, men en annen sti: delingen kan slås av uten at TV-en slutter å virke.
        #expect(TavlaShare.url("ABCDEFGHJK") != TVCode.url("ABCDEFGHJK"))
    }

    @Test func teksten() {
        #expect(TavlaShare.message("Jakkeracet 2026") == "Følg Jakkeracet 2026 live – tabellen og scorekortene, uten app:")
    }

    @Test func arketForArrangørenOgSpilleren() {
        let link = TavlaShare.url("ABCDEFGHJK")
        #expect(TavlaShare.presentation(code: nil, isOrganizer: true) == .organizerOff)
        #expect(TavlaShare.presentation(code: "ABCDEFGHJK", isOrganizer: true) == .organizerOn(link))
        #expect(TavlaShare.presentation(code: "ABCDEFGHJK", isOrganizer: false) == .playerOn(link))
        #expect(TavlaShare.presentation(code: nil, isOrganizer: false) == .playerOff)
    }
}
