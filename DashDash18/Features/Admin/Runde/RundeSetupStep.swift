import GolfgutuCore
import SwiftUI

/// «Flere valg» på hurtigstarten: konkurranseform, lag og matcher, sidepremier, vekt og handicap.
struct RundeSetupStep: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft
    let bayCount: Int

    @State private var editingMatch: MatchEditItem?

    private var rules: Ruleset { model.rules }
    private var coreCourse: Course? { model.course(draft.courseID)?.coreCourse }

    var body: some View {
        let form = draft.form
        let holes = draft.coreRound(course: coreCourse).courseHoles()
        DDForm {
            formSection(form)
            if form.isTeamForm { teamSection(form) }
            matchSection(form)
            sidePrizeSection(holes)
            Section {
                Picker("Hvor mye runden teller", selection: $draft.weight) {
                    ForEach(Self.weights, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
            } footer: {
                DDFooter("Ganger opp poengene runden gir. 0 betyr at den ikke teller sammenlagt.")
            }
            handicapSection(form)
            let issues = model.issues(draft, forStart: true)
            if !issues.isEmpty {
                DDSection("Før runden kan starte") {
                    ForEach(issues.map { $0.message(draft.groupTerm) }, id: \.self) { text in
                        Label(text, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.ddRustText)
                    }
                }
            }
        }
        .sheet(item: $editingMatch) { item in
            NavigationStack {
                MatchEditor(model: model, draft: draft, match: item.match, isNew: item.index == nil) { result in
                    apply(result, at: item.index)
                    editingMatch = nil
                }
            }
        }
    }

    // MARK: Form

    @ViewBuilder
    private func formSection(_ form: CompetitionForm) -> some View {
        let count = draft.participants.count
        let suggestions = rules.suggestions(players: count)
        Section {
            Picker("Konkurranseform", selection: Binding(
                get: { draft.formID },
                set: { draft.setForm($0, rules: rules, roster: model.members) }
            )) {
                ForEach(formChoices) { f in
                    Text(f.name + supportNote(f)).tag(f.id)
                }
            }
            Text(form.help)
                .font(.dd(.sans, size: 13, relativeTo: .footnote))
                .foregroundStyle(Color.ddInkSecondary)
            let setup = rules.setup(formID: form.id, players: count)
            if let text = setup.text {
                Label("\(count) med: \(text)" + (setup.isUneven ? " (ulike lag)" : ""), systemImage: "checkmark.circle")
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
            } else if let reason = setup.reason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddRustText)
            }
        } header: {
            DDHeader("Konkurranseform")
        } footer: {
            if !suggestions.isEmpty {
                Text("Går opp med \(count): " + suggestions.map { "\($0.name) (\($0.text))" }.joined(separator: ", ") + ".")
            }
        }
    }

    /// De tillatte formene i regelsettet, og formen kladden har om den ikke er tillatt lenger.
    private var formChoices: [CompetitionForm] {
        var forms = rules.allowedForms
        if !forms.contains(where: { $0.id == draft.formID }) { forms.insert(draft.form, at: 0) }
        return forms
    }

    private func supportNote(_ form: CompetitionForm) -> String {
        switch form.support {
        case .full: ""
        case .partial: " · ikke ferdig"
        case .missing: " · ikke støttet ennå"
        }
    }

    // MARK: Lag

    @ViewBuilder
    private func teamSection(_ form: CompetitionForm) -> some View {
        // Nok lagnumre til at alle kan stå alene der formen tåler skjeve lag (`lagOppsettFelt`).
        let count = draft.participants.count
        let numbers = max(2, form.allowsUnevenTeams ? count : (count + form.teamSize - 1) / form.teamSize)
        Section {
            ForEach(draft.participants, id: \.self) { id in
                Picker(model.memberName(id), selection: Binding(
                    get: { draft.teams[id] },
                    set: { draft.teams[id] = $0; draft.redrawMatches(roster: model.members) }
                )) {
                    Text("Uten lag").tag(Int?.none)
                    ForEach(1...numbers, id: \.self) { n in
                        Text("Lag \(n)").tag(Optional(n))
                    }
                }
            }
            Button("Foreslå lag", systemImage: "wand.and.stars") {
                draft.teams = TeamPlanner.suggested(participants: draft.participants, form: form,
                                                    maxPerBay: rules.formats.maxPerBay)
                draft.redrawMatches(roster: model.members)
            }
        } header: {
            DDHeader("Lag · \(form.teamSize) per lag")
        } footer: {
            if let problem = TeamPlanner.problem(teams: draft.teams, participants: draft.participants, form: form,
                                                 maxPerBay: rules.formats.maxPerBay) {
                Text(problem).foregroundStyle(Color.ddRustText)
            }
        }
    }

    // MARK: Matcher

    @ViewBuilder
    private func matchSection(_ form: CompetitionForm) -> some View {
        Section {
            if draft.matches.isEmpty {
                Text("Ingen matcher. Runden gir da ingen duellpoeng.")
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ForEach(Array(draft.matches.enumerated()), id: \.offset) { index, match in
                Button {
                    editingMatch = MatchEditItem(index: index, match: match)
                } label: {
                    LabeledContent("Match \(index + 1)", value: matchText(match))
                        .foregroundStyle(.primary)
                }
            }
            .onDelete { draft.matches.remove(atOffsets: $0) }
            Button("Trekk matchene på nytt", systemImage: "dice") {
                draft.redrawMatches(roster: model.members)
            }
            Button("Ny match", systemImage: "plus") {
                editingMatch = MatchEditItem(index: nil, match: form.isTeamForm ? .teams(1, 2) : MatchDraft())
            }
            Button("Sett matchene sammen i \(draft.groupTerm.definitePlural)", systemImage: "square.grid.2x2") {
                draft.reshuffleBays(count: bayCount)
            }
        } header: {
            DDHeader("Matcher")
        } footer: {
            DDFooter(form.isTeamForm
                 ? "Lag mot lag i rekkefølge: 1 mot 2, 3 mot 4. Trykk en match for å endre den."
                 : "Trukket sveitsisk på navn. Ved oddetall blir de tre siste en trekant. Trykk en match for å endre den.")
        }
    }

    private func matchText(_ match: MatchDraft) -> String {
        if match.isTeamMatch {
            return "Lag \(match.teamA.map(String.init) ?? "?") – lag \(match.teamB.map(String.init) ?? "?")"
        }
        let names = [match.playerA, match.playerB, match.playerC].compactMap { $0 }.map(model.memberName)
        return names.joined(separator: " – ") + (match.isTriangle ? " (trekant)" : "")
    }

    private func apply(_ result: MatchEditor.Result, at index: Int?) {
        switch result {
        case .cancel: break
        case .save(let match):
            if let index { draft.matches[index] = match } else { draft.matches.append(match) }
        case .delete:
            if let index { draft.matches.remove(at: index) }
        }
    }

    // MARK: Sidepremier

    @ViewBuilder
    private func sidePrizeSection(_ holes: [PlayedHole]) -> some View {
        let round = draft.coreRound(course: coreCourse)
        let ldSuggestion = SidePrizes.suggestedLongestDriveHole(round)
        let kpSuggestion = SidePrizes.suggestedClosestToPinHole(round)
        Section {
            Toggle("Longest drive", isOn: $draft.ldEnabled)
            if draft.ldEnabled {
                holePicker("Hull", selection: $draft.ldHoleIndex, suggestion: ldSuggestion, holes: holes)
            }
            Toggle("Nærmest pinnen", isOn: $draft.kpEnabled)
            if draft.kpEnabled {
                holePicker("Hull", selection: $draft.kpHoleIndex, suggestion: kpSuggestion, holes: holes)
            }
        } header: {
            DDHeader("Sidepremier")
        } footer: {
            DDFooter("Appen foreslår hull \(holeNumber(ldSuggestion)) for longest drive og hull \(holeNumber(kpSuggestion)) for nærmest pinnen.")
        }
    }

    private func holePicker(_ title: String, selection: Binding<Int?>, suggestion: Int, holes: [PlayedHole]) -> some View {
        Picker(title, selection: Binding(
            get: { selection.wrappedValue ?? suggestion },
            set: { selection.wrappedValue = $0 == suggestion ? nil : $0 }
        )) {
            ForEach(Array(holes.enumerated()), id: \.offset) { i, hole in
                Text("Hull \(holeNumber(i)) · par \(hole.par)" + (i == suggestion ? " (forslag)" : "")).tag(i)
            }
        }
    }

    /// Banens hullnummer for rundens hull (siste ni teller fra 10).
    private func holeNumber(_ index: Int) -> Int {
        index + (draft.firstHole == 10 ? 10 : 1)
    }

    // MARK: Handicap

    @ViewBuilder
    private func handicapSection(_ form: CompetitionForm) -> some View {
        Section {
            // Trackman deler bare ut slag i simulatoren.
            if draft.venue == .simulator {
                Toggle("Trackman fordeler slagene", isOn: $draft.externalHandicap)
            }
            if !draft.externalHandicap {
                Stepper("Handicapandel: \(Int((draft.allowance * 100).rounded())) %",
                        value: $draft.allowance, in: 0...1, step: 0.05)
                if draft.allowance != rules.allowance(for: form) {
                    Button("Tilbake til regelsettets \(Int((rules.allowance(for: form) * 100).rounded())) %") {
                        draft.allowance = rules.allowance(for: form)
                    }
                }
            }
        } header: {
            DDHeader("Handicap")
        } footer: {
            DDFooter(draft.externalHandicap
                 ? "Simulatoren deler ut slagene, og dere fører netto fra skjermen. Appen gir ingen slag."
                 : "Dere fører brutto. Appen trekker fra slagene etter stroke index. Spillehandicapet regnes og lagres når runden starter.")
        }
    }

    // MARK: Vekt

    struct WeightOption {
        let value: Double
        let title: String
    }

    /// Valgene fra PWA-ens `vektValg`.
    static let weights = [
        WeightOption(value: 1, title: "Vanlig runde"),
        WeightOption(value: 1.5, title: "Halvannen"),
        WeightOption(value: 2, title: "Dobbelt · avsluttende runde"),
        WeightOption(value: 3, title: "Tredobbelt"),
        WeightOption(value: 0, title: "Teller ikke sammenlagt"),
    ]
}

