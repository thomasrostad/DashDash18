import Foundation
import Testing
@testable import DashDash18

// Push (fase 8): token som heks, miljø, parameterne til register_push_device og valgene per
// spiller og klubb. Kategorilistene må stå likt som push_player_categories() og
// push_club_categories() i sql/010_push.sql, og som logic.ts i push-send.

private let member = UUID(uuidString: "11111111-0000-0000-0000-000000000002")!
private let club = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!

struct PushTokenTests {
    @Test func heksMedSmaaBokstaverOgToTegnPerByte() {
        #expect(PushToken.hex(Data([0x00, 0x0f, 0xab, 0xff, 0x10])) == "000fabff10")
        #expect(PushToken.hex(Data()) == "")
    }

    @Test func etEkteTokenPaa32ByteGir64TegnSomDatabasenGodtar() {
        let token = PushToken.hex(Data((0..<32).map { UInt8($0 * 7 & 0xff) }))
        #expect(token.count == 64)
        #expect(PushToken.isValid(token))
    }

    @Test func databasensRegelForToken() {
        #expect(PushToken.isValid(String(repeating: "ab", count: 32)))
        #expect(PushToken.isValid(String(repeating: "a", count: 200)))
        #expect(!PushToken.isValid(String(repeating: "a", count: 63)))
        #expect(!PushToken.isValid(String(repeating: "a", count: 201)))
        #expect(!PushToken.isValid(String(repeating: "AB", count: 32)))
        #expect(!PushToken.isValid(String(repeating: "g", count: 64)))
    }

    @Test func miljoeFraBygget() {
        #expect(PushEnvironment.forBuild(isDebug: true) == .sandbox)
        #expect(PushEnvironment.forBuild(isDebug: false) == .production)
    }

    @Test func parameterneTilRegisterPushDevice() throws {
        let registration = PushDeviceRegistration(deviceID: "enhet", token: "ab", environment: .sandbox, bundleID: "no.x")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(registration)) as? [String: String]
        #expect(json == ["p_device_id": "enhet", "p_token": "ab", "p_environment": "sandbox", "p_bundle_id": "no.x"])
    }
}

struct PushKategoriTests {
    @Test func spillerenKanSlaaAvAltUnntattMeldingTilAlle() {
        // push_player_categories() i 010.
        #expect(PushCategories.playerToggleable.map(\.rawValue) == [
            "score", "lead", "side_prize", "round", "setup", "bet", "signup",
            "social", "club", "tips", "nudge", "reminder",
        ])
    }

    @Test func klubbenKanIkkeSlaaAvMeldingTilAlleOgPurring() {
        // push_club_categories() i 010, uten 'thread'.
        #expect(PushCategories.clubToggleable.map(\.rawValue) == [
            "score", "lead", "side_prize", "round", "setup", "bet", "signup",
            "social", "club", "tips", "reminder",
        ])
    }

    @Test func innstillingeneViserKategorieneFraRoadmapFoerst() {
        let shown = PushCategories.shownToPlayer
        #expect(Array(shown.prefix(5)) == [.score, .lead, .round, .reminder, .nudge])
        #expect(Set(shown).isSubset(of: Set(PushCategories.playerToggleable)))
        #expect(!shown.contains(.bet))
        #expect(!shown.contains(.announcement))
        #expect(Set(shown).count == shown.count)
    }

    @Test func standardErAltPaaOgTraadenNaarJegNevnes() {
        let prefs = PushPreferences.defaults(memberID: member, clubID: club)
        #expect(ActivityCategory.allCases.allSatisfy { prefs.isOn($0) })
        #expect(prefs.threadMode == .mentions)
    }

    @Test func avOgPaaIgjen() {
        var prefs = PushPreferences.defaults(memberID: member, clubID: club)
        prefs.set(.score, on: false)
        #expect(!prefs.isOn(.score))
        #expect(prefs.isOn(.lead))
        #expect(prefs.disabledCategories == ["score"])
        prefs.set(.score, on: false)
        #expect(prefs.disabledCategories == ["score"])
        prefs.set(.score, on: true)
        #expect(prefs.isOn(.score))
        #expect(prefs.disabledCategories.isEmpty)
    }

    @Test func meldingTilAlleKanIkkeSlaasAv() {
        var prefs = PushPreferences.defaults(memberID: member, clubID: club)
        prefs.set(.announcement, on: false)
        #expect(prefs.isOn(.announcement))
        #expect(prefs.disabledCategories.isEmpty)
    }

    @Test func rundturMotDatabasen() throws {
        var prefs = PushPreferences(memberID: member, clubID: club, threadMode: .all)
        prefs.set(.setup, on: false)
        let data = try JSONEncoder().encode(prefs)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["member_id"] as? String == member.uuidString)
        #expect(json?["disabled_categories"] as? [String] == ["setup"])
        #expect(json?["thread_mode"] as? String == "all")
        #expect(try JSONDecoder().decode(PushPreferences.self, from: data) == prefs)
    }

    @Test func ukjenteKategorierBeholdesOgUkjentTraadvalgBlirStandard() throws {
        let json = """
        {"member_id": "\(member.uuidString)", "club_id": "\(club.uuidString)",
         "disabled_categories": ["score", "noe_nytt"], "thread_mode": "rart"}
        """
        var prefs = try JSONDecoder().decode(PushPreferences.self, from: Data(json.utf8))
        #expect(prefs.threadMode == .mentions)
        #expect(!prefs.isOn(.score))
        prefs.set(.score, on: true)
        #expect(prefs.disabledCategories == ["noe_nytt"])
    }

    @Test func klubbensValg() throws {
        let json = #"{"push_disabled_categories": ["setup", "nudge", "thread"]}"#
        let settings = try JSONDecoder().decode(ClubPushSettings.self, from: Data(json.utf8))
        #expect(settings.blocks(.setup))
        #expect(!settings.blocks(.score))
        // Purring og «Melding til alle» har ingen klubbryter, selv om lista skulle si det.
        #expect(!settings.blocks(.nudge))
        #expect(!settings.blocks(.announcement))
        #expect(settings.blocksThread)
        #expect(try JSONDecoder().decode(ClubPushSettings.self, from: Data("{}".utf8)) == ClubPushSettings())
    }

    @Test func traadvalgeneHarNorskeNavn() {
        #expect(ThreadPushMode.allCases.map(\.title) == ["Alle meldinger", "Når jeg nevnes", "Av"])
        #expect(ThreadPushMode.allCases.map(\.rawValue) == ["all", "mentions", "off"])
    }

    @Test(arguments: ActivityCategory.allCases)
    func hverKategoriHarUndertekst(_ category: ActivityCategory) {
        #expect(!PushCategories.subtitle(category).isEmpty)
    }
}

