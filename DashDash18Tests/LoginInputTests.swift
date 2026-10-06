import Testing
@testable import DashDash18

struct LoginInputTests {
    @Test(arguments: [
        ("deg@epost.no", "deg@epost.no"),
        ("  Thomas@Fink.NO \n", "thomas@fink.no"),
        ("a.b+golf@sub.example.com", "a.b+golf@sub.example.com"),
    ])
    func gyldigEpost(_ input: String, _ forventet: String) {
        #expect(LoginInput.normalizedEmail(input) == forventet)
    }

    @Test(arguments: ["", "deg", "deg@", "deg@epost", "@epost.no", "deg @epost.no", "deg@ep ost.no"])
    func ugyldigEpost(_ input: String) {
        #expect(LoginInput.normalizedEmail(input) == nil)
    }

    @Test(arguments: [
        ("123456", "123456"),
        ("12345678", "12345678"),   // 8 sifre: PWA-en klippet denne en gang
        (" 123 456 ", "123456"),
        ("123-456", "123456"),
    ])
    func gyldigKode(_ input: String, _ forventet: String) {
        #expect(LoginInput.normalizedCode(input) == forventet)
    }

    @Test(arguments: ["", "123", "12345678901", "12a456", "١٢٣٤٥٦"])
    func ugyldigKode(_ input: String) {
        #expect(LoginInput.normalizedCode(input) == nil)
    }

    @Test func feilkoderFraSupabase() {
        #expect(LoginError.from(errorCode: "otp_expired", fallback: "") == .wrongOrExpiredCode)
        #expect(LoginError.from(errorCode: "over_email_send_rate_limit", fallback: "") == .tooManyAttempts)
        #expect(LoginError.from(errorCode: "over_request_rate_limit", fallback: "") == .tooManyAttempts)
        #expect(LoginError.from(errorCode: "email_address_invalid", fallback: "") == .invalidEmail)
        #expect(LoginError.from(errorCode: "noe_nytt", fallback: "detalj") == .unknown("detalj"))
        #expect(LoginError.from(errorCode: nil, fallback: "detalj") == .unknown("detalj"))
    }

    @Test func alleFeilHarNorskMelding() {
        let feil: [LoginError] = [.invalidEmail, .invalidCode, .wrongOrExpiredCode, .tooManyAttempts, .offline, .unknown("x")]
        #expect(feil.allSatisfy { !$0.message.isEmpty })
    }
}
