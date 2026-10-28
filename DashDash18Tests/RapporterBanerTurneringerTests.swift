import Foundation
import Testing
@testable import DashDash18

/// 1.0.1 (App Review 1.2): rapporter baner i det felles biblioteket og turneringer i «Finn
/// turneringer» (sql/066, `PublicContentReportFeature`).
struct RapporterBanerTurneringerTests {
    private static func course(_ name: String, by owner: UUID?, fromSource: Bool = false) -> CourseListItem {
        let row = CourseRow(id: UUID(), clubID: nil, name: name, externalName: nil, courseRating: nil,
                            slopeRating: nil, inUse: true, confirmedBy: nil, confirmedAt: nil,
                            createdByProfile: owner)
        return CourseListItem(course: row, holes: [], isFromSource: fromSource)
    }

    @Test func flaggetErPaaEtter066() {
        #expect(PublicContentReportFeature.flag)
    }

    @Test func nyeTyperMedTekster() {
        #expect(ReportKind.course.rawValue == "course")
        #expect(ReportKind.competition.rawValue == "competition")
        #expect(ReportKind.course.title == "Rapporter banen")
        #expect(ReportKind.competition.title == "Rapporter turneringen")
        #expect(ReportKind.course.label == "Bane")
        #expect(ReportKind.competition.label == "Turnering")
    }

    @Test func banerOgTurneringerGaarBareTilOss() {
        #expect(!ReportKind.course.reachesOrganizer)
        #expect(!ReportKind.competition.reachesOrganizer)
        #expect(ReportKind.message.reachesOrganizer)
        #expect(ReportKind.course.sentText == "Takk. Rapporten er sendt til oss, og vi ser på den innen 24 timer.")
        #expect(ReportKind.comment.sentText.contains("arrangøren og oss"))
    }

    @Test func grunnene() {
        #expect(ReportReason.options(for: .course) == [.offensive, .harassment, .spam, .other])
        #expect(ReportReason.options(for: .competition) == [.offensive, .harassment, .spam, .impersonation, .other])
    }

    @Test func rapportradenMedNyTypeLeses() throws {
        let json = #"{"id": "00000000-0000-0000-0000-000000000001", "kind": "competition", "target_id": "00000000-0000-0000-0000-000000000002", "club_id": null, "reason": "spam", "note": null, "snapshot": "Vinterserien · Bryn", "status": "open", "created_at": "2026-10-21T10:00:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(ContentReportRow.self, from: Data(json.utf8))
        #expect(row.kind == .competition && row.clubID == nil)
    }

    @Test func skjultInnholdFraServeren() throws {
        let course = UUID(), competition = UUID(), message = UUID()
        let json = """
        [{"kind": "course", "target_id": "\(course)"}, {"kind": "competition", "target_id": "\(competition)"},
         {"kind": "message", "target_id": "\(message)"}, {"kind": "noe_nytt", "target_id": "\(UUID())"}]
        """
        let rows = try JSONDecoder().decode([HiddenContent.Row].self, from: Data(json.utf8))
        let hidden = HiddenContent(rows: rows)
        #expect(hidden.courses == [course])
        #expect(hidden.competitions == [competition])

        var local = HiddenContent()
        local.insert(.course, message)
        local.insert(.comment, UUID())
        #expect(local.courses == [message] && local.competitions.isEmpty)
        let merged = local.merging(hidden)
        #expect(merged.courses == [course, message] && merged.competitions == [competition])
    }

    @Test func baneKanRapporteresNaarEnAnnenHarLagtDenInn() {
        let me = UUID(), other = UUID()
        let mine = Self.course("Min bane", by: me)
        let theirs = Self.course("Deres bane", by: other)
        let fetched = Self.course("Losby", by: nil, fromSource: true)
        let orphan = Self.course("Uten eier", by: nil)
        func can(_ item: CourseListItem, shared: Bool = true, enabled: Bool = true) -> Bool {
            CourseReports.canReport(item, isShared: shared, isOwn: item.course.createdByProfile == me, enabled: enabled)
        }
        #expect(can(theirs))
        #expect(can(orphan), "kontoen bak banen er slettet")
        #expect(!can(mine))
        #expect(!can(fetched), "hentet fra slope.no")
        #expect(!can(theirs, shared: false), "klubbens bibliotek")
        #expect(!can(theirs, enabled: false))
    }

    @Test func rapporterteBanerSkjulesMenEgneStaar() {
        let me = UUID()
        let mine = Self.course("Min bane", by: me)
        let theirs = Self.course("Deres bane", by: UUID())
        let notReady = Self.course("Ikke klar", by: UUID())
        let items = [mine, theirs, notReady]
        let isOwn: (CourseListItem) -> Bool = { $0.course.createdByProfile == me }
        #expect(CourseReports.listed(items, hidden: [], isOwn: isOwn) == items)
        #expect(CourseReports.listed(items, hidden: [theirs.id, notReady.id], isOwn: isOwn) == [mine])
        #expect(CourseReports.listed(items, hidden: [mine.id], isOwn: isOwn) == items)
    }

    @Test func rapporterteTurneringerSkjulesIFinn() throws {
        let a = try FindTournamentsTests.row(name: "Vinterserien")
        let b = try FindTournamentsTests.row(name: "Bryn Cup")
        #expect(FindTournaments.visible([a, b], query: "", hidden: []) == [a, b])
        #expect(FindTournaments.visible([a, b], query: "", hidden: [a.id]) == [b])
        #expect(FindTournaments.visible([a, b], query: "vinter", hidden: [b.id]) == [a])
        #expect(FindTournaments.visible([a, b], query: "vinter", hidden: [a.id]).isEmpty)
    }

    @Test func rapportmaaletForTurneringen() throws {
        let row = try FindTournamentsTests.row(name: "Vinterserien")
        let target = FindTournaments.reportTarget(row)
        #expect(target.kind == .competition && target.targetID == row.id)
        #expect(target.memberID == nil, "ingen å blokkere")
        #expect(target.authorName == "Vinterserien")
    }
}
