import Foundation
import Testing
@testable import DashDash18

/// Fixturen `TradFixtures.json`: tall og tilfeller fra kveldens-traad-test.js og traad-bilder-test.js.
enum TradFixture {
    struct File: Decodable {
        struct Player: Decodable { let id: String; let navn: String }
        struct Mention: Decodable { let hva: String; let tekst: String; let avsender: String; let nevnte: [String] }
        struct Suggestion: Decodable { let hva: String; let utkast: String; let meg: String; let forslag: [String] }
        struct Insert: Decodable { let utkast: String; let navn: String; let resultat: String }
        struct Message: Decodable { let id: String; let fra: String; let tid: Date }
        struct Unread: Decodable {
            let meg: String
            let meldinger: [Message]
            let aldriApnet: Int
            let etterLest: Int
            let nye: [Message]
            let etterNye: Int
        }
        struct Size: Decodable { let hva: String; let b: Int; let h: Int; let maks: Int; let ut: [Int] }

        let spillere: [Player]
        let nevneNavn: [String: String]
        let finnNevnte: [Mention]
        let forslag: [Suggestion]
        let settInnNevn: [Insert]
        let uleste: Unread
        let bildemaal: [Size]
    }

    private final class BundleToken {}

    static func load() throws -> File {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "TradFixtures", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(File.self, from: Data(contentsOf: url))
    }

    /// Fast uuid per bokstav-id i fixturen.
    static func id(_ key: String) -> UUID {
        let hex = key.unicodeScalars.map { String(format: "%02x", $0.value) }.joined()
        let padded = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-4000-8000-" + padded.suffix(12))!
    }

    static func directory(_ file: File) -> MentionDirectory {
        MentionDirectory(people: file.spillere.map { TradPerson(id: id($0.id), name: $0.navn) })
    }

    static func message(_ m: File.Message, event: UUID = id("s1")) -> ThreadMessageRow {
        ThreadMessageRow(id: id(m.id), clubID: id("klubb"), eventID: event, memberID: id(m.fra), body: "Hei",
                         mentions: [], imagePath: nil, createdAt: m.tid)
    }
}

struct TradMentionTests {
    @Test func nevneNavnFraFixturen() throws {
        let file = try TradFixture.load()
        let directory = TradFixture.directory(file)
        for player in file.spillere {
            #expect(directory.handle(for: TradFixture.id(player.id)) == file.nevneNavn[player.id], "\(player.navn)")
        }
    }

    @Test func finnNevnteFraFixturen() throws {
        let file = try TradFixture.load()
        let directory = TradFixture.directory(file)
        for c in file.finnNevnte {
            let found = directory.mentions(in: c.tekst, sender: TradFixture.id(c.avsender))
            #expect(found == c.nevnte.map(TradFixture.id), "\(c.hva)")
        }
    }

    @Test func forslagFraFixturen() throws {
        let file = try TradFixture.load()
        let directory = TradFixture.directory(file)
        for c in file.forslag {
            let handles = directory.suggestions(for: c.utkast, viewer: TradFixture.id(c.meg)).map(\.handle)
            #expect(handles == c.forslag, "\(c.hva)")
        }
    }

    @Test func settInnNevnFraFixturen() throws {
        let file = try TradFixture.load()
        for c in file.settInnNevn {
            #expect(MentionDirectory.inserting(c.navn, into: c.utkast) == c.resultat)
        }
    }

    @Test func forslagEtterLinjeskiftOgIkkeMidtIOrd() {
        let a = UUID(), me = UUID()
        let directory = MentionDirectory(people: [TradPerson(id: a, name: "Kåre Ås"), TradPerson(id: me, name: "Meg")])
        #expect(directory.suggestions(for: "Hei\n@kå", viewer: me).map(\.handle) == ["Kåre"])
        #expect(directory.suggestions(for: "mail@kå", viewer: me).isEmpty)
        #expect(directory.suggestions(for: "@kåre ", viewer: me).isEmpty)
    }

    @Test func forslagErHoyst6() {
        let me = UUID()
        let people = (1...9).map { TradPerson(id: UUID(), name: "Anders\($0) Berg") }
        let directory = MentionDirectory(people: people)
        #expect(directory.suggestions(for: "@a", viewer: me).count == MentionDirectory.suggestionLimit)
    }

