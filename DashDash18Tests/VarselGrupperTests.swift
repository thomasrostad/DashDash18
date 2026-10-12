import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Varsler, steg 5 (sql/046): fire grupper, demping av én kveld, e-post når du ikke har push,
// og «kvelden er i gang».

struct VarselGruppeTests {
    @Test func gruppenSomPushGroupISql() {
        // Samme tabell som public.push_group(kategori, kind) i 046.
        for category in ["score", "lead", "side_prize", "round", "bet", "tips"] {
            #expect(PushGroup.of(category: category) == .game)
        }
        for category in ["social", "club", "thread"] { #expect(PushGroup.of(category: category) == .social) }
        for category in ["signup", "reminder", "nudge", "setup", "announcement"] {
            #expect(PushGroup.of(category: category) == .evening)
        }
        #expect(PushGroup.of(category: "round", kind: "evening_started") == .evening)
        #expect(PushGroup.of(category: "signup", kind: "signup_dropped") == .organizer)
        #expect(PushGroup.of(category: "penger") == nil)
        // Alle kategoriene appen kjenner har en gruppe.
        for category in ActivityCategory.allCases { #expect(PushGroup.of(category: category.rawValue) != nil) }
    }

    @Test func navnOgArrangørBareMedRettighet() {
        #expect(PushGroup.allCases.map { $0.title() } == ["Spillet", "Sosialt", "Kvelden", "Arrangør"])
        #expect(PushGroup.evening.title(term: .playingDay) == "Spilledagen")
        #expect(PushGroup.evening.subtitle(term: .playingDay) == "Påmelding, påminnelser og når spilledagen er i gang")
        #expect(PushGroup.shown(isOrganizer: false) == [.game, .social, .evening])
        #expect(PushGroup.shown(isOrganizer: true) == [.game, .social, .evening, .organizer])
    }

    @Test func kategorieneUnderHverGruppe() {
        let map = PushGroupMap.local
        let shown = PushCategories.shown(bets: true)
        #expect(map.categories(in: .game, shown: shown) == [.score, .lead, .round, .sidePrize, .tips, .bet])
        #expect(map.categories(in: .social, shown: shown) == [.social, .club])
        #expect(map.categories(in: .evening, shown: shown) == [.reminder, .nudge, .signup, .setup])
        #expect(map.categories(in: .organizer, shown: shown).isEmpty)
        // «Rundene» er Spillet, selv om «kvelden er i gang» er Kvelden.
        #expect(map.mainGroup(of: "round") == .game)
        #expect(map.mainGroup(of: "signup") == .evening)
        #expect(map.extraKinds(in: .evening) == ["evening_started"])
        #expect(map.extraKinds(in: .organizer) == ["signup_dropped"])
        #expect(map.extraKinds(in: .game).isEmpty)
        #expect(PushGroupMap.kindTitle("evening_started", term: .playingDay) == "Spilledagen er i gang")
        #expect(PushGroupMap.kindTitle("signup_dropped") == "Avmeldinger fra «kommer»")
        #expect(PushGroupMap.kindTitle("noe_nytt") == nil)
    }

    @Test func kartetFraServeren() throws {
        let json = #"""
        [{"group_key":"evening","category":"round","kind":"evening_started"},
         {"group_key":"game","category":"round","kind":"round_locked"},
         {"group_key":"game","category":"round","kind":"round_started"},
         {"group_key":null,"category":"ukjent","kind":"x"}]
        """#
        let rows = try JSONDecoder().decode([PushGroupMapRow].self, from: Data(json.utf8))
        let map = PushGroupMap(rows: rows)
        #expect(map.mainGroup(of: "round") == .game)
        #expect(map.extraKinds(in: .evening) == ["evening_started"])
        // Uten rader for kategorien: som push_group(kategori).
        #expect(map.mainGroup(of: "club") == .social)
        #expect(map.mainGroup(of: "ukjent") == nil)
    }

    @Test func gruppevalgetLesesOgLagres() throws {
        let row = try JSONDecoder().decode(PushGroupSettings.self,
                                           from: Data(#"{"disabled_groups":["social"],"email_fallback":false}"#.utf8))
        #expect(row.disabledGroups == ["social"])
        #expect(!row.emailFallback)
        #expect(!row.isOn(.social))
        #expect(row.isOn(.game))
        // Mangler feltene: alt på, e-post på.
        let empty = try JSONDecoder().decode(PushGroupSettings.self, from: Data("{}".utf8))
        #expect(empty == .defaults)
        #expect(empty.emailFallback)

        var next = PushGroupSettings.defaults
        next.set(.social, on: false)
        next.set(.game, on: false)
        next.set(.game, on: false)
        #expect(next.disabledGroups == ["game", "social"])
        next.set(.game, on: true)
        #expect(next.disabledGroups == ["social"])
        #expect(PushGroupSettings(disabledGroups: ["social", "ukjent", "social"]).matches(PushGroupSettings(disabledGroups: ["social"])))
        #expect(!PushGroupSettings(emailFallback: false).matches(.defaults))
    }

    @Test func parameterneTilPushSetGroups() throws {
        let params = PushGroupSettings(disabledGroups: ["social", "evening", "x"], emailFallback: false).rpcParams
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any]
        #expect(json?["p_disabled_groups"] as? [String] == ["evening", "social"])
        #expect(json?["p_email_fallback"] as? Bool == false)
    }

    @Test func dempingOgManglende046() {
        #expect(PushEventMuteText.title() == "Demp denne kvelden")
        #expect(PushEventMuteText.title(term: .playingDay) == "Demp denne spilledagen")
        #expect(PushEventMuteText.subtitle() == "Ingen push om kvelden. Meldinger til alle kommer fortsatt.")
        for code in ["PGRST202", "42883", "42703", "PGRST204", "42P01", "PGRST205"] {
            #expect(PushSchema.isMissing(code: code))
        }
        #expect(!PushSchema.isMissing(code: "42501"))
        #expect(!PushSchema.isMissing(code: nil))
    }

    @Test func ingenTankestrekINyeTekster() {
        var texts = PushGroup.allCases.flatMap { [$0.title(), $0.subtitle(), $0.title(term: .playingDay)] }
        texts += [PushEventMuteText.title(), PushEventMuteText.subtitle(),
                  PushGroupMap.kindTitle("evening_started") ?? "", PushGroupMap.kindTitle("signup_dropped") ?? "",
                  ActivityText.eveningStarted(eventDate: "2026-10-08", roundNo: 1, courseName: "X", term: .evening)]
        for text in texts { #expect(!text.contains("—"), "\(text)") }
    }
}

struct KveldenErIGangTests {
    private func text(_ event: ActivityEvent, term: DayTerm? = nil) -> String {
        ActivityText.display(event, actor: nil, term: term, name: { _ in nil }).text
    }

    private let started = ActivityEvent.eveningStarted(eventDate: "2026-10-08", roundNo: 1, courseName: "Pebble Beach",
                                                       holeCount: 18)

    @Test func tekstenSomPushSend() {
        // Samme tekst som eveningStartedText i push-send (logic_test.ts).
        #expect(text(started) == "Runden er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach")
        #expect(text(started, term: .evening) == "Kvelden er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach")
        #expect(text(started, term: .playingDay) == "Spilledagen er i gang: torsdag 8. oktober · Runde 1 – Pebble Beach")
        #expect(text(.eveningStarted(eventDate: nil, roundNo: 2, courseName: nil, holeCount: nil), term: .playingDay)
                == "Spilledagen er i gang: Runde 2")
        #expect(text(.eveningStarted(eventDate: "2026-10-08", roundNo: nil, courseName: nil, holeCount: nil))
                == "Runden er i gang: torsdag 8. oktober")
        #expect(text(.eveningStarted(eventDate: nil, roundNo: 0, courseName: "Losby", holeCount: nil)) == "Runden er i gang: Losby")
        #expect(text(.eveningStarted(eventDate: nil, roundNo: nil, courseName: nil, holeCount: nil)) == "Runden er i gang")
        let display = ActivityText.display(started, actor: nil, name: { _ in nil })
        #expect(display.emoji == "🏁")
        #expect(display.symbol == "flag.checkered")
    }

    @Test func kategoriRundeOgLestFraDatabasen() throws {
        #expect(started.category == .round)
        #expect(started.kind == "evening_started")
        #expect(ActivityEvent.knownKinds.contains("evening_started"))
        // Feltene slik triggeren i 046 skriver dem.
        let json = #"{"event_date":"2026-10-08","round_no":1,"course_name":"Pebble Beach","hole_count":18}"#
        let data = try JSONDecoder().decode(ActivityData.self, from: Data(json.utf8))
        #expect(ActivityEvent(kind: "evening_started", data: data) == started)
        // Uten felt (jsonb_strip_nulls): fortsatt en kjent hendelse.
        #expect(ActivityEvent(kind: "evening_started", data: ActivityData())
                == .eveningStarted(eventDate: nil, roundNo: nil, courseName: nil, holeCount: nil))
    }
}
