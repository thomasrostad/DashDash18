import GolfgutuCore
import SwiftUI

/// «Konkurranser i runden» i oppsettet (sql/048): hovedkonkurransen (formen) og de ekstra fra
/// oppskriftene. Detaljene ligger i hver konkurranse, under «Avansert».
struct RundeCompetitionsSection: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft

    var body: some View {
        Section {
            LabeledContent(draft.form.name, value: "Hovedkonkurranse")
            ForEach($draft.competitions) { $competition in
                NavigationLink {
                    CompetitionEditor(model: model, draft: draft, competition: $competition) {
                        draft.competitions.removeAll { $0.id == competition.id }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(competition.name)
                        Text(CompetitionSetup.summary(competition, holeCount: draft.holeCount, firstHole: draft.firstHole))
                            .font(.dd(.sans, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            }
            .onDelete { draft.competitions.remove(atOffsets: $0) }
            if draft.competitions.count < CompetitionSetup.maxExtra {
                Menu {
                    ForEach(CompetitionRecipe.allCases.filter { $0.isAvailable(holeCount: draft.holeCount) }) { recipe in
                        Button(recipe.title, systemImage: recipe.symbol) {
                            draft.competitions.append(recipe.make(for: draft))
                        }
                    }
                } label: {
                    Label("Legg til konkurranse", systemImage: "plus")
                }
            }
        } header: {
            DDHeader("Konkurranser i runden")
        } footer: {
            DDFooter("Alle regnes fra de samme scorene.")
        }
    }
}

/// Én ekstra konkurranse: navn, hvem som er med og hullene. Andel og par under «Avansert».
struct CompetitionEditor: View {
    let model: RundeAdminModel
    let draft: RoundDraft
    @Binding var competition: RoundCompetitionDraft
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showsAdvanced = false

    var body: some View {
        DDForm {
            Section {
                TextField("Navn", text: $competition.name)
                LabeledContent("Form", value: RoundCompetitionBoard.formName(competition.axes))
                if CompetitionHoles.choices(holeCount: draft.holeCount).count > 1 {
                    Picker("Hull", selection: Binding(
                        get: { CompetitionHoles(competition.config.holes) },
                        set: { competition.config.holes = $0.range }
                    )) {
                        ForEach(CompetitionHoles.choices(holeCount: draft.holeCount)) { Text($0.title).tag($0) }
                    }
                }
            }
            if !competition.isPairs { entrantsSection }
            Section {
                DisclosureGroup("Avansert", isExpanded: $showsAdvanced) {
                    Stepper("Handicapandel: \(Int(((competition.config.allowance ?? 1) * 100).rounded())) %",
                            value: Binding(get: { competition.config.allowance ?? 1 },
                                           set: { competition.config.allowance = $0 >= 1 ? nil : $0 }),
                            in: 0...1, step: 0.05)
                    if competition.isPairs { pairsRows }
                }
            } footer: {
                DDFooter("Andelen gjelder spillehandicapet i runden.")
            }
            Section {
                Button("Fjern konkurransen", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .navigationTitle(competition.name.isEmpty ? "Konkurranse" : competition.name)
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Hvem

    private var entrantsSection: some View {
        let selected = competition.selectedPlayers
        return Section {
            Picker("Hvem", selection: Binding(
                get: { selected == nil },
                set: { all in
                    let ids: Set<UUID>? = all ? nil : Set(draft.participants)
                    competition.config.entrants = CompetitionSetup.entrants(selected: ids, draft: competition,
                                                                           participants: draft.participants)
                }
            )) {
                Text("Alle").tag(true)
                Text("Valgte").tag(false)
            }
            .pickerStyle(.segmented)
            if let selected {
                ForEach(draft.participants, id: \.self) { id in
                    Toggle(model.memberName(id), isOn: Binding(
                        get: { selected.contains(id.uuidString) },
                        set: { on in
                            var ids = Set(selected.compactMap(UUID.init(uuidString:)))
                            if on { ids.insert(id) } else { ids.remove(id) }
                            competition.config.entrants = CompetitionSetup.entrants(selected: ids, draft: competition,
                                                                                   participants: draft.participants)
                        }
                    ))
                }
            }
        } header: {
            DDHeader("Hvem er med")
        } footer: {
            if competition.isPointsGame {
                DDFooter(selected == nil ? "Gruppene er lagene, ellers \(draft.groupTerm.definitePlural)." : "De valgte er én gruppe.")
            }
        }
    }

    // MARK: Par

    @ViewBuilder
    private var pairsRows: some View {
        let pairs = competition.config.entrants ?? []
        ForEach(Array(pairs.enumerated()), id: \.offset) { i, pair in
            LabeledContent("Par \(i + 1)", value: pair.compactMap(UUID.init(uuidString:)).map(model.memberName).joined(separator: " og "))
        }
        Button("Nye par fra \(draft.groupTerm.definitePlural)", systemImage: "arrow.triangle.2.circlepath") {
            competition.config.entrants = CompetitionSetup.suggestedPairs(draft)
        }
    }
}

/// «Lag mot lag» i oppsettet (sql/048): av eller på, og siden for hver spiller (laget følger med).
struct RundeTeamVsTeamSection: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft
    let plan: MatchDrawPlan

    var body: some View {
        Section {
            Toggle("Lag mot lag", isOn: Binding(
                get: { draft.isTeamVsTeam },
                set: { draft.setTeamVsTeam($0, roster: model.members, plan: plan) }
            ))
            if draft.isTeamVsTeam {
                ForEach(draft.participants, id: \.self) { id in
                    Picker(sideLabel(id), selection: Binding(
                        get: { draft.sides[id] ?? 0 },
                        set: { draft.setSide($0, for: id, roster: model.members, plan: plan) }
                    )) {
                        Text("Side 1").tag(1)
                        Text("Side 2").tag(2)
                        if draft.sides[id] == nil { Text("Ingen").tag(0) }
                    }
                }
                Button("Fordel sidene på nytt", systemImage: "arrow.left.arrow.right") {
                    draft.sides = TeamVsTeam.suggested(participants: draft.participants,
                                                       teams: draft.form.isTeamForm ? draft.teams : [:])
                    draft.redrawMatches(roster: model.members, plan: plan)
                }
            }
        } header: {
            DDHeader("Lag mot lag")
        } footer: {
            if draft.isTeamVsTeam,
               let problem = TeamVsTeam.problem(sides: draft.sides, teams: draft.form.isTeamForm ? draft.teams : [:],
                                                participants: draft.participants) {
                Text(problem).foregroundStyle(Color.ddRustText)
            } else {
                DDFooter(draft.isTeamVsTeam ? "Matchene er side mot side. Hver match gir poeng til siden." : "To sider samler poeng fra matchene.")
            }
        }
    }

    /// «Ola (lag 2)» i lagformer, ellers navnet.
    private func sideLabel(_ id: UUID) -> String {
        let name = model.memberName(id)
        guard draft.form.isTeamForm, let team = draft.teams[id] else { return name }
        return "\(name) (lag \(team))"
    }
}

// MARK: - Resultatene

/// «Konkurranser» i runden: hver konkurranse med stillingen, og lag mot lag med poengene til sidene.
struct CompetitionBoardsSection: View {
    let game: RoundGame

    var body: some View {
        let boards = RoundCompetitionBoard.boards(game)
        let teamResult = TeamVsTeam.result(game)
        if !boards.isEmpty || teamResult != nil {
            VStack(alignment: .leading, spacing: 10) {
                DDSectionLabel("Konkurranser")
                if game.snapshot.freeze?.isReconstructed == true {
                    Text("Øyeblikksbildet er laget i ettertid.")
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if let teamResult { TeamVsTeamCard(result: teamResult, game: game) }
                ForEach(boards) { board in CompetitionBoardCard(board: board) }
            }
        }
    }
}

struct CompetitionBoardCard: View {
    let board: RoundCompetitionBoard.Board
    /// Hvor mange rader som vises.
    var limit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(board.name)
                    .font(.dd(.sans, size: 16, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.ddForestInk)
                Spacer()
                if !board.detail.isEmpty {
                    Text(board.detail)
                        .font(.dd(.sans, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            if !board.supported {
                Text(RoundCompetitionBoard.unsupportedText)
                    .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ddInkSecondary)
            } else if board.lines.isEmpty {
                Text("Ingen scorer ennå")
                    .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ddInkSecondary)
            } else {
                ForEach(board.lines.prefix(limit)) { line in
                    HStack {
                        Text("\(line.rank).")
                            .monospacedDigit()
                            .frame(width: 26, alignment: .leading)
                            .foregroundStyle(Color.ddInkSecondary)
                        Text(line.names).lineLimit(1)
                        Spacer()
                        Text(line.score).monospacedDigit()
                    }
                    .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ddEarth, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Tavla

nonisolated extension TavlaStandings {
    /// Lagtabellen for lag mot lag over turneringens runder. nil når ingen runde har sider.
    var teamVsTeamTable: [TeamVsTeam.Row]? {
        let withSides = snapshots.filter { $0.players.contains { $0.side != nil } }
        guard !withSides.isEmpty else { return nil }
        return TeamVsTeam.table(withSides.map(RoundGame.init))
    }
}

/// «Lag mot lag» på Tavla: sidene med poeng og seire, delte og tap.
struct TeamVsTeamTavlaCard: View {
    let table: [TeamVsTeam.Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lag mot lag")
                .font(.dd(.sans, size: 16, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Color.ddForestInk)
            ForEach(table, id: \.side) { row in
                HStack {
                    Text(TeamVsTeam.sideName(row.side))
                    Spacer()
                    Text("\(row.won)–\(row.halved)–\(row.lost)")
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ddInkSecondary)
                        .monospacedDigit()
                    Text(TeamVsTeam.pointsText(row.points))
                        .font(.dd(.sans, size: 18, weight: .bold, relativeTo: .body))
                        .monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Seier, delt og tap i matchene side mot side.")
                .font(.dd(.sans, size: 12, relativeTo: .caption))
                .foregroundStyle(Color.ddInkSecondary)
        }
        .ddCard(padding: DDSpacing.l)
    }
}

/// Lag mot lag i runden: poengene til sidene og hver match.
struct TeamVsTeamCard: View {
    let result: RyderCup.Result
    let game: RoundGame

    var body: some View {
        let score = TeamVsTeam.score(result.table)
        VStack(alignment: .leading, spacing: 6) {
            Text("Lag mot lag")
                .font(.dd(.sans, size: 16, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(Color.ddForestInk)
            HStack {
                Text("Side 1")
                Spacer()
                Text("\(TeamVsTeam.pointsText(score.one)) – \(TeamVsTeam.pointsText(score.two))")
                    .font(.dd(.sans, size: 20, weight: .bold, relativeTo: .title3))
                    .monospacedDigit()
                Spacer()
                Text("Side 2")
            }
            .accessibilityElement(children: .combine)
            ForEach(Array(result.matches.enumerated()), id: \.offset) { _, m in
                if let text = matchText(m) {
                    Text(text)
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ddEarth, in: .rect(cornerRadius: 14))
    }

    private func matchText(_ m: RyderCup.MatchResult) -> String? {
        let label = "Match \(m.matchNo.map(String.init) ?? "")"
        switch m.state {
        case .invalid: return "\(label): ikke side mot side"
        case .pending: return "\(label): ikke startet"
        case .decided:
            guard let o = m.outcomeA, let a = m.sideA, let b = m.sideB else { return nil }
            if o == 0.5 { return "\(label): delt" }
            return "\(label): side \(o == 1 ? a : b) \(game.status == .locked ? "vant" : "leder")"
        }
    }
}