// MARK: - Én match

struct MatchEditItem: Identifiable {
    let id = UUID()
    let index: Int?
    let match: MatchDraft
}

/// Setter en match for hånd: to spillere (tre for trekant) eller to lag.
struct MatchEditor: View {
    enum Result {
        case cancel
        case save(MatchDraft)
        case delete
    }

    let model: RundeAdminModel
    let draft: RoundDraft
    @State var match: MatchDraft
    let isNew: Bool
    let onDone: (Result) -> Void

    var body: some View {
        DDForm {
            if match.isTeamMatch {
                let numbers = Array(Set(draft.teams.values)).sorted()
                Picker("Lag A", selection: $match.teamA) {
                    ForEach(numbers, id: \.self) { Text("Lag \($0)").tag(Optional($0)) }
                }
                Picker("Lag B", selection: $match.teamB) {
                    ForEach(numbers, id: \.self) { Text("Lag \($0)").tag(Optional($0)) }
                }
            } else {
                playerPicker("Spiller A", $match.playerA, allowNone: false)
                playerPicker("Spiller B", $match.playerB, allowNone: false)
                playerPicker("Tredje (trekant)", $match.playerC, allowNone: true)
                if match.isTriangle {
                    Text("En trekant avgjøres på poengsum, ikke hull mot hull.")
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            if !isNew {
                Button("Fjern matchen", role: .destructive) { onDone(.delete) }
            }
        }
        .navigationTitle(isNew ? "Ny match" : "Endre match")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { onDone(.cancel) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Ferdig") {
                    var saved = match
                    if saved.isTriangle { saved.result = nil }
                    onDone(.save(saved))
                }
                .disabled(!isComplete)
            }
        }
    }

    private var isComplete: Bool {
        if match.isTeamMatch { return match.teamA != nil && match.teamB != nil && match.teamA != match.teamB }
        let ids = match.members()
        return match.playerA != nil && match.playerB != nil && Set(ids).count == ids.count
    }

    private func playerPicker(_ title: String, _ selection: Binding<UUID?>, allowNone: Bool) -> some View {
        Picker(title, selection: selection) {
            Text(allowNone ? "Ingen" : "Velg").tag(UUID?.none)
            ForEach(draft.participants, id: \.self) { id in
                Text(model.memberName(id)).tag(Optional(id))
            }
        }
    }
}
