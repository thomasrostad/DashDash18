import GolfgutuCore
import SwiftUI

/// Rundene: alle startede runder, nyeste først. Trykk en for å se hele runden og rette et hull.
struct RundeneView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            RundeneContent(model: RundeneModel(context: context))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "flag.2.crossed")
        }
    }
}

private struct RundeneContent: View {
    @State var model: RundeneModel

    var body: some View {
        content
            .navigationTitle("Rundene")
            .ddNavigationChrome()
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter rundene …")
        case .failed(let text):
            ContentUnavailableView {
                Label("Fikk ikke hentet rundene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if model.items.isEmpty {
                ContentUnavailableView("Ingen runder ennå", systemImage: "flag.2.crossed",
                                       description: Text("Rundene står her når den første er startet."))
            } else {
                DDList {
                    Section {
                        ForEach(model.items) { item in
                            NavigationLink {
                                RoundTableView(round: item.round, title: item.title)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                        Text(subtitle(item))
                                            .font(.dd(.sans, size: 13, relativeTo: .footnote))
                                            .foregroundStyle(Color.ddInkSecondary)
                                    }
                                    Spacer()
                                    StatusBadge(status: item.round.status)
                                }
                            }
                        }
                    } footer: {
                        DDFooter("Trykk en runde for å se alle spillerne og hullene, og rette et hull, også i en låst runde.")
                    }
                }
            }
        }
    }

    private func subtitle(_ item: RundeneItem) -> String {
        [item.eventDate.map { EveningDates.longText($0, capitalized: true) } ?? "Ingen dato",
         "\(item.round.holeCount) hull",
         item.players == 1 ? "1 spiller" : "\(item.players) spillere"]
            .joined(separator: " · ")
    }
}

// MARK: - Hele runden

/// Spillere × hull med brutto, sum og poeng. Trykk en rute for å rette den.
struct RoundTableView: View {
    @Environment(\.clubContext) private var context
    let round: RoundRow
    let title: String

    var body: some View {
        if let context {
            RoundTableContent(model: RoundReviewModel(context: context, round: round, title: title))
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "flag.2.crossed")
        }
    }
}

/// Retting som er åpen i arket.
private struct CorrectionItem: Identifiable {
    let id = UUID()
    let member: UUID?
    let hole: Int?
}

private struct RoundTableContent: View {
    @State var model: RoundReviewModel
    @State private var correcting: CorrectionItem?
    @State private var cutting = false
    @State private var message: String?

    private let rowHeight: CGFloat = 36
    private let cellWidth: CGFloat = 32

    var body: some View {
        content
            .navigationTitle(model.title)
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Mer", systemImage: "ellipsis.circle") {
                        Button("Rett en score", systemImage: "pencil") {
                            correcting = CorrectionItem(member: nil, hole: nil)
                        }
                        if model.game?.status == .active {
                            Button("Avkort runden", systemImage: "scissors") { cutting = true }
                        }
                    }
                    .disabled(model.game == nil)
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(item: $correcting) { item in
                if let game = model.game {
                    NavigationStack {
                        ScoreCorrectionSheet(model: model, game: game, member: item.member, hole: item.hole) { text in
                            message = text
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $cutting, onDismiss: { Task { await model.load() } }) {
                if let game = model.game {
                    NavigationStack {
                        AvkortSheet(round: game.snapshot.round, title: model.title) { message = $0 }
                    }
                }
            }
            .alert("Ferdig", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter runden …")
        case .failed(let text):
            ContentUnavailableView {
                Label("Fikk ikke hentet runden", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if let game = model.game {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(header(game))
                            .font(.dd(.sans, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Color.ddInkSecondary)
                        let table = game.table()
                        if table.rows.isEmpty {
                            Text("Runden har ingen deltakere.")
                                .foregroundStyle(Color.ddInkSecondary)
                        } else {
                            grid(table, game: game)
                        }
                        Text(footer(table))
                            .font(.dd(.sans, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    .padding()
                }
            }
        }
    }

    private func header(_ game: RoundGame) -> String {
        var parts: [String] = []
        if let date = game.snapshot.eventDate { parts.append(EveningDates.longText(date, capitalized: true)) }
        parts.append(game.snapshot.course?.name ?? "Ingen bane")
        parts.append("\(game.holeCount) hull")
        parts.append(game.round.form.name)
        if let cut = game.cutSummary { parts.append(cut.lowercased()) }
        parts.append(RoundListing.statusText(game.status).lowercased())
        return parts.joined(separator: " · ")
    }

    private func footer(_ table: RoundTable) -> String {
        "Brutto slag. Fargen er netto mot par, som på scorekortet."
            + (table.hasOutside ? " Grå hull er utenfor avkortingen og teller ikke." : "")
            + " Trykk en rute for å rette den."
    }

    private func grid(_ table: RoundTable, game: RoundGame) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Navnet står fast til venstre.
            VStack(alignment: .leading, spacing: 0) {
                label("Hull", bold: true)
                label("Par")
                ForEach(table.rows) { row in label(row.name) }
            }
            .frame(width: 96, alignment: .leading)

            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(table.columns) { col in
                            cellText("\(col.number)", bold: true).opacity(col.outside ? 0.4 : 1)
                        }
                        cellText("Slag", bold: true, width: 44)
                        cellText("Poeng", bold: true, width: 48)
                    }
                    HStack(spacing: 0) {
                        ForEach(table.columns) { col in
                            cellText("\(col.par)").foregroundStyle(Color.ddInkSecondary).opacity(col.outside ? 0.4 : 1)
                        }
                        cellText("\(table.parTotal)", width: 44).foregroundStyle(Color.ddInkSecondary)
                        cellText("", width: 48)
                    }
                    ForEach(table.rows) { row in
                        HStack(spacing: 0) {
                            ForEach(row.cells) { cell in
                                Button {
                                    correcting = CorrectionItem(member: row.memberID, hole: cell.index)
                                } label: {
                                    cellText(cell.strokes.map(String.init) ?? "·")
                                        .background(tint(cell.scoreName))
                                        .opacity(cell.outside ? 0.4 : 1)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(row.name), hull \(game.holeNumber(cell.index)): "
                                                    + (cell.strokes.map { "\($0) slag" } ?? "ikke ført"))
                                .accessibilityHint("Trykk for å rette")
                            }
                            cellText(row.strokes.map(String.init) ?? "—", width: 44)
                            cellText("\(row.points)", bold: true, width: 48)
                        }
                    }
                }
            }
        }
        .font(.dd(.sans, size: 15, relativeTo: .callout)).monospacedDigit()
    }

    private func label(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .fontWeight(bold ? .semibold : .regular)
            .lineLimit(1)
            .frame(height: rowHeight)
    }

    private func cellText(_ text: String, bold: Bool = false, width: CGFloat? = nil) -> some View {
        Text(text)
            .fontWeight(bold ? .semibold : .regular)
            .frame(width: width ?? cellWidth, height: rowHeight)
    }

    private func tint(_ name: ScoreName?) -> Color {
        // Samme farger som score-merkene; par står uten farge, som før.
        switch name {
        case .par, nil: .clear
        case let name?: name.tone.background
        }
    }
}

// MARK: - Rett en score

/// Rett ett hull for én spiller, i hvilken som helst runde (også låst). Sendes via `scoreSubmitter`.
struct ScoreCorrectionSheet: View {
    let model: RoundReviewModel
    let game: RoundGame
    var onDone: (String) -> Void

