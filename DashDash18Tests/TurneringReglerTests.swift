import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Fase 18: regelvisningen sammenligner med oppsettene, ikke med Golfgutu.
struct TurneringReglerTests {
    @Test func merketSierOppsettet() {
        #expect(RulesetSummary.badge(for: RulesetTemplate.stablefordSeries.rules) == "Stableford-serie")
        #expect(RulesetSummary.badge(for: RulesetTemplate.matchSeries.rules) == "Matchspill-serie")
        #expect(RulesetSummary.isTemplate(RulesetTemplate.stablefordSeries.rules))
        #expect(RulesetSummary.badge(for: RulesetTemplate.cup.rules, kind: .cup) == "Cup")
        #expect(RulesetSummary.badge(for: RulesetTemplate.fun.rules, kind: .fun) == "Morroturnering")
    }

    @Test func endringerTellesFraNaermesteOppsett() {
        var r = RulesetTemplate.stablefordSeries.rules
        r.evenings = 10
        #expect(RulesetSummary.badge(for: r) == "1 valg endret fra Stableford-serie")
        r.sidePrizes.longestDrive.enabled = true
        #expect(RulesetSummary.badge(for: r) == "2 valg endret fra Stableford-serie")
        #expect(!RulesetSummary.isTemplate(r))
    }

    /// Ligger to oppsett like nær, vinner det som teller det samme (matcher eller stableford).
    @Test func likAvstandGirOppsettetSomTellerDetSamme() {
        #expect(RulesetSummary.candidates(for: .season, rules: .golfgutu) == [.matchSeries, .stablefordSeries])
        #expect(RulesetSummary.candidates(for: .league, rules: RulesetTemplate.stablefordSeries.rules)
                == [.stablefordSeries, .matchSeries])
        #expect(RulesetSummary.candidates(for: .cup, rules: .golfgutu) == [.cup])
        #expect(RulesetSummary.candidates(for: .fun, rules: .golfgutu) == [.fun])
    }

    @Test func pointsSourceErEtValg() {
        var r = Ruleset.golfgutu
        r.table.pointsSource = .stableford
        #expect(RulesetField.changed(r, from: .golfgutu) == [.pointsSource])
        #expect(RulesetField.pointsSource.changeNote(r, from: .golfgutu) == "Endret · standard matcher")
        #expect(RulesetField.pointsSource.title == "Tabellen teller")
    }

    @Test func utkastetSammenlignerMedOppsettetDetStartetFra() {
        var d = RulesetDraft(RulesetTemplate.stablefordSeries.rules)
        #expect(d.base == .stablefordSeries)
        #expect(d.isTemplate)
        #expect(!d.countsMatches)
        d.rules.evenings = 9
        #expect(d.changeNote(.evenings) == "Endret · standard 7")
        // Oppsettet står stille selv om reglene nå ligger nærmere et annet.
        d.pointsSource = .matches
        #expect(d.base == .stablefordSeries)
        d.resetToTemplate()
        #expect(d.rules == RulesetTemplate.stablefordSeries.rules)
        #expect(d.isTemplate)
    }

    @Test func stablefordByttetMatchTilKvelder() {
        var d = RulesetDraft(.golfgutu)
        #expect(d.tableUnits == [.evening, .match, .round])
        #expect(d.unusedTiebreaks.isEmpty)
        d.pointsSource = .stableford
        #expect(d.rules.table.counting.unit == .evening)
        #expect(d.tableUnits == [.evening, .round])
        #expect(d.canSave)
        d.removeTiebreaks(at: [0])
        // Uten matcher finnes ikke hulldifferanse som skille.
        #expect(d.unusedTiebreaks.isEmpty)
    }

    @Test func sammendragOgForklaringForStableford() {
        let r = RulesetTemplate.stablefordSeries.rules
        let lines = RulesetSummary.lines(for: r)
        #expect(lines.contains("Stablefordpoengene er tabellpoengene"))
        #expect(lines.contains("Beste 5 av 7 kvelder teller"))
        #expect(!lines.contains { $0.hasPrefix("Seier") })
        let sentences = RulesetExplanation.sentences(for: r)
        #expect(sentences.contains("Stablefordpoengene i hver runde er tabellpoengene."))
        #expect(!sentences.contains { $0.hasPrefix("Seier") || $0.hasPrefix("Trekanten") })
    }
}
