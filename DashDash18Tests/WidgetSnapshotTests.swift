import Foundation
import Testing
@testable import DashDash18

/// Widget-data: neste kveld og topp 3, JSON og lagring i App Group (eller reserven).
struct WidgetSnapshotTests {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static func event(date: String = "2026-10-08", time: String? = "17:00:00", venue: String? = "Losby") -> EventRow {
        EventRow(id: id(1), clubID: id(2), seasonID: nil, eventDate: date, startTime: time, venue: venue, note: nil)
    }

    static func row(_ n: Int, _ name: String, place: Int, total: Double, isMe: Bool = false) -> TavlaStandings.Row {
        TavlaStandings.Row(memberID: id(n), name: name, place: place, total: total, duel: total, side: 0,
                           matches: 0, holes: 0, stableford: 0, evenings: 1, isMe: isMe)
    }

    static func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    // MARK: Neste kveld

    @Test func nesteKveldMedDatoTidOgBane() {
        let next = WidgetSnapshot.NextEvening(event: Self.event(), referenceYear: 2026)
        #expect(next.eventDate == "2026-10-08")
        #expect(next.dateText == "Torsdag 8. oktober")
        #expect(next.timeText == "17:00")
        // 17:00 i Oslo (sommertid, UTC+2).
        #expect(next.startsAt == Self.iso("2026-10-08T15:00:00Z"))
        #expect(next.venue == "Losby")
    }

    @Test func utenKlokkeslettStarterKvelden12() {
        let next = WidgetSnapshot.NextEvening(event: Self.event(date: "2026-12-03", time: nil, venue: "  "),
                                              referenceYear: 2026)
        #expect(next.timeText == nil)
        // Vintertid, UTC+1.
        #expect(next.startsAt == Self.iso("2026-12-03T11:00:00Z"))
        #expect(next.venue == nil)
    }

    @Test func aaretTasMedNaarDetErEtAnnet() {
        let next = WidgetSnapshot.NextEvening(event: Self.event(date: "2027-04-01"), referenceYear: 2026)
        #expect(next.dateText == "Torsdag 1. april 2027")
    }

    // MARK: Topp 3

    @Test func toppTreITabellensRekkefolge() {
        let rows = [Self.row(1, "Anders", place: 1, total: 14.5), Self.row(2, "Bjørn", place: 2, total: 12),
                    Self.row(3, "Cato", place: 3, total: 9, isMe: true), Self.row(4, "Dag", place: 4, total: 3)]
        let top = WidgetSnapshot.topThree(rows) { "\($0) p" }
        #expect(top.map(\.place) == [1, 2, 3])
        #expect(top.map(\.name) == ["Anders", "Bjørn", "Cato"])
        #expect(top.map(\.pointsText) == ["14.5 p", "12.0 p", "9.0 p"])
        #expect(top.map(\.isMe) == [false, false, true])
    }

    @Test func faerreEnnTreSpillere() {
        let top = WidgetSnapshot.topThree([Self.row(1, "Anders", place: 1, total: 2)]) { "\($0)" }
        #expect(top.count == 1)
        #expect(WidgetSnapshot.topThree([]) { "\($0)" }.isEmpty)
    }

    // MARK: JSON

    static let sample = WidgetSnapshot(
        nextEvening: .init(eventDate: "2026-10-08", dateText: "Torsdag 8. oktober", timeText: "17:00",
                           startsAt: iso("2026-10-08T15:00:00Z"), venue: "Losby"),
        seasonName: "Sesong 2026",
        top: [.init(place: 1, name: "Anders", points: 14.5, pointsText: "14,5", isMe: false)],
        updatedAt: iso("2026-10-07T10:00:00Z"))

    @Test func kodesOgLesesTilbake() throws {
        let data = try WidgetSnapshotStore.encoder().encode(Self.sample)
        let back = try WidgetSnapshotStore.decoder().decode(WidgetSnapshot.self, from: data)
        #expect(back == Self.sample)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"startsAt\":\"2026-10-08T15:00:00Z\""))
        #expect(json.contains("\"eventDate\":\"2026-10-08\""))
    }

    @Test func sammeInnholdUansettTidspunkt() {
        var later = Self.sample
        later.updatedAt = .now
        #expect(later.sameContent(as: Self.sample))
        later.top = []
        #expect(!later.sameContent(as: Self.sample))
    }

    // MARK: Lagring

    static func tempStore() -> WidgetSnapshotStore {
        WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "widget-tests-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func tomtNaarIngentingErLagret() {
        #expect(Self.tempStore().read() == .empty)
    }

    @Test func oppdateringSkriverOgBeholderResten() throws {
        let store = Self.tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let t1 = Self.iso("2026-10-07T10:00:00Z"), t2 = Self.iso("2026-10-07T11:00:00Z")

        #expect(store.update(now: t1, reloadWidgets: false) { $0.nextEvening = Self.sample.nextEvening })
        #expect(store.update(now: t2, reloadWidgets: false) { $0.top = Self.sample.top; $0.seasonName = "Sesong 2026" })

        let saved = store.read()
        #expect(saved.nextEvening == Self.sample.nextEvening)
        #expect(saved.top == Self.sample.top)
        #expect(saved.updatedAt == t2)
    }

    @Test func ingenSkrivingNaarInnholdetErLikt() throws {
        let store = Self.tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let t1 = Self.iso("2026-10-07T10:00:00Z")
        store.update(now: t1, reloadWidgets: false) { $0.seasonName = "Sesong 2026" }
        #expect(!store.update(now: .now, reloadWidgets: false) { $0.seasonName = "Sesong 2026" })
        #expect(store.read().updatedAt == t1)
    }

    @Test func oedelagtFilGirTomt() throws {
        let store = Self.tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("ikke json".utf8).write(to: store.fileURL)
        #expect(store.read() == .empty)
    }

    @Test func appGroupErGroupPlussBundleID() {
        #expect(AppGroup.identifier == "group.com.dashdash18.app")
    }

    @Test func reserveNaarContainerenMangler() {
        let fallback = WidgetSnapshotStore.containerDirectory(nil)
        #expect(fallback.path().hasSuffix("WidgetSnapshot/"))
        let group = URL(filePath: "/tmp/group", directoryHint: .isDirectory)
        #expect(WidgetSnapshotStore.containerDirectory(group) == group)
    }
}
