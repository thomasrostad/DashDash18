import Foundation
import Testing
@testable import DashDash18

// Trykk på en push åpner skjermen varselet handler om (fiks/varsel-apner-skjerm). Innholdet er
// det `push-send` lager (`planActivity`/`planThread` + `apnsBody` i logic.ts).

struct PushTapPayloadTests {
    private let event = UUID(uuidString: "6f1c2e2a-1111-4c3a-9d55-2b7a0d9f0a01")!
    private let round = UUID(uuidString: "7a2d3f3b-2222-4c3a-9d55-2b7a0d9f0a02")!
    private let competition = UUID(uuidString: "8b3e4a4c-3333-4c3a-9d55-2b7a0d9f0a03")!
    private let club = UUID(uuidString: "9c4f5b5d-4444-4c3a-9d55-2b7a0d9f0a04")!

    /// Slik `apnsBody` pakker en aktivitet: `dd18` med type, id, kind, og kveld og runde når de finnes.
    private func activity(_ kind: String, category: String = "round", event: UUID? = nil, round: UUID? = nil,
                          extra: [String: String] = [:]) -> [AnyHashable: Any] {
        var data: [String: String] = ["type": "activity", "activity_id": "a1", "kind": kind, "category": category]
        if let event { data["event_id"] = event.uuidString.lowercased() }
        if let round { data["round_id"] = round.uuidString.lowercased() }
        data.merge(extra) { _, new in new }
        return ["aps": ["alert": ["title": "Golfgutu Invitational", "body": "…"], "sound": "default",
                        "thread-id": "club-1"],
                "dd18": data]
    }

    private func destination(_ userInfo: [AnyHashable: Any], bets: Bool = true) -> PushDestination? {
        PushTap(userInfo: userInfo, bets: bets)?.destination
    }

