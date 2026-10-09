import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Hjem-feeden (fase 19): kortene på tvers av klubber, turneringer og løse runder, filterpillene,
// seksjonene, oppsummeringen, «Pågår nå» og «Neste kveld». Ingen nettverk.

enum H {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    /// Torsdag 8. oktober 2026 kl. 20:00 i Oslo.
    static let now = Date(timeIntervalSince1970: 1_791_482_400)  // 2026-10-08T18:00:00Z
    static func ago(minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
    static func ago(days: Double) -> Date { now.addingTimeInterval(-days * 24 * 3600) }

    // Klubb A (Golfgutu, med jakkeracet) og klubb B (uten hovedturnering).
    static let clubA = id(900), clubB = id(800)
    static let profile = id(100)
    static let me = id(9), meB = id(19)
    static let anders = id(1), bjorn = id(2), cato = id(3), kari = id(21)
    static let viewer = HomeViewer(profileID: profile, memberships: [clubA: me, clubB: meB])
    static let clubs = [HomeClub(id: clubA, name: "Golfgutu Invitational"), HomeClub(id: clubB, name: "Torsdagsgjengen")]
    static let names: [UUID: String] = [me: "Thomas", meB: "Thomas", anders: "Anders Berg", bjorn: "Bjørn",
                                        cato: "Cato", kari: "Kari", per: "Per", ola: "Ola"]

    static let jakke = competition(7000, kind: .season, name: "Jakkeracet", club: clubA, main: true)
    static let morro = competition(7100, kind: .fun, name: "Morrocupen", club: nil, entry: .open)
    static let liga = competition(7200, kind: .league, name: "Høstligaen", club: clubA)

    static func competition(_ n: Int, kind: CompetitionKind, name: String, club: UUID?, main: Bool = false,
                            entry: CompetitionEntry = .club) -> CompetitionRow {
        CompetitionRow(id: id(n), kind: kind, name: name, clubID: club, ownerID: club == nil ? profile : nil,
                       seasonID: kind == .season ? id(n + 1) : nil, status: .active, entry: entry, rules: .golfgutu,
                       startsOn: nil, endsOn: nil, isMain: main, requiresPurchase: false, entitlementID: nil)
    }

    static let clubRound = id(901), clubRound2 = id(902)

    static func row(_ n: Int, club: UUID = clubA, _ event: ActivityEvent, actor: UUID? = nil, round: UUID? = nil,
                    at date: Date, recipients: [UUID]? = nil) -> ActivityRow {
        ActivityRow(id: id(10_000 + n), clubID: club, kind: event.kind, category: event.category, data: event.data,
                    actorMemberID: actor, eventID: nil, roundID: round, recipients: recipients, createdAt: date)
    }

    static func input(_ activity: [ActivityRow] = [], filter: HomeFeedFilter = .all, lastSeen: Date? = nil)
        -> HomeFeedInput {
        var input = HomeFeedInput(now: now, viewer: viewer)
        input.clubs = clubs
        input.competitions = [jakke, morro, liga]
        input.links = [CompetitionRoundRow(competitionID: jakke.id, roundID: clubRound, source: .season),
                       CompetitionRoundRow(competitionID: jakke.id, roundID: clubRound2, source: .season),
                       CompetitionRoundRow(competitionID: liga.id, roundID: clubRound2, source: .manual)]
        input.activity = activity
        input.names = names
        input.roundLabels = [clubRound: HomeRoundLabel(courseName: "Losby", roundNo: 4)]
        input.filter = filter
        input.lastSeen = lastSeen
        return input
    }

    // MARK: Runder

    static let par = [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 3, 5, 4, 4, 3, 4, 5, 4]

    static func roundRow(_ rid: UUID, club: UUID?, status: RoundStatus, roundNo: Int = 1, locked: Date? = nil,
                         started: Date? = nil) -> RoundRow {
        RoundRow(id: rid, clubID: club, eventID: club == nil ? nil : id(950), courseID: id(960), roundNo: roundNo,
                 name: nil, status: status, holeCount: 18, firstHole: 1, teeTime: nil, format: "stableford",
                 handicapAllowance: 1, externalHandicap: false, weight: 1, ldEnabled: false, ldHoleIndex: nil,
                 kpEnabled: false, kpHoleIndex: nil, cutRule: nil, cutAfter: nil, parConfirmedBy: nil,
                 parConfirmedAt: Date(timeIntervalSince1970: 0), startedAt: started ?? locked, lockedAt: locked)
    }

    /// `players`: (spiller-id, navn, bås). `scores`: (spiller-id, hull, slag, ført).
    static func snapshot(_ round: RoundRow, players: [(UUID, String, Int?)], scores: [(UUID, Int, Int, Date?)],
                         course: String = "Losby", loose: LooseRoundInfo? = nil) -> RoundSnapshot {
        var s = RoundSnapshot(round: round)
        s.players = players.map { p in
            RoundPlayerRow(roundID: round.id, memberID: p.0, clubID: round.clubID, handicapIndex: 0, seedGroup: nil,
                           playingHandicap: nil, bayNo: p.2, isMarker: false, teamNo: nil)
        }
        s.names = Dictionary(uniqueKeysWithValues: players.map { ($0.0, $0.1) })
        s.course = CourseRow(id: id(960), clubID: round.clubID, name: course, externalName: nil, courseRating: 72,
                             slopeRating: 113, inUse: true, confirmedBy: nil, confirmedAt: nil)
        s.courseHoles = par.indices.map { i in
            CourseHoleRecord(courseID: id(960), holeNumber: i + 1, par: par[i], strokeIndex: i + 1, lengthM: nil)
        }
        s.scores = scores.map { p, hole, strokes, at in
            HoleScoreRow(roundID: round.id, memberID: p, holeIndex: hole, strokes: strokes, recordedAt: at,
                         updatedBy: nil, updatedAt: nil)
        }
        if let loose {
            s.loose = loose
            s.rules = LooseRoundRules.template
            s.eventDate = round.startedAt.map(LooseRoundInfo.day)
        }
        return s
    }

    /// Klubbrunden du spilte: Thomas 3 + 5 + 5 (birdie, par, dobbel = 5 p), Anders 4 + 3 (par, eagle = 6 p),
    /// Bjørn 5 (bogey = 1 p).
    static func myClubRound(locked: Date = ago(minutes: 90)) -> RoundSnapshot {
        snapshot(roundRow(clubRound, club: clubA, status: .locked, roundNo: 4, locked: locked),
                 players: [(me, "Thomas", 1), (anders, "Anders Berg", 1), (bjorn, "Bjørn", 2)],
                 scores: [(me, 0, 3, nil), (me, 1, 5, nil), (me, 2, 5, nil), (anders, 0, 4, nil), (anders, 1, 3, nil),
                          (bjorn, 0, 5, nil)])
    }

    // Løse runder: Thomas (profil) og Per (gjest), Ola (gjest).
    static let looseRound = id(970), looseRound2 = id(971)
    static let myPart = id(980), per = id(981), ola = id(982)

    static func looseInfo(_ rid: UUID, _ seats: [(UUID, String, UUID?)]) -> LooseRoundInfo {
        LooseRoundInfo(ownerID: profile, roster: seats.map {
            RoundRosterRow(roundID: rid, playerID: $0.0, clubID: nil, displayName: $0.1, profileID: $0.2,
                           isGuest: $0.2 == nil)
        })
    }

    /// Løs runde i går: Per hole in one på hull 3 (par 3).
    static func myLooseRound(status: RoundStatus = .locked) -> RoundSnapshot {
        let rid = looseRound
        let row = roundRow(rid, club: nil, status: status, locked: status == .locked ? ago(days: 1) : nil,
                           started: ago(days: 1.1))
        return snapshot(row, players: [(myPart, "Thomas", 1), (per, "Per", 1)],
                        scores: [(myPart, 0, 3, ago(days: 1.05)), (per, 0, 4, ago(days: 1.05)),
                                 (per, 2, 1, ago(days: 1.04))],
                        course: "Oslo GK", loose: looseInfo(rid, [(myPart, "Thomas", profile), (per, "Per", nil)]))
    }
}

// MARK: - Kilder og filtre

struct HjemFeedKildeTests {
    @Test func aktivitetFraAlleKlubbene() throws {
        let feed = HomeFeed.build(H.input([
            H.row(1, .bigScore(member: H.anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5),
                  actor: H.anders, round: H.clubRound, at: H.ago(minutes: 3)),
            H.row(2, club: H.clubB, .announcement(text: "Vi starter 17:00"), actor: H.kari, at: H.ago(minutes: 30)),
        ]))
        let cards = feed.sections.flatMap(\.cards)
        #expect(cards.count == 2)
        #expect(cards[0].source == HomeFeedSource(filter: .competition(H.jakke.id), title: "Jakkeracet", tone: .lime))
        #expect(cards[1].source == HomeFeedSource(filter: .club(H.clubB), title: "Torsdagsgjengen", tone: .lime))
        #expect(feed.pills.map(\.title) == ["Alt", "Jakkeracet", "Torsdagsgjengen"])
        #expect(feed.pills.first?.isSelected == true)
    }