    @Test func bindestrekOgTallINavn() {
        let a = UUID(), b = UUID()
        let directory = MentionDirectory(people: [TradPerson(id: a, name: "Per-Erik Ås"), TradPerson(id: b, name: "Ola2 Nordmann")])
        #expect(directory.handle(for: a) == "Per-Erik")
        #expect(directory.handle(for: b) == "Ola")
        #expect(directory.mentions(in: "@per-erik kom", sender: nil) == [a])
        #expect(directory.mentions(in: "@Ola2", sender: nil).isEmpty)
    }

    @Test func navnUtenBokstaverKanIkkeNevnes() {
        let a = UUID()
        let directory = MentionDirectory(people: [TradPerson(id: a, name: "  123  ")])
        #expect(directory.handle(for: a) == nil)
        #expect(directory.mentions(in: "@123", sender: nil).isEmpty)
    }

    @Test func biteneUthevesForDeNevnte() throws {
        let file = try TradFixture.load()
        let directory = TradFixture.directory(file)
        let text = "Blir sen, @Kåre tar du bås 3? @ThomasR"
        let segments = directory.segments(of: text, mentions: [TradFixture.id("c"), TradFixture.id("a")])
        #expect(segments.map(\.text).joined() == text)
        #expect(segments.filter { $0.mention != nil }.map(\.text) == ["@Kåre", "@ThomasR"])
        #expect(segments.first?.text == "Blir sen, ")
    }
}

struct TradDraftTests {
    @Test func trimmes() {
        #expect(TradDraft.check("  Kommer 17:30, @kåre og @ThomasR!  ", hasImage: false) == .ready("Kommer 17:30, @kåre og @ThomasR!"))
    }

    @Test func tomSendesIkke() {
        #expect(TradDraft.check("", hasImage: false) == .empty)
        #expect(TradDraft.check("   \n ", hasImage: false) == .empty)
    }

    @Test func tomMedBildeErLov() {
        #expect(TradDraft.check("  ", hasImage: true) == .ready(""))
    }

    @Test func grensenEr500Tegn() {
        #expect(TradDraft.check(String(repeating: "x", count: 500), hasImage: false) == .ready(String(repeating: "x", count: 500)))
        let tooLong = TradDraft.check(String(repeating: "x", count: 501), hasImage: false)
        #expect(tooLong == .tooLong)
        #expect(tooLong.message?.contains("maks 500") == true)
        // Mellomrom rundt teller ikke.
        #expect(TradDraft.check("  " + String(repeating: "x", count: 500) + "  ", hasImage: false) != .tooLong)
    }

    @Test func tellerKodepunkterSomPostgres() {
        // «👍🏽» er to kodepunkter, «å» ett.
        #expect(TradDraft.check(String(repeating: "👍🏽", count: 250), hasImage: false) != .tooLong)
        #expect(TradDraft.check(String(repeating: "👍🏽", count: 251), hasImage: false) == .tooLong)
        #expect(TradDraft.check(String(repeating: "å", count: 500), hasImage: false) != .tooLong)
    }

    @Test func tekstenStarIgjenVedFeil() {
        #expect(TradDraft.restored(sent: "Denne feiler", typedSince: "") == "Denne feiler")
        #expect(TradDraft.restored(sent: "Denne feiler", typedSince: "  ") == "Denne feiler")
        #expect(TradDraft.restored(sent: "Denne feiler", typedSince: "og mer") == "Denne feiler og mer")
    }
}

