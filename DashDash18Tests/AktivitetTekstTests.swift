import Foundation
import Testing
@testable import DashDash18

// Visningstekstene for alle hendelsestypene. Ordlyden følger PWA-ens logActivity-kall
// (app-nytt.js: loggStorScore, loggLedelseHvisEndret, svarLinje, purreTekst, handleLockRound,
// handleMeldLongestDrive, handleSendKunngjoring), uten emoji i teksten: ikonet står ved siden av.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let anders = id(1), bjorn = id(2), cato = id(3), thomas = id(9), stranger = id(77)
private let names = [anders: "Anders", bjorn: "Bjørn", cato: "Cato", thomas: "Thomas"]
private func lookup(_ id: UUID) -> String? { names[id] }

private func text(_ event: ActivityEvent, actor: UUID? = thomas, recipients: [UUID]? = nil) -> String {
    ActivityText.display(event, actor: actor, recipients: recipients, name: lookup).text
}

/// Én av hver, for rundtur og dekning.
private let samples: [ActivityEvent] = [
    .roundStarted(roundNo: 1, courseName: "Pebble Beach", holeCount: 18, bays: 3, ldHole: 7, kpHole: nil),
    .roundLocked(roundNo: 2, courseName: nil),
    .roundDeleted(roundNo: 2, courseName: "Pebble Beach"),
    .bigScore(member: anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5),
    .leadChanged(afterHole: 3, leaders: [anders], points: 7, outcome: .leads),
    .sidePrize(kind: .drive, member: bjorn, hole: 7, meters: 245, passed: anders, passedMeters: 231),
    .scoreCorrected(member: anders, hole: 5, from: 5, to: 4, roundNo: 1, courseName: nil),
    .signup(member: anders, status: .yes, eventDate: "2026-10-08"),
    .nudge(eventDate: "2026-10-08"),
    .reminder(eventDate: "2026-10-08", coming: 9, unsure: 2),
    .announcement(text: "Vi starter 17:00"),
    .committeeDrawn(eventDate: "2026-10-08", members: [anders, bjorn]),
    .memberJoined(member: cato),
    .tipsKing(members: [anders], correct: 4, possible: 5, eventDate: "2026-10-08"),
    .betCreated(question: "Noen får birdie på hull 3", side: "no", points: 20),
    .betChallenge(question: "Anders slår Thomas netto på hull 7", against: anders, side: "yes", points: 50),
    .betResolved(question: "Anders slår Thomas netto på hull 7", resolution: "yes"),
]

