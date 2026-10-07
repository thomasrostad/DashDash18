import GolfgutuCore
import SwiftUI

/// Former og oppsett: standardform, tillatte former, maks per bås og slag i match.
struct RulesetFormatSection: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        Section {
            Picker(selection: $draft.rules.formats.defaultFormID) {
                ForEach(draft.rules.allowedForms) { Text($0.name).tag($0.id) }
                if !draft.rules.allowedForms.contains(where: { $0.id == draft.rules.formats.defaultFormID }) {
                    Text("\(CompetitionForm.form(id: draft.rules.formats.defaultFormID).name) (ikke tillatt)")
                        .tag(draft.rules.formats.defaultFormID)
                }
            } label: {
                RuleFieldLabel(title: "Standardform", changeNote: draft.changeNote(.defaultForm))
            }
            NavigationLink {
                AllowedFormsView(draft: $draft)
            } label: {
                LabeledContent {
                    Text("\(draft.rules.allowedForms.count) av \(CompetitionForm.all.count)")
                } label: {
                    RuleFieldLabel(title: "Tillatte former", changeNote: draft.changeNote(.allowedForms))
                }
            }
            RuleStepper("Maks per bås", value: $draft.rules.formats.maxPerBay, changeNote: draft.changeNote(.maxPerBay))
            Picker(selection: $draft.rules.formats.matchStrokes) {
                ForEach(Ruleset.MatchStrokes.allCases, id: \.self) { Text(RuleNames.title($0)).tag($0) }
            } label: {
                RuleFieldLabel(title: "Slag i match", changeNote: draft.changeNote(.matchStrokes))
            }
        } header: {
            DDHeader(RulesetSection.formats.title)
        } footer: {
            RuleSectionFooter(text: "Laveste fra scratch: den beste i matchen spiller uten slag, de andre får forskjellen.",
                              issues: draft.issues(in: .formats))
        }
    }
}

/// Formene arrangøren kan velge når en runde settes opp.
private struct AllowedFormsView: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        DDForm {
            Section {
                ForEach(CompetitionForm.all) { form in
                    Toggle(isOn: Binding(get: { draft.isAllowed(form) }, set: { draft.setAllowed(form, $0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(form.name)
                            Text(form.help)
                                .font(.dd(.sans, size: 13, relativeTo: .footnote))
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                    }
                }
            } footer: {
                RuleSectionFooter(text: nil, issues: draft.issues(in: .formats))
            }
        }
        .navigationTitle("Tillatte former")
        .ddNavigationChrome()
    }
}
