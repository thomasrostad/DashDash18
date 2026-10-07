import Foundation
import GolfgutuCore
import Testing
@testable import DashImportKit

/// Syntetisk øyeblikksbilde (Fixtures/syntetisk). Ingen ekte navn eller id-er.
enum Fixture {
    static var directory: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!.appendingPathComponent("syntetisk")
    }

    static func snapshot() throws -> PWASnapshot {
        try PWASnapshot.load(directory: directory).snapshot
    }

    static func plan() throws -> ImportPlan {
        try Mapper.plan(snapshot())
    }

    static func pwaPlayer(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }
    static func pwaRound(_ n: Int) -> String { String(format: "20000000-0000-4000-8000-%012d", n) }
}

@Suite("Stabile id-er")
struct StableIDTests {
    @Test("SHA-1 gir standardsvaret")
    func sha1() {
        #expect(SHA1.hex(Array("abc".utf8)) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(SHA1.hex([]) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }

    @Test("UUIDv5 gir RFC-eksempelet (DNS, python.org)")
    func uuidV5() {
        let dns = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!
        #expect(StableID.v5("python.org", namespace: dns).uuidString.lowercased() == "886313e1-3b8a-5372-9b90-0c9aee199e5d")
    }

    @Test("Samme PWA-id gir samme UUID, uansett store og små bokstaver; typene skilles")
    func stable() {
        let id = "AbCdEf00-0000-4000-8000-000000000001"
        #expect(StableID.member(id) == StableID.member(id.lowercased()))
        #expect(StableID.member(id) != StableID.round(id))
        #expect(StableID.course("test_bane") == StableID.course("test_bane"))
        let v = StableID.member(id).uuidString
        #expect(v[v.index(v.startIndex, offsetBy: 14)] == "5")   // versjon 5
    }
}

@Suite("Lesing av øyeblikksbildet")
struct SnapshotTests {
    @Test("Leser listen SQL Editor eksporterer, objektet selv og snapshot som tekst")
    func shapes() throws {
        let inner = #"{"players":[{"id":"p1","name":"Åse","commissioner":false,"handicap":"12.5"}]}"#
        for text in [inner, #"{"snapshot":\#(inner)}"#, #"[{"snapshot":\#(inner)}]"#,
                     #"[{"snapshot":"\#(inner.replacingOccurrences(of: "\"", with: "\\\""))"}]"#] {
            let s = try PWASnapshot.decode(Data(text.utf8))
            #expect(s.players.count == 1)
            #expect(s.players[0].handicap == 12.5)
            #expect(s.players[0].name == "Åse")
        }
    }

    @Test("Fixturen leses")
    func fixture() throws {
        let s = try Fixture.snapshot()
        #expect(s.players.count == 6)
        #expect(s.rounds.count == 4)
        #expect(s.holeScores.count == 145)
    }
}

@Suite("Mapping PWA → app")
struct MappingTests {
    @Test("Antall rader")
    func counts() throws {
        let p = try Fixture.plan()
        #expect(p.members.count == 6)
        #expect(p.courses.count == 2)
        #expect(p.courseHoles.count == 27)
        #expect(p.events.count == 3)          // 2 i terminlista + 1 laget for en rundedato
        #expect(p.rounds.count == 4)
        #expect(p.roundPlayers.count == 11)
        #expect(p.matches.count == 3)
        #expect(p.scores.count == 144)        // én score utenfor 9-hullsrunden er hoppet over
        #expect(p.sideClaims.count == 3)      // én uten runde er hoppet over
        #expect(p.signups.count == 3)
        #expect(p.tips.count == 1)
        #expect(p.threadMessages.count == 2)
    }

    @Test("Troppen: norske tegn, trimmet navn, roller, ingen innlogging")
    func members() throws {
        let p = try Fixture.plan()
        let names = p.members.map(\.displayName)
        #expect(names.contains("Ærlige Åse"))
        #expect(names.contains("Øystein Ørn"))
        #expect(names.contains("Zakarias Zå"))
        let organizer = p.members.first { $0.pwaID == Fixture.pwaPlayer(1) }!
        #expect(organizer.isOrganizer && !organizer.isTreasurer)
        #expect(p.members.first { $0.pwaID == Fixture.pwaPlayer(3) }!.isTreasurer)
        #expect(p.members.first { $0.pwaID == Fixture.pwaPlayer(2) }!.seedGroup == 2)
        #expect(p.members.first { $0.pwaID == Fixture.pwaPlayer(1) }!.handicapIndex == 12.3)
    }

