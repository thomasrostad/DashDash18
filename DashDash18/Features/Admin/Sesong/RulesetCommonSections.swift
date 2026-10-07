import GolfgutuCore
import SwiftUI

/// De vanligste valgene i regelsettet, med en forklaring under hvert felt og «endret fra standard»
/// der valget ikke er som i Golfgutu-oppsettet: hva som teller, poeng, handicapandel og sidepremier.
struct RulesetCommonSections: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        countingSection
        pointsSection
        allowanceSection
        sidePrizeSection
    }

    private var countingSection: some View {
        Section {
            RuleStepper("Kvelder i sesongen", value: $draft.rules.evenings,
                        help: "Hvor mange kvelder dere spiller.", changeNote: draft.changeNote(.evenings))
            Picker(selection: $draft.rules.table.counting.unit) {
                ForEach(Ruleset.Counting.Unit.allCases, id: \.self) { Text(RuleNames.title($0)).tag($0) }
            } label: {
                RuleFieldLabel(title: "Tabellen teller", changeNote: draft.changeNote(.counting))
            }
            Toggle(isOn: $draft.countsAllInTable) {
                RuleFieldLabel(title: "Alle teller",
                               help: "Slå av for at bare de beste skal telle, så én dårlig kveld ikke ødelegger.")
            }
            if !draft.countsAllInTable {
                RuleStepper("De beste", value: $draft.tableBest,
                            help: "Så mange \(RuleNames.nouns(draft.rules.table.counting.unit).plural) teller for hver spiller.")
            }
        } header: {
            DDHeader("Hva teller")
        } footer: {
            RuleSectionFooter(text: "Matcher: de beste matchene teller, sidepremiene teller alltid. Runder eller kvelder: alt spilleren vant der, teller sammen.",
                              issues: draft.issues.filter { $0.field == "evenings" || $0.field.hasPrefix("table.counting") })
        }
    }

    private var pointsSection: some View {
        Section {
            RuleNumberField("Seier", value: $draft.rules.table.matchPoints.win,
                            help: "Poeng for å vinne en match.", changeNote: draft.changeNote(.win))
            RuleNumberField("Uavgjort", value: $draft.rules.table.matchPoints.draw,
                            help: "Poeng til hver når matchen ender likt.", changeNote: draft.changeNote(.draw))
            RuleNumberField("Tap", value: $draft.rules.table.matchPoints.loss,
                            help: "Poeng for å tape. Vanligvis 0.", changeNote: draft.changeNote(.loss))
        } header: {
            DDHeader("Poeng i tabellen")
        } footer: {
            RuleSectionFooter(text: nil, issues: draft.issues.filter { $0.field.hasPrefix("table.matchPoints") })
        }
    }

    private var allowanceSection: some View {
        Section {
            Toggle(isOn: $draft.usesCommonAllowance) {
                RuleFieldLabel(title: "Samme andel for alle former",
                               help: "Av: hver form har sin egen andel, som i Golfgutu-oppsettet.",
                               changeNote: draft.changeNote(.allowance))
            }
            if draft.usesCommonAllowance {
                RuleNumberField("Handicapandel", value: $draft.commonAllowancePercent, suffix: "%",
                                help: "100 % er fullt handicap. Lavere andel gir dem med lavt handicap en fordel.")
            } else {
                NavigationLink("Andel per form") { FormAllowancesView(draft: $draft) }
            }
        } header: {
            DDHeader("Handicap")
        } footer: {
            RuleSectionFooter(text: "Andelen er hvor stor del av banehandicapet spilleren får i en ny runde.",
                              issues: draft.issues.filter {
                                  $0.field.hasPrefix("handicap.allowanceOverride") || $0.field.hasPrefix("handicap.formAllowances")
                              })
        }
    }

    private var sidePrizeSection: some View {
        Section {
            Toggle(isOn: $draft.rules.sidePrizes.longestDrive.enabled) {
                RuleFieldLabel(title: "Longest drive", help: "Lengste utslag på hullet som er valgt for kvelden.",
                               changeNote: draft.changeNote(.longestDrive))
            }
            if draft.rules.sidePrizes.longestDrive.enabled {
                RuleNumberField("Poeng for longest drive", value: $draft.rules.sidePrizes.longestDrive.points)
            }
            Toggle(isOn: $draft.rules.sidePrizes.closestToPin.enabled) {
                RuleFieldLabel(title: "Nærmest pinnen", help: "Nærmest hullet på et kort hull.",
                               changeNote: draft.changeNote(.closestToPin))
            }
            if draft.rules.sidePrizes.closestToPin.enabled {
                RuleNumberField("Poeng for nærmest pinnen", value: $draft.rules.sidePrizes.closestToPin.points)
            }
            Toggle(isOn: $draft.rules.sidePrizes.splitTies) {
                RuleFieldLabel(title: "Del poenget ved likt",
                               help: "På: to på likt får halvparten hver. Av: alle på delt førsteplass får fullt.",
                               changeNote: draft.changeNote(.splitTies))
            }
        } header: {
            DDHeader(RulesetSection.sidePrizes.title)
        } footer: {
            RuleSectionFooter(text: nil, issues: draft.issues(in: .sidePrizes))
        }
    }
}