struct TradImageLogicTests {
    @Test func stienErMedlemOgMeldingMedSmaBokstaver() {
        let member = UUID(uuidString: "ABCDEF00-1234-4234-8234-123456789ABC")!
        let message = UUID(uuidString: "00000000-AAAA-4BBB-8CCC-DDDDDDDDDDDD")!
        #expect(TradImagePath.make(memberID: member, messageID: message)
                == "abcdef00-1234-4234-8234-123456789abc/00000000-aaaa-4bbb-8ccc-dddddddddddd.jpg")
        #expect(TradImagePath.bucket == "thread")
    }

    @Test func bildemaalFraFixturen() throws {
        let file = try TradFixture.load()
        for c in file.bildemaal {
            let size = TradImageSpec.targetSize(width: c.b, height: c.h, maxSide: c.maks)
            #expect([size.width, size.height] == c.ut, "\(c.hva)")
        }
    }

    @Test func bildemaalAvrunderSomMathRound() {
        // 1000×333 → 1600/1000 = 1 (ikke opp). 4000×2999 → 1199,6 → 1200. 3001×2000 → 1066,31 → 1066.
        #expect(TradImageSpec.targetSize(width: 4000, height: 2999) == (1600, 1200))
        #expect(TradImageSpec.targetSize(width: 3001, height: 2000) == (1600, 1066))
        #expect(TradImageSpec.targetSize(width: 6400, height: 2) == (1600, 1))
    }

    @Test func komprimeringsmaal() {
        #expect(TradImageSpec.maxSide == 1600)
        #expect(TradImageSpec.quality == 0.82)
        #expect(TradImageSpec.maxBytes == 3_145_728)
    }
}

struct TradUnreadTests {
    @Test func ulesteFraFixturen() throws {
        let file = try TradFixture.load()
        let me = TradFixture.id(file.uleste.meg)
        var messages = file.uleste.meldinger.map { TradFixture.message($0) }
        #expect(TradUnread.count(messages, viewer: me, lastSeen: nil) == file.uleste.aldriApnet)

        let mark = try #require(TradUnread.readMark(messages, viewer: me, current: nil))
        #expect(TradUnread.count(messages, viewer: me, lastSeen: mark) == file.uleste.etterLest)
        // Lest til = andres nyeste (m4, 10:07), ikke egen m3.
        #expect(mark == file.uleste.meldinger[3].tid)

        messages += file.uleste.nye.map { TradFixture.message($0) }
        #expect(TradUnread.count(messages, viewer: me, lastSeen: mark) == file.uleste.etterNye)
    }

    @Test func lestTilFlyttesIkkeBakover() {
        let me = UUID(), other = UUID()
        let t = Date(timeIntervalSince1970: 1_000)
        let messages = [row(other, t)]
        #expect(TradUnread.readMark(messages, viewer: me, current: t) == nil)
        #expect(TradUnread.readMark(messages, viewer: me, current: t.addingTimeInterval(60)) == nil)
        #expect(TradUnread.readMark([row(me, t)], viewer: me, current: nil) == nil)
    }

    private func row(_ member: UUID, _ date: Date) -> ThreadMessageRow {
        ThreadMessageRow(id: UUID(), clubID: UUID(), eventID: UUID(), memberID: member, body: "x", mentions: [],
                         imagePath: nil, createdAt: date)
    }
}

struct TradSummaryTests {
    @Test func antallUlesteOgDeTreSiste() {
        let me = UUID(), anders = UUID(), bjorn = UUID()
        let base = Date(timeIntervalSince1970: 1_000_000)
        func m(_ who: UUID, _ minutes: Double, _ body: String, image: String? = nil) -> ThreadMessageRow {
            ThreadMessageRow(id: UUID(), clubID: UUID(), eventID: UUID(), memberID: who, body: body, mentions: [],
                             imagePath: image, createdAt: base.addingTimeInterval(minutes * 60))
        }
        // Usortert inn.
        let messages = [m(bjorn, 3, "", image: "b/x.jpg"), m(anders, 0, "Vi starter 17:00"), m(me, 2, "Ja"),
                        m(anders, 1, "Blir sen")]
        let summary = TradSummary.make(messages: messages, names: [anders: "Anders Berg", bjorn: "Bjørn Li"],
                                       viewer: me, lastSeen: base.addingTimeInterval(30))
        #expect(summary.count == 4)
        #expect(summary.unread == 2)
        #expect(summary.recent.map(\.preview) == ["Blir sen", "Ja", "📷 Bilde"])
        #expect(summary.last?.author == "Bjørn Li")
        #expect(summary.recent[1].author == "Ukjent")
    }

    @Test func tomTraad() {
        let summary = TradSummary.make(messages: [], names: [:], viewer: UUID(), lastSeen: nil)
        #expect(summary.count == 0 && summary.unread == 0 && summary.last == nil)
    }
}

struct TradSignedURLCacheTests {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let a = "b/m1.jpg", b = "b/m2.jpg"

