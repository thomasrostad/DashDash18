import Foundation
import Testing
@testable import DashDash18

/// TV-kode (sql/041).
struct TVCodeTests {
    @Test func flaggetErAvTil041ErKjørt() {
        #expect(TVCodeFeature.isEnabled == false)
    }

    @Test func lenkeOgVisning() {
        #expect(TVCode.url("ABCDEFGHJK").absoluteString == "https://dashdash18.com/tv/ABCDEFGHJK")
        #expect(TVCode.spaced("ABCDEFGHJK") == "ABCDE FGHJK")
        #expect(TVCode.spaced("KORT") == "KORT")
    }
}
