import GolfgutuCore
import Supabase
import SwiftUI

// Spill på runden (fase 14): inngangen på runde-skjermen, ett lite kort per spill med stillingen,
// markeringene (Wolf-valg på tee, bingo-bango-bongo) og oppgjøret i poeng. Vises bare med
// `GamesFeature.isEnabled`.

/// Inngangen under føringen: «Spill i runden». Henter spillene for runden og viser kortene.
struct SpillIRunden: View {
    let game: RoundGame
    let hole: Int
    let viewer: Viewer
    let client: SupabaseClient
    let userID: UUID

    var body: some View {
        if GamesFeature.isEnabled {
            SpillIRundenLoader(game: game, hole: hole, viewer: viewer, client: client, userID: userID)
        }
    }
}

private struct SpillIRundenLoader: View {
    let game: RoundGame
    let hole: Int
    let viewer: Viewer
    let client: SupabaseClient
    let userID: UUID
    @State private var model: GamesModel?

    var body: some View {
        Group {
            if let model, model.roundID == game.roundID {
                SpillSeksjon(model: model, game: game, hole: hole, viewer: viewer, me: userID)
            }
        }
        .task(id: game.roundID) {
            let fresh = GamesModel(client: client, roundID: game.roundID)
            model = fresh
            await fresh.load()
        }
        // Nye scorer og låsing: hent markeringene og oppgjøret på nytt.
        .task(id: reloadKey) { await model?.load() }
    }

    private var reloadKey: String {
        "\(game.snapshot.scores.count)-\(game.status.rawValue)-\(hole)"
    }
}

/// Kortene for spillene i runden, og «Legg til spill».
struct SpillSeksjon: View {
    let model: GamesModel
    let game: RoundGame
    let hole: Int
    let viewer: Viewer
    let me: UUID?
    @State private var draft: GameDraft?
    @State private var error: String?

    var body: some View {
        let board = GamesBoard(model.input, game: game, viewer: viewer, me: me, hole: hole)
        VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
            DDSectionLabel("Spill i runden") {
                if canAdd {
                    Button("Legg til", systemImage: "plus") { draft = newDraft() }
                        .font(.ddChip)
                        .foregroundStyle(Color.ddForestInk)
                }
            }
            if board.cards.isEmpty {
                SpillTomtKort(canAdd: canAdd) { draft = newDraft() }
            }
            ForEach(board.cards) { card in
                SpillKort(card: card, name: game.name, holeNumber: game.holeNumber,
                          isSaving: model.isSaving, perform: perform)
            }
            if let error {
                Text(error).ddErrorStyle()
            }
        }
        .sheet(item: $draft) { d in
            NyttSpillArk(model: model, draft: d, name: game.name)
        }
    }

    private var canAdd: Bool {
        game.status != .locked && (viewer.isOrganizer || game.isPlaying(viewer.memberID))
    }

    private func newDraft() -> GameDraft {
        let mine = game.bay(of: viewer.memberID)?.players ?? (game.isPlaying(viewer.memberID) ? [viewer.memberID] : [])
        return GameDraft(kind: .skins, roundPlayers: game.snapshot.players.map(\.memberID)
                            .sorted { NorwegianSort.areInIncreasingOrder(game.name($0), game.name($1)) },
                         preferred: mine)
    }

    private func perform(_ action: SpillKort.Action) {
        error = nil
        Task {
            do {
                switch action {
                case .wolf(let id, let hole, let choice): try await model.setWolf(id, hole: hole, choice: choice)
                case .award(let id, let hole, let award, let player):
                    try await model.setAward(id, hole: hole, award: award, player: player)
                case .settle(let card): try await model.settle(card)
                case .delete(let id): try await model.delete(id)
                }
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}

extension GameDraft: Identifiable {
    var id: String { kind.rawValue }
}

/// Før noen har lagt til et spill.
private struct SpillTomtKort: View {
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Text("Skins, Nassau, Wolf, bingo-bango-bongo eller 2 mot 2 oppå runden. Poengene gjøres opp når runden er ferdig.")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
            if canAdd {
                Button("Legg til spill", systemImage: "plus", action: onAdd)
                    .buttonStyle(.dd(.secondary, fullWidth: true, compact: true))
            }
        }
        .ddCard(.empty)
    }
}

