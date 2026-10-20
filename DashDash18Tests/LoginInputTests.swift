import Foundation
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

    /// Uten feilkode, eller med en ny: kjente engelske tekster fra Supabase blir norske feil.
    @Test func engelskeTeksterUtenKode() {
        #expect(LoginError.from(errorCode: nil, fallback: "Email rate limit exceeded") == .tooManyAttempts)
        #expect(LoginError.from(errorCode: nil, fallback: "Request rate limit reached") == .tooManyAttempts)
        #expect(LoginError.from(errorCode: "unexpected_failure", fallback: "Too many requests") == .tooManyAttempts)
        #expect(LoginError.from(errorCode: nil, fallback: "Token has expired or is invalid") == .wrongOrExpiredCode)
        #expect(LoginError.from(errorCode: "too_many_requests", fallback: "") == .tooManyAttempts)
    }

    /// Ukjente feil viser ingen engelsk systemtekst, bare en norsk melding.
    @Test func ukjentFeilErNorsk() {
        #expect(LoginError.unknown("AuthApiError: Database error saving new user").message
                == "Noe gikk galt med innloggingen. Vent litt og prøv igjen.")
        #expect(LoginError.tooManyAttempts.message == "For mange forsøk – vent litt og prøv igjen.")
    }

    @Test func alleFeilHarNorskMelding() {
        let feil: [LoginError] = [.invalidEmail, .invalidCode, .wrongOrExpiredCode, .tooManyAttempts, .offline, .appleFailed, .unknown("x")]
        #expect(feil.allSatisfy { !$0.message.isEmpty })
    }

    // Autofyll fra Mail/Meldinger (`oneTimeCode`) og innliming kommer i ett jafs.
    @Test func autofyllSendesMedEnGang() {
        #expect(LoginInput.autoSubmittableCode(previous: "", current: "123456") == "123456")
        #expect(LoginInput.autoSubmittableCode(previous: "", current: "12345678") == "12345678")
        #expect(LoginInput.autoSubmittableCode(previous: "12", current: "123 456") == "123456")
    }

    @Test func skrivingVenterPaaKnappen() {
        // Ett siffer om gangen: vi vet ikke om koden har 6 eller 8 sifre.
        #expect(LoginInput.autoSubmittableCode(previous: "12345", current: "123456") == nil)
        #expect(LoginInput.autoSubmittableCode(previous: "1234567", current: "12345678") == nil)
        // Sletting og søppel sendes ikke.
        #expect(LoginInput.autoSubmittableCode(previous: "123456", current: "") == nil)
        #expect(LoginInput.autoSubmittableCode(previous: "", current: "hei du") == nil)
        #expect(LoginInput.autoSubmittableCode(previous: "", current: "12") == nil)
    }

    @Test func nedtellingTilNyKode() {
        let sendt = Date(timeIntervalSince1970: 1_000)
        #expect(LoginInput.secondsUntilResend(lastSent: nil, now: sendt) == 0)
        #expect(LoginInput.secondsUntilResend(lastSent: sendt, now: sendt) == 60)
        #expect(LoginInput.secondsUntilResend(lastSent: sendt, now: sendt.addingTimeInterval(0.4)) == 60)
        #expect(LoginInput.secondsUntilResend(lastSent: sendt, now: sendt.addingTimeInterval(59.5)) == 1)
        #expect(LoginInput.secondsUntilResend(lastSent: sendt, now: sendt.addingTimeInterval(60)) == 0)
        #expect(LoginInput.secondsUntilResend(lastSent: sendt, now: sendt.addingTimeInterval(500)) == 0)
    }
}
