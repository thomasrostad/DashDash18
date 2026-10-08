import Foundation
import Testing
@testable import DashDash18

// Hjem-fanen (fase 19, del 2): det lille viewene trenger utover feeden, og Varsler bak bjella.

struct HjemVisningTests {
    private func live(loose: Bool, me: HomeLive.Row? = nil) -> HomeLive {
        HomeLive(roundID: H.id(1), isLoose: loose, progress: "Hull 10 av 18", title: "Losby · runde 4", detail: nil,
                 top: [HomeLive.Row(id: H.id(2), place: "1.", name: "Bjørn", value: "23", isMe: false)],
                 me: me, actionTitle: "Fortsett føringen")
    }

    @Test func pågårNåFølgerFilteret() {
        let club = live(loose: false), loose = live(loose: true)
        #expect(HjemDisplay.showsLive(club, filter: .all))
        #expect(HjemDisplay.showsLive(club, filter: .competition(H.jakke.id)))
        #expect(!HjemDisplay.showsLive(club, filter: .loose))
        #expect(HjemDisplay.showsLive(loose, filter: .loose))
        #expect(!HjemDisplay.showsLive(loose, filter: .club(H.clubB)))
        #expect(HjemDisplay.showsEvening(filter: .all))
        #expect(!HjemDisplay.showsEvening(filter: .loose))
    }

    @Test func degUnderTopp3() {
        let me = HomeLive.Row(id: H.id(9), place: "5.", name: "Thomas", value: "18", isMe: true)
        let rows = HjemDisplay.liveRows(live(loose: false, me: me))
        #expect(rows.map(\.name) == ["Bjørn", "Thomas"])
        #expect(HjemDisplay.liveName(me) == "Thomas (deg)")
        #expect(HjemDisplay.liveName(rows[0]) == "Bjørn")
    }

    @Test func tabellenGårTilTavlaForHovedturneringenIKlubben() {
        #expect(HjemDisplay.tableLink(competitionID: H.jakke.id, competition: H.jakke, currentClub: H.clubA) == .tavla)
        // Hovedturneringen i en annen klubb, en liga og en ukjent turnering har egen side.
        #expect(HjemDisplay.tableLink(competitionID: H.jakke.id, competition: H.jakke, currentClub: H.clubB)
                == .competition(H.jakke.id))
        #expect(HjemDisplay.tableLink(competitionID: H.liga.id, competition: H.liga, currentClub: H.clubA)
                == .competition(H.liga.id))
        #expect(HjemDisplay.tableLink(competitionID: H.id(5), competition: nil, currentClub: H.clubA)
                == .competition(H.id(5)))
    }

    @Test func tomTilstandSierHvaSomKommer() {
        #expect(HjemDisplay.emptyTitle == "Ingenting her ennå.")
        #expect(HjemDisplay.emptyLine(.all).contains("eagle"))
        #expect(HjemDisplay.emptyLine(.loose).contains("Løse runder"))
        #expect(HjemDisplay.emptyLine(.competition(H.jakke.id)) != HjemDisplay.emptyLine(.all))
    }

    @Test func dinRundeForVoiceOver() throws {
        let feed = HomeFeed.build({ var i = H.input(); i.rounds = [H.myClubRound()]; return i }())
        let card = try #require(feed.sections.flatMap(\.cards).first)
        guard case .myRound(let round) = card.content else { Issue.record("ikke din runde"); return }
        let label = HjemDisplay.myRoundLabel(round)
        #expect(label.hasPrefix("Din runde. Losby"))
        #expect(label.contains("5 poeng"))
        #expect(HjemDisplay.isUp(1) && !HjemDisplay.isUp(-1))
    }
}

struct HjemVarslerTests {
    @Test func bareDetSomAngårDegMedUlestOgReaksjoner() throws {
        let rows = [
            H.row(1, .announcement(text: "Husk sko"), actor: H.anders, at: H.ago(minutes: 5)),
            H.row(2, .announcement(text: "Min egen"), actor: H.me, at: H.ago(minutes: 4)),
            H.row(3, club: H.clubB, .nudge(eventDate: "2026-10-15"), at: H.ago(days: 2), recipients: [H.meB]),
        ]
        let bell = HomeBell.rows(rows, viewer: H.viewer)
        let reactions = [ActivityReactionRow(activityID: rows[0].id, memberID: H.me, clubID: H.clubA, emoji: .fire)]
        let sections = HomeBellList.sections(bell, reactions: reactions, names: H.names, viewer: H.viewer,
                                             lastSeen: H.ago(minutes: 30), now: H.now)
        #expect(sections.map(\.title) == ["I dag", "Tidligere"])
        let today = try #require(sections.first)
        #expect(today.items.map(\.row.id) == [rows[1].id, rows[0].id])
        // Ditt eget er aldri ulest; det andres er nyere enn sist sett.
        #expect(today.items.map(\.isUnread) == [false, true])
        let husk = today.items[1]
        #expect(husk.chips.first?.isMine == true)
        #expect(husk.target == HomeReactions(activityID: rows[0].id, clubID: H.clubA, chips: husk.chips))
        // Purringen i den andre klubben står også, og reaksjonen går dit.
        #expect(sections[1].items.first?.target.clubID == H.clubB)
    }

    @Test func aldriSettErAltUlest() {
        let row = H.row(1, .announcement(text: "Hei"), actor: H.anders, at: H.ago(minutes: 5))
        #expect(HomeBellList.isUnread(row, lastSeen: nil, viewer: H.viewer))
        #expect(!HomeBellList.isUnread(row, lastSeen: H.ago(minutes: 1), viewer: H.viewer))
    }
}