/// Ett spill: stillingen, markeringen på hullet og oppgjøret.
struct SpillKort: View {
    enum Action {
        case wolf(UUID, hole: Int, WolfChoice?)
        case award(UUID, hole: Int, RoundGameMarkRow.Award, UUID?)
        case settle(GameCard)
        case delete(UUID)
    }

    let card: GameCard
    let name: (UUID) -> String
    let holeNumber: (Int) -> Int
    var isSaving = false
    let perform: (Action) -> Void
    @State private var confirmsDelete = false
    @State private var confirmsSettle = false

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            header
            if !card.lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(card.lines, id: \.self) { line in
                        Text(line)
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInk)
                    }
                }
            }
            if let action = card.action {
                SpillMarkering(action: action, gameID: card.id, name: name, holeNumber: holeNumber,
                               isSaving: isSaving, perform: perform)
            }
            VStack(spacing: 0) {
                if card.isSettled || card.canSettle {
                    Text("Sluttresultat")
                        .ddEyebrow()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                }
                ForEach(card.rows) { row in
                    SpillRad(row: row)
                    if row.id != card.rows.last?.id { DDDivider() }
                }
            }
            if card.canSettle {
                Button("Gjør opp i poeng") { confirmsSettle = true }
                    .buttonStyle(.dd(.primary, fullWidth: true, compact: true))
                    .disabled(isSaving)
                    .confirmationDialog("Gjøre opp \(card.title)?", isPresented: $confirmsSettle, titleVisibility: .visible) {
                        Button("Gjør opp") { perform(.settle(card)) }
                    } message: {
                        Text("Poengene skrives i rundens poengbank. Arrangøren kan gjøre opp på nytt hvis en score rettes.")
                    }
            }
            DisclosureGroup("Slik spilles det") {
                Text(GameTexts.explanation(card.kind))
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.ddCaption)
            .tint(Color.ddForestInk)
        }
        .ddCard()
        .confirmationDialog("Fjerne \(card.title)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Fjern spillet", role: .destructive) { perform(.delete(card.id)) }
        } message: {
            Text("Markeringene i spillet forsvinner også. Scorene i runden står.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DDSpacing.m) {
            Image(systemName: GameTexts.icon(card.kind))
                .font(.title3)
                .foregroundStyle(Color.ddForestInk)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(card.summary)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                DDPill(card.status, tone: card.isSettled ? .lime : (card.canSettle ? .sun : .earth))
                if card.canDelete {
                    Menu {
                        Button("Fjern spillet", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Color.ddInkSecondary)
                            .frame(width: 32, height: 24)
                    }
                    .accessibilityLabel("Mer for \(card.title)")
                }
            }
        }
    }
}

/// Én spiller på kortet: navn, spillpoeng og oppgjøret.
private struct SpillRad: View {
    let row: GameCard.Row

    var body: some View {
        HStack {
            Text(row.name)
                .font(.ddBody)
                .foregroundStyle(Color.ddInk)
            if let detail = row.detail {
                Text(detail)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            Text(GameTexts.signed(row.points))
                .font(.dd(.mono, size: 15, weight: .semibold, relativeTo: .body))
                .foregroundStyle(row.points > 0 ? Color.ddForestInk : (row.points < 0 ? Color.ddRustText : Color.ddInkSecondary))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(GameTexts.signed(row.points)) poeng")
    }
}

private struct WolfOption: Identifiable {
    let title: String
    let choice: WolfChoice
    var id: String { "\(choice.mode.rawValue)-\(choice.partner ?? "")" }
}

/// Markeringen på hullet: Wolf-valget på tee, eller bingo, bango og bongo.
private struct SpillMarkering: View {
    let action: GameHoleAction
    let gameID: UUID
    let name: (UUID) -> String
    let holeNumber: (Int) -> Int
    let isSaving: Bool
    let perform: (SpillKort.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            switch action {
            case .wolf(let hole, let wolf, let partners, let blindAllowed, let current):
                Text("Velg for \(name(wolf)) etter utslagene:")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                let options = partners.map { WolfOption(title: name($0), choice: .partner($0.uuidString)) }
                    + [WolfOption(title: "Alene", choice: .alone)]
                    + (blindAllowed ? [WolfOption(title: "Blind", choice: .blind)] : [])
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(options) { option in
                        // Trykk på valget som står, fjerner det.
                        Button(option.title) {
                            perform(.wolf(gameID, hole: hole, option.choice == current ? nil : option.choice))
                        }
                        .buttonStyle(DDChoiceButtonStyle(selected: option.choice == current))
                    }
                }
            case .bingoBangoBongo(let hole, let players, let current):
                Text("Hull \(holeNumber(hole))")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                award("Bingo", hint: "først på green", .bingo, current.bingo, hole: hole, players: players)
                award("Bango", hint: "nærmest når alle er på green", .bango, current.bango, hole: hole, players: players)
                award("Bongo", hint: "først i hullet", .bongo, current.bongo, hole: hole, players: players)
            }
        }
        .padding(DDSpacing.m)
        .background(RoundedRectangle(cornerRadius: DDRadius.input).fill(Color.ddEarth.opacity(0.45)))
        .disabled(isSaving)
    }

