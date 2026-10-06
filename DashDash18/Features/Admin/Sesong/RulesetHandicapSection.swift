import GolfgutuCore
import SwiftUI

/// Handicapmodellen: andel, seeding, ekstern handicap og lagshandicap.
struct RulesetHandicapSection: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        Section {
            Toggle("Samme andel for alle former", isOn: $draft.usesCommonAllowance)
            if draft.usesCommonAllowance {
                RuleNumberField("Andel", value: $draft.commonAllowancePercent, suffix: "%")
            } else {
                NavigationLink("Andel per form") { FormAllowancesView(draft: $draft) }
            }
            Toggle("Ekstern handicap", isOn: $draft.rules.handicap.externalHandicap)
            NavigationLink("Lagshandicap") { TeamHandicapView(draft: $draft) }
        } header: {
            DDHeader(RulesetSection.handicap.title)
        } footer: {
            RuleSectionFooter(text: "Andelen er hvor stor del av banehandicapet en ny runde gir. Ekstern handicap: simulatoren deler ut slagene.",
                              issues: draft.issues(in: .handicap).filter { !$0.field.hasPrefix("handicap.seedingGroups") })
        }

        Section {
            ForEach(draft.rules.handicap.seedingGroups.indices, id: \.self) { i in
                HStack {
                    Text("\(draft.rules.handicap.seedingGroups[i].number).")
                        .foregroundStyle(Color.ddInkSecondary)
                        .monospacedDigit()
                    TextField("Navn", text: $draft.rules.handicap.seedingGroups[i].name)
                    RuleNumberField("Handicap", value: $draft.rules.handicap.seedingGroups[i].handicap)
                        .labelsHidden()
                }
            }
            .onDelete { draft.removeSeedingGroups(at: $0) }
            Button("Legg til gruppe", systemImage: "plus") { draft.addSeedingGroup() }
        } header: {
            DDHeader("Seeding")
        } footer: {
            RuleSectionFooter(text: "Seedede spillere spiller på gruppens faste handicap. Sveip for å fjerne en gruppe. Ingen grupper: ingen seeding.",
                              issues: draft.issues(in: .handicap).filter { $0.field.hasPrefix("handicap.seedingGroups") })
        }
    }
}

/// Andelen en ny runde får, per form.
private struct FormAllowancesView: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        DDForm {
            Section {
                ForEach(CompetitionForm.all) { form in
                    RulePercentField(title: form.name,
                                     get: { draft.formAllowance(form) },
                                     set: { draft.setFormAllowance(form, percent: $0 * 100) })
                }
            } footer: {
                RuleSectionFooter(text: "Arrangøren kan endre andelen når runden startes.",
                                  issues: draft.issues(in: .handicap).filter { $0.field.hasPrefix("handicap.formAllowances") })
            }
        }
        .navigationTitle("Andel per form")
        .ddNavigationChrome()
    }
}

/// Hvordan et lag får ett handicap, per lagform.
private struct TeamHandicapView: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        DDForm {
            ForEach(RulesetDraft.teamForms) { form in
                Section {
                    Picker("Metode", selection: Binding(get: { draft.teamMethod(form) },
                                                        set: { draft.setTeamMethod(form, $0) })) {
                        ForEach(Ruleset.TeamHandicapRule.Method.allCases, id: \.self) {
                            Text(RuleNames.title($0)).tag($0)
                        }
                    }
                    if draft.teamMethod(form) == .weighted {
                        let weights = draft.teamWeights(form)
                        ForEach(weights.indices, id: \.self) { i in
                            RulePercentField(title: "Spiller \(i + 1)",
                                             get: { draft.teamWeights(form)[safe: i] ?? 0 },
                                             set: { draft.setTeamWeight(form, index: i, percent: $0 * 100) })
                        }
                        .onDelete { draft.removeTeamWeights(form, at: $0) }
                        Button("Legg til vekt", systemImage: "plus") { draft.addTeamWeight(form) }
                    }
                } header: {
                    DDHeader(form.name)
                } footer: {
                    RuleSectionFooter(text: nil, issues: draft.issues(in: .handicap).filter { $0.field == "handicap.teamHandicap.\(form.id)" })
                }
            }
        }
        .navigationTitle("Lagshandicap")
        .ddNavigationChrome()
        .safeAreaInset(edge: .bottom) {
            Text("Snitt: gjennomsnittet av spillernes grunnlag. Vektet: lavest først, med vekt per spiller. Laveste: laveste grunnlag ganger andelen.")
                .font(.dd(.sans, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color.ddInkSecondary)
                .padding()
                .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.card))
                .padding(.horizontal, DDSpacing.s)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
