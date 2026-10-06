import Foundation
import Testing
@testable import DashDash18

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(999)

private func event(_ n: Int, _ date: String) -> EventRow {
    EventRow(id: id(100 + n), clubID: club, seasonID: nil, eventDate: date, startTime: "17:00:00", venue: nil, note: nil)
}

private func member(_ n: Int, _ name: String, status: MemberStatus = .active, userID: UUID? = UUID()) -> ClubMemberRow {
    ClubMemberRow(id: id(n), clubID: club, userID: userID, displayName: name, handicapIndex: nil, seedGroup: nil,
                  isOrganizer: false, isTreasurer: false, status: status, avatarPath: nil)
}

private func signup(_ n: Int, _ status: SignupStatus, _ comment: String? = nil) -> SignupRow {
    SignupRow(eventID: id(101), memberID: id(n), clubID: club, status: status, comment: comment)
}

/// Fra neste-kveld-test.js: «Neste kveld rykker opp når kvelden er ferdig».
struct NextEveningTests {
    // Terminlista som i prod: i dag, så hver tredje uke.
    let events = [event(0, "2026-10-06"), event(1, "2026-10-27"), event(2, "2026-11-17"), event(3, "2026-09-15")]

    @Test func datoISagUtenRunderStaarForTur() {
        #expect(NextEvening.next(in: events, today: "2026-10-06")?.id == id(100))
    }

    @Test func kvelderSomHarVaertHoppesOver() {
        #expect(NextEvening.next(in: events, today: "2026-10-07")?.id == id(101))
        #expect(NextEvening.next(in: events, today: "2026-12-01") == nil)
        #expect(NextEvening.next(in: [], today: "2026-10-06") == nil)
    }

    @Test func foersteNiLaastSisteNiSomKladdEllerIGang() {
        let kladd = NextEvening.finishedEventIDs(rounds: [(id(100), .locked), (id(100), .draft)])
        #expect(kladd.isEmpty)
        #expect(NextEvening.next(in: events, today: "2026-10-06", finished: kladd)?.id == id(100))
        let iGang = NextEvening.finishedEventIDs(rounds: [(id(100), .locked), (id(100), .active)])
        #expect(NextEvening.next(in: events, today: "2026-10-06", finished: iGang)?.id == id(100))
    }

    @Test func beggeLaastNesteKveldRykkerOpp() {
        let finished = NextEvening.finishedEventIDs(rounds: [(id(100), .locked), (id(100), .locked)])
        #expect(finished == [id(100)])
        let next = NextEvening.next(in: events, today: "2026-10-06", finished: finished)
        #expect(next?.id == id(101))
        // «… og 21 dager igjen»
        #expect(EveningDates.daysBetween("2026-10-06", next!.eventDate) == 21)
    }

    @Test func enLaastRundeEnAnnenDagRorerIkkeIDag() {
        let finished = NextEvening.finishedEventIDs(rounds: [(id(101), .locked)])
        #expect(NextEvening.next(in: events, today: "2026-10-06", finished: finished)?.id == id(100))
    }
}

/// Fra paamelding-svar-test.js.
struct SignupSummaryTests {
    // Troppen fra testen: a–e og arrangøren k. Erik (e) har aldri logget inn.
    let members = [
        member(1, "Anders Berg"), member(2, "Bjørn Li"), member(3, "Carl <Moe>"),
        member(4, "Dag Ås"), member(5, "Erik Sand", userID: nil), member(6, "Thomas Rostad"),
    ]

    @Test func oversiktenFordelerHeleTroppen() {
        let summary = SignupSummary(members: members, signups: [
            signup(1, .yes, "kommer 17:30"), signup(2, .maybe, ""), signup(3, .no, "<b>bortreist</b>"),
        ])
        #expect(summary.yes.map(\.memberID) == [id(1)])
        #expect(summary.maybe.map(\.memberID) == [id(2)])
        #expect(summary.no.map(\.memberID) == [id(3)])
        #expect(summary.notAnswered.map(\.memberID) == [id(4), id(5), id(6)])
        // Kommentaren står ved navnet, tom kommentar er ingen kommentar.
        #expect(summary.yes.first?.comment == "kommer 17:30")
        #expect(summary.maybe.first?.comment == nil)
        // Navn og kommentar vises som tekst, ikke HTML.
        #expect(summary.no.first?.name == "Carl <Moe>")
        #expect(summary.no.first?.comment == "<b>bortreist</b>")
    }