/// Push mens appen står åpen (`dd18` fra push-send) og tillatelse som endres i Innstillinger.
struct PushForegroundTests {
    let event = UUID(uuidString: "eeeeeeee-0000-0000-0000-000000000001")!
    let other = UUID(uuidString: "eeeeeeee-0000-0000-0000-000000000002")!

    @Test func leserTypeOgKveldFraPushen() {
        let thread = PushTarget(userInfo: ["aps": [:], "dd18": ["type": "thread", "message_id": "m", "event_id": event.uuidString.lowercased(), "category": "thread"]])
        #expect(thread == PushTarget(kind: .thread, eventID: event))
        let activity = PushTarget(userInfo: ["dd18": ["type": "activity", "activity_id": "a", "kind": "big_score"]])
        #expect(activity == PushTarget(kind: .activity, eventID: nil))
        #expect(PushTarget(userInfo: [:]) == PushTarget(kind: nil, eventID: nil))
        #expect(PushTarget(userInfo: ["dd18": ["type": "noe nytt", "event_id": "ikke-en-uuid"]]) == PushTarget(kind: nil, eventID: nil))
    }

    @Test func traadenDuSerPaaVarslesIkke() {
        let thread = PushTarget(kind: .thread, eventID: event)
        #expect(!PushForeground.shouldShow(thread, visibleThreadEventID: event))
        #expect(PushForeground.shouldShow(thread, visibleThreadEventID: other))
        #expect(PushForeground.shouldShow(thread, visibleThreadEventID: nil))
    }

    @Test func altAnnetVisesSomBanner() {
        #expect(PushForeground.shouldShow(PushTarget(kind: .activity, eventID: event), visibleThreadEventID: event))
        #expect(PushForeground.shouldShow(PushTarget(kind: nil, eventID: nil), visibleThreadEventID: event))
    }

    @MainActor @Test func tillatelseLestPaaNytt() {
        // Slått på i Innstillinger: registrer. Alt registrert: bli stående.
        #expect(PushRegistrar.nextStatus(.allowed, current: .denied) == .registering)
        #expect(PushRegistrar.nextStatus(.allowed, current: .failed("x")) == .registering)
        #expect(PushRegistrar.nextStatus(.allowed, current: .registered) == .registered)
        // Slått av i Innstillinger mens appen var registrert.
        #expect(PushRegistrar.nextStatus(.denied, current: .registered) == .denied)
        #expect(PushRegistrar.nextStatus(.notDetermined, current: .disabled) == .notDetermined)
    }
}
