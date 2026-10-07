import Foundation
import Testing
@testable import DashDash18

// MARK: - Testdobler

/// Serveren uten nett. Feil settes per kall.
actor FakeTradBackend: TradBackend {
    var rows: [ThreadMessageRow] = []
    var memberRows: [ClubMemberRow] = []
    var serverTime = Date(timeIntervalSince1970: 3_000_000)

    var insertError: (any Error)?
    var uploadError: (any Error)?
    var deleteError: (any Error)?
    /// Svar fra `delete` når den ikke feiler (false = RLS sa nei).
    var deleteResult = true
    var signError: (any Error)?
    var unsignable: Set<String> = []

    private(set) var inserted: [ThreadMessageInsert] = []
    private(set) var uploaded: [(path: String, bytes: Int)] = []
    private(set) var removed: [[String]] = []
    private(set) var deleted: [UUID] = []
    private(set) var signCalls: [(paths: [String], seconds: Int)] = []

    func set(rows: [ThreadMessageRow]) { self.rows = rows }
    func set(members: [ClubMemberRow]) { memberRows = members }
    func failInsert(_ error: (any Error)?) { insertError = error }
    func failUpload(_ error: (any Error)?) { uploadError = error }
    func failDelete(_ error: (any Error)?) { deleteError = error }
    func set(deleteResult: Bool) { self.deleteResult = deleteResult }
    func set(unsignable: Set<String>) { self.unsignable = unsignable }

    func messages(eventID: UUID) async throws -> [ThreadMessageRow] { rows.filter { $0.eventID == eventID } }
    func members(clubID: UUID) async throws -> [ClubMemberRow] { memberRows }

    /// Lagrer meldingen, men svaret kommer aldri fram (nettet faller ut etter lagringen).
    var loseInsertAnswer = false
    func set(loseInsertAnswer: Bool) { self.loseInsertAnswer = loseInsertAnswer }

    func insert(_ message: ThreadMessageInsert) async throws -> ThreadMessageRow {
        inserted.append(message)
        if let insertError { throw insertError }
        let row = ThreadMessageRow(id: message.id, clubID: message.clubID, eventID: message.eventID,
                                   memberID: message.memberID, body: message.body, mentions: message.mentions,
                                   imagePath: message.imagePath, createdAt: serverTime)
        rows.append(row)
        if loseInsertAnswer { throw URLError(.networkConnectionLost) }
        return row
    }

    func delete(messageID: UUID) async throws -> Bool {
        deleted.append(messageID)
        if let deleteError { throw deleteError }
        guard deleteResult else { return false }
        rows.removeAll { $0.id == messageID }
        return true
    }

    func uploadImage(path: String, jpeg: Data) async throws {
        uploaded.append((path, jpeg.count))
        if let uploadError { throw uploadError }
    }

    func removeImages(paths: [String]) async throws { removed.append(paths) }

    private(set) var avatarCalls: [[String]] = []

    func avatarURLs(paths: [String], expiresIn: Int) async throws -> [String: URL] {
        avatarCalls.append(paths)
        return Dictionary(uniqueKeysWithValues: paths.map { ($0, URL(string: "https://portretter/\($0)")!) })
    }

    func signedURLs(paths: [String], expiresIn: Int) async throws -> [String: URL] {
        signCalls.append((paths, expiresIn))
        if let signError { throw signError }
        var urls: [String: URL] = [:]
        for path in paths where !unsignable.contains(path) {
            urls[path] = URL(string: "https://lager/\(path)?token=t")
        }
        return urls
    }
}

final class MemoryTradReadStore: TradReadStoring, @unchecked Sendable {
    var marks: [String: Date] = [:]
    func lastSeen(memberID: UUID, eventID: UUID) -> Date? { marks["\(memberID)\(eventID)"] }
    func setLastSeen(_ date: Date, memberID: UUID, eventID: UUID) { marks["\(memberID)\(eventID)"] = date }
}

// MARK: - Tester

@MainActor
struct TradModelTests {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

    let club = id(900)
    let event = id(901)
    let thomasR = id(1), thomasS = id(2), kare = id(3), carl = id(4)
    let backend = FakeTradBackend()
    let store = MemoryTradReadStore()

    func member(_ id: UUID, _ name: String, status: MemberStatus = .active) -> ClubMemberRow {
        ClubMemberRow(id: id, clubID: club, userID: nil, displayName: name, handicapIndex: nil, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: status, avatarPath: nil)
    }

