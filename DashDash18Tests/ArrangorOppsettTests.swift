import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// Fase 11: enklere oppsett av baner og sesong. Ren logikk bak skjermene.

struct BaneKlarTests {
    @Test func klarNarAlleHullHarPar() {
        #expect(CourseReadiness(pars: Course.defaultPar) == .ready)
        #expect(CourseReadiness(pars: Array(Course.defaultPar.prefix(9))).title == "Klar")
    }

    @Test func manglerParIKlartSprak() {
        var pars: [Int?] = Course.defaultPar
        pars[2] = nil
        #expect(CourseReadiness(pars: pars).title == "Mangler par på 1 hull")
        pars[5] = nil
        pars[11] = nil
        #expect(CourseReadiness(pars: pars) == .missingPar(missing: 3, total: 18))
        #expect(CourseReadiness(pars: pars).title == "Mangler par på 3 hull")
        #expect(CourseReadiness(pars: Array(repeating: nil, count: 9)).title == "Mangler par på alle hull")
        #expect(CourseReadiness(pars: []).title == "Mangler par")
    }

    @Test func ugyldigParTellerSomManglende() {
        var pars: [Int?] = Course.defaultPar
        pars[0] = 7
        #expect(CourseReadiness(pars: pars).title == "Mangler par på 1 hull")
    }

    @Test func forklaringenSierHvaSomKreves() {
        let missing = CourseReadiness.missingPar(missing: 2, total: 18)
        #expect(missing.detail(kind: .simulator).contains("alle hullene har par"))
        #expect(missing.detail(kind: .simulator).contains("skjermen"))
        #expect(missing.detail(kind: .course).contains("scorekortet"))
        #expect(missing.detail(kind: .course).contains("Indeks, lengde og rating er valgfritt"))
    }

    @Test func skjemaetsKlarStatus() {
        var draft = CourseDraft()
        #expect(draft.readiness.title == "Mangler par på alle hull")
        draft.fillStandardPar()
        #expect(draft.readiness == .ready)
        #expect(draft.par == 72)
    }

    @Test func listeradenUtenHullManglerPar() {
        let item = BanerFixtures.item(pars: [])
        #expect(item.readiness == .noHoles)
        #expect(BanerFixtures.item(pars: Course.defaultPar).readiness == .ready)
    }
}

struct BaneSkjemaTests {
    @Test func standardParFyllerBareTommeHull() {
        var draft = CourseDraft()
        draft.holes[0].par = 3
        draft.fillStandardPar()
        #expect(draft.holes[0].par == 3)
        #expect(Array(draft.holes.dropFirst().map(\.par)) == Array(Course.defaultPar.dropFirst()).map(Optional.some))
        #expect(draft.holesMissingPar.isEmpty)
    }

    @Test func standardParFor9Og18Hull() {
        #expect(CourseDraft(holeCount: 18).standardPar == 72)
        #expect(CourseDraft(holeCount: 9).standardPar == 36)
    }

    @Test func hurtigknappVelgerOgTommer() {
        var draft = CourseDraft(holeCount: 9)
        draft.tapPar(4, hole: 3)
        #expect(draft.holes[2].par == 4)
        draft.tapPar(5, hole: 3)
        #expect(draft.holes[2].par == 5)
        draft.tapPar(5, hole: 3)
        #expect(draft.holes[2].par == nil)
        #expect(draft.holesMissingPar == Array(1...9))
    }

    @Test func ekteBaneHarIkkeSimulatornavn() throws {
        var draft = CourseDraft(holeCount: 9)
        draft.name = "Bogstad"
        draft.externalName = "Noe i simulatoren"
        draft.fillStandardPar()
        draft.kind = .course
        #expect(!draft.usesExternalName)
        let values = try #require(draft.validate().values)
        #expect(values.externalName == nil)
        #expect(values.kind == .course)

        draft.kind = .simulator
        #expect(try #require(draft.validate().values).externalName == "Noe i simulatoren")
    }
}

