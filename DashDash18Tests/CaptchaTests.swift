import Foundation
import Testing
@testable import DashDash18

/// CAPTCHA (Turnstile) ved innlogging med e-postkode, 1.0.1.
struct CaptchaTests {
    private let key = "0x4AAAAAAAabcdefghijKLMN"

    private func plist(_ values: [String: String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    private var gyldig: [String: String] {
        [
            "Environment": "test",
            "SupabaseURL": "https://abcdefghijklmnop.supabase.co",
            "SupabasePublishableKey": "sb_publishable_abc",
        ]
    }

    // MARK: - Konfig og flagg

    @Test func avUtenSiteKey() throws {
        let config = try AppConfig(plistData: plist(gyldig), expecting: .test)
        #expect(config.turnstileSiteKey == nil)
        #expect(!CaptchaFeature.isEnabled(siteKey: config.turnstileSiteKey))
    }

    @Test func tomSiteKeyErAv() throws {
        var verdier = gyldig
        verdier["TurnstileSiteKey"] = "  "
        let config = try AppConfig(plistData: plist(verdier), expecting: .test)
        #expect(config.turnstileSiteKey == nil)
    }

    @Test func paMedSiteKey() throws {
        var verdier = gyldig
        verdier["TurnstileSiteKey"] = " \(key)\n"
        let config = try AppConfig(plistData: plist(verdier), expecting: .test)
        #expect(config.turnstileSiteKey == key)
        #expect(CaptchaFeature.isEnabled(siteKey: config.turnstileSiteKey))
    }

    @Test func feilSiteKeyStopperAppen() throws {
        for ugyldig in ["kort", "\(key)<script>", String(repeating: "A", count: 101)] {
            var verdier = gyldig
            verdier["TurnstileSiteKey"] = ugyldig
            #expect(throws: AppConfig.LoadError.invalidValue("TurnstileSiteKey")) {
                try AppConfig(plistData: plist(verdier), expecting: .test)
            }
        }
    }

    @Test func siteKeyRegel() {
        #expect(CaptchaFeature.isValidSiteKey(key))
        #expect(CaptchaFeature.isValidSiteKey("1x00000000000000000000AA")) // Cloudflares testnøkkel
        #expect(!CaptchaFeature.isValidSiteKey(""))
        #expect(!CaptchaFeature.isValidSiteKey("0x4AAA"))
        #expect(!CaptchaFeature.isValidSiteKey("0x4AAAAAAA abcdefghijKLMN"))
    }

    // MARK: - Siden

    @Test func sideadressen() {
        let url = TurnstilePage.url(siteKey: key)
        #expect(url.absoluteString == "https://dashdash18.com/captcha?sitekey=\(key)")
        #expect(TurnstilePage.isPageURL(url))
        #expect(TurnstilePage.isPageURL(URL(string: "https://dashdash18.com/captcha/")))
        #expect(!TurnstilePage.isPageURL(URL(string: "http://dashdash18.com/captcha")))
        #expect(!TurnstilePage.isPageURL(URL(string: "https://dashdash18.com.evil.example/captcha")))
        #expect(!TurnstilePage.isPageURL(URL(string: "https://dashdash18.com/klubb/ABC")))
        #expect(!TurnstilePage.isPageURL(nil))
    }

    @Test func meldingerFraSiden() {
        #expect(TurnstileEvent(message: ["type": "token", "token": "abc"]) == .token("abc"))
        #expect(TurnstileEvent(message: ["type": "token", "token": ""]) == nil)
        #expect(TurnstileEvent(message: ["type": "token"]) == nil)
        #expect(TurnstileEvent(message: ["type": "interactive"]) == .interactive)
        #expect(TurnstileEvent(message: ["type": "expired"]) == .expired)
        #expect(TurnstileEvent(message: ["type": "timeout"]) == .timeout)
        #expect(TurnstileEvent(message: ["type": "error", "code": "110200"]) == .error("110200"))
        #expect(TurnstileEvent(message: ["type": "error"]) == .error(""))
        #expect(TurnstileEvent(message: ["type": "noe annet"]) == nil)
        #expect(TurnstileEvent(message: "token") == nil)
    }

    // MARK: - Forløpet

    @Test func tokenGjorSjekkenFerdig() {
        #expect(CaptchaPhase.checking.next(.token("abc")) == .done(token: "abc"))
        #expect(CaptchaPhase.interactive.next(.token("abc")) == .done(token: "abc"))
        // Et ferdig token byttes ikke ut av senere meldinger.
        #expect(CaptchaPhase.done(token: "abc").next(.error("300010")) == .done(token: "abc"))
        #expect(CaptchaPhase.done(token: "abc").next(.token("xyz")) == .done(token: "abc"))
    }

    @Test func feilOgTidsavbrudd() {
        #expect(CaptchaPhase.checking.next(.interactive) == .interactive)
        #expect(CaptchaPhase.interactive.next(.timeout) == .failed(.timedOut))
        #expect(CaptchaPhase.checking.next(.expired) == .checking)
        #expect(CaptchaPhase.checking.next(.error("300010")) == .failed(.failed))
        #expect(CaptchaPhase.checking.next(.error("110200")) == .failed(.misconfigured))
        #expect(CaptchaPhase.checking.next(.error("load")) == .failed(.pageUnavailable))
        #expect(CaptchaPhase.checking.next(.loadFailed(.offline)) == .failed(.offline))
        // «Prøv igjen» starter på nytt.
        #expect(CaptchaPhase.failed(.failed).next(.token("abc")) == .done(token: "abc"))
    }

    @Test func turnstileKoder() {
        #expect(CaptchaError.from(turnstileCode: "110100") == .misconfigured)
        #expect(CaptchaError.from(turnstileCode: "110200") == .misconfigured)
        #expect(CaptchaError.from(turnstileCode: "400020") == .misconfigured)
        #expect(CaptchaError.from(turnstileCode: "200500") == .pageUnavailable)
        #expect(CaptchaError.from(turnstileCode: "load") == .pageUnavailable)
        #expect(CaptchaError.from(turnstileCode: "600010") == .failed)
        #expect(CaptchaError.from(turnstileCode: "") == .failed)
    }

    @Test func nettfeil() {
        #expect(CaptchaError.from(navigationError: URLError(.notConnectedToInternet)) == .offline)
        #expect(CaptchaError.from(navigationError: URLError(.timedOut)) == .offline)
        #expect(CaptchaError.from(navigationError: URLError(.badServerResponse)) == .pageUnavailable)
        #expect(CaptchaError.isCancellation(URLError(.cancelled)))
        #expect(CaptchaError.isCancellation(NSError(domain: "WebKitErrorDomain", code: 102)))
        #expect(!CaptchaError.isCancellation(URLError(.notConnectedToInternet)))
    }

    @Test func feiltekstenePaNorsk() {
        let alle: [CaptchaError] = [.offline, .pageUnavailable, .misconfigured, .failed, .timedOut]
        for error in alle {
            #expect(!error.message.isEmpty)
            #expect(error.message.hasSuffix("."))
        }
        #expect(CaptchaError.failed.message.contains("Prøv igjen"))
    }

    // MARK: - Svaret fra Supabase

    @Test func supabaseAvvisteTokenet() {
        #expect(LoginError.from(errorCode: "captcha_failed", fallback: "") == .captchaFailed)
        #expect(LoginError.from(errorCode: nil, fallback: "captcha protection: request disallowed (no captcha response)") == .captchaFailed)
        #expect(LoginError.captchaFailed.message.contains("Prøv igjen"))
    }
}