    @Test func klubbensLinjerUtenRundeGårTilHovedturneringen() throws {
        let feed = HomeFeed.build(H.input([
            H.row(1, .announcement(text: "Husk sko"), actor: H.me, at: H.ago(minutes: 5)),
        ]))
        let card = try #require(feed.sections.first?.cards.first)
        #expect(card.source.title == "Jakkeracet")
        guard case .lines(let lines) = card.content else { Issue.record("ikke linjer"); return }
        #expect(lines.map(\.text) == ["Thomas: Husk sko"])
        #expect(lines.first?.context == "Golfgutu Invitational")
        #expect(lines.first?.symbol == "megaphone.fill")
    }

    @Test func rundeSomTellerIToTurneringerStårUnderBegge() throws {
        let rows = [H.row(1, .sidePrize(kind: .drive, member: H.bjorn, hole: 7, meters: 245, passed: nil, passedMeters: nil),
                          round: H.clubRound2, at: H.ago(minutes: 10))]
        let all = HomeFeed.build(H.input(rows))
        let card = try #require(all.sections.first?.cards.first)
        #expect(card.source.title == "Jakkeracet")
        #expect(card.filters == [.competition(H.jakke.id), .competition(H.liga.id)])
        #expect(all.pills.map(\.title) == ["Alt", "Jakkeracet", "Høstligaen"])
        #expect(all.pills.last?.tone == .sun)
        let liga = HomeFeed.build(H.input(rows, filter: .competition(H.liga.id)))
        #expect(liga.sections.flatMap(\.cards).count == 1)
        #expect(liga.pills.first { $0.isSelected }?.title == "Høstligaen")
        let morro = HomeFeed.build(H.input(rows, filter: .competition(H.morro.id)))
        #expect(morro.isEmpty)
        // Det valgte filteret står selv om det er tomt.
        #expect(morro.pills.map(\.title) == ["Alt", "Jakkeracet", "Høstligaen", "Morrocupen"])
    }