struct BanetypeTests {
    @Test func utenLagretTypeErAlleSimulatorbaner() {
        #expect(CourseKind.resolve(stored: nil) == .simulator)
        #expect(CourseKind.resolve(stored: .course) == .course)
        #expect(BanerFixtures.item(pars: [], external: nil).kind == .simulator)
    }

    /// 016 er kjørt på test (07.10.2026).
    @Test func flaggetErPaaEtter016() {
        #expect(CourseKindFeature.isEnabled)
    }

    /// Hurtigstarten viser banene som passer stedet, og beholder valgt bane.
    @Test func hurtigstartenFiltrererBaneneEtterSted() {
        func bane(_ kind: CourseKind) -> CourseListItem {
            var item = BanerFixtures.item(name: kind.rawValue, pars: Course.defaultPar)
            item.storedKind = kind
            return item
        }
        let sim = bane(.simulator), ute = bane(.course)
        #expect(QuickStart.courses([sim, ute], for: .simulator, selected: nil).map(\.id) == [sim.id])
        #expect(QuickStart.courses([sim, ute], for: .course, selected: nil).map(\.id) == [ute.id])
        #expect(QuickStart.courses([sim, ute], for: .course, selected: sim.id).map(\.id) == [sim.id, ute.id])
    }

    @Test func rawVerdierSomISkjemaet() {
        #expect(CourseKind.allCases.map(\.rawValue) == ["simulator", "course"])
    }

    @Test func listaDelesISimulatorOgEkte() {
        let a = BanerFixtures.item(name: "Adare Manor", pars: Course.defaultPar)
        var b = BanerFixtures.item(name: "Bogstad", pars: Course.defaultPar)
        b.storedKind = .course
        let c = BanerFixtures.item(name: "Lofoten Links", pars: [])
        let groups = CourseListItem.grouped([b, a, c])
        #expect(groups.map(\.kind) == [.simulator, .course])
        #expect(groups[0].items.map(\.course.name) == ["Adare Manor", "Lofoten Links"])
        #expect(groups[0].kind.groupTitle == "Simulatorbaner")
        #expect(groups[1].kind.groupTitle == "Ekte baner")
        #expect(CourseListItem.grouped([a]).map(\.kind) == [.simulator])
    }

    @Test func lagredeTyperFolgerMedFraSporringen() {
        let a = BanerFixtures.item(name: "A", pars: [])
        let items = CourseListItem.make(courses: [a.course], holes: [], kinds: [a.id: .course])
        #expect(items.first?.kind == .course)
    }
}

struct RegelsettSammendragTests {
    @Test func golfgutuIKlartSprak() {
        #expect(RulesetSummary.lines(for: .golfgutu) == [
            "Stableford (netto), høyst 4 per bås",
            "7 kvelder, alle matcher teller",
            "Seier 1 poeng, uavgjort 0,5, tap 0",
            "95 % handicap i stableford (netto), egen andel per form",
            "Seeding i 3 grupper (0, 5 og 10)",
            "Longest drive og nærmest pinnen gir 1 poeng hver",
        ])
        #expect(RulesetSummary.badge(for: .golfgutu) == "Golfgutu-oppsettet")
        #expect(RulesetSummary.short(for: .golfgutu) == "7 kvelder, alle matcher teller")
    }

    @Test func endretOppsett() {
        var r = Ruleset.golfgutu
        r.table.counting = .init(unit: .evening, best: 5)
        r.handicap.allowanceOverride = 0.85
        r.handicap.seedingGroups = []
        r.sidePrizes.closestToPin.enabled = false
        let lines = RulesetSummary.lines(for: r)
        #expect(lines.contains("Beste 5 av 7 kvelder teller"))
        #expect(lines.contains("85 % handicap i alle former"))
        #expect(lines.contains("Longest drive gir 1 poeng"))
        #expect(!lines.contains { $0.hasPrefix("Seeding") })
        #expect(RulesetSummary.badge(for: r) == "4 valg endret fra Golfgutu")
        #expect(!RulesetSummary.isGolfgutu(r))
    }

    @Test func varianterAvTelling() {
        var r = Ruleset.golfgutu
        r.table.counting = .init(unit: .match, best: 10)
        #expect(RulesetSummary.short(for: r) == "7 kvelder, beste 10 matcher teller")
        r.table.counting = .init(unit: .evening, best: 1)
        #expect(RulesetSummary.short(for: r) == "Beste kveld av 7 teller")
        r.evenings = 1
        r.table.counting = .init(unit: .round, best: nil)
        #expect(RulesetSummary.short(for: r) == "1 kveld, alle runder teller")
        r.handicap.externalHandicap = true
        #expect(RulesetSummary.lines(for: r).contains("Simulatoren deler ut slagene"))
        #expect(RulesetSummary.badge(for: r) == "3 valg endret fra Golfgutu")
    }

    @Test func golfgutuEtterLagringErFortsattGolfgutu() throws {
        let data = try RulesetDraft.encoded(.golfgutu)
        let decoded = try JSONDecoder().decode(Ruleset.self, from: data)
        #expect(RulesetSummary.isGolfgutu(decoded))
        #expect(RulesetField.changed(decoded).isEmpty)
    }
}