    private func award(_ title: String, hint: String, _ kind: RoundGameMarkRow.Award, _ current: String?,
                       hole: Int, players: [UUID]) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.ddBodyEmphasis).foregroundStyle(Color.ddInk)
                Text(hint).font(.ddCaption).foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Ingen") { perform(.award(gameID, hole: hole, kind, nil)) }
                ForEach(players, id: \.self) { p in
                    Button(name(p)) { perform(.award(gameID, hole: hole, kind, p)) }
                }
            } label: {
                Text(current.flatMap(UUID.init(uuidString:)).map(name) ?? "Velg")
                    .font(.ddChip)
            }
            .buttonStyle(.dd(.secondary, compact: true))
            .accessibilityLabel("\(title): \(current.flatMap(UUID.init(uuidString:)).map(name) ?? "ingen")")
        }
    }
}

// MARK: - Nytt spill

/// Arket for et nytt spill: type med forklaring, hvem som er med (og sider), og verdiene.
struct NyttSpillArk: View {
    let model: GamesModel
    @State var draft: GameDraft
    let name: (UUID) -> String
    @State private var error: String?
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DDForm {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(GameKind.allCases, id: \.self) { kind in
                            Button(GameTexts.name(kind)) { draft.setKind(kind) }
                                .buttonStyle(DDChoiceButtonStyle(selected: draft.kind == kind))
                        }
                    }
                } header: {
                    DDHeader("Spill")
                } footer: {
                    DDFooter(GameTexts.explanation(draft.kind))
                }

                Section {
                    ForEach(draft.roundPlayers, id: \.self) { id in
                        playerRow(id)
                    }
                } header: {
                    DDHeader(draft.kind == .wolf ? "Hvem er med (rekkefølgen på tee)" : "Hvem er med")
                } footer: {
                    DDFooter(playersHint)
                }

                SpillVerdier(draft: $draft)

                Section {
                    Button("Legg til \(GameTexts.name(draft.kind))") { submit() }
                        .buttonStyle(.dd(.primary, fullWidth: true))
                        .disabled(problem != nil || busy || model.isSaving)
                    if let text = problem ?? error {
                        Text(text).ddErrorStyle()
                    }
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Nytt spill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func playerRow(_ id: UUID) -> some View {
        let order = draft.players.firstIndex(of: id)
        HStack(spacing: DDSpacing.m) {
            Button {
                draft.toggle(id)
            } label: {
                HStack {
                    Image(systemName: order != nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(order != nil ? Color.ddForestInk : Color.ddInkSecondary)
                    Text(name(id)).foregroundStyle(Color.ddInk)
                    if draft.kind == .wolf, let order {
                        Text("\(order + 1).").font(.ddCaption).foregroundStyle(Color.ddInkSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            if draft.kind.hasSides, order != nil {
                Picker("Lag for \(name(id))", selection: Binding(get: { draft.sides[id] ?? 1 },
                                                                   set: { draft.setSide(id, $0) })) {
                    Text("Lag 1").tag(1)
                    Text("Lag 2").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
        }
    }

    private var playersHint: String {
        switch draft.kind {
        case .wolf: "Første spiller er wolf på første hull, så går det på rundgang."
        case .nassau: "To sider, én eller to på hver. Beste ball teller når dere er to."
        case .bestBall: "To lag på to."
        default: "Trykk for å ta med eller ut. Spillere kan være med i noen spill og ikke andre."
        }
    }

    private var problem: String? {
        draft.problems().first.map { GameTexts.problem($0, names: { s in UUID(uuidString: s).map(name) ?? s }) }
    }

    private func submit() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await model.create(draft)
                dismiss()
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}

/// Verdiene for typen. Starter med malen, og hvert spill kan overstyre dem.
private struct SpillVerdier: View {
    @Binding var draft: GameDraft

    var body: some View {
        Section {
            switch draft.kind {
            case .skins:
                handicap($draft.skins.handicap)
                stepper("Poeng per skin", $draft.skins.valuePerSkin, step: 5)
                Toggle("Delt hull går videre (carry-over)", isOn: $draft.skins.carryOver)
                if draft.skins.carryOver {
                    Picker("Delt siste hull", selection: $draft.skins.leftover) {
                        Text("Faller bort").tag(SkinsRules.Leftover.lapse)
                        Text("Deles").tag(SkinsRules.Leftover.split)
                    }
                }
            case .nassau:
                Picker("Telling", selection: $draft.nassau.scoring) {
                    Text("Match (hull)").tag(NassauRules.Scoring.match)
                    Text("Slag").tag(NassauRules.Scoring.stroke)
                }
                handicap($draft.nassau.handicap)
                stepper("Første ni", $draft.nassau.front, step: 5)
                stepper("Siste ni", $draft.nassau.back, step: 5)
                stepper("Totalt", $draft.nassau.total, step: 5)
                if draft.nassau.scoring == .match {
                    Toggle("Press ved \(draft.nassau.pressTrigger) under", isOn: $draft.nassau.press)
                    if draft.nassau.press {
                        stepper("Poeng per press", $draft.nassau.pressValue, step: 5)
                    }
                }
            case .wolf:
                handicap($draft.wolf.handicap)
                stepper("Wolf og partner vinner (hver)", $draft.wolf.partnerWin)
                stepper("De andre vinner (hver)", $draft.wolf.opponentsWin)
                stepper("Alene og vinner", $draft.wolf.loneWin)
                stepper("Alene og taper (til hver)", $draft.wolf.loneLoss)
                Toggle("Blind wolf er lov", isOn: $draft.wolf.blindAllowed)
                if draft.wolf.blindAllowed {
                    stepper("Blind og vinner", $draft.wolf.blindWin)
                    stepper("Blind og taper (til hver)", $draft.wolf.blindLoss)
                }
                stepper("Oppgjør per wolf-poeng", $draft.wolf.pointValue)
            case .bingoBangoBongo:
                stepper("Bingo", $draft.bingoBangoBongo.bingo)
                stepper("Bango", $draft.bingoBangoBongo.bango)
                stepper("Bongo", $draft.bingoBangoBongo.bongo)
                stepper("Oppgjør per poeng", $draft.bingoBangoBongo.pointValue)
            case .bestBall:
                Picker("Telling", selection: $draft.bestBall.scoring) {
                    Text("Match").tag(BestBallRules.Scoring.match)
                    Text("Stableford").tag(BestBallRules.Scoring.stableford)
                }
                if draft.bestBall.scoring == .match {
                    handicap($draft.bestBall.matchHandicap)
                } else {
                    handicap($draft.bestBall.stablefordHandicap)
                }
                stepper("Poeng per spiller", $draft.bestBall.value, step: 5)
            }
        } header: {
            DDHeader("Verdier")
        } footer: {
            DDFooter("Bare poeng, aldri kroner. Taperne gir poengene til vinnerne, og summen går i null.")
        }
    }

    private func stepper(_ title: String, _ value: Binding<Int>, step: Int = 1) -> some View {
        Stepper(value: value, in: 0...1000, step: step) {
            LabeledContent(title, value: "\(value.wrappedValue)")
        }
    }

    @ViewBuilder
    private func handicap(_ h: Binding<GameHandicap>) -> some View {
        Toggle("Netto (med handicap)", isOn: h.net)
        if h.wrappedValue.net {
            Stepper(value: h.allowance, in: 0...1, step: 0.05) {
                LabeledContent("Andel av handicapet", value: GameTexts.percent(h.wrappedValue.allowance))
            }
        }
    }
}
