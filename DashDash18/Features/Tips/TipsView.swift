import GolfgutuCore
import SwiftUI

/// Tippekupongen for én kveld: fem spørsmål mens den er åpen, alles kuponger når den er låst,
/// og fasit og resultatliste når kvelden er ferdig.
struct TipsView: View {
    let eventID: UUID
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            TipsContent(model: TipsModel(context: context, eventID: eventID))
        } else {
            ContentUnavailableView("Ikke logget inn", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

private struct TipsContent: View {
    @State var model: TipsModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle("Tippekupongen")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter kupongen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet kupongen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
            }
        case .loaded:
            if let board = model.board {
                List {
                    TipsHeader(board: board)
                    switch board.phase {
                    case .open:
                        TipsFormSections(model: model, board: board)
                        TipsSubmittedSection(board: board)
                        if board.isOrganizer { TipsSettingsSection(model: model, board: board) }
                    case .locked:
                        TipsAllSections(board: board)
                    case .finished:
                        TipsFinishedSections(board: board)
                    }
                }
            }
        }
    }
}

// MARK: - Hodet

private struct TipsHeader: View {
    let board: TipsBoard

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(EveningDates.longText(board.event.eventDate, capitalized: true))
                    .font(.title2.bold())
                Text(board.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(board.stakeText)
                    Spacer()
                    Text(board.potText).monospacedDigit()
                }
                .font(.footnote)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Åpen: skjemaet

private struct TipsFormSections: View {
    @Bindable var model: TipsModel
    let board: TipsBoard
    @State private var error: String?
    @State private var confirmWithdraw = false

    private var saved: TipsCoupon? { board.myCoupon }

    var body: some View {
        ForEach(Array(TipsQuestion.allCases.enumerated()), id: \.element) { index, q in
            Section {
                answerControl(q)
            } header: {
                Text("\(index + 1) / \(TipsQuestion.allCases.count)")
            } footer: {
                Text(q.subtitle)
            }
        }
        Section {
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    Spacer()
                    if model.isSaving {
                        ProgressView()
                    } else {
                        if saved != nil && !model.draft.isChanged(from: saved) {
                            Image(systemName: "checkmark")
                        }
                        Text(model.draft.buttonTitle(saved: saved)).bold()
                    }
                    Spacer()
                }
            }
            .disabled(model.isSaving || !model.draft.canSubmit(saved: saved))
            if saved != nil {
                Button("Trekk kupongen …", role: .destructive) { confirmWithdraw = true }
                    .disabled(model.isSaving)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error { Text(error).foregroundStyle(.red) }
                Text(hint)
            }
        }
        .confirmationDialog("Trekke kupongen?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Trekk kupongen", role: .destructive) { Task { await withdraw() } }
        } message: {
            Text("Du kan levere en ny til \(board.deadlineText).")
        }
    }

    private var hint: String {
        let n = model.draft.coupon.answeredCount, total = TipsQuestion.allCases.count
        if n < total { return "\(n) av \(total) besvart." }
        return (saved != nil ? "Du kan endre svarene til \(board.deadlineText). " : "")
            + "De andre ser kupongen din først når den er låst."
    }

    @ViewBuilder
    private func answerControl(_ q: TipsQuestion) -> some View {
        switch q.kind {
        case .player:
            Picker(board.title(q), selection: playerBinding(q)) {
                Text("Velg spiller").tag(UUID?.none)
                Section(board.otherCandidates.isEmpty ? "Troppen" : "Kommer") {
                    ForEach(board.firstCandidates) { c in Text(c.name).tag(UUID?.some(c.memberID)) }
                }
                if !board.otherCandidates.isEmpty {
                    Section("Ikke påmeldt") {
                        ForEach(board.otherCandidates) { c in Text(c.name).tag(UUID?.some(c.memberID)) }
                    }
                }
            }
            .pickerStyle(.navigationLink)
        case .yesNo, .overUnder:
            VStack(alignment: .leading, spacing: 8) {
                Text(board.title(q)).font(.headline)
                Picker(board.title(q), selection: flagBinding(q)) {
                    Text(q.kind == .yesNo ? "Ja" : "Over").tag(Bool?.some(true))
                    Text(q.kind == .yesNo ? "Nei" : "Under").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 2)
        }
    }

    private func playerBinding(_ q: TipsQuestion) -> Binding<UUID?> {
        Binding(
            get: { model.draft.coupon.player(q).flatMap(UUID.init(uuidString:)) },
            set: { if let id = $0 { model.draft.choose(q, player: id) } }
        )
    }

    private func flagBinding(_ q: TipsQuestion) -> Binding<Bool?> {
        Binding(
            get: { model.draft.coupon.flag(q) },
            set: { if let v = $0 { model.draft.set(q, v) } }
        )
    }

    private func submit() async {
        error = nil
        do { try await model.submit() } catch { self.error = error.message }
    }

    private func withdraw() async {
        error = nil
        do { try await model.withdraw() } catch { self.error = error.message }
    }
}

private struct TipsSubmittedSection: View {
    let board: TipsBoard

