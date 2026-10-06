import Foundation
import Testing
@testable import DashDash18

struct AppConfigTests {
    private func plist(_ values: [String: String]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    private let gyldig = [
        "Environment": "test",
        "SupabaseURL": "https://abcdefghijklmnop.supabase.co",
        "SupabasePublishableKey": "sb_publishable_abc",
    ]

    @Test func lesesGyldigKonfig() throws {
        let config = try AppConfig(plistData: plist(gyldig), expecting: .test)
        #expect(config.environment == .test)
        #expect(config.supabaseURL.absoluteString == "https://abcdefghijklmnop.supabase.co")
        #expect(config.publishableKey == "sb_publishable_abc")
        #expect(config.projectRef == "abcdefghijklmnop")
    }

    @Test func avviserFeilMiljo() throws {
        #expect(throws: AppConfig.LoadError.wrongEnvironment(expected: .prod, found: "test")) {
            try AppConfig(plistData: plist(gyldig), expecting: .prod)
        }
    }

    @Test func avviserHemmeligNokkel() throws {
        var verdier = gyldig
        verdier["SupabasePublishableKey"] = "sb_secret_abc"
        #expect(throws: AppConfig.LoadError.secretKey) {
            try AppConfig(plistData: plist(verdier), expecting: .test)
        }
    }

    @Test func avviserManglendeEllerUsikkerUrl() throws {
        for url in ["", "http://abcdefghijklmnop.supabase.co"] {
            var verdier = gyldig
            verdier["SupabaseURL"] = url
            #expect(throws: AppConfig.LoadError.missingValue("SupabaseURL")) {
                try AppConfig(plistData: plist(verdier), expecting: .test)
            }
        }
    }

    @Test func avviserManglendeNokkel() throws {
        var verdier = gyldig
        verdier.removeValue(forKey: "SupabasePublishableKey")
        #expect(throws: AppConfig.LoadError.missingValue("SupabasePublishableKey")) {
            try AppConfig(plistData: plist(verdier), expecting: .test)
        }
    }

    @Test func byggetBrukerTest() {
        #expect(AppEnvironment.current == .test)
    }

    @Test func testKonfigLiggerIAppen() throws {
        let config = try AppConfig.load(.test)
        #expect(config.environment == .test)
        #expect(config.publishableKey.hasPrefix("sb_publishable_"))
    }
}