    func row(_ n: Int, from: UUID, minutes: Double, body: String = "Hei", image: String? = nil) -> ThreadMessageRow {
        ThreadMessageRow(id: Self.id(100 + n), clubID: club, eventID: event, memberID: from, body: body, mentions: [],
                         imagePath: image, createdAt: Date(timeIntervalSince1970: 2_000_000 + minutes * 60))
    }

    /// Modellen sett fra `viewer`, med de fire fra kveldens-traad-test.js i troppen.
    func makeModel(viewer: UUID, organizer: Bool = false, rows: [ThreadMessageRow] = []) async -> TradModel {
        await backend.set(members: [member(thomasR, "Thomas Rostad"), member(thomasS, "Thomas Strypet"),
                                    member(kare, "Kåre Ås"), member(carl, "Carl <Moe>")])
        await backend.set(rows: rows)
        let model = TradModel(eventID: event, clubID: club, viewer: viewer, isOrganizer: organizer, backend: backend,
                              readStore: store, images: TradImageStore(),
                              now: { Date(timeIntervalSince1970: 2_500_000) })
        await model.load()
        return model
    }

    func image() throws -> TradImageCompressor.Output {
        try TradImageCompressor.compress(TradImageCompressorTests.jpeg(width: 400, height: 300))
    }

    // MARK: Henting

    @Test func henterOgSortererNyesteNederst() async {
        let model = await makeModel(viewer: kare, rows: [row(2, from: thomasS, minutes: 5), row(1, from: thomasR, minutes: 0)])
        #expect(model.state == .loaded)
        #expect(model.items.map(\.id) == [Self.id(101), Self.id(102)])
        #expect(model.items.first?.author == "Thomas Rostad")
        #expect(model.items.allSatisfy { !$0.isMine })
    }

    @Test func arkiverteVisesMenKanIkkeNevnes() async {
        let gone = Self.id(9)
        await backend.set(members: [member(kare, "Kåre Ås"), member(gone, "Ola Borte", status: .archived)])
        await backend.set(rows: [row(1, from: gone, minutes: 0)])
        let model = TradModel(eventID: event, clubID: club, viewer: kare, isOrganizer: false, backend: backend,
                              readStore: store, images: TradImageStore())
        await model.load()
        #expect(model.items.first?.author == "Ola Borte")
        #expect(model.directory.mentions(in: "@Ola", sender: kare).isEmpty)
    }

    @Test func portretterForDemSomHarSkrevet() async {
        let kareFace = "\(kare.uuidString.lowercased())/aaaaaaaa-0000-4000-8000-000000000001.jpg"
        let carlFace = "\(carl.uuidString.lowercased())/aaaaaaaa-0000-4000-8000-000000000002.jpg"
        var kareRow = member(kare, "Kåre Ås")
        kareRow.avatarPath = kareFace
        var carlRow = member(carl, "Carl Moe")
        carlRow.avatarPath = carlFace
        await backend.set(members: [member(thomasR, "Thomas Rostad"), kareRow, carlRow])
        await backend.set(rows: [row(1, from: kare, minutes: 0), row(2, from: thomasR, minutes: 1)])
        let model = TradModel(eventID: event, clubID: club, viewer: thomasR, isOrganizer: false, backend: backend,
                              readStore: store, images: TradImageStore(),
                              now: { Date(timeIntervalSince1970: 2_500_000) })
        await model.load()
        #expect(model.items.map(\.avatarPath) == [kareFace, nil])
        // Bare Kåre har skrevet og har portrett; Carl har ikke skrevet.
        #expect(await backend.avatarCalls == [[kareFace]])
        #expect(model.avatarURL(for: kareFace) != nil)
        // Ny henting med fersk lenke ber ikke om den igjen.
        await model.load()
        #expect(await backend.avatarCalls.count == 1)
    }

    @Test func vistTraadMerkesLest() async {
        let rows = [row(1, from: thomasR, minutes: 0), row(2, from: kare, minutes: 10)]
        let model = await makeModel(viewer: kare, rows: rows)
        #expect(model.unreadCount == 1)
        model.isVisible = true
        model.markReadIfVisible()
        #expect(model.unreadCount == 0)
        // Lest til = andres nyeste, ikke egen.
        #expect(store.lastSeen(memberID: kare, eventID: event) == rows[0].createdAt)
    }