    @Test func traadenAapnerTraaden() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Tråden · tirsdag 14. oktober", "body": "Ola: hei"]],
            "dd18": ["type": "thread", "message_id": "m1", "event_id": event.uuidString.lowercased(),
                     "category": "thread"],
        ]
        #expect(destination(userInfo) == .thread(eventID: event, camera: false))
        #expect(destination(userInfo)?.tab == .hjem)
    }

    @Test func traadenUtenKveldAapnerBareAppen() {
        #expect(PushTap(userInfo: ["dd18": ["type": "thread", "message_id": "m1"]]) == nil)
    }

    @Test func rundenMedKveldErKlubbensRunde() {
        for kind in ["round_started", "evening_started", "lead_changed", "big_score", "side_prize", "score_corrected"] {
            #expect(destination(activity(kind, event: event, round: round)) == .clubRound(round), "\(kind)")
        }
    }

    @Test func rundenUtenKveldErLoes() {
        #expect(destination(activity("big_score", category: "score", round: round)) == .looseRound(round))
        #expect(destination(activity("round_locked", round: round)) == .looseRound(round))
    }

    @Test func kveldenStartetUtenRundeAapnerKvelden() {
        #expect(destination(activity("evening_started", event: event)) == .evening(event))
        #expect(destination(activity("round_started")) == .home)
    }

    @Test func laastKlubbrundeAapnerTavla() {
        let target = destination(activity("round_locked", event: event, round: round))
        #expect(target == .tavla)
        #expect(target?.tab == .tavla)
    }

    @Test func slettetRundeOgNySpillerAapnerHjem() {
        #expect(destination(activity("round_deleted", event: event, round: round)) == .home)
        #expect(destination(activity("member_joined", category: "club")) == .home)
    }

    @Test func paameldingOgPurringAapnerKvelden() {
        for kind in ["signup", "signup_dropped", "waitlist_promoted", "nudge", "reminder", "committee_drawn",
                     "tips_king"] {
            #expect(destination(activity(kind, category: "signup", event: event)) == .evening(event), "\(kind)")
        }
        #expect(destination(activity("reminder", category: "reminder")) == .evening(nil))
    }

    @Test func bildeoppfordringenAapnerKameraetITraaden() {
        #expect(destination(activity("photo_prompt", category: "social", event: event, round: round))
            == .thread(eventID: event, camera: true))
        #expect(destination(activity("photo_prompt", category: "social")) == .home)
    }

    @Test func meldingKommentarOgFoelgingAapnerVarsler() {
        for kind in ["announcement", "comment_added", "mentioned", "follow_requested", "follow_accepted", "followed"] {
            #expect(destination(activity(kind, category: "social",
                                         extra: ["target_kind": "activity", "target_id": "x"])) == .notifications,
                    "\(kind)")
        }
    }

    @Test func veddemaalAapnerVeddNaarDetErPaa() {
        for kind in ["bet_challenge", "bet_created", "bet_resolved"] {
            #expect(destination(activity(kind, category: "bet", event: event, round: round)) == .bets, "\(kind)")
            #expect(destination(activity(kind, category: "bet"), bets: false) == .home, "\(kind)")
        }
    }

    @Test func regningenAapnerOppgjoerene() {
        #expect(destination(activity("bill_share_sent", category: "club")) == .bills)
        #expect(destination(activity("bill_share_disputed", category: "club")) == .bills)
    }

    /// `push-send` sender ikke turneringen i dag: da Tavla. Kommer `competition_id`, åpnes tabellen.
    @Test func tabellendringAapnerTavlaEllerTurneringen() {
        #expect(destination(activity("table_changed", category: "lead", event: event, round: round)) == .tavla)
        let withCompetition = activity("table_changed", category: "lead", event: event, round: round,
                                       extra: ["competition_id": competition.uuidString])
        #expect(destination(withCompetition) == .competition(competition))
        #expect(destination(withCompetition)?.tab == .hjem)
    }

    @Test func klubbenLesesNaarDenSendes() {
        #expect(PushTap(userInfo: activity("signup", event: event))?.clubID == nil)
        let tap = PushTap(userInfo: activity("signup", event: event, extra: ["club_id": club.uuidString]))
        #expect(tap == PushTap(destination: .evening(event), clubID: club))
    }

    @Test func ukjentEllerMangelfulltInnholdAapnerBareAppen() {
        let odd: [[AnyHashable: Any]] = [
            [:],
            ["aps": ["alert": "bare tekst"]],
            ["dd18": "ikke en ordbok"],
            ["dd18": NSNull()],
            ["dd18": ["type": 42]],
            ["dd18": ["type": "noe nytt", "event_id": event.uuidString]],
            ["dd18": ["type": "activity"]],
            ["dd18": ["type": "activity", "kind": 7]],
            ["dd18": ["type": "activity", "kind": "en_ny_type", "round_id": round.uuidString]],
            ["dd18": ["type": "thread", "event_id": 123]],
            ["dd18": ["type": "thread", "event_id": ""]],
            ["dd18": [1: "tall som nøkkel"]],
        ]
        for userInfo in odd {
            #expect(PushTap(userInfo: userInfo) == nil)
        }
    }

    @Test func ugyldigeIdErBlirSomOmDeMangler() {
        let userInfo: [AnyHashable: Any] = ["dd18": ["type": "activity", "kind": "big_score",
                                                     "event_id": "ikke-en-uuid", "round_id": 5,
                                                     "club_id": "x"]]
        #expect(PushTap(userInfo: userInfo) == PushTap(destination: .home))
    }
}

@MainActor
struct PushTapInboxTests {
    private let tap = PushTap(destination: .bets)
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    /// Kald oppstart: trykket kommer før innloggingen, og åpnes én gang når RootView er klar.
    @Test func venterTilDetHentesOgHentesBareEnGang() {
        let inbox = PushTapInbox()
        #expect(inbox.take(now: start) == nil)
        inbox.receive(tap, at: start)
        #expect(inbox.pending == tap)
        #expect(inbox.take(now: start.addingTimeInterval(60)) == tap)
        #expect(inbox.pending == nil)
        #expect(inbox.take(now: start.addingTimeInterval(61)) == nil)
    }

    @Test func detSisteTrykketGjelder() {
        let inbox = PushTapInbox()
        inbox.receive(tap, at: start)
        inbox.receive(PushTap(destination: .tavla), at: start.addingTimeInterval(1))
        #expect(inbox.take(now: start.addingTimeInterval(2)) == PushTap(destination: .tavla))
    }

    @Test func gamleTrykkAapnesIkke() {
        let inbox = PushTapInbox()
        inbox.receive(tap, at: start)
        #expect(inbox.take(now: start.addingTimeInterval(PushTapInbox.maxAge + 1)) == nil)
        #expect(inbox.pending == nil)
    }
}

@MainActor
struct HjemRouterPushTests {
    /// Hjem finnes ikke ennå ved kald oppstart: målet venter i routeren til Hjem henter det.
    @Test func maaletVenterTilHjemHenterDet() {
        let router = HjemRouter()
        let round = UUID()
        router.open(.clubRound(round))
        #expect(router.pendingPush == .clubRound(round))
        #expect(router.takePush() == .clubRound(round))
        #expect(router.takePush() == nil)
    }
}
