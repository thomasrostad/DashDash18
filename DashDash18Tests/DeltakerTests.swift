import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Deltakermodus (sql/059): påmeldt en klubbturnering uten å være medlem. Deltakerraden i
// `club_members` (kind = participant) er spiller-id-en i klubbens runder og påmeldingen i turneringen,
// men gir ingen klubb i appen. Ingen nettverk.

private enum D {
    static func id(_ n: Int) -> UUID { H.id(n) }

    /// Klubb B: deltakerraden din der, og turneringen du er påmeldt.
    static let clubB = H.clubB
    static let rowB = id(1900)
    static let participation = Participation(id: rowB, clubID: clubB, club: .init(name: "Torsdagsgjengen"))
    static let liga = H.competition(7300, kind: .league, name: "Torsdagsligaen", club: clubB)
    /// En annen turnering i klubb B, som du ikke er påmeldt.
    static let other = H.competition(7400, kind: .league, name: "Vårligaen", club: clubB)

    static func entry(_ c: CompetitionRow, member: UUID, status: CompetitionParticipantRow.Status = .active)
        -> CompetitionParticipantRow {
        CompetitionParticipantRow(id: UUID(), competitionID: c.id, memberID: member, profileID: nil, status: status)
    }

    /// Uten klubb (vennemodus), med deltakerraden i klubb B.
    static let friends = CompetitionAccess(profileID: H.profile, memberships: []).with(participations: [participation])

    /// Medlem i klubb A (valgt i appen) og deltaker i klubb B.
    static let memberA = CompetitionAccess(profileID: H.profile, memberships: [
        .init(clubID: H.clubA, memberID: H.me, isOrganizer: false, isActive: true),
    ]).with(participations: [participation])

    /// Klubbrunde i klubb B som går, der deltakerraden spiller.
    static func roundB(status: RoundStatus = .active, players: [(UUID, String, Int?)]? = nil) -> RoundSnapshot {
        H.snapshot(H.roundRow(id(1901), club: clubB, status: status, roundNo: 2, started: H.ago(minutes: 40)),
                   players: players ?? [(rowB, "Thomas", 1), (H.kari, "Kari", 1)],
                   scores: [(rowB, 0, 4, nil), (H.kari, 0, 5, nil)])
    }
}

struct DeltakerTilgangTests {
    @Test func påmeldingenErDinMedDeltakerraden() {
        let mine = D.entry(D.liga, member: D.rowB)
        #expect(D.friends.isMine(mine))
        #expect(D.friends.participantIDs == [D.rowB])
        #expect(D.friends.rowID(inClub: D.clubB) == D.rowB)
        #expect(D.friends.myEntrants.contains(.member(D.rowB)))
        // Uten deltakerraden kjente appen deg ikke igjen.
        let before = CompetitionAccess(profileID: H.profile, memberships: [])
        #expect(!before.isMine(mine))
        #expect(!before.canSee(D.liga, [mine]))
    }

    @Test func serBareTurneringenDuErPåmeldt() {
        let participants = [D.entry(D.liga, member: D.rowB), D.entry(D.other, member: H.kari)]
        #expect(D.friends.canSee(D.liga, participants))
        // En deltaker er ikke medlem: klubbens andre turneringer er ikke dine.
        #expect(!D.friends.canSee(D.other, participants))
        // Meldt av: borte.
        #expect(!D.friends.canSee(D.liga, [D.entry(D.liga, member: D.rowB, status: .withdrawn)]))
        // Aldri arrangør.
        #expect(!D.friends.isAdmin(D.liga))
        #expect(!D.friends.canCreate(inClub: D.clubB))
    }