    @Test("Påmelding: kommer/usikker/kommer_ikke → yes/maybe/no, tom kommentar blir null")
    func signups() throws {
        let p = try Fixture.plan()
        let byMember = Dictionary(uniqueKeysWithValues: p.signups.map { ($0.memberID, $0) })
        #expect(byMember[StableID.member(Fixture.pwaPlayer(1))]?.status == "yes")
        let maybe = byMember[StableID.member(Fixture.pwaPlayer(2))]
        #expect(maybe?.status == "maybe")
        #expect(maybe?.comment == "Kommer sent – på grunn av jobb, «kanskje»")
        #expect(byMember[StableID.member(Fixture.pwaPlayer(3))]?.status == "no")
        #expect(byMember[StableID.member(Fixture.pwaPlayer(3))]?.comment == nil)
    }

    @Test("Terminlista: første klokkeslett, tipslinje bare x,5, innsats i kroner tas ikke med")
    func events() throws {
        let p = try Fixture.plan()
        let first = p.events.first { $0.eventDate == "2026-05-07" }!
        #expect(first.startTime == "18:00")
        #expect(first.tipsLine == 2.5)
        #expect(first.tipsStakePoints == nil)
        let second = p.events.first { $0.eventDate == "2026-05-14" }!
        #expect(second.startTime == "18:30")
        #expect(second.tipsLine == nil)
        #expect(p.events.contains { $0.eventDate == "2026-05-21" && $0.id == StableID.eventForDate("2026-05-21") })
        #expect(p.committee.count == 2)
    }

    @Test("Runder: status, 9 hull med siste ni, ekstern handicap, form, avkorting, nummer per kveld")
    func rounds() throws {
        let p = try Fixture.plan()
        func round(_ n: Int) -> ImportPlan.Round { p.rounds.first { $0.pwaID == Fixture.pwaRound(n) }! }
        #expect(round(1).status == "locked")
        #expect(round(1).format == "stableford")         // «Stableford» → id
        #expect(round(1).ldHoleIndex == 3 && round(1).kpHoleIndex == 2)
        #expect(round(2).holeCount == 9 && round(2).firstHole == 10)
        #expect(round(2).externalHandicap)
        #expect(!round(2).ldEnabled && !round(2).kpEnabled)
        #expect(round(2).roundNo == 1 && round(3).roundNo == 2)   // samme kveld
        #expect(round(3).status == "draft" && round(3).startedAt == nil)
        #expect(round(4).cutRule == "common" && round(4).cutAfter == 6)
        #expect(round(4).cutBy == StableID.member(Fixture.pwaPlayer(1)))
        #expect(round(4).weight == 2)
        #expect(round(4).lockedAt == "2026-05-21T20:00:00+00:00")   // siste score i PWA-en
    }

    @Test("Deltakere: bås, én markør per bås, lag, handicap frosset fra troppen")
    func roundPlayers() throws {
        let p = try Fixture.plan()
        let r1 = p.roundPlayers.filter { $0.roundID == StableID.round(Fixture.pwaRound(1)) }
        #expect(r1.count == 5)
        #expect(r1.filter { $0.bayNo == 2 && $0.isMarker }.count == 1)
        let r2 = p.roundPlayers.filter { $0.roundID == StableID.round(Fixture.pwaRound(2)) }
        #expect(Set(r2.compactMap(\.teamNo)) == [1, 2])
        let aase = r1.first { $0.memberID == StableID.member(Fixture.pwaPlayer(1)) }!
        #expect(aase.handicapIndex == 12.3 && aase.isMarker && aase.bayNo == 1)
        #expect(p.warnings.contains { $0.contains("to markører i bås 2") })
    }

    @Test("Matcher: manuelt resultat A → a, trekant mister manuelt resultat, lagmatch")
    func matches() throws {
        let p = try Fixture.plan()
        let triangle = p.matches.first { $0.playerC != nil }!
        #expect(triangle.result == nil)
        let team = p.matches.first { $0.teamA != nil }!
        #expect(team.teamA == 1 && team.teamB == 2 && team.playerA == nil)
    }