    @Test func ikkeVistMerkesIkkeLest() async {
        let model = await makeModel(viewer: kare, rows: [row(1, from: thomasR, minutes: 0)])
        model.markReadIfVisible()
        #expect(model.unreadCount == 1)
        #expect(model.summary.unread == 1 && model.summary.count == 1)
    }

    // MARK: Sending

    @Test func senderTrimmetTekstMedNevnte() async {
        let model = await makeModel(viewer: thomasS)
        model.draft = "  Kommer 17:30, @kåre og @ThomasR!  "
        await model.send()
        let inserted = await backend.inserted
        #expect(inserted.count == 1)
        let insert = inserted[0]
        #expect(insert.body == "Kommer 17:30, @kåre og @ThomasR!")
        #expect(Set(insert.mentions) == [thomasR, kare])
        #expect(insert.memberID == thomasS && insert.eventID == event && insert.clubID == club)
        #expect(insert.imagePath == nil)
        #expect(model.draft.isEmpty)
        #expect(model.pending.isEmpty)
        // Serverens tid, ikke telefonens.
        #expect(model.items.last?.message.createdAt == Date(timeIntervalSince1970: 3_000_000))
        #expect(model.items.last?.isMine == true)
        #expect(await backend.uploaded.isEmpty)
    }

    @Test func avvistRullesTilbakeMedTekstenIBehold() async {
        let model = await makeModel(viewer: thomasS)
        await backend.failInsert(DataError.notAllowed)
        model.draft = "Denne feiler"
        await model.send()
        #expect(model.items.isEmpty)
        #expect(model.pending.isEmpty)
        #expect(model.draft == "Denne feiler")
        #expect(model.errorMessage?.hasPrefix("Klarte ikke å sende") == true)
    }

    @Test func lagretMenSvaretGikkTaptGirIkkeDobbel() async throws {
        let model = await makeModel(viewer: thomasS)
        await backend.set(loseInsertAnswer: true)
        model.draft = "Kommer straks"
        await model.attach(imageData: try TradImageCompressorTests.jpeg(width: 400, height: 300))
        await model.send()
        // Meldingen står én gang, teksten er ikke lagt tilbake, og bildet er ikke fjernet.
        #expect(model.items.map(\.message.body) == ["Kommer straks"])
        #expect(model.items.first?.isPending == false)
        #expect(model.draft.isEmpty)
        #expect(model.attachment == nil)
        #expect(model.errorMessage == nil)
        #expect(await backend.removed.isEmpty)
    }

    @Test func tomOgForLangSendesIkke() async {
        let model = await makeModel(viewer: thomasS)
        model.draft = "   "
        await model.send()
        #expect(model.errorMessage == nil)
        model.draft = String(repeating: "x", count: 501)
        #expect(!model.canSend)
        await model.send()
        #expect(model.errorMessage?.contains("maks 500") == true)
        #expect(await backend.inserted.isEmpty)
        #expect(model.draft.count == 501)
    }

    @Test func bildeLastesOppForMeldingen() async throws {
        let model = await makeModel(viewer: thomasS)
        let attachment = try image()
        await model.attach(imageData: attachment.data)
        #expect(model.attachment != nil)
        #expect(model.canSend)
        await model.send()
        let uploaded = await backend.uploaded
        let insert = try #require(await backend.inserted.first)
        let path = TradImagePath.make(memberID: thomasS, messageID: insert.id)
        #expect(uploaded.map(\.path) == [path])
        #expect(insert.imagePath == path)
        #expect(insert.body == "")
        #expect(model.attachment == nil)
        // Vises fra telefonen selv, uten signert lenke.
        #expect(model.images.hasLocal(path))
        #expect(await backend.signCalls.isEmpty)
    }

    @Test func opplastingFeilerIngenMelding() async throws {
        let model = await makeModel(viewer: thomasS)
        await model.attach(imageData: try image().data)
        await backend.failUpload(URLError(.notConnectedToInternet))
        model.draft = "Se her"
        await model.send()
        #expect(await backend.inserted.isEmpty)
        #expect(model.draft == "Se her")
        #expect(model.attachment != nil)
        #expect(model.items.isEmpty)
        #expect(model.errorMessage?.hasPrefix("Klarte ikke å laste opp bildet") == true)
    }