/// Veddemål (012): PWA-ens ordlyd fra handleUtfordring og markets, med poeng for kroner.
struct AktivitetVeddemaalTests {
    @Test func utfordringNyttOgAvgjort() {
        #expect(text(.betChallenge(question: "Anders slår Thomas netto på hull 7", against: anders, side: "yes", points: 50))
                == "Thomas utfordret Anders: «Anders slår Thomas netto på hull 7» — 50 poeng på JA")
        #expect(text(.betCreated(question: "Noen får birdie på hull 3", side: "no", points: 20))
                == "Thomas åpnet «Noen får birdie på hull 3» og satset 20 poeng på NEI")
        #expect(text(.betCreated(question: "Noen får birdie på hull 3", side: nil, points: nil))
                == "Thomas åpnet «Noen får birdie på hull 3»")
        #expect(text(.betResolved(question: "Q", resolution: "no"), actor: nil) == "Veddemål avgjort: «Q» → NEI")
        #expect(text(.betResolved(question: "Q", resolution: "void"), actor: nil) == "Veddemål annullert: «Q»")
    }

    @Test func leserRadeneFraDatabasen() throws {
        // Feltene slik create_bet og settle_bet skriver dem (sql/012).
        let json = #"{"bet_id":"00000000-0000-0000-0000-000000000099","question":"Q","against":"00000000-0000-0000-0000-000000000001","side":"yes","points":50}"#
        let data = try JSONDecoder().decode(ActivityData.self, from: Data(json.utf8))
        #expect(ActivityEvent(kind: "bet_challenge", data: data) == .betChallenge(question: "Q", against: anders, side: "yes", points: 50))
        let auto = try JSONDecoder().decode(ActivityData.self, from: Data(#"{"question":"Q","resolution":"void","auto":true}"#.utf8))
        #expect(ActivityEvent(kind: "bet_resolved", data: auto) == .betResolved(question: "Q", resolution: "void"))
        #expect(ActivityEvent(kind: "bet_created", data: ActivityData()) == .unknown(kind: "bet_created"))
        #expect(ActivityEvent.betResolved(question: "Q", resolution: "yes").category == .bet)
    }
}

struct AktivitetKatalogTests {
    @Test func katalogenDekkerAlleKjenteTyper() {
        #expect(Set(samples.map(\.kind)) == Set(ActivityEvent.knownKinds))
        #expect(samples.count == ActivityEvent.knownKinds.count)
    }

    @Test(arguments: samples)
    func rundturGjennomKindOgData(_ event: ActivityEvent) throws {
        let json = try JSONEncoder().encode(event.data)
        let back = try JSONDecoder().decode(ActivityData.self, from: json)
        #expect(ActivityEvent(kind: event.kind, data: back) == event)
    }

    @Test func dataBrukerSnakeCaseOgUtelaterTommeFelt() throws {
        let event = ActivityEvent.leadChanged(afterHole: 9, leaders: [anders], points: 19, outcome: .tookLead)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event.data)) as? [String: Any])
        #expect(Set(object.keys) == ["after_hole", "leaders", "points", "outcome"])
        #expect(object["outcome"] as? String == "took_lead")
        let big = ActivityEvent.bigScore(member: anders, hole: 1, holeIndex: 0, name: .holeInOne, strokes: 1, par: 3)
        let o2 = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(big.data)) as? [String: Any])
        #expect(o2["name"] as? String == "hole_in_one")
        #expect(o2["hole_index"] as? Int == 0)
    }

    @Test func kategorierFølgerSkjemaet() {
        #expect(Set(ActivityCategory.allCases.map(\.rawValue)) == [
            "score", "lead", "side_prize", "round", "setup", "bet", "signup", "social", "club", "tips",
            "announcement", "nudge", "reminder",
        ])
        #expect(ActivityEvent.announcement(text: "x").category == .announcement)
        #expect(ActivityEvent.nudge(eventDate: nil).category == .nudge)
        #expect(ActivityEvent.bigScore(member: anders, hole: 1, holeIndex: 0, name: .eagle, strokes: 2, par: 4).category == .score)
        #expect(ActivityEvent.leadChanged(afterHole: 3, leaders: [anders], points: 6, outcome: .leads).category == .lead)
        #expect(ActivityEvent.sidePrize(kind: .kp, member: anders, hole: 3, meters: 2, passed: nil, passedMeters: nil).category == .sidePrize)
        #expect(ActivityEvent.signup(member: anders, status: .yes, eventDate: nil).category == .signup)
        #expect(ActivityCategory.allCases.filter(\.isOrganizerOnly) == [.announcement, .nudge, .reminder])
    }

    @Test func reaksjonssettetErDetFasteFra008() {
        #expect(ActivityReaction.allCases.map(\.rawValue) == ["👍", "😂", "⛳", "🔥", "❤️"])
    }

    @Test func ukjentKindOgManglendeFeltBlirUkjent() {
        #expect(ActivityEvent(kind: "bet_settled", data: ActivityData()) == .unknown(kind: "bet_settled"))
        #expect(ActivityEvent(kind: "big_score", data: ActivityData(member: anders)) == .unknown(kind: "big_score"))
        #expect(text(.unknown(kind: "x")) == "Ny hendelse i klubben")
    }

    @Test func radenTålerUkjentKategoriOgRareData() throws {
        let json = """
        {"id":"\(id(100).uuidString)","club_id":"\(id(900).uuidString)","kind":"big_score","category":"money",
         "data":{"member":"\(anders.uuidString)","hole":"fem","name":"eagle","strokes":3,"par":5},
         "actor_member_id":null,"event_id":null,"round_id":null,"recipients":null,
         "created_at":"2026-10-06T19:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(ActivityRow.self, from: Data(json.utf8))
        #expect(row.category == nil)
        #expect(row.data.hole == nil)
        #expect(row.data.strokes == 3)
        #expect(row.event == .unknown(kind: "big_score"))
    }
}

struct AktivitetTekstTests {
    @Test func nyRunde() {
        #expect(text(samples[0]) == "Ny runde: Runde 1 – Pebble Beach · 18 hull — longest drive på hull 7, 3 båser")
        #expect(text(.roundStarted(roundNo: 2, courseName: nil, holeCount: 9, bays: 1, ldHole: nil, kpHole: 3))
                == "Ny runde: Runde 2 · 9 hull — nærmest pinnen på hull 3, 1 bås")
    }

    @Test func låstOgSlettet() {
        #expect(text(.roundLocked(roundNo: 2, courseName: nil)) == "Thomas låste Runde 2")
        #expect(text(.roundDeleted(roundNo: 2, courseName: "Pebble Beach")) == "Thomas slettet Runde 2 – Pebble Beach")
        // Systemet (cron) eller et slettet medlem.
        #expect(text(.roundLocked(roundNo: 1, courseName: nil), actor: nil) == "Noen låste Runde 1")
    }

    @Test func storeScorerSierSlagOgPar() {
        #expect(text(.bigScore(member: anders, hole: 7, holeIndex: 6, name: .holeInOne, strokes: 1, par: 3))
                == "Anders HOLE IN ONE på hull 7!")
        #expect(text(.bigScore(member: anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5))
                == "Anders eagle på hull 5 — 3 slag på par 5")
        #expect(text(.bigScore(member: anders, hole: 5, holeIndex: 4, name: .albatross, strokes: 2, par: 5))
                == "Anders albatross på hull 5 — 2 slag på par 5")
    }

    @Test func ledelsen() {
        #expect(text(.leadChanged(afterHole: 3, leaders: [anders], points: 7, outcome: .leads))
                == "Anders leder etter 3 hull · 7 poeng")
        #expect(text(.leadChanged(afterHole: 6, leaders: [bjorn], points: 13, outcome: .tookLead))
                == "Bjørn har tatt ledelsen etter 6 hull · 13 poeng")
        #expect(text(.leadChanged(afterHole: 9, leaders: [anders, bjorn, cato], points: 19, outcome: .shares))
                == "Anders, Bjørn og Cato deler ledelsen etter 9 hull · 19 poeng")
        #expect(text(.leadChanged(afterHole: 18, leaders: [anders], points: 38, outcome: .won))
                == "Anders vant runden etter 18 hull · 38 poeng")
        #expect(text(.leadChanged(afterHole: 9, leaders: [bjorn], points: 20, outcome: .snatched))
                == "Bjørn snappet runden på siste hull etter 9 hull · 20 poeng")
        #expect(text(.leadChanged(afterHole: 18, leaders: [anders, bjorn], points: 36, outcome: .tiedFinish))
                == "Anders og Bjørn endte likt etter 18 hull · 36 poeng")
    }

    @Test func sidepremier() {
        #expect(text(.sidePrize(kind: .drive, member: bjorn, hole: 7, meters: 245, passed: anders, passedMeters: 231))
                == "Bjørn leder longest drive på hull 7 med 245 m — forbi Anders (231 m)")
        #expect(text(.sidePrize(kind: .kp, member: anders, hole: 3, meters: 3.4, passed: nil, passedMeters: nil))
                == "Anders nærmest pinnen på hull 3 med 3,4 m")
        #expect(text(.sidePrize(kind: .drive, member: anders, hole: 7, meters: 272.5, passed: bjorn, passedMeters: nil))
                == "Anders leder longest drive på hull 7 med 272,5 m — forbi Bjørn")
    }

    @Test func retting() {
        #expect(text(.scoreCorrected(member: anders, hole: 5, from: 5, to: 4, roundNo: 1, courseName: nil))
                == "Thomas rettet hull 5 for Anders i Runde 1: 5 → 4")
        #expect(text(.scoreCorrected(member: anders, hole: 5, from: nil, to: 4, roundNo: nil, courseName: nil))
                == "Thomas rettet hull 5 for Anders: – → 4")
    }

    @Test func påmeldingenSierBareDetSomErNytt() {
        #expect(text(.signup(member: anders, status: .yes, eventDate: "2026-10-08"))
                == "Anders meldte seg på torsdag 8. oktober")
        #expect(text(.signup(member: anders, status: .no, eventDate: "2026-10-08"))
                == "Anders meldte forfall til torsdag 8. oktober")
        #expect(text(.signup(member: anders, status: .maybe, eventDate: "2026-10-08"))
                == "Anders er likevel usikker på torsdag 8. oktober")
    }

    @Test func purringNavngirDemSomMangler() {
        #expect(text(.nudge(eventDate: "2026-10-08"), recipients: [anders, bjorn, cato])
                == "Hvem kommer torsdag 8. oktober? Mangler svar fra Anders, Bjørn og Cato — svar i appen.")
        #expect(text(.nudge(eventDate: "2026-10-08"), recipients: [bjorn])
                == "Hvem kommer torsdag 8. oktober? Mangler svar fra Bjørn — svar i appen.")
    }

    @Test func påminnelse() {
        #expect(text(.reminder(eventDate: "2026-10-08", coming: 9, unsure: 2))
                == "Påminnelse: torsdag 8. oktober om en uke · 9 kommer, 2 usikre")
        #expect(text(.reminder(eventDate: "2026-10-08", coming: 9, unsure: 1))
                == "Påminnelse: torsdag 8. oktober om en uke · 9 kommer, 1 usikker")
        #expect(text(.reminder(eventDate: "2026-10-08", coming: 9, unsure: 0))
                == "Påminnelse: torsdag 8. oktober om en uke · 9 kommer")
    }

    @Test func meldingTilAlleHarAvsender() {
        #expect(text(.announcement(text: "Vi starter 17:00")) == "Thomas: Vi starter 17:00")
    }

    @Test func meldingTilAlleRensesOgKuttes() {
        // kunngjoring-test.js: linjeskift blir mellomrom, kuttes ved 300 tegn.
        #expect(ActivityText.cleanAnnouncement("Vi starter 17:00 <b>torsdag</b> &\n husk sko")
                == "Vi starter 17:00 <b>torsdag</b> & husk sko")
        #expect(ActivityText.cleanAnnouncement(String(repeating: "x", count: 400)).count == 300)
        #expect(ActivityText.cleanAnnouncement("  \n ").isEmpty)
    }

    @Test func sosialkomiteenKlubbenOgTippekongen() {
        #expect(text(.committeeDrawn(eventDate: "2026-10-08", members: [anders, bjorn]))
                == "Sosialkomiteen torsdag 8. oktober: Anders og Bjørn")
        #expect(text(.memberJoined(member: cato)) == "Cato ble med i klubben")
        #expect(text(.tipsKing(members: [anders], correct: 4, possible: 5, eventDate: "2026-10-08"))
                == "Tippekongen torsdag 8. oktober: Anders med 4 av 5 riktige")
        #expect(text(.tipsKing(members: [anders, bjorn], correct: 3, possible: 5, eventDate: nil))
                == "Tippekongene: Anders og Bjørn med 3 av 5 riktige")
    }

    @Test func ukjentNavnBlirNoen() {
        #expect(text(.memberJoined(member: stranger)) == "Noen ble med i klubben")
    }

    @Test(arguments: samples)
    func alleHarIkonOgEmoji(_ event: ActivityEvent) {
        let d = ActivityText.display(event, actor: thomas, name: lookup)
        #expect(!d.symbol.isEmpty && !d.emoji.isEmpty && !d.text.isEmpty)
        #expect(!d.text.contains("<"))
    }
}
