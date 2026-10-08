import GolfgutuCore
import SwiftUI

/// De vanligste valgene i regelsettet, med «endret fra standard» der valget ikke er som i oppsettet:
/// hva tabellen teller, poeng (bare med matcher), handicapandel og sidepremier. Høyst én hjelpelinje
/// per del.
struct RulesetCommonSections: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        countingSection
        if draft.countsMatches {
            pointsSection
        }
        allowanceSection
        sidePrizeSection
    }

    private var countingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                RuleFieldLabel(title: "Tabellen teller", changeNote: draft.changeNote(.pointsSource))
                Picker("Tabellen teller", selection: $draft.pointsSource) {
                    ForEach(Ruleset.TablePointsSource.allCases, id: \.self) { Text(RuleNames.title($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            RuleStepper("Kvelder", value: $draft.rules.evenings, changeNote: draft.changeNote(.evenings))
            Picker(selection: $draft.rules.table.counting.unit) {
                ForEach(draft.tableUnits, id: \.self) { Text(RuleNames.title($0)).tag($0) }
            } label: {
                RuleFieldLabel(title: "Telles per", changeNote: draft.changeNote(.counting))
            }
            Toggle("Alle teller", isOn: $draft.countsAllInTable)
            if !draft.countsAllInTable {
                RuleStepper("De beste", value: $draft.tableBest)
            }
        } header: {
            DDHeader("Hva teller")
        } footer: {
            RuleSectionFooter(text: draft.countsMatches
                                  ? "Matcher gir poeng i tabellen. Sidepremiene teller alltid."
                                  : "Stablefordpoengene i hver runde gir poeng i tabellen.",
                              issues: draft.issues.filter {
                                  $0.field == "evenings" || $0.field.hasPrefix("table.counting") || $0.field == "table.pointsSource"
                              })
        }
    }

    private var pointsSection: some View {
        Section {
            RuleNumberField("Seier", value: $draft.rules.table.matchPoints.win, changeNote: draft.changeNote(.win))
            RuleNumberField("Uavgjort", value: $draft.rules.table.matchPoints.draw, changeNote: draft.changeNote(.draw))
            RuleNumberField("Tap", value: $draft.rules.table.matchPoints.loss, changeNote: draft.changeNote(.loss))
        } header: {
            DDHeader("Poeng for en match")
        } footer: {
            RuleSectionFooter(text: nil, issues: draft.issues.filter { $0.field.hasPrefix("table.matchPoints") })
        }
    }

    private var allowanceSection: some View {
        Section {
            Toggle(isOn: $draft.usesCommonAllowance) {
                RuleFieldLabel(title: "Samme andel for alle former", changeNote: draft.changeNote(.allowance))
            }
            if draft.usesCommonAllowance {
                RuleNumberField("Handicapandel", value: $draft.commonAllowancePercent, suffix: "%")
            } else {
                NavigationLink("Andel per form") { FormAllowancesView(draft: $draft) }
            }
        } header: {
            DDHeader("Handicap")
        } footer: {
            RuleSectionFooter(text: "Hvor stor del av banehandicapet spilleren får. 100 % er fullt.",
                              issues: draft.issues.filter {
                                  $0.field.hasPrefix("handicap.allowanceOverride") || $0.field.hasPrefix("handicap.formAllowances")
                              })
        }
    }

    private var sidePrizeSection: some View {
        Section {
            Toggle(isOn: $draft.rules.sidePrizes.longestDrive.enabled) {
                RuleFieldLabel(title: "Longest drive", changeNote: draft.changeNote(.longestDrive))
            }
            if draft.rules.sidePrizes.longestDrive.enabled {
                RuleNumberField("Poeng for longest drive", value: $draft.rules.sidePrizes.longestDrive.points)
            }
            Toggle(isOn: $draft.rules.sidePrizes.closestToPin.enabled) {
                RuleFieldLabel(title: "Nærmest pinnen", changeNote: draft.changeNote(.closestToPin))
            }
            if draft.rules.sidePrizes.closestToPin.enabled {
                RuleNumberField("Poeng for nærmest pinnen", value: $draft.rules.sidePrizes.closestToPin.points)
            }
            Toggle(isOn: $draft.rules.sidePrizes.splitTies) {
                RuleFieldLabel(title: "Del poenget ved likt", changeNote: draft.changeNote(.splitTies))
            }
        } header: {
            DDHeader(RulesetSection.sidePrizes.title)
        } footer: {
            RuleSectionFooter(text: "Poengene kommer i tillegg til tabellpoengene.", issues: draft.issues(in: .sidePrizes))
        }
    }
}
