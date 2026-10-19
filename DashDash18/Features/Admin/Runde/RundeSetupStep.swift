import GolfgutuCore
import SwiftUI

/// «Flere valg» på «Ny runde»: formen, lag og matcher når formen bruker dem, sidepremiene som én rad
/// hver, og vekt og handicap under «Avansert». Det som ikke gjelder, skjules (se `RoundSetupOptions`).
struct RundeSetupStep: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft
    let bayCount: Int

    @State private var editingMatch: MatchEditItem?
    /// «Avansert» åpen. Nil: åpen bare når noe der er endret fra standarden.
    @State private var showsAdvanced: Bool?
    /// «Tilfeldige lag» kunne ikke fordele lagene (de står da som de var), så footeren sier hvorfor.
    @State private var randomTeamsFailed = false

    private var rules: Ruleset { model.rules }
    private var coreCourse: Course? { model.coreCourse(for: draft) }
    /// Trekningen etter regelsettet (`formats.drawMethod`).
    private var plan: MatchDrawPlan { model.drawPlan(for: draft) }

    var body: some View {
        let form = draft.form
        let options = RoundSetupOptions(draft: draft, rules: rules)
        let holes = draft.coreRound(course: coreCourse).courseHoles()
        DDForm {
            formSection(form)
            if options.showsTeams { teamSection(form) }
            if RoundFormatsFeature.isAvailable, options.showsMatches || draft.isTeamVsTeam {
                RundeTeamVsTeamSection(model: model, draft: $draft, plan: plan)
            }
            if options.showsMatches { matchSection(form) }
            if RoundFormatsFeature.isAvailable { RundeCompetitionsSection(model: model, draft: $draft) }
            sidePrizeSection(holes)
            advancedSection(form, options: options)
            if RoundRulesFeature.isAvailable { tableSection }
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
        let setup = rules.setup(formID: form.id, players: count)
        Section {
            Picker("Form", selection: Binding(
                get: { draft.formID },
                set: { draft.setForm($0, rules: rules, roster: model.members, plan: plan) }
            )) {
                ForEach(formChoices) { f in
                    Text(f.name + supportNote(f)).tag(f.id)
                }
            }
            // Bare når formen ikke går opp med de som er med.
            if setup.text == nil, let reason = setup.reason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddRustText)
            }
        } footer: {
            DDFooter(formFooter(form, count: count, failed: setup.text == nil && setup.reason != nil))
        }
    }

    /// Én linje: formens forklaring, eller hva som går opp når formen ikke gjør det.
    private func formFooter(_ form: CompetitionForm, count: Int, failed: Bool) -> String {
        let suggestions = rules.suggestions(players: count)
        guard failed, !suggestions.isEmpty else { return form.help }
        return "Går opp med \(count): " + suggestions.map { "\($0.name) (\($0.text))" }.joined(separator: ", ") + "."
    }

    /// De tillatte formene i regelsettet, og formen kladden har om den ikke er tillatt lenger.
    private var formChoices: [CompetitionForm] {
        var forms = rules.allowedForms
        if !forms.contains(where: { $0.id == draft.formID }) { forms.insert(draft.form, at: 0) }
        return forms
    }

    /// Formene som er ferdige i appen etter PWA-en, selv om PWA-katalogen (`CompetitionForm.all`) sier
    /// «delvis»: par/bogey regnes av motoren i konkurransene, stillingen og tabellen.
    nonisolated static let completedForms: Set<String> = ["par-bogey"]

    private func supportNote(_ form: CompetitionForm) -> String {
        switch form.support {
        case .full: ""
        case .partial: RundeSetupStep.completedForms.contains(form.id) ? "" : " · ikke ferdig"
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
                    set: { draft.teams[id] = $0; draft.redrawMatches(roster: model.members, plan: plan) }
                )) {
                    Text("Uten lag").tag(Int?.none)
                    ForEach(1...numbers, id: \.self) { n in
                        Text("Lag \(n)").tag(Optional(n))
                    }
                }
            }
            Button("Tilfeldige lag", systemImage: "dice") {
                let teams = TeamPlanner.random(participants: draft.participants, form: form,
                                               maxPerBay: rules.formats.maxPerBay, seed: .random(in: .min ... .max))
                // Går det ikke opp, står lagene som de var, og arrangøren får vite hvorfor.
                randomTeamsFailed = teams.isEmpty
                guard !teams.isEmpty else { return }
                draft.teams = teams
                draft.redrawMatches(roster: model.members, plan: plan)
            }
            NavigationLink {
                TeamSwapView(model: model, draft: $draft, plan: plan)
            } label: {
                Label("Bytt to spillere", systemImage: "arrow.left.arrow.right")
            }
            .disabled(Set(draft.participants.compactMap { draft.teams[$0] }).count < 2)
        } header: {
            DDHeader("Lag · \(form.teamSize) per lag")
        } footer: {
            if let problem = TeamPlanner.problem(teams: draft.teams, participants: draft.participants, form: form,
                                                 maxPerBay: rules.formats.maxPerBay, term: draft.groupTerm) {
                Text(problem).foregroundStyle(Color.ddRustText)
            } else if randomTeamsFailed,
                      let reason = TeamPlanner.unavailable(players: draft.participants.count, form: form,
                                                           maxPerBay: rules.formats.maxPerBay) {
                // Bare så lenge det fortsatt ikke går opp (deltakerne eller formen kan ha endret seg).
                Text(reason).foregroundStyle(Color.ddRustText)
            }
        }
    }

    // MARK: Matcher

    @ViewBuilder
    private func matchSection(_ form: CompetitionForm) -> some View {
        Section {
            if draft.matches.isEmpty {
                Text("Ingen matcher")
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
            Button("Ny match", systemImage: "plus") {
                editingMatch = MatchEditItem(index: nil, match: form.isTeamForm ? .teams(1, 2) : MatchDraft())
            }
            Menu {
                if plan.method == .manual {
                    // Manuelt: arrangøren setter opp matchene, men kan få et forslag etter tabellen.
                    Button("Foreslå matcher etter tabellen", systemImage: "list.number") {
                        draft.redrawMatches(roster: model.members, plan: .standings)
                    }
                } else {
                    Button("Trekk matchene på nytt", systemImage: "dice") {
                        draft.redrawMatches(roster: model.members, plan: plan)
                    }
                }
                Button("Sett matchene sammen i \(draft.groupTerm.definitePlural)", systemImage: "square.grid.2x2") {
                    draft.reshuffleBays(count: bayCount)
                }
            } label: {
                Label("Trekk på nytt", systemImage: "dice")
            }
        } header: {
            DDHeader("Matcher")
        } footer: {
            if !form.isTeamForm, let text = MatchDrawText.footer(plan: plan, matches: draft.matches) { DDFooter(text) }
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
            sidePrizeRow("Longest drive", enabled: $draft.ldEnabled, holeIndex: $draft.ldHoleIndex,
                         suggestion: ldSuggestion, holes: holes)
            sidePrizeRow("Nærmest pinnen", enabled: $draft.kpEnabled, holeIndex: $draft.kpHoleIndex,
                         suggestion: kpSuggestion, holes: holes)
        } header: {
            DDHeader("Sidepremier")
        }
    }

    /// Av/på og hull i én rad: «Av» eller «Hull 7 · par 3».
    private func sidePrizeRow(_ title: String, enabled: Binding<Bool>, holeIndex: Binding<Int?>, suggestion: Int,
                              holes: [PlayedHole]) -> some View {
        Picker(title, selection: Binding(
            get: { RoundSetupOptions.sidePrizeChoice(enabled: enabled.wrappedValue, holeIndex: holeIndex.wrappedValue,
                                                     suggestion: suggestion) },
            set: { RoundSetupOptions.applySidePrize($0, enabled: &enabled.wrappedValue,
                                                    holeIndex: &holeIndex.wrappedValue, suggestion: suggestion) }
        )) {
            Text("Av").tag(Int?.none)
            ForEach(Array(holes.enumerated()), id: \.offset) { i, hole in
                Text("Hull \(holeNumber(i)) · par \(hole.par)" + (i == suggestion ? " (forslag)" : "")).tag(Optional(i))
            }
        }
    }

    /// Banens hullnummer for rundens hull (siste ni teller fra 10).
    private func holeNumber(_ index: Int) -> Int {
        index + (draft.firstHole == 10 ? 10 : 1)
    }

    // MARK: Avansert: vekt og handicap

    @ViewBuilder
    private func advancedSection(_ form: CompetitionForm, options: RoundSetupOptions) -> some View {
        let changed = options.advancedIsChanged(weight: draft.weight, allowance: draft.allowance)
        Section {
            DisclosureGroup("Avansert", isExpanded: Binding(
                get: { showsAdvanced ?? changed },
                set: { showsAdvanced = $0 }
            )) {
                Picker("Hvor mye runden teller", selection: $draft.weight) {
                    ForEach(RoundSetupOptions.weights, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                // Trackman deler bare ut slag i simulatoren.
                if options.showsTrackmanToggle {
                    Toggle("Trackman fordeler slagene", isOn: $draft.externalHandicap)
                }
                if options.showsAllowance {
                    Stepper("Handicapandel: \(Int((draft.allowance * 100).rounded())) %",
                            value: $draft.allowance, in: 0...1, step: 0.05)
                    if draft.allowance != rules.allowance(for: form) {
                        Button("Tilbake til regelsettets \(Int((rules.allowance(for: form) * 100).rounded())) %") {
                            draft.allowance = rules.allowance(for: form)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tabellen (sql/047)

extension RundeSetupStep {
    /// «Teller ikke i tabellen», poengtabellen og «Skjul de siste hullene» (antallet fra regelsettet,
    /// `play.hiddenHoles`, og kan endres for runden).
    var tableSection: some View {
        Section {
            Toggle("Teller ikke i tabellen", isOn: Binding(get: { !draft.counts }, set: { draft.counts = !$0 }))
            let tables = RoundTableRules.tableNames(rules)
            if !tables.isEmpty || draft.pointsTable != nil {
                Picker("Poengtabell", selection: $draft.pointsTable) {
                    Text("Vanlig").tag(String?.none)
                    ForEach(RoundTableRules.choices(tables, current: draft.pointsTable), id: \.self) { name in
                        Text(RoundTableRules.title(name, rules: rules)).tag(String?.some(name))
                    }
                }
                .disabled(!draft.counts)
            }
            Toggle("Skjul de siste hullene", isOn: $draft.hidesLastHoles)
            if draft.hidesLastHoles {
                Stepper(value: $draft.hiddenHoles,
                        in: Ruleset.PlayRules.hiddenHolesRange.lowerBound...min(Ruleset.PlayRules.hiddenHolesRange.upperBound,
                                                                                max(1, draft.holeCount))) {
                    LabeledContent("Antall hull", value: "\(draft.storedHiddenHoles)")
                }
            }
        } header: {
            Text("Tabellen")
        } footer: {
            Text(draft.hidesLastHoles
                 ? "Stillingen på Tavla, i Hjem og i varslene regnes uten de \(draft.storedHiddenHoles) siste hullene til runden er låst. Arrangøren og \(draft.groupTerm.definite) som fører, ser alt."
                 : "Skjulte hull vises for andre når runden er låst.")
        }
    }
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
            DDCancelToolbarItem {
                Button("Avbryt") { onDone(.cancel) }
            }
            DDConfirmToolbarItem {
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

#if DEBUG
/// Skjermprøven `flerevalg`: «Flere valg» for kvelden i dag, slik hurtigstarten åpner den.
struct FlereValgSample: View {
    let model: RundeAdminModel
    @State private var draft: RoundDraft

    init() {
        let model = RundeAdminModel.sample()
        var draft = model.newDraft()!
        draft.prepareSetup(rules: model.rules, roster: model.members, plan: model.drawPlan(for: draft))
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            RundeSetupStep(model: model, draft: $draft, bayCount: max(1, draft.bays.bayCount))
                .navigationTitle("Flere valg")
                .ddNavigationChrome()
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
