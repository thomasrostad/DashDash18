import GolfgutuCore
import SwiftUI

/// Tabellreglene fra steg 6: minste antall kvelder for plass, sum eller snitt, navngitte poengtabeller og
/// likt på første plass (skilletegn eller playoff). Alle er av eller som i dag til arrangøren endrer dem.
struct RulesetTableRulesSection: View {
    @Binding var draft: RulesetDraft

    private var day: DayTerm { draft.rules.day }

    var body: some View {
        Section {
            Toggle(isOn: $draft.hasMinEvenings) {
                RuleFieldLabel(title: "Minste antall \(day.many)", changeNote: draft.changeNote(.minEvenings))
            }
            if draft.hasMinEvenings {
                RuleStepper("Minst", value: $draft.minEvenings, in: 1...max(1, draft.rules.evenings))
            }
            Picker(selection: $draft.rules.table.aggregation) {
                Text("Sum").tag(Ruleset.Aggregation.sum)
                Text("Snitt per \(day.one)").tag(Ruleset.Aggregation.average)
            } label: {
                RuleFieldLabel(title: "Tabellen regnes som", changeNote: draft.changeNote(.aggregation))
            }
            Picker(selection: $draft.rules.table.tieRule) {
                Text("Skilletegn").tag(Ruleset.TieRule.tiebreaks)
                Text("Playoff").tag(Ruleset.TieRule.playoff)
            } label: {
                RuleFieldLabel(title: "Likt på første plass", changeNote: draft.changeNote(.tieRule))
            }
            NavigationLink {
                PointsTablesView(draft: $draft)
            } label: {
                LabeledContent {
                    Text(draft.pointsTables.isEmpty ? "Ingen" : "\(draft.pointsTables.count)")
                } label: {
                    RuleFieldLabel(title: "Poengtabeller", changeNote: draft.changeNote(.pointsTables))
                }
            }
        } header: {
            DDHeader("Plass i tabellen")
        } footer: {
            RuleSectionFooter(text: footer, issues: draft.issues(in: .table).filter {
                $0.field.hasPrefix("table.minEvenings") || $0.field.hasPrefix("table.pointsTables")
            })
        }
    }

    private var footer: String {
        var parts: [String] = []
        if draft.hasMinEvenings {
            parts.append("De med færre \(day.many) står under tabellen uten plass.")
        }
        if draft.rules.table.aggregation == .average {
            parts.append("Snitt: poengene delt på antall \(day.many) som teller.")
        }
        parts.append(draft.rules.table.tieRule == .playoff
                     ? "Likt på første plass avgjøres med playoff. Annet likt er delt plass."
                     : "Likt avgjøres med skilletegnene under.")
        return parts.joined(separator: " ")
    }
}

/// «Poengtabeller»: navn og hvor mange ganger poengene teller (f.eks. Finale × 2).
/// Kvelden velger tabell når runden settes opp.
private struct PointsTablesView: View {
    @Binding var draft: RulesetDraft

    var body: some View {
        DDForm {
            Section {
                if draft.pointsTables.isEmpty {
                    Text("Ingen poengtabeller")
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(draft.pointsTables, id: \.name) { table in
                    NavigationLink {
                        PointsTableEditView(draft: $draft, name: table.name)
                    } label: {
                        LabeledContent(table.name, value: "× \(RuleNumberText.format(table.multiplier))")
                    }
                }
                .onDelete { offsets in
                    let names = offsets.map { draft.pointsTables[$0].name }
                    for name in names { draft.removePointsTable(name) }
                }
                Button("Ny poengtabell", systemImage: "plus") { draft.addPointsTable() }
            } footer: {
                RuleSectionFooter(text: "En kveld som peker på en tabell, teller så mange ganger.",
                                  issues: draft.issues(in: .table).filter { $0.field.hasPrefix("table.pointsTables") })
            }
        }
        .navigationTitle("Poengtabeller")
        .ddNavigationChrome()
    }
}

/// Navn og gange for én poengtabell. Navnet lagres når du går tilbake; er det tomt eller i bruk, står det gamle.
private struct PointsTableEditView: View {
    @Binding var draft: RulesetDraft
    @State private var name: String
    @State private var current: String
    @State private var nameIsTaken = false

    init(draft: Binding<RulesetDraft>, name: String) {
        _draft = draft
        _name = State(initialValue: name)
        _current = State(initialValue: name)
    }

    var body: some View {
        DDForm {
            Section {
                TextField("Navn", text: $name)
                    .onSubmit(commitName)
                RuleNumberField("Teller", value: Binding(
                    get: { draft.rules.table.pointsTables[current]?.multiplier ?? 1 },
                    set: { draft.setPointsTableMultiplier(current, $0) }
                ), suffix: "ganger")
            } footer: {
                if nameIsTaken {
                    Text("Navnet er tomt eller i bruk.").foregroundStyle(Color.ddError)
                }
            }
        }
        .navigationTitle(current)
        .ddNavigationChrome()
        .onDisappear(perform: commitName)
    }

    private func commitName() {
        if draft.renamePointsTable(current, to: name) {
            current = name.trimmingCharacters(in: .whitespacesAndNewlines)
            nameIsTaken = false
        } else {
            nameIsTaken = true
        }
    }
}