    @Test func hentesSamletUtenDubletter() {
        let cache = TradSignedURLCache()
        #expect(cache.pathsToSign([a, b, a], now: now) == [a, b])
        #expect(TradSignedURLCache.lifetimeSeconds == 3600)
    }

    @Test func ferskeHentesIkkePaNytt() {
        var cache = TradSignedURLCache()
        cache.store(signed: [a: URL(string: "https://lager/a")!, b: URL(string: "https://lager/b")!], requested: [a, b], now: now)
        #expect(cache.pathsToSign([a, b], now: now.addingTimeInterval(30 * 60)).isEmpty)
        #expect(cache.url(for: a, now: now) == URL(string: "https://lager/a"))
    }

    @Test func fornyesNaarDetErUnderTiMinutterIgjen() {
        var cache = TradSignedURLCache()
        cache.store(signed: [a: URL(string: "https://lager/a")!], requested: [a], now: now)
        // Brukes i 55 minutter; 46 minutter senere er det 9 igjen.
        #expect(cache.pathsToSign([a], now: now.addingTimeInterval(46 * 60)) == [a])
        #expect(cache.pathsToSign([a], now: now.addingTimeInterval(44 * 60)).isEmpty)
        #expect(cache.url(for: a, now: now.addingTimeInterval(56 * 60)) == nil)
    }

    @Test func feilProvesIkkeIgjenFoerNyHenting() {
        var cache = TradSignedURLCache()
        cache.store(signed: [a: URL(string: "https://lager/a")!], requested: [a, b], now: now)
        #expect(cache.failed == [b])
        #expect(cache.pathsToSign([a, b], now: now).isEmpty)
        cache.retryFailed()
        #expect(cache.pathsToSign([a, b], now: now) == [b])
        cache.markFailed([a])
        cache.forget(a)
        #expect(cache.pathsToSign([a], now: now) == [a])
    }
}

struct TradTimeLabelTests {
    @Test func iDagIGaarOgEldre() throws {
        let calendar = TradTimeLabel.osloCalendar
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-08T18:00:00Z"))  // 20:00 i Oslo
        #expect(TradTimeLabel.text(for: now.addingTimeInterval(-55 * 60), now: now, calendar: calendar) == "19:05")
        #expect(TradTimeLabel.text(for: now.addingTimeInterval(-24 * 3600), now: now, calendar: calendar) == "i går 20:00")
        let older = TradTimeLabel.text(for: now.addingTimeInterval(-3 * 24 * 3600), now: now, calendar: calendar)
        #expect(older.hasPrefix("5. okt") && older.hasSuffix("20:00"), "\(older)")
    }
}

struct TradRowTests {
    @Test func insertUtenBildeSenderIkkeImagePathEllerTid() throws {
        let insert = ThreadMessageInsert(id: UUID(), clubID: UUID(), eventID: UUID(), memberID: UUID(), body: "Hei",
                                         mentions: [UUID()], imagePath: nil)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(insert)) as? [String: Any])
        #expect(Set(json.keys) == ["id", "club_id", "event_id", "member_id", "body", "mentions"])
    }

    @Test func insertMedBilde() throws {
        let insert = ThreadMessageInsert(id: UUID(), clubID: UUID(), eventID: UUID(), memberID: UUID(), body: "",
                                         mentions: [], imagePath: "a/b.jpg")
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(insert)) as? [String: Any])
        #expect(json["image_path"] as? String == "a/b.jpg")
        #expect(json["created_at"] == nil && json["pushed_at"] == nil)
    }

    @Test func radenLesesFraDatabasen() throws {
        let raw = """
        {"id":"11111111-1111-4111-8111-111111111111","club_id":"22222222-2222-4222-8222-222222222222",
         "event_id":"33333333-3333-4333-8333-333333333333","member_id":"44444444-4444-4444-8444-444444444444",
         "body":"","mentions":[],"image_path":"44444444-4444-4444-8444-444444444444/11111111-1111-4111-8111-111111111111.jpg",
         "created_at":"2026-10-08T17:05:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(ThreadMessageRow.self, from: Data(raw.utf8))
        #expect(row.imagePath?.hasSuffix(".jpg") == true)
        #expect(TradSummary.preview(row) == "📷 Bilde")
    }
}
