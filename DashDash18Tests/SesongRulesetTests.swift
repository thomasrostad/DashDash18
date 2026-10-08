import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

struct SesongForklaringTests {
    @Test func golfgutuTeksten() {
        let tekst = RulesetExplanation.text(for: .golfgutu)
        #expect(tekst == """
        Sesongen har 7 kvelder. Seier gir 1 poeng, uavgjort 0,5. Trekanten gir 1 / 0,5 / 0 poeng etter plass. \
        Alle matcher teller. Longest drive og nærmest pinnen gir 1 poeng hver. Likt deler poenget. \
        Tabellpoengene rundes til nærmeste 0,5. Ved likt poeng skiller hulldifferanse, så stablefordsummen. \
        Stablefordsummen er de 5 beste rundene. Netto par gir 2 stablefordpoeng. Handicapandelen følger formen. \
        Seeding: Gruppe 1 spiller på 0, Gruppe 2 på 5 og Gruppe 3 på 10. \
        Stableford (netto) er standardformen, og alle 16 former er tillatt. Høyst 4 spillere per bås. \
        I match spiller den laveste fra scratch.
        """)
    }

    /// «Et annet oppsett» fra REGELSETT.md.
    @Test func annetOppsett() {
        var r = Ruleset.golfgutu
        r.evenings = 5
        r.table.matchPoints = .init(win: 3, draw: 1, loss: 0)
        r.table.trianglePoints = [3, 1, 0]
        r.table.counting = .init(unit: .evening, best: 3)
        r.table.stablefordCounting = .init(unit: .evening, best: 3)
        r.table.tiebreaks = [.stableford, .holeDifference]
        r.table.roundingStep = nil
        r.sidePrizes.longestDrive = .init(enabled: false, points: 0)
        r.sidePrizes.closestToPin = .init(enabled: false, points: 0)
        r.handicap.allowanceOverride = 1
        r.handicap.seedingGroups = []
        r.formats.allowedFormIDs = ["stableford", "match", "fourball", "scramble-2"]

        let s = RulesetExplanation.sentences(for: r)
        #expect(s.contains("Sesongen har 5 kvelder."))
        #expect(s.contains("Seier gir 3 poeng, uavgjort 1."))
        #expect(s.contains("De 3 beste kveldene teller."))
        #expect(s.contains("Ingen sidepremier."))
        #expect(!s.contains { $0.hasPrefix("Likt") || $0.hasPrefix("Tabellpoengene") || $0.hasPrefix("Seeding") })
        #expect(s.contains("Ved likt poeng skiller stablefordsummen, så hulldifferanse."))
        #expect(s.contains("Stablefordsummen er de 3 beste kveldene."))
        #expect(s.contains("Alle spiller med 100 % av handicapet."))
        #expect(s.contains("Stableford (netto) er standardformen, og 4 av 16 former er tillatt."))
    }

    @Test func varianter() {
        var r = Ruleset.golfgutu
        r.evenings = 1
        r.table.matchPoints = .init(win: 2, draw: 1, loss: 0.5)
        r.table.counting = .init(unit: .round, best: 1)
        r.table.stablefordCounting = .init(unit: .round, best: nil)
        r.sidePrizes.closestToPin = .init(enabled: true, points: 2)
        r.sidePrizes.splitTies = false
        r.handicap.allowanceOverride = 0.95
        r.handicap.externalHandicap = true
        r.formats.maxPerBay = 1
        r.formats.matchStrokes = .fullHandicap
        r.formats.allowedFormIDs = ["stableford"]
        r.scoring.minimumPoints = 1

        let s = RulesetExplanation.sentences(for: r)
        #expect(s.contains("Sesongen har 1 kveld."))
        #expect(s.contains("Seier gir 2 poeng, uavgjort 1 og tap 0,5."))
        #expect(s.contains("Den beste runden teller."))
        #expect(s.contains("Stablefordsummen tar med alle runder."))
        #expect(s.contains("Longest drive gir 1 poeng og nærmest pinnen 2."))
        #expect(s.contains("Ved likt får alle på delt førsteplass fullt."))
        #expect(s.contains("Alle spiller med 95 % av handicapet."))
        #expect(s.contains("Simulatoren deler ut slagene."))
        #expect(s.contains("Laveste poeng på et hull er 1."))
        #expect(s.contains("Stableford (netto) er standardformen og den eneste tillatte formen."))
        #expect(s.contains("Høyst 1 spiller per bås."))
        #expect(s.contains("I match spiller alle på fullt handicap."))
    }

    @Test func norskeTall() {
        #expect(RuleFormat.number(0.5) == "0,5")
        #expect(RuleFormat.number(1) == "1")
        #expect(RuleFormat.number(0.25) == "0,25")
        #expect(RuleFormat.number(1000) == "1000")
        #expect(RuleFormat.percent(0.75) == "75 %")
        #expect(RuleFormat.list(["a", "b", "c"]) == "a, b og c")
        #expect(RuleFormat.list(["a", "b", "c"], last: "så") == "a, så b, så c")
        #expect(RuleFormat.list(["a"]) == "a")
    }
}

struct SesongRedigeringTests {
    @Test func rundturGolfgutu() throws {
        let draft = RulesetDraft(.golfgutu)
        #expect(draft.rules == .golfgutu)
        #expect(!draft.hasChanges)
        #expect(draft.canSave)

        // Slå valgfrie felt av og på igjen: tilbake til det samme.
        var d = draft
        d.countsAllInTable = false
        d.countsAllInTable = true
        d.countsAllInStableford = true
        d.countsAllInStableford = false
        d.roundsTablePoints = false
        d.roundsTablePoints = true
        d.usesCommonAllowance = true
        d.usesCommonAllowance = false
        #expect(d.rules == .golfgutu)

        // Og gjennom JSON.
        let decoded = try JSONDecoder().decode(Ruleset.self, from: RulesetDraft.encoded(d.rules))
        #expect(decoded == .golfgutu)
    }

    @Test func valgfrieFeltHuskerVerdien() {
        var d = RulesetDraft(.golfgutu)
        d.countsAllInTable = false
        #expect(d.rules.table.counting.best == Ruleset.golfgutu.evenings)
        d.tableBest = 5
        d.countsAllInTable = true
        #expect(d.rules.table.counting.best == nil)
        d.countsAllInTable = false
        #expect(d.rules.table.counting.best == 5)

        d.countsAllInStableford = true
        #expect(d.rules.table.stablefordCounting.best == nil)
        d.countsAllInStableford = false
        #expect(d.rules.table.stablefordCounting.best == Ruleset.golfgutu.table.stablefordCounting.best)

        d.roundingStep = 1
        d.roundsTablePoints = false
        #expect(d.rules.table.roundingStep == nil)
        d.roundsTablePoints = true
        #expect(d.rules.table.roundingStep == 1)

        // Felles andel starter på standardformens andel.
        d.usesCommonAllowance = true
        #expect(d.rules.handicap.allowanceOverride == Ruleset.golfgutu.allowance(for: CompetitionForm.form(id: "stableford")))
        d.commonAllowancePercent = 100
        #expect(d.rules.handicap.allowanceOverride == 1)
    }

    @Test func endringerSkrivesTilGyldigRegelsett() throws {
        var d = RulesetDraft(.golfgutu)
        d.rules.evenings = 5
        d.rules.table.matchPoints = .init(win: 3, draw: 1, loss: 0)
        d.rules.table.trianglePoints = [3, 1, 0]
        d.rules.table.counting.unit = .evening
        d.countsAllInTable = false
        d.tableBest = 3
        d.removeTiebreaks(at: [0])
        d.addTiebreak(.holeDifference)
        #expect(d.rules.table.tiebreaks == [.stableford, .holeDifference])
        d.rules.sidePrizes.longestDrive.enabled = false
        d.removeSeedingGroups(at: [2])
        d.addSeedingGroup()
        #expect(d.rules.handicap.seedingGroups.last == SeedingGroup(number: 3, handicap: 5, name: "Gruppe 3"))
        let foursome = CompetitionForm.form(id: "foursome")
        d.setFormAllowance(foursome, percent: 50)
        #expect(d.formAllowance(foursome) == 0.5)
        d.setTeamMethod(foursome, .weighted)
        #expect(d.teamWeights(foursome).isEmpty)
        #expect(!d.canSave) // Vektet uten vekter.
        d.addTeamWeight(foursome)
        d.addTeamWeight(foursome)
        d.setTeamWeight(foursome, index: 0, percent: 60)
        d.setTeamWeight(foursome, index: 1, percent: 40)
        #expect(d.teamWeights(foursome) == [0.6, 0.4])
        d.removeTeamWeights(foursome, at: [1])
        #expect(d.teamWeights(foursome) == [0.6])
        let scramble4 = CompetitionForm.form(id: "scramble-4")
        d.setTeamMethod(scramble4, .lowest)
        d.setTeamMethod(scramble4, .weighted)
        #expect(d.teamWeights(scramble4) == Ruleset.golfgutu.handicap.teamHandicapRule(for: "scramble-4").weights)
        d.rules.formats.maxPerBay = 3

        #expect(d.canSave)
        #expect(d.hasChanges)
        let decoded = try JSONDecoder().decode(Ruleset.self, from: RulesetDraft.encoded(d.rules))
        #expect(decoded == d.rules)
        #expect(decoded.validate().isEmpty)
    }

    @Test func tillatteFormerIKatalogensRekkefolge() {
        var d = RulesetDraft(.golfgutu)
        let match = CompetitionForm.form(id: "match")
        d.setAllowed(match, false)
        #expect(!d.isAllowed(match))
        #expect(d.rules.formats.allowedFormIDs.count == CompetitionForm.all.count - 1)
        d.setAllowed(match, true)
        #expect(d.rules.formats.allowedFormIDs == Ruleset.golfgutu.formats.allowedFormIDs)
    }

    @Test func flyttSkilletegn() {
        var d = RulesetDraft(.golfgutu)
        d.moveTiebreaks(from: [1], to: 0)
        #expect(d.rules.table.tiebreaks == [.stableford, .holeDifference])
        #expect(d.unusedTiebreaks.isEmpty)
        d.removeTiebreaks(at: [0])
        #expect(d.unusedTiebreaks == [.stableford])
    }

    @Test func tilbakestillTilGolfgutu() {
        var start = Ruleset.golfgutu
        start.evenings = 3
        var d = RulesetDraft(start)
        d.resetToGolfgutu()
        #expect(d.rules == .golfgutu)
        #expect(d.hasChanges) // Utgangspunktet var et annet regelsett.
        d.markSaved(d.rules)
        #expect(!d.hasChanges)
    }
}

struct SesongValideringTests {
    @Test func feilSperrerLagringOgHavnerIRiktigDel() {
        var d = RulesetDraft(.golfgutu)
        d.rules.evenings = 0
        d.rules.table.matchPoints.win = 0.25
        d.rules.sidePrizes.closestToPin.points = -1
        d.rules.formats.allowedFormIDs = ["match"]
        #expect(!d.canSave)
        #expect(d.issues(in: .season).map(\.field) == ["evenings"])
        #expect(d.issues(in: .table).map(\.field) == ["table.matchPoints"])
        #expect(d.issues(in: .sidePrizes).map(\.field) == ["sidePrizes.closestToPin.points"])
        #expect(d.issues(in: .formats).map(\.field) == ["formats.defaultFormID"])
        #expect(d.issues(in: .handicap).isEmpty)
        // Hver melding havner i nøyaktig én del.
        let total = RulesetSection.allCases.map { d.issues(in: $0).count }.reduce(0, +)
        #expect(total == d.issues.count)
    }

    @Test func beste_N_overAntallKvelder() {
        var d = RulesetDraft(.golfgutu)
        d.rules.table.counting.unit = .evening
        d.countsAllInTable = false
        d.tableBest = 8
        #expect(d.issues(in: .table).map(\.field) == ["table.counting.best"])
        d.tableBest = 7
        #expect(d.canSave)
    }

    @Test(arguments: [
        ("evenings", RulesetSection.season),
        ("scoring.minimumPoints", .scoring),
        ("table.roundingStep", .table),
        ("sidePrizes.longestDrive.points", .sidePrizes),
        ("handicap.teamHandicap.scramble-4", .handicap),
        ("formats.maxPerBay", .formats),
    ])
    func feltTilDel(_ field: String, _ section: RulesetSection) {
        #expect(RulesetSection.section(for: field) == section)
    }
}

struct SesongLagringTests {
    @Test func kodingGirVersjon2() throws {
        let data = try JSONEncoder().encode(SeasonRulesPatch(rules: .golfgutu))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rules = try #require(json["rules"] as? [String: Any])
        #expect(rules["version"] as? Int == 2)
        #expect(rules["evenings"] as? Int == 7)
        // `best: null` står i JSON-en, så det er tydelig at alle teller.
        let counting = try #require((rules["table"] as? [String: Any])?["counting"] as? [String: Any])
        #expect(counting.keys.contains("best"))
    }

    @Test func nySesongSenderKlubbNavnStatusOgRegler() throws {
        let club = UUID()
        let data = try JSONEncoder().encode(NewSeasonPayload(clubID: club, name: "Vinter", status: .planned, rules: .golfgutu))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["club_id"] as? String == club.uuidString)
        #expect(json["status"] as? String == "planned")
        #expect((json["rules"] as? [String: Any])?["version"] as? Int == 2)
    }

    @Test func versjon1LesesOgSkrivesSomVersjon2() throws {
        let v1 = try JSONDecoder().decode(Ruleset.self, from: Data(#"{"version": 1}"#.utf8))
        let draft = RulesetDraft(v1)
        let json = try #require(JSONSerialization.jsonObject(with: RulesetDraft.encoded(draft.rules)) as? [String: Any])
        #expect(json["version"] as? Int == 2)
    }
}

struct SesongLivslopTests {
    private let club = UUID()

    private func season(_ name: String, _ status: SeasonStatus, evenings: Int = 7) -> SeasonRow {
        var rules = Ruleset.golfgutu
        rules.evenings = evenings
        return SeasonRow(id: UUID(), clubID: club, name: name, status: status, rules: rules)
    }

    @Test func handlingerPerStatus() {
        #expect(SeasonLifecycle.actions(for: .planned) == [.activate, .delete])
        #expect(SeasonLifecycle.actions(for: .active) == [.finish])
        #expect(SeasonLifecycle.actions(for: .finished) == [.activate])
    }

    @Test func aktiveringMaAvslutteDenAktive() {
        let aktiv = season("2026", .active)
        let ny = season("2027", .planned)
        #expect(SeasonLifecycle.activeConflict(activating: ny, in: [ny, aktiv])?.id == aktiv.id)
        #expect(SeasonLifecycle.activeConflict(activating: aktiv, in: [ny, aktiv]) == nil)
        #expect(SeasonLifecycle.activeConflict(activating: ny, in: [ny]) == nil)
    }

    @Test func malForNySesong() {
        let forrige = season("2026", .finished, evenings: 5)
        let eldre = season("2025", .finished, evenings: 9)
        let liste = [forrige, eldre]
        #expect(SeasonLifecycle.defaultTemplate(seasons: liste) == .copy(forrige.id))
        #expect(SeasonLifecycle.defaultTemplate(seasons: []) == .golfgutu)
        #expect(SeasonLifecycle.rules(for: .copy(eldre.id), seasons: liste).evenings == 9)
        #expect(SeasonLifecycle.rules(for: .golfgutu, seasons: liste) == .golfgutu)
        #expect(SeasonLifecycle.rules(for: .copy(UUID()), seasons: liste) == .golfgutu)
    }

    @Test func grupperingAktivPlanlagtFerdig() {
        let liste = [season("c", .finished), season("b", .planned), season("a", .active), season("d", .planned)]
        let grupper = SeasonLifecycle.grouped(liste)
        #expect(grupper.map(\.status) == [.active, .planned, .finished])
        #expect(grupper[1].seasons.map(\.name) == ["b", "d"])
    }

    @Test func landerPaDenAktiveSesongen() {
        let aktiv = season("2026", .active)
        let liste = [season("2027", .planned), aktiv, season("2025", .finished)]
        #expect(SeasonLifecycle.landing(liste) == .season(aktiv.id))
        #expect(SeasonLifecycle.listPrompt(liste) == nil)
    }

    @Test func utenAktivSesongLanderDetPaLista() {
        #expect(SeasonLifecycle.landing([]) == .list)
        #expect(SeasonLifecycle.landing([season("2027", .planned), season("2025", .finished)]) == .list)
        #expect(SeasonLifecycle.listPrompt([]) == nil)
        #expect(SeasonLifecycle.listPrompt([season("2027", .planned)])?.contains("Åpne en planlagt sesong") == true)
        #expect(SeasonLifecycle.listPrompt([season("2025", .finished)])?.contains("Lag en ny sesong") == true)
    }

    @Test func flereAktiveGirDenForste() {
        let nyest = season("2027", .active)
        let eldre = season("2026", .active)
        #expect(SeasonLifecycle.landing([season("2028", .planned), nyest, eldre]) == .season(nyest.id))
    }
}

/// Tallfeltene i regelsettet: norsk komma, og verdien oppdateres mens du skriver.
struct RuleNumberTextTests {
    @Test(arguments: [
        ("1,5", 1.5), ("1.5", 1.5), (" 95 ", 95.0), ("0,95", 0.95), ("1,", 1.0), (",5", 0.5),
        ("-2", -2.0), ("\u{2212}2", -2.0), ("87,5", 87.5),
    ])
    func tolker(_ input: String, _ forventet: Double) {
        #expect(RuleNumberText.parse(input) == forventet)
    }

    @Test(arguments: ["", ",", "abc", "1,2,3", "1e3", "inf", "0x1A", "-"])
    func avviser(_ input: String) {
        #expect(RuleNumberText.parse(input) == nil)
    }

    @Test func viserMedKomma() {
        #expect(RuleNumberText.format(0.5) == "0,5")
        #expect(RuleNumberText.format(95) == "95")
        #expect(RuleNumberText.format(1234.5) == "1234,5")
        #expect(RuleNumberText.format(0.95 * 100) == "95")
    }

    @Test func endringUtenfraByttesInn() {
        // Halvskrevet «1,» betyr 1: kommaet skal stå.
        #expect(RuleNumberText.text(replacing: "1,", for: 1) == nil)
        #expect(RuleNumberText.text(replacing: "95", for: 0.95 * 100) == nil)
        // «Tilbakestill til Golfgutu» setter en ny verdi.
        #expect(RuleNumberText.text(replacing: "3", for: 1) == "1")
        #expect(RuleNumberText.text(replacing: "", for: 0.5) == "0,5")
    }
}