    @Test func ikkeAlleAndresRunderOgIkkeStøy() {
        let feed = HomeFeed.build(H.input([
            H.row(1, .roundStarted(roundNo: 1, courseName: "Losby", holeCount: 18, bays: 2, ldHole: nil, kpHole: nil),
                  round: H.clubRound, at: H.ago(minutes: 1)),
            H.row(2, .roundLocked(roundNo: 1, courseName: "Losby"), round: H.clubRound, at: H.ago(minutes: 2)),
            H.row(3, .leadChanged(afterHole: 18, leaders: [H.anders], points: 38, outcome: .won), round: H.clubRound,
                  at: H.ago(minutes: 3)),
            H.row(4, .nudge(eventDate: "2026-10-15"), at: H.ago(minutes: 4), recipients: [H.me]),
            H.row(5, .reminder(eventDate: "2026-10-15", coming: 8, unsure: 1), at: H.ago(minutes: 5)),
            H.row(6, .betCreated(question: "Q", side: "yes", points: 10), at: H.ago(minutes: 6)),
            H.row(7, .memberJoined(member: H.cato), at: H.ago(minutes: 7)),
            H.row(8, .scoreCorrected(member: H.me, hole: 3, from: 5, to: 4, roundNo: 1, courseName: nil), at: H.ago(minutes: 8)),
            H.row(9, .unknown(kind: "noe_nytt"), at: H.ago(minutes: 9)),
        ]))
        #expect(feed.isEmpty)
    }

    @Test func eldreEnnVinduetErBorte() {
        let feed = HomeFeed.build(H.input([H.row(1, .announcement(text: "Gammelt"), at: H.ago(days: 31))]))
        #expect(feed.isEmpty)
    }
}

// MARK: - Seksjoner og linjer

struct HjemFeedSeksjonTests {
    @Test func iDagIGårOgTidligere() {
        let feed = HomeFeed.build(H.input([
            H.row(1, .announcement(text: "a"), at: H.ago(minutes: 10)),
            H.row(2, .announcement(text: "b"), at: H.ago(days: 1)),
            H.row(3, .announcement(text: "c"), at: H.ago(days: 4)),
        ]))
        #expect(feed.sections.map(\.title) == ["I dag", "I går", "Tidligere"])
    }