    @Test func ikkeSvartStaarSistMedAntall() {
        let summary = SignupSummary(members: members, signups: [signup(1, .yes), signup(2, .maybe), signup(3, .no)])
        #expect(summary.groups.map(\.title) == ["Kommer", "Usikker", "Kommer ikke", "Ikke svart"])
        #expect(summary.groups.map(\.entries.count) == [1, 1, 1, 3])
    }

    @Test func ingenSvarAlleErIkkeSvart() {
        let summary = SignupSummary(members: members, signups: [])
        #expect(summary.yes.isEmpty && summary.maybe.isEmpty && summary.no.isEmpty)
        #expect(summary.notAnswered.count == 6)
    }

    @Test func barAktiveMedlemmerTelles() {
        let roster = [member(1, "Anders"), member(2, "Bjørn", status: .archived), member(3, "Cato", status: .pending)]
        let summary = SignupSummary(members: roster, signups: [signup(2, .yes), signup(9, .yes)])
        #expect(summary.yes.isEmpty)
        #expect(summary.notAnswered.map(\.memberID) == [id(1)])
    }

    @Test func troppenSorteresNorsk() {
        let sorted = KveldQueries.sortedByName([member(1, "Åge"), member(2, "Øystein"), member(3, "Zack"), member(4, "Ærlig"), member(5, "Anders")])
        #expect(sorted.map(\.displayName) == ["Anders", "Zack", "Ærlig", "Øystein", "Åge"])
    }
}

/// Fra paamelding-svar-test.js: kommentaren og «samme svar igjen».
struct SignupInputTests {
    @Test func kommentarenTrimmes() {
        #expect(SignupInput.cleanComment("  kommer   18:00  ") == "kommer 18:00")
        #expect(SignupInput.cleanComment("linje\nto\tog tre") == "linje to og tre")
        #expect(SignupInput.cleanComment("   ") == nil)
        #expect(SignupInput.cleanComment("") == nil)
    }

    @Test func kommentarenKappesTil80Tegn() {
        #expect(SignupInput.cleanComment(String(repeating: "x", count: 200))?.count == 80)
        #expect(SignupInput.cleanComment(String(repeating: "x", count: 80))?.count == 80)
        // Emoji med flere kodepunkter kappes helt, og databasens char_length holder.
        let flags = String(repeating: "🇳🇴", count: 50)  // 2 kodepunkter per flagg
        let cut = SignupInput.cleanComment(flags)
        #expect(cut?.count == 40)
        #expect(cut?.unicodeScalars.count == 80)
    }

    @Test func sammeSvarIgjenGjoerIngenting() {
        let current = SignupRow(eventID: id(101), memberID: id(4), clubID: club, status: .yes, comment: "sent")
        #expect(!SignupInput.needsWrite(current: current, status: .yes, comment: "sent"))
        #expect(SignupInput.needsWrite(current: current, status: .no, comment: "sent"))
        #expect(SignupInput.needsWrite(current: current, status: .yes, comment: nil))
        #expect(SignupInput.needsWrite(current: nil, status: .no, comment: nil))
    }

    @Test func svaretSendesMedNullKommentar() throws {
        let row = SignupUpsert(eventID: id(101), memberID: id(4), clubID: club, status: .maybe, comment: nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]
        #expect(json?["status"] as? String == "maybe")
        #expect(json?["comment"] is NSNull)
        #expect(json?["event_id"] as? String == id(101).uuidString)
        #expect(json?["member_id"] as? String == id(4).uuidString)
        #expect(json?["club_id"] as? String == club.uuidString)
    }
}