    @Test("9-hullsrunde: score utenfor runden hoppes over med merknad")
    func nineHoles() throws {
        let p = try Fixture.plan()
        let r4 = StableID.round(Fixture.pwaRound(4))
        #expect(p.scores.filter { $0.roundID == r4 }.allSatisfy { $0.holeIndex < 9 })
        #expect(p.warnings.contains { $0.contains("hull 13 i en 9-hullsrunde") })
    }

    @Test("Baner: course_holes vinner, ellers courses.holes; Trackman-navn og bekreftelse")
    func courses() throws {
        let p = try Fixture.plan()
        let test = p.courses.first { $0.pwaID == "test_bane" }!
        #expect(test.externalName == "Test Course")
        #expect(test.confirmedBy == StableID.member(Fixture.pwaPlayer(1)))
        #expect(p.courseHoles.filter { $0.courseID == test.id }.count == 18)
        let old = p.courses.first { $0.pwaID == "gammel_bane" }!
        #expect(!old.inUse)
        #expect(p.courseHoles.filter { $0.courseID == old.id }.count == 9)
    }

    @Test("Tråden: bilde flyttes ikke, men meldingen beholdes; @nevnt mappes")
    func thread() throws {
        let p = try Fixture.plan()
        let text = p.threadMessages.first { $0.body.hasPrefix("Hei") }!
        #expect(text.mentions == [StableID.member(Fixture.pwaPlayer(2))])
        #expect(p.threadMessages.contains { $0.body == "(Bilde fra PWA-en, ikke flyttet)" })
    }

    @Test("To spillere med samme navn (store/små bokstaver) stopper importen")
    func duplicateNames() {
        let s = PWASnapshot(players: [.init(id: "a", name: "Bjørn"), .init(id: "b", name: " bjørn ")])
        #expect(throws: ImportError.self) { try Mapper.plan(s) }
    }

    @Test("To runder som pågår stopper importen")
    func severalActive() {
        let s = PWASnapshot(players: [.init(id: "a", name: "A")],
                            rounds: [.init(id: "r1", date: "2026-01-01"), .init(id: "r2", date: "2026-01-02")])
        #expect(throws: ImportError.severalActiveRounds(["r1", "r2"])) { try Mapper.plan(s) }
    }

    @Test("Ugyldige verdier ryddes: LD-hull utenfor runden, handicap utenfor skjemaet")
    func clamping() throws {
        let s = PWASnapshot(players: [.init(id: "a", name: "A", handicap: 60)],
                            rounds: [.init(id: "r1", date: "2026-01-01", locked: true, ldHoleIndex: 12, holeCount: 9)])
        let p = try Mapper.plan(s)
        #expect(p.members[0].handicapIndex == nil)
        #expect(p.rounds[0].ldHoleIndex == nil)
        #expect(p.warnings.count >= 3)   // handicap, LD-hull, kveld laget
    }
}

@Suite("SQL")
struct SQLTests {
    @Test("Samme input gir byte for byte samme SQL")
    func deterministic() throws {
        let a = try ImportRun.sql(snapshotDirectory: Fixture.directory).sql
        let b = try ImportRun.sql(snapshotDirectory: Fixture.directory).sql
        #expect(a == b)
    }

    @Test("Rekkefølgen i fila spiller ingen rolle")
    func orderIndependent() throws {
        var s = try Fixture.snapshot()
        let original = SQLWriter.write(try Mapper.plan(s))
        s.players.reverse(); s.holeScores.reverse(); s.roundBays.reverse(); s.roundTeams.reverse()
        s.roundMatches.reverse(); s.signups.reverse(); s.courseHoles.reverse(); s.schedule.reverse()
        s.sideClaims.reverse(); s.roundHoles.reverse(); s.courses.reverse()
        #expect(SQLWriter.write(try Mapper.plan(s)) == original)
    }