    @Test func linjerFraSammeKildeBlirEttKortOgPåmeldingerSlåsSammen() throws {
        let feed = HomeFeed.build(H.input([
            H.row(1, .signup(member: H.anders, status: .yes, eventDate: "2026-10-15"), actor: H.anders, at: H.ago(minutes: 1)),
            H.row(2, .signup(member: H.bjorn, status: .yes, eventDate: "2026-10-15"), actor: H.bjorn, at: H.ago(minutes: 2)),
            H.row(3, .signup(member: H.cato, status: .yes, eventDate: "2026-10-15"), actor: H.cato, at: H.ago(minutes: 3)),
            H.row(4, .signup(member: H.kari, status: .yes, eventDate: "2026-10-15"), actor: H.kari, at: H.ago(minutes: 4)),
            H.row(5, .signup(member: H.me, status: .no, eventDate: "2026-10-15"), actor: H.me, at: H.ago(minutes: 5)),
            H.row(6, .tipsKing(members: [H.cato], correct: 9, possible: 12, eventDate: "2026-10-01"), at: H.ago(minutes: 6)),
            H.row(7, club: H.clubB, .announcement(text: "Annen klubb"), actor: H.kari, at: H.ago(minutes: 7)),
        ]))
        let cards = try #require(feed.sections.first?.cards)
        #expect(cards.count == 2)
        guard case .lines(let lines) = cards[0].content, case .lines(let other) = cards[1].content else {
            Issue.record("ikke linjer"); return
        }
        #expect(lines.map(\.text) == [
            "Anders Berg, Bjørn og 2 til meldte seg på torsdag 15. oktober",
            "Thomas meldte forfall til torsdag 15. oktober",
            "Tippekongen torsdag 1. oktober: Cato med 9 av 12 riktige",
        ])
        #expect(lines[0].reactions == nil)  // sammenslått
        #expect(lines[1].reactions?.activityID == H.id(10_005))
        #expect(other.map(\.text) == ["Kari: Annen klubb"])
        #expect(cards[0].id == "l-a-" + H.id(10_001).uuidString)
    }

    @Test func toPåmeldingerBlirOgSammenslått() {
        let texts = HomeFeedText.signups(["Anders", "Bjørn"], eventDate: "2026-10-15")
        #expect(texts == "Anders og Bjørn meldte seg på torsdag 15. oktober")
        #expect(HomeFeedText.signups(["A", "B", "C"], eventDate: nil) == "A, B og C meldte seg på")
    }

    @Test func linjeMedRundeHarTurneringOgRundeSomKontekst() throws {
        let feed = HomeFeed.build(H.input([
            H.row(1, .sidePrize(kind: .drive, member: H.bjorn, hole: 7, meters: 245, passed: H.anders, passedMeters: 231),
                  round: H.clubRound, at: H.ago(minutes: 10)),
        ]))
        guard case .lines(let lines) = try #require(feed.sections.first?.cards.first).content else {
            Issue.record("ikke linjer"); return
        }
        #expect(lines.first?.text == "Bjørn leder longest drive på hull 7 med 245 m — forbi Anders Berg (231 m)")
        #expect(lines.first?.context == "Jakkeracet · runde 4")
        #expect(lines.first?.time == "10 min")
    }
}

// MARK: - Kortene

struct HjemFeedKortTests {
    @Test func bragdFraAktivitetenMedReaksjoner() throws {
        var input = H.input([
            H.row(1, .bigScore(member: H.anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5),
                  actor: H.anders, round: H.clubRound, at: H.ago(minutes: 3)),
        ])
        input.reactions = [ActivityReactionRow(activityID: H.id(10_001), memberID: H.me, clubID: H.clubA, emoji: .fire),
                           ActivityReactionRow(activityID: H.id(10_001), memberID: H.bjorn, clubID: H.clubA, emoji: .fire),
                           ActivityReactionRow(activityID: H.id(10_001), memberID: H.cato, clubID: H.clubA, emoji: .thumbsUp)]
        let card = try #require(HomeFeed.build(input).sections.first?.cards.first)
        guard case .feat(let feat) = card.content else { Issue.record("ikke bragd"); return }
        #expect(feat.name == "Anders Berg")
        #expect(feat.initials == "AB")
        #expect(feat.headline == "Eagle på hull 5")
        #expect(feat.detail == "3 slag på par 5 · Losby")
        #expect(feat.place == "Losby · runde 4 · hull 5")
        #expect(feat.strokes == 3)
        #expect(!feat.isMe)
        let reactions = try #require(feat.reactions)
        #expect(reactions.clubID == H.clubA)
        #expect(reactions.chips.map(\.reaction) == [.thumbsUp, .fire])
        #expect(reactions.chips.last?.count == 2)
        #expect(reactions.chips.last?.isMine == true)
        #expect(card.time == "3 min")
    }