    @Test func meldingFeilerBildetFjernesIgjen() async throws {
        let model = await makeModel(viewer: thomasS)
        await model.attach(imageData: try image().data)
        await backend.failInsert(DataError.invalid("nei"))
        model.draft = "Se her"
        await model.send()
        let uploaded = await backend.uploaded.map(\.path)
        #expect(await backend.removed == [uploaded])
        #expect(model.draft == "Se her")
        #expect(model.attachment != nil)
        #expect(!model.images.hasLocal(uploaded[0]))
        #expect(model.errorMessage?.hasPrefix("Klarte ikke å sende") == true)
    }

    // MARK: Sletting

    @Test func sletterEgenMedBildet() async {
        let path = TradImagePath.make(memberID: kare, messageID: Self.id(101))
        let model = await makeModel(viewer: kare, rows: [row(1, from: kare, minutes: 0, body: "", image: path)])
        #expect(model.items.first?.canDelete == true)
        await model.delete(Self.id(101))
        #expect(await backend.deleted == [Self.id(101)])
        #expect(await backend.removed == [[path]])
        #expect(model.items.isEmpty)
    }

    @Test func vanligSpillerKanIkkeSletteAndres() async {
        let model = await makeModel(viewer: thomasS, rows: [row(3, from: kare, minutes: 0)])
        #expect(model.items.first?.canDelete == false)
        await model.delete(Self.id(103))
        #expect(await backend.deleted.isEmpty)
        #expect(model.items.count == 1)
    }

    @Test func arrangorenKanSletteAlle() async {
        let model = await makeModel(viewer: thomasR, organizer: true, rows: [row(2, from: thomasS, minutes: 0)])
        #expect(model.items.first?.canDelete == true)
        await model.delete(Self.id(102))
        #expect(await backend.deleted == [Self.id(102)])
        #expect(model.items.isEmpty)
    }

    @Test func avvistSlettingStarIgjen() async {
        let model = await makeModel(viewer: kare, rows: [row(3, from: kare, minutes: 0)])
        await backend.failDelete(URLError(.timedOut))
        await model.delete(Self.id(103))
        #expect(model.items.map(\.id) == [Self.id(103)])
        #expect(model.errorMessage?.hasPrefix("Klarte ikke å slette") == true)
        #expect(await backend.removed.isEmpty)
    }

    @Test func ingenRadSlettetSierFra() async {
        let model = await makeModel(viewer: kare, rows: [row(3, from: kare, minutes: 0)])
        await backend.set(deleteResult: false)
        await model.delete(Self.id(103))
        #expect(model.items.map(\.id) == [Self.id(103)])
        #expect(model.errorMessage?.contains("tilgang") == true)
    }

    // MARK: Bilder

    @Test func lenkeneHentesSamletEnTime() async {
        let p1 = "b/m1.jpg", p2 = "b/m2.jpg"
        let model = await makeModel(viewer: kare, rows: [row(1, from: thomasS, minutes: 0, body: "", image: p1),
                                                         row(2, from: thomasS, minutes: 1, image: p2),
                                                         row(3, from: thomasR, minutes: 2)])
        let calls = await backend.signCalls
        #expect(calls.count == 1)
        #expect(calls.first?.paths == [p1, p2] && calls.first?.seconds == 3600)
        #expect(model.imageURL(for: p1) == URL(string: "https://lager/b/m1.jpg?token=t"))
        // Ferske lenker hentes ikke på nytt.
        await model.refreshImageURLs()
        #expect(await backend.signCalls.count == 1)
    }

    @Test func lenkeSomFeilerMerkesOgProvesIkkeIUendelighet() async {
        let p1 = "b/m1.jpg", p2 = "b/m2.jpg"
        await backend.set(unsignable: [p2])
        let model = await makeModel(viewer: kare, rows: [row(1, from: thomasS, minutes: 0, body: "", image: p1),
                                                         row(2, from: thomasS, minutes: 1, body: "", image: p2)])
        #expect(model.imageURL(for: p1) != nil)
        #expect(model.imageFailed(p2) && model.imageURL(for: p2) == nil)
        await model.refreshImageURLs()
        #expect(await backend.signCalls.count == 1)
        // Ny henting av tråden prøver igjen.
        await model.load()
        #expect(await backend.signCalls.last?.paths == [p2])
    }

    // MARK: @navn

    @Test func forslagOgInnsetting() async {
        let model = await makeModel(viewer: carl)
        model.draft = "Hei @tho"
        #expect(model.suggestions.map(\.handle) == ["ThomasR", "ThomasS"])
        model.insertMention("ThomasS")
        #expect(model.draft == "Hei @ThomasS ")
        #expect(model.suggestions.isEmpty)
    }
}