    @Environment(\.scoreSubmitter) private var submitter
    @Environment(\.dismiss) private var dismiss
    @State private var member: UUID
    @State private var hole: Int
    @State private var correction: ScoreCorrection
    @State private var error: String?
    @State private var isBusy = false

    init(model: RoundReviewModel, game: RoundGame, member: UUID?, hole: Int?, onDone: @escaping (String) -> Void) {
        self.model = model
        self.game = game
        self.onDone = onDone
        let players = game.snapshot.players.map(\.memberID)
            .sorted { NorwegianSort.areInIncreasingOrder(game.name($0), game.name($1)) }
        let m = member ?? players.first ?? UUID()
        let h = min(max(0, hole ?? 0), max(0, game.holeCount - 1))
        _member = State(initialValue: m)
        _hole = State(initialValue: h)
        _correction = State(initialValue: ScoreCorrection(game: game, member: m, hole: h))
    }

    private var players: [UUID] {
        game.snapshot.players.map(\.memberID)
            .sorted { NorwegianSort.areInIncreasingOrder(game.name($0), game.name($1)) }
    }

    var body: some View {
        DDForm {
            Section {
                Picker("Spiller", selection: $member) {
                    ForEach(players, id: \.self) { id in
                        Text(game.name(id)).tag(id)
                    }
                }
                Picker("Hull", selection: $hole) {
                    ForEach(game.holes.indices, id: \.self) { i in
                        Text("Hull \(game.holeNumber(i)) · par \(game.holes[i].par)").tag(i)
                    }
                }
            } footer: {
                DDFooter(correction.currentText)
            }

            Section {
                HStack {
                    Button("Ett slag mindre", systemImage: "minus.circle") { correction.step(-1) }
                        .labelStyle(.iconOnly)
                        .font(.dd(.sans, size: 28, relativeTo: .title))
                    Spacer()
                    VStack(spacing: 6) {
                        Text("\(correction.strokes)")
                            .font(.dd(.sans, size: 34, relativeTo: .largeTitle)).monospacedDigit()
                            .contentTransition(.numericText())
                        let outcome = correction.outcome(game)
                        HStack(spacing: 6) {
                            ScoreChip(name: outcome.name)
                            Text("\(outcome.points) p").font(.dd(.sans, size: 13, relativeTo: .footnote)).monospacedDigit()
                        }
                    }
                    Spacer()
                    Button("Ett slag mer", systemImage: "plus.circle") { correction.step(1) }
                        .labelStyle(.iconOnly)
                        .font(.dd(.sans, size: 28, relativeTo: .title))
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 4)
            } footer: {
                DDFooter("Dette er en retting. Tallet erstatter det som står, for alle med én gang, og det lagres hvem som rettet.")
            }

            if let notice = CorrectionNotice.text(for: game.status) {
                Section {
                    Label(notice, systemImage: "lock")
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                }
            }

            Section {
                Button(correction.buttonTitle(game)) { save() }
                    .disabled(!correction.isChanged || isBusy)
            } footer: {
                if !correction.isChanged { Text("Ingen endring.") }
            }
        }
        .disabled(isBusy)
        .navigationTitle("Rett en score")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
        }
        .onChange(of: member) { reset() }
        .onChange(of: hole) { reset() }
        .alert("Det gikk ikke", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func reset() {
        correction = ScoreCorrection(game: game, member: member, hole: hole)
    }

    private func save() {
        isBusy = true
        let correction = correction
        Task {
            defer { isBusy = false }
            do {
                let text = try await model.correct(correction, submitter: submitter)
                onDone(text)
                dismiss()
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