    @Test func tabellendringSettFraDeg() throws {
        let table = [ActivityTableSpot(member: H.anders, place: 1, from: 1, points: 58),
                     ActivityTableSpot(member: H.bjorn, place: 2, from: 2, points: 55),
                     ActivityTableSpot(member: H.cato, place: 3, from: 4, points: 50),
                     ActivityTableSpot(member: H.me, place: 4, from: 3, points: 49.5)]
        let feed = HomeFeed.build(H.input([
            H.row(1, .tableChanged(competition: H.jakke.id, competitionName: "Jakkeracet", roundNo: 3, table: table),
                  actor: H.anders, round: H.clubRound, at: H.ago(minutes: 12)),
        ]))
        let card = try #require(feed.sections.first?.cards.first)
        guard case .table(let t) = card.content else { Issue.record("ikke tabell"); return }
        #expect(card.source.title == "Jakkeracet")
        #expect(t.text == "Cato gikk forbi deg i Jakkeracet etter runde 3")
        #expect(t.rows.map(\.name) == ["Anders Berg", "Bjørn", "Cato", "Thomas"])
        #expect(t.rows.map(\.points) == ["58", "55", "50", "49,5"])
        #expect(t.rows.map(\.moveText) == [nil, nil, "↑1", "↓1"])
        #expect(t.rows.map(\.isMe) == [false, false, false, true])
        #expect(t.myPlace == 4)
        #expect(t.myMove == -1)
        #expect(t.reactions?.activityID == H.id(10_001))
    }

    @Test func dinRundeIKlubben() throws {
        var input = H.input([H.row(1, .roundLocked(roundNo: 4, courseName: "Losby"), actor: H.anders,
                                   round: H.clubRound, at: H.ago(minutes: 90))])
        input.rounds = [H.myClubRound()]
        input.reactions = [ActivityReactionRow(activityID: H.id(10_001), memberID: H.anders, clubID: H.clubA, emoji: .heart)]
        let card = try #require(HomeFeed.build(input).sections.first?.cards.first)
        guard case .myRound(let r) = card.content else { Issue.record("ikke din runde"); return }
        #expect(card.id == "r-" + H.clubRound.uuidString)
        #expect(card.source.title == "Jakkeracet")
        #expect(r.title == "Losby")
        #expect(r.subtitle == "Runde 4 · med Anders Berg og Bjørn")
        #expect(r.points == 5)
        #expect(r.value == "5 p")
        #expect(r.place == 2)
        #expect(r.placeText == "2. plass")
        #expect(r.ofText == "av 3 spillere")
        #expect(r.marks.map(\.label) == ["Birdie 1", "Par 1", "Dobbel 1"])
        #expect(r.winner == "Vinner: Anders Berg · 6 p")
        #expect(r.insight == nil)
        #expect(r.reactions?.chips.map(\.reaction) == [.heart])
        #expect(!r.isLoose)
    }

    @Test func runderDuIkkeSpilteOgSomPågårErIkkeDinRunde() {
        var input = H.input()
        var other = H.myClubRound()
        other.players.removeAll { $0.memberID == H.me }
        input.rounds = [other, H.myLooseRound(status: .active)]
        let feed = HomeFeed.build(input)
        #expect(!feed.sections.flatMap(\.cards).contains { if case .myRound = $0.content { true } else { false } })
    }

    @Test func løsRundeGirDinRundeOgBragdFraHullscorene() throws {
        var input = H.input()
        input.rounds = [H.myLooseRound()]
        let feed = HomeFeed.build(input)
        let cards = feed.sections.flatMap(\.cards)
        #expect(cards.count == 2)
        #expect(feed.sections.map(\.title) == ["I går"])
        guard case .myRound(let r) = cards[0].content, case .feat(let f) = cards[1].content else {
            Issue.record("feil kort: \(cards.map(\.id))"); return
        }
        #expect(cards[0].source == HomeFeedSource(filter: .loose, title: "Løs runde", tone: .earth))
        #expect(cards[0].filters == [.loose])
        #expect(r.isLoose)
        #expect(r.title == "Oslo GK")
        #expect(r.subtitle == "med Per")
        #expect(f.name == "Per")
        #expect(f.headline == "Hole in one på hull 3!")
        #expect(f.detail == "1 slag på par 3 · Oslo GK")
        #expect(f.place == "Oslo GK · hull 3")
        #expect(f.reactions == nil)
        #expect(feed.pills.map(\.title) == ["Alt", "Løse runder"])
        #expect(feed.pills.last?.tone == .earth)
    }

    @Test func bragderIKlubbrundeneDineKommerBareFraAktiviteten() {
        var input = H.input()
        input.rounds = [H.myClubRound()]  // Anders' eagle står i hullscorene, men ikke i aktiviteten
        let feats = HomeFeed.build(input).sections.flatMap(\.cards).filter {
            if case .feat = $0.content { true } else { false }
        }
        #expect(feats.isEmpty)
    }
}