    @Test func påmeldingenViserMeldMegAv() {
        var liga = D.liga
        liga.entry = .listed
        liga.signupOpen = true
        #expect(D.friends.signup(liga, [D.entry(liga, member: D.rowB)], isDrawn: false) == .entered)
        // Meldt av: turneringen er ikke lesbar lenger (can_read_competition), så knappen er borte.
        let withdrawn = [D.entry(liga, member: D.rowB, status: .withdrawn)]
        #expect(CompetitionAccess(profileID: H.profile, memberships: [], participants: [.init(clubID: D.clubB, memberID: D.rowB)])
            .signup(liga, withdrawn, isDrawn: false) == .closed)
        // Uten rad i klubben: stengt (join_competition krever en rad).
        #expect(CompetitionAccess(profileID: H.profile, memberships: []).signup(liga, [], isDrawn: false) == .closed)
    }

    @Test func medlemIEnKlubbDeltakerIEnAnnen() {
        let participants = [D.entry(D.liga, member: D.rowB), D.entry(H.liga, member: H.me)]
        #expect(D.memberA.canSee(D.liga, participants))
        #expect(D.memberA.canSee(H.liga, participants))
        #expect(D.memberA.rowIDs == [H.me, D.rowB])
        #expect(D.memberA.rowID(inClub: H.clubA) == H.me)
        #expect(D.memberA.rowID(inClub: D.clubB) == D.rowB)
        #expect(!D.memberA.canSee(D.other, participants))
    }

    /// En klubb du er medlem i, telles ikke også som deltaker.
    @Test func medlemskapetGårForan() {
        let both = CompetitionAccess(profileID: H.profile, memberships: [
            .init(clubID: D.clubB, memberID: H.meB, isOrganizer: false, isActive: true),
        ]).with(participations: [D.participation])
        #expect(both.participants.isEmpty)
        #expect(both.rowID(inClub: D.clubB) == H.meB)
    }

    @Test func deltakerradenDekodes() throws {
        let json = #"[{"id": "\#(D.rowB.uuidString)", "club_id": "\#(D.clubB.uuidString)", "clubs": {"name": "Torsdagsgjengen"}}]"#
        let rows = try JSONDecoder().decode([Participation].self, from: Data(json.utf8))
        #expect(rows == [D.participation])
        #expect(rows.first?.clubName == "Torsdagsgjengen")
        #expect(Participation(id: D.rowB, clubID: D.clubB, club: nil).clubName == "Klubben")
    }
}

struct DeltakerRundeTests {
    @Test func førRundenPåTurneringssiden() {
        let entries = CompetitionPlay.entries(rounds: [D.roundB()], access: D.friends, currentClub: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.title == "Losby · runde 2")
        #expect(entries.first?.target == .participant(ParticipantRound(roundID: D.id(1901), clubID: D.clubB,
                                                                       memberID: D.rowB)))
        // Låst, eller du spiller ikke: ingen knapp.
        #expect(CompetitionPlay.entries(rounds: [D.roundB(status: .locked)], access: D.friends, currentClub: nil).isEmpty)
        let without = D.roundB(players: [(H.kari, "Kari", 1)])
        #expect(CompetitionPlay.entries(rounds: [without], access: D.friends, currentClub: nil).isEmpty)
    }

    @Test func medlemmetFørerPåHjem() {
        let round = H.snapshot(H.roundRow(H.clubRound, club: H.clubA, status: .active, roundNo: 4),
                               players: [(H.me, "Thomas", 1)], scores: [])
        let entries = CompetitionPlay.entries(rounds: [round, D.roundB()], access: D.memberA, currentClub: H.clubA)
        #expect(entries.map(\.target).contains(.club(roundID: H.clubRound)))
        #expect(entries.map(\.target).contains(.participant(ParticipantRound(roundID: D.id(1901), clubID: D.clubB,
                                                                             memberID: D.rowB))))
    }

    @Test func løsRundeIEnTurneringUtenKlubb() {
        let entries = CompetitionPlay.entries(rounds: [H.myLooseRound(status: .active)], access: D.friends, currentClub: nil)
        #expect(entries.map(\.target) == [.loose(roundID: H.looseRound)])
        #expect(entries.first?.title == "Oslo GK")
    }

    @Test func turneringsrunderISpill() throws {
        let items = ParticipantRounds.items([D.roundB(), D.roundB(status: .locked), H.myLooseRound(status: .active)],
                                            participations: [D.participation], referenceYear: 2026)
        let first = try #require(items.first)
        #expect(items.count == 1)
        #expect(first.round == ParticipantRound(roundID: D.id(1901), participation: D.participation))
        #expect(first.item.title == "Losby")
        #expect(first.item.subtitle.hasPrefix("Torsdagsgjengen · "))
        #expect(first.item.mine?.hasPrefix("Du: ") == true)
        #expect(first.item.status == .active)
    }

    @Test func rundenHørerTilKlubbenDuErDeltakerI() {
        #expect(ParticipantRounds.round(D.roundB(), participations: [D.participation]) != nil)
        #expect(ParticipantRounds.round(D.roundB(), participations: []) == nil)
        #expect(ParticipantRounds.participation(forClub: H.clubA, in: [D.participation]) == nil)
        #expect(ParticipantRounds.participation(forClub: nil, in: [D.participation]) == nil)
        #expect(ParticipantRounds.memberships([D.participation]) == [D.clubB: D.rowB])
    }

    @Test func livebarenUtenKlubb() throws {
        let live = LiveRoundsModel.live([D.roundB(), H.myLooseRound(status: .active)], userID: H.profile,
                                        participations: [D.participation], now: H.now)
        #expect(live.count == 2)
        let club = try #require(live.first { !$0.isLoose })
        #expect(club.roundID == D.id(1901))
        #expect(club.barAction == "Fortsett")
        // Uten deltakerraden: bare den løse runden, som før.
        #expect(LiveRoundsModel.live([D.roundB()], userID: H.profile, now: H.now).isEmpty)
    }
}
