import Foundation
import Testing
@testable import DashDash18

// Trykk på en push (fiks/krasj-fra-varsel): appen krasjet når den ble åpnet fra et varsel, fordi
// svaret til iOS kom fra en bakgrunnstråd. Her: innholdet slik `push-send` lager det (`apnsBody` i
// logic.ts), og at svaret alltid går på hovedtråden, én gang.

struct PushTrykkPayloadTests {
    private let event = UUID(uuidString: "6f1c2e2a-1111-4c3a-9d55-2b7a0d9f0a01")!

    /// `planThread` + `apnsBody`: tråden med event_id.
    @Test func traadenFraPushSend() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Tråden · tirsdag 14. oktober", "body": "Ola: hei"],
                    "sound": "default", "thread-id": "thread-\(event.uuidString.lowercased())"],
            "dd18": ["type": "thread", "message_id": "0b6c8a52-2222-4c3a-9d55-2b7a0d9f0a01",
                     "event_id": event.uuidString.lowercased(), "category": "thread"],
        ]
        #expect(PushTarget(userInfo: userInfo) == PushTarget(kind: .thread, eventID: event))
    }

    /// `planActivity` + `apnsBody`: aktivitet med kveld, runde og mål.
    @Test func aktivitetFraPushSend() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "Golfgutu Invitational", "body": "🦅 Ola fikk eagle"], "sound": "default"],
            "dd18": ["type": "activity", "activity_id": "a1", "kind": "big_score",
                     "event_id": event.uuidString, "round_id": "r1",
                     "target_kind": "round", "target_id": "r1", "category": "score"],
        ]
        #expect(PushTarget(userInfo: userInfo) == PushTarget(kind: .activity, eventID: event))
    }

    /// Ved kald oppstart kan innholdet være hva som helst (eldre server, test fra konsollen).
    /// Feil typer skal gi en tom `PushTarget`, aldri krasj.
    @Test func rartInnholdKrasjerIkke() {
        let odd: [[AnyHashable: Any]] = [
            [:],
            ["aps": ["alert": "bare tekst"]],
            ["dd18": "ikke en ordbok"],
            ["dd18": NSNull()],
            ["dd18": ["type": 42, "event_id": NSNull()]],
            ["dd18": ["type": "thread", "event_id": 123]],
            ["dd18": ["type": "thread", "event_id": ""]],
            ["dd18": [1: "tall som nøkkel"]],
        ]
        for userInfo in odd {
            let target = PushTarget(userInfo: userInfo)
            #expect(target.eventID == nil)
        }
        #expect(PushTarget(userInfo: ["dd18": ["type": "thread", "event_id": 123]]).kind == .thread)
    }
}

@MainActor
struct PushSvarTilIOSTests {
    /// iOS kaller delegaten fra hovedtråden: svaret går med en gang.
    @Test func fraHovedtraadenSvaresDetMedEnGang() {
        var ran = false
        PushMainThread.run { ran = Thread.isMainThread }
        #expect(ran)
    }

    /// Fra en bakgrunnstråd (det `async`-delegaten gjorde) skal svaret likevel komme på hovedtråden.
    @Test func fraBakgrunnenSvaresDetPaaHovedtraaden() async {
        let onMain = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                PushMainThread.run { continuation.resume(returning: Thread.isMainThread) }
            }
        }
        #expect(onMain)
    }

    /// iOS tåler ikke at ferdig-blokka kalles to ganger.
    @Test func ferdigBlokkaKallesBareEnGang() {
        var calls = [Int]()
        let done = PushCompletion<Int> { calls.append($0) }
        #expect(!done.isDone)
        done.call(1)
        done.call(2)
        #expect(calls == [1])
        #expect(done.isDone)
    }
}