// MARK: - Private turneringer

struct HjemFeedPrivatTurneringTests {
    /// Morrocupen (privat, åpen): runde 1 i forgårs (Thomas 6 p, Per 2 p), runde 2 i dag (bare Per, 7 p
    /// med eagle på hull 2). Per går forbi.
    static func morroInput() -> CompetitionInput {
        let r1 = H.snapshot(H.roundRow(H.looseRound, club: nil, status: .locked, locked: H.ago(days: 2)),
                            players: [(H.myPart, "Thomas", nil), (H.per, "Per", nil)],
                            scores: [(H.myPart, 0, 3, nil), (H.myPart, 1, 4, nil), (H.per, 0, 4, nil)],
                            course: "Oslo GK",
                            loose: H.looseInfo(H.looseRound, [(H.myPart, "Thomas", H.profile), (H.per, "Per", nil)]))
        let r2 = H.snapshot(H.roundRow(H.looseRound2, club: nil, status: .locked, locked: H.ago(minutes: 20)),
                            players: [(H.per, "Per", nil)],
                            scores: [(H.per, 0, 3, H.ago(minutes: 40)), (H.per, 1, 3, H.ago(minutes: 35))],
                            course: "Bærum GK", loose: H.looseInfo(H.looseRound2, [(H.per, "Per", nil)]))
        let links = [CompetitionRoundRow(competitionID: H.morro.id, roundID: H.looseRound, source: .manual),
                     CompetitionRoundRow(competitionID: H.morro.id, roundID: H.looseRound2, source: .manual)]
        let directory = PersonDirectory(participants: [
            RoundParticipantRow(id: H.myPart, roundID: H.looseRound, profileID: H.profile, displayName: "Thomas",
                                handicapIndex: 0),
            RoundParticipantRow(id: H.per, roundID: H.looseRound, profileID: nil, displayName: "Per", handicapIndex: 0),
        ])
        return CompetitionScope(competition: H.morro, links: links).input(candidates: [r1, r2], directory: directory)
    }

    @Test func plassbytteRegnesIAppen() throws {
        let ci = Self.morroInput()
        var input = H.input()
        input.links += [CompetitionRoundRow(competitionID: H.morro.id, roundID: H.looseRound2, source: .manual)]
        input.competitionInputs = [ci]
        input.rounds = ci.rounds
        let feed = HomeFeed.build(input)
        let cards = feed.sections.flatMap(\.cards)
        let table = try #require(cards.compactMap { c -> HomeTableCard? in
            if case .table(let t) = c.content { return t } else { return nil }
        }.first)
        #expect(table.competitionName == "Morrocupen")
        #expect(table.text == "Per gikk forbi deg i Morrocupen etter runde 2")
        #expect(table.rows.map(\.name) == ["Per", "Thomas"])
        #expect(table.rows.map(\.points) == ["9", "6"])
        #expect(table.myPlace == 2)
        #expect(table.myMove == -1)
        #expect(table.reactions == nil)
        // Pers eagle i runde 2 står som bragd i Morrocupen.
        let feat = try #require(cards.compactMap { c -> (HomeFeedCard, HomeFeatCard)? in
            if case .feat(let f) = c.content { return (c, f) } else { return nil }
        }.first)
        #expect(feat.1.headline == "Eagle på hull 2")
        #expect(feat.0.source.title == "Morrocupen")
        #expect(feat.0.source.tone == .blush)  // Høstligaen er sol (etter navn)
        #expect(feat.0.filters == [.competition(H.morro.id), .loose])
        #expect(feed.pills.map(\.title) == ["Alt", "Morrocupen", "Løse runder"])
    }

    @Test func klubbensTurneringerRegnesIkkeIAppen() {
        var ci = Self.morroInput()
        ci = CompetitionInput(competition: H.liga, entrants: ci.entrants, roster: ci.roster, rounds: ci.rounds)
        var input = H.input()
        input.competitionInputs = [ci]
        #expect(HomeFeed.build(input).isEmpty)
    }
}

// MARK: - Oppsummeringen (1b)

struct HjemOppsummeringTests {
    private let rows = [
        H.row(1, .tableChanged(competition: H.jakke.id, competitionName: "Jakkeracet", roundNo: 3,
                               table: [ActivityTableSpot(member: H.anders, place: 1, from: 1),
                                       ActivityTableSpot(member: H.me, place: 3, from: 5)]),
              actor: H.anders, round: H.clubRound, at: H.ago(minutes: 12)),
        H.row(2, .bigScore(member: H.anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5),
              actor: H.anders, round: H.clubRound, at: H.ago(minutes: 30)),
        H.row(3, .roundLocked(roundNo: 4, courseName: "Losby"), actor: H.anders, round: H.clubRound, at: H.ago(minutes: 11)),
        H.row(4, .announcement(text: "Min egen"), actor: H.me, at: H.ago(minutes: 5)),
    ]