struct EndretFraStandardTests {
    @Test func golfgutuHarIngenEndringer() {
        #expect(RulesetField.changed(.golfgutu).isEmpty)
        for field in RulesetField.allCases {
            #expect(field.changeNote(.golfgutu) == nil)
        }
    }

    /// Hver endring treffer akkurat ett valg, så merket står på riktig felt.
    @Test func endringTrefferEttValg() {
        let cases: [(RulesetField, (inout Ruleset) -> Void)] = [
        (RulesetField.evenings, { (r: inout Ruleset) in r.evenings = 8 }),
        (.counting, { r in r.table.counting.best = 5 }),
        (.win, { r in r.table.matchPoints.win = 3 }),
        (.draw, { r in r.table.matchPoints.draw = 1 }),
        (.loss, { r in r.table.matchPoints.loss = -1 }),
        (.allowance, { r in r.handicap.allowanceOverride = 0.85 }),
        (.allowance, { r in r.handicap.formAllowances["stableford"] = 1 }),
        (.longestDrive, { r in r.sidePrizes.longestDrive.points = 2 }),
        (.closestToPin, { r in r.sidePrizes.closestToPin.enabled = false }),
        (.splitTies, { r in r.sidePrizes.splitTies = false }),
        (.scoring, { r in r.scoring.netParPoints = 3 }),
        (.trianglePoints, { r in r.table.trianglePoints = [3, 1, 0] }),
        (.stablefordCounting, { r in r.table.stablefordCounting.best = nil }),
        (.tiebreaks, { r in r.table.tiebreaks = [.stableford] }),
        (.rounding, { r in r.table.roundingStep = nil }),
        (.seeding, { r in r.handicap.seedingGroups = [] }),
        (.externalHandicap, { r in r.handicap.externalHandicap = true }),
        (.teamHandicap, { r in r.handicap.teamHandicap = [:] }),
        (.defaultForm, { r in r.formats.defaultFormID = "match" }),
        (.allowedForms, { r in r.formats.allowedFormIDs = ["stableford"] }),
        (.maxPerBay, { r in r.formats.maxPerBay = 3 }),
        (.matchStrokes, { r in r.formats.matchStrokes = .fullHandicap }),
        (.other, { r in r.leadCheckpoints = [9, 18] }),
        ]
        for (field, change) in cases {
            var r = Ruleset.golfgutu
            change(&r)
            #expect(RulesetField.changed(r) == [field], "\(field)")
            #expect(field.changeNote(r) != nil)
        }
        // Alle valgene er prøvd.
        #expect(Set(cases.map(\.0)) == Set(RulesetField.allCases))
    }

