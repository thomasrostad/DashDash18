import Testing
@testable import DashDash18

struct AppleNonceTests {
    @Test func sha256SomKjentTestvektor() {
        // FIPS 180-2, «abc».
        #expect(AppleNonce.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func tilfeldigNonceHarRiktigLengdeOgVarierer() {
        let a = AppleNonce.random()
        let b = AppleNonce.random()
        #expect(a.count == 32)
        #expect(AppleNonce.random(length: 16).count == 16)
        #expect(a != b)
    }
}