    @Test func aldriSettGirIngenOppsummering() {
        #expect(HomeFeed.build(H.input(rows)).summary == nil)
        #expect(HomeFeed.build(H.input(rows)).sections.flatMap(\.cards).allSatisfy { !$0.isUnread })
    }

    @Test func detViktigsteFørstOgTreTall() throws {
        // Sist sett søndag 4. oktober.
        let summary = try #require(HomeFeed.build(H.input(rows, lastSeen: H.ago(days: 4))).summary)
        #expect(summary.eyebrow == "Siden sist · søndag")
        #expect(summary.sentence == "Du klatret til 3. plass i Jakkeracet, og Anders Berg slo eagle.")
        #expect(summary.stats == [.init(value: "1", label: "ny runde"), .init(value: "1", label: "bragd"),
                                  .init(value: "+2", label: "plasser")])
    }

    @Test func detDuGjordeSelvTellerIkke() {
        let feed = HomeFeed.build(H.input([rows[3]], lastSeen: H.ago(minutes: 20)))
        #expect(feed.summary == nil)
        #expect(feed.sections.first?.cards.first?.isUnread == false)
    }

    @Test func ingentingNyttSidenSist() {
        #expect(HomeFeed.build(H.input(rows, lastSeen: H.ago(minutes: 1))).summary == nil)
    }

    @Test func ulestPåKortene() {
        let cards = HomeFeed.build(H.input(rows, lastSeen: H.ago(minutes: 20))).sections.flatMap(\.cards)
        let unread = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.isUnread) })
        #expect(unread["a-" + H.id(10_001).uuidString] == true)
        #expect(unread["a-" + H.id(10_002).uuidString] == false)
    }

    @Test func dinRundeOgBragdenDinUtenTabell() throws {
        var input = H.input([H.row(1, .bigScore(member: H.me, hole: 1, holeIndex: 0, name: .eagle, strokes: 2, par: 4),
                                   actor: H.anders, round: H.clubRound, at: H.ago(minutes: 100))],
                            lastSeen: H.ago(days: 1.2))
        input.rounds = [H.myClubRound()]
        let summary = try #require(HomeFeed.build(input).summary)
        #expect(summary.eyebrow == "Siden sist · i går")
        #expect(summary.sentence == "Du slo eagle, og du fikk 5 poeng på Losby.")
        #expect(summary.stats.map(\.value) == ["1", "1", "0"])
        #expect(summary.stats.last?.label == "plasser")
    }

    @Test func dagteksten() {
        #expect(HomeSummaryBuilder.dayText(H.ago(minutes: 30), now: H.now) == "i dag")
        #expect(HomeSummaryBuilder.dayText(H.ago(days: 1), now: H.now) == "i går")
        #expect(HomeSummaryBuilder.dayText(H.ago(days: 3), now: H.now) == "mandag")
        #expect(HomeSummaryBuilder.dayText(H.ago(days: 10), now: H.now) == "28. sep.")
    }
}

// MARK: - Pågår nå og Neste kveld

struct HjemTilstandTests {
    @Test func pågårNå() throws {
        let s = H.snapshot(H.roundRow(H.clubRound, club: H.clubA, status: .active, roundNo: 4, started: H.ago(minutes: 60)),
                           players: [(H.me, "Thomas", 2), (H.anders, "Anders Berg", 1), (H.bjorn, "Bjørn", 1),
                                     (H.cato, "Cato", 2)],
                           scores: [(H.me, 0, 5, nil), (H.anders, 0, 3, nil), (H.anders, 1, 5, nil), (H.bjorn, 0, 4, nil),
                                    (H.cato, 0, 4, nil)])
        var input = H.input()
        input.live = HomeLiveInput(snapshot: s, viewer: Viewer(memberID: H.me, isOrganizer: false))
        let live = try #require(HomeFeed.build(input).live)
        #expect(live.title == "Losby · runde 4")
        #expect(live.progress == "Hull 2 av 18")
        #expect(live.detail == "Teller i Jakkeracet · bås 2")
        #expect(live.top.map(\.name) == ["Anders Berg", "Bjørn", "Cato"])
        #expect(live.top.first?.place == "1.")
        #expect(live.me?.name == "Thomas")
        #expect(live.me?.isMe == true)
        #expect(live.actionTitle == "Fortsett føringen")
        #expect(!live.isLoose)
    }