    @Test("Idempotent: én transaksjon, hver insert har on conflict, opprydding under importerte runder")
    func idempotent() throws {
        let sql = try ImportRun.sql(snapshotDirectory: Fixture.directory).sql
        let statements = sql.components(separatedBy: "insert into public.").dropFirst()
        #expect(statements.count >= 15)
        #expect(statements.allSatisfy { $0.contains("on conflict (") })
        #expect(sql.components(separatedBy: "\nbegin;").count == 2)
        #expect(sql.components(separatedBy: "\ncommit;").count == 2)
        for table in ["hole_scores", "round_players", "round_matches", "round_holes", "side_claims", "signups", "course_holes"] {
            #expect(sql.contains("delete from public.\(table) t"))
        }
        #expect(sql.contains("to_regclass('public.players')"))   // vern mot PWA-basen
    }

    @Test("Ledige navn: importen setter aldri user_id og rører ikke invitasjonskoden")
    func openNames() throws {
        let sql = try ImportRun.sql(snapshotDirectory: Fixture.directory).sql
        let members = sql.components(separatedBy: "insert into public.club_members")[1].components(separatedBy: ";")[0]
        #expect(!members.contains("user_id"))
        #expect(members.contains("'active'"))
        #expect(!sql.contains("join_code ="))
        let clubs = sql.components(separatedBy: "insert into public.clubs")[1].components(separatedBy: ";")[0]
        #expect(clubs.contains("do nothing"))
    }

    @Test("Tekst escapes, norske tegn beholdes, tråden får pushed_at")
    func literals() throws {
        let sql = try ImportRun.sql(snapshotDirectory: Fixture.directory).sql
        #expect(sql.contains("'Per O''Persen'"))
        #expect(sql.contains("'Ærlige Åse'"))
        #expect(sql.contains("«gøy»"))
        let thread = sql.components(separatedBy: "insert into public.thread_messages")[1].components(separatedBy: ";")[0]
        #expect(thread.contains("pushed_at"))
        #expect(thread.contains("do nothing"))
        #expect(SQLWriter.ts("ikke en dato") == "null")
        #expect(SQLWriter.ts("2026-05-07T19:00:00.123+00:00") == "'2026-05-07T19:00:00.123+00:00'::timestamptz")
    }

    @Test("Eksisterende klubb: lages ikke, men sjekkes")
    func existingClub() throws {
        let club = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let (sql, plan) = try ImportRun.sql(snapshotDirectory: Fixture.directory, options: ImportOptions(clubID: club))
        #expect(plan.club.id == club)
        #expect(!sql.contains("insert into public.clubs"))
        #expect(sql.contains("Fant ikke klubben 11111111-2222-4333-8444-555555555555"))
    }

    @Test("Utfil inne i et git-tre stoppes, import-out/ er lov")
    func riskyOutput() {
        let repo = Fixture.directory   // ligger i repoet
        #expect(ImportRun.isRiskyOutput(repo.appendingPathComponent("ut.sql")))
        #expect(!ImportRun.isRiskyOutput(URL(fileURLWithPath: "/tmp/import-out/ut.sql")))
    }
}

@Suite("Paritet")
struct ParityTests {
    @Test("Rundepoeng stemmer med PWA-ens lagrede tall (ekstern handicap, avkortet etter 6)")
    func storedPointsMatch() throws {
        let report = Parity.check(try Fixture.plan())
        #expect(report.comparedPoints == 2)
        #expect(report.isOK)
        #expect(report.roundCount == 3)        // kladden er ikke med
        #expect(report.eveningCount == 3)
    }

    @Test("Et endret lagret tall gir avvik")
    func mismatch() throws {
        var plan = try Fixture.plan()
        plan.storedPoints[0].points += 1
        let report = Parity.check(plan)
        #expect(!report.isOK)
        #expect(report.mismatches.count == 1)
        #expect(Parity.render(report).contains("AVVIK"))
    }

    @Test("Jakketabellen har hele troppen, sortert som Tavla; vekt 2 dobler stablefordsummen")
    func jacket() throws {
        let report = Parity.check(try Fixture.plan())
        #expect(report.jacket.count == 6)
        let totals = report.jacket.map(\.total)
        #expect(totals == totals.sorted(by: >))
        let zakarias = report.stableford.first { $0.player.name == "Zakarias Zå" }!
        #expect(zakarias.total == 12)          // 6 poeng × vekt 2
        #expect(Parity.render(report).contains("Jakkeracet"))
    }
}