    @Test func merketViserStandardverdien() {
        var r = Ruleset.golfgutu
        r.table.matchPoints.win = 2
        r.evenings = 10
        r.handicap.allowanceOverride = 0.85
        r.sidePrizes.longestDrive.enabled = false
        r.table.counting.best = 5
        #expect(RulesetField.win.changeNote(r) == "Endret · standard 1")
        #expect(RulesetField.evenings.changeNote(r) == "Endret · standard 7")
        #expect(RulesetField.allowance.changeNote(r) == "Endret · standard per form")
        #expect(RulesetField.longestDrive.changeNote(r) == "Endret · standard 1 poeng")
        #expect(RulesetField.counting.changeNote(r) == "Endret · standard alle matcher")
        #expect(RulesetField.draw.changeNote(r) == nil)
    }

    @Test func vanligeOgAvanserteValg() {
        let common = RulesetField.allCases.filter(\.isCommon)
        #expect(common == [.evenings, .counting, .win, .draw, .loss, .allowance, .longestDrive, .closestToPin, .splitTies])
    }

    @Test func utkastetTellerAvanserteEndringerOgTilbakestilles() {
        var draft = RulesetDraft(.golfgutu)
        #expect(draft.isGolfgutu)
        draft.rules.table.roundingStep = nil
        draft.rules.formats.maxPerBay = 3
        draft.rules.table.matchPoints.win = 2
        #expect(draft.changedAdvancedCount == 2)
        #expect(draft.changeNote(.win) == "Endret · standard 1")
        #expect(!draft.isGolfgutu)
        draft.resetToGolfgutu()
        #expect(draft.isGolfgutu)
        #expect(draft.changeNote(.win) == nil)
        #expect(draft.changedAdvancedCount == 0)
    }
}

struct NySesongForslagTests {
    private static let club = UUID()
    private static let oct2026 = Date(timeIntervalSince1970: 1_791_367_200) // 7. oktober 2026, 12:00 i Oslo

    private static var oslo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return c
    }

    private static func season(_ name: String, rules: Ruleset = .golfgutu) -> SeasonRow {
        SeasonRow(id: UUID(), clubID: club, name: name, status: .finished, rules: rules)
    }

    @Test func navnMedAret() {
        #expect(SeasonLifecycle.suggestedName(seasons: [], now: Self.oct2026, calendar: Self.oslo) == "Sesongen 2026")
    }

    @Test func tattNavnGirNesteAr() {
        let seasons = [Self.season(" sesongen 2026 "), Self.season("Sesongen 2027")]
        #expect(SeasonLifecycle.suggestedName(seasons: seasons, now: Self.oct2026, calendar: Self.oslo) == "Sesongen 2028")
    }

    @Test func reglerKopieresFraForrigeSesong() {
        var rules = Ruleset.golfgutu
        rules.evenings = 9
        let seasons = [Self.season("Sesongen 2026", rules: rules), Self.season("Sesongen 2025")]
        let template = SeasonLifecycle.defaultTemplate(seasons: seasons)
        #expect(SeasonLifecycle.rules(for: template, seasons: seasons) == rules)
        #expect(SeasonLifecycle.rules(for: SeasonLifecycle.defaultTemplate(seasons: []), seasons: []) == .golfgutu)
    }
}

private enum BanerFixtures {
    static let club = UUID()

    static func item(name: String = "Testbanen", pars: [Int], external: String? = nil) -> CourseListItem {
        let id = UUID()
        let course = CourseRow(id: id, clubID: club, name: name, externalName: external, courseRating: nil,
                               slopeRating: nil, inUse: true, confirmedBy: nil, confirmedAt: nil)
        let holes = pars.enumerated().map { i, par in
            CourseHoleRecord(courseID: id, holeNumber: i + 1, par: par, strokeIndex: nil, lengthM: nil)
        }
        return CourseListItem(course: course, holes: holes)
    }
}