    var body: some View {
        if !board.submitted.isEmpty || !board.missing.isEmpty {
            Section("Levert · \(board.submitted.count)") {
                Text(board.submitted.isEmpty ? "Ingen ennå." : board.nameList(board.submitted))
                if !board.missing.isEmpty {
                    Text("Påmeldt, men ikke levert: \(board.nameList(board.missing))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Arrangøren

private struct TipsSettingsSection: View {
    let model: TipsModel
    let board: TipsBoard
    @State private var error: String?

    private var fixed: Bool { !board.canEditSettings }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Innsats per kupong").font(.subheadline.weight(.semibold))
                HStack {
                    ForEach(board.rules.tips.stakeOptions, id: \.self) { n in
                        Button(n > 0 ? "\(n)" : "Æra") { save(stake: n, line: board.line) }
                            .buttonStyle(.bordered)
                            .tint(n == board.stake ? .accentColor : .secondary)
                            .accessibilityAddTraits(n == board.stake ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)
            HStack {
                Text("Linja")
                Spacer()
                Button {
                    save(stake: board.stake, line: board.line - board.rules.tips.lineStep)
                } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered)
                    .disabled(fixed || !Tips.isValidLine(board.line - board.rules.tips.lineStep))
                    .accessibilityLabel("Senk linja")
                Text(Tips.formatSigned(board.line, decimals: 1))
                    .monospacedDigit()
                    .frame(minWidth: 56)
                Button {
                    save(stake: board.stake, line: board.line + board.rules.tips.lineStep)
                } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .disabled(fixed || !Tips.isValidLine(board.line + board.rules.tips.lineStep))
                    .accessibilityLabel("Hev linja")
            }
        } header: {
            Text("Arrangør")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error { Text(error).foregroundStyle(.red) }
                Text(fixed ? "Står fast nå som noen har levert – de tippet på det som sto."
                     : "Netto slag over par per ni hull. Kan endres til første kupong er levert.")
            }
        }
        .disabled(fixed || model.isSaving)
    }

    private func save(stake: Int, line: Double) {
        error = nil
        Task {
            do { try await model.saveSettings(stake: stake, line: line) } catch { self.error = DataError.from(error).message }
        }
    }
}

// MARK: - Låst og ferdig

/// «Dette tippet gjengen»: svarene per spørsmål, flest stemmer først.
private struct TipsAllSections: View {
    let board: TipsBoard

    var body: some View {
        if board.result.rows.isEmpty {
            Section {
                ContentUnavailableView("Ingen kuponger", systemImage: "ticket",
                                       description: Text("Ingen leverte kupong til denne kvelden."))
            }
        } else {
            ForEach(Array(TipsQuestion.allCases.enumerated()), id: \.element) { index, q in
                Section("\(index + 1). \(board.title(q))") {
                    ForEach(board.groups(q)) { g in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if g.correct == true {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                                Text(g.text).bold()
                                Spacer()
                                Text("\(g.memberIDs.count) tips").font(.footnote).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(g.memberIDs.map { $0 == board.me ? "deg" : board.shortName($0) }.joined(separator: ", "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private struct TipsFinishedSections: View {
    let board: TipsBoard
    @State private var showAll = false

    var body: some View {
        if board.result.rows.isEmpty {
            Section {
                ContentUnavailableView("Ingen kuponger", systemImage: "ticket",
                                       description: Text("Ingen leverte kupong til denne kvelden."))
            }
        } else {
            Section("Tippekongen") {
                HStack(spacing: 12) {
                    Text("👑").font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text(board.nameList(board.result.winners)).font(.title3.bold())
                        Text(board.kingText).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                ForEach(Array(board.result.rows.enumerated()), id: \.element.playerID) { i, row in
                    resultRow(row, showPlace: i == 0 || board.result.rows[i - 1].points != row.points)
                }
            } header: {
                Text("Resultatliste")
            } footer: {
                Text("Merkene er spørsmål 1–5 i rekkefølge. Ett poeng per riktig svar"
                     + (board.result.possible < TipsQuestion.allCases.count ? "; · er strøket og teller ikke for noen." : "."))
            }
            Section("Fasit") {
                ForEach(TipsQuestion.allCases) { q in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(board.title(q)).font(.footnote).foregroundStyle(.secondary)
                        Text(board.answerKeyText(q))
                    }
                }
            }
            Section {
                Button(showAll ? "Skjul hva alle tippet" : "Vis hva alle tippet") { showAll.toggle() }
            }
            if showAll { TipsAllSections(board: board) }
        }
    }

    private func resultRow(_ row: TipsResult.Row, showPlace: Bool) -> some View {
        let id = UUID(uuidString: row.playerID)
        let isMe = id == board.me
        return HStack {
            Text(showPlace ? "\(board.place(of: row))." : "")
                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            Text(board.shortName(row.playerID) + (board.result.winners.contains(row.playerID) ? " 👑" : ""))
                .fontWeight(isMe ? .semibold : .regular)
            Spacer()
            HStack(spacing: 4) {
                ForEach(TipsQuestion.allCases) { q in
                    let v = row.correct[q] ?? nil
                    Text(v == nil ? "·" : (v! ? "✓" : "✗"))
                        .foregroundStyle(v == nil ? Color.secondary : (v! ? Color.green : Color.red))
                        .frame(width: 14)
                }
            }
            .font(.footnote.monospaced())
            Text("\(row.points)").font(.body.monospacedDigit().weight(.medium)).frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