    @Test func løsRundeSomPågår() throws {
        var input = H.input()
        let s = H.myLooseRound(status: .active)
        input.live = HomeLiveInput(snapshot: s, viewer: LooseRoundRights.viewer(info: s.loose, userID: H.profile))
        let live = try #require(HomeFeed.build(input).live)
        #expect(live.title == "Oslo GK")
        #expect(live.detail == "bås 1")
        #expect(live.isLoose)
        #expect(live.me == nil)
    }

    @Test func nesteKveld() throws {
        var input = H.input()
        let event = EventRow(id: H.id(950), clubID: H.clubA, seasonID: nil, eventDate: "2026-10-15", startTime: "18:00:00",
                             venue: "Golfstudio Bryn", note: nil)
        input.evening = HomeEveningInput(clubID: H.clubA, clubName: "Golfgutu Invitational", event: event,
                                         today: "2026-10-08", answer: .yes, coming: 6, isOrganizer: true)
        let e = try #require(HomeFeed.build(input).evening)
        #expect(e.eyebrow == "Golfgutu Invitational · neste kveld")
        #expect(e.title == "Torsdag 15. oktober")
        #expect(e.countdown == "Om 7 dager")
        #expect(e.detail == "Kl. 18:00 · Golfstudio Bryn · 6 kommer")
        #expect(e.answer == .yes)
        #expect(e.isOrganizer)
        var bare = input
        bare.evening?.event.startTime = nil
        bare.evening?.event.venue = " "
        #expect(HomeFeed.build(bare).evening?.detail == "6 kommer")
        #expect(e.previousEventID == nil)
        // Forrige kveld gir «Forrige kupong · Torsdag 8. oktober».
        var withPrevious = input
        withPrevious.evening?.previous = EventRow(id: H.id(949), clubID: H.clubA, seasonID: nil, eventDate: "2026-10-08",
                                                  startTime: nil, venue: nil, note: nil)
        let p = try #require(HomeFeed.build(withPrevious).evening)
        #expect(p.previousEventID == H.id(949) && p.previousTitle == "Torsdag 8. oktober")
    }
}

// MARK: - Modellen uten nett

@MainActor
struct HjemModellTests {
    @Test func modellenByggerFeedenOgFilteret() {
        var raw = HomeFeedQueries.Raw()
        raw.activity = [H.row(1, .announcement(text: "Hei"), actor: H.anders, at: H.ago(minutes: 5)),
                        H.row(2, club: H.clubB, .announcement(text: "Hallo"), actor: H.kari, at: H.ago(minutes: 6))]
        raw.members = [ClubMemberRow(id: H.anders, clubID: H.clubA, userID: nil, displayName: "Anders", handicapIndex: nil,
                                     seedGroup: nil, isOrganizer: true, isTreasurer: false, status: .active, avatarPath: nil)]
        raw.competitions = [H.jakke]
        let model = HomeFeedModel(preview: raw, viewer: H.viewer, clubs: H.clubs, lastSeen: H.ago(minutes: 10),
                                  now: { H.now })
        #expect(model.feed.sections.flatMap(\.cards).count == 2)
        #expect(model.feed.summary != nil)
        #expect(model.bellCount == 2)  // to meldinger til alle
        model.filter = .club(H.clubB)
        #expect(model.feed.sections.flatMap(\.cards).count == 1)
        #expect(model.feed.pills.first { $0.isSelected }?.title == "Torsdagsgjengen")
        #expect(model.newestDate == H.ago(minutes: 5))
        model.markBellSeen()
        #expect(model.bellCount == 0)
    }

    @Test func reaksjonVisesMedEnGang() async throws {
        var raw = HomeFeedQueries.Raw()
        raw.activity = [H.row(1, .bigScore(member: H.anders, hole: 5, holeIndex: 4, name: .eagle, strokes: 3, par: 5),
                              actor: H.anders, at: H.ago(minutes: 5))]
        let model = HomeFeedModel(preview: raw, viewer: H.viewer, clubs: H.clubs, lastSeen: nil, now: { H.now })
        let target = HomeReactions(activityID: H.id(10_001), clubID: H.clubA, chips: [])
        await model.toggle(.fire, on: target)
        guard case .feat(let f) = model.feed.sections.first?.cards.first?.content else { Issue.record("ikke bragd"); return }
        #expect(f.reactions?.chips.map(\.reaction) == [.fire])
        #expect(f.reactions?.chips.first?.isMine == true)
        await model.toggle(.fire, on: target)
        guard case .feat(let g) = model.feed.sections.first?.cards.first?.content else { Issue.record("ikke bragd"); return }
        #expect(g.reactions?.chips.isEmpty == true)
    }
}
