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
            .ddNavigationChrome()
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
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if let board = model.board {
                DDList {
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
            // Grønt hero-kort øverst, som kveldskortet i PWA-en.
            VStack(alignment: .leading, spacing: 8) {
                Text("Tippekupongen").ddEyebrow(color: .ddGold)
                Text(EveningDates.longText(board.event.eventDate, capitalized: true))
                    .font(.ddTitle)
                Text(board.statusText)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddOnDark.opacity(0.8))
                DDDivider(onDark: true)
                    .padding(.vertical, 4)
                HStack(alignment: .firstTextBaseline) {
                    Text(board.stakeText)
                        .font(.ddCallout)
                    Spacer(minLength: 8)
                    Text(board.potText)
                        .font(.ddNumber)
                        .monospacedDigit()
                        .foregroundStyle(Color.ddGold)
                }
            }
            .foregroundStyle(Color.ddOnDark)
            .padding(.vertical, 10)
            .accessibilityElement(children: .combine)
            .listRowBackground(Color.ddHeroCard)
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
                DDHeader("\(index + 1) / \(TipsQuestion.allCases.count)")
            } footer: {
                DDFooter(q.subtitle)
            }
        }
        Section {
            VStack(spacing: 10) {
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isSaving {
                            ProgressView()
                        } else {
                            if saved != nil && !model.draft.isChanged(from: saved) {
                                Image(systemName: "checkmark")
                            }
                            Text(model.draft.buttonTitle(saved: saved))
                        }
                    }
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .disabled(model.isSaving || !model.draft.canSubmit(saved: saved))
                if saved != nil {
                    Button("Trekk kupongen …", role: .destructive) { confirmWithdraw = true }
                        .buttonStyle(.dd(.danger, fullWidth: true))
                        .disabled(model.isSaving)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error { Text(error).ddErrorStyle() }
                DDFooter(hint)
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
            VStack(alignment: .leading, spacing: 10) {
                Text(board.title(q))
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddForestInk)
                // To piller i stedet for systemets segmentvelger: valgt er grønn (golfee).
                HStack(spacing: 8) {
                    flagChoice(q, value: true, title: q.kind == .yesNo ? "Ja" : "Over")
                    flagChoice(q, value: false, title: q.kind == .yesNo ? "Nei" : "Under")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func flagChoice(_ q: TipsQuestion, value: Bool, title: String) -> some View {
        let binding = flagBinding(q)
        let selected = binding.wrappedValue == value
        return Button(title) { binding.wrappedValue = value }
            .buttonStyle(DDChoiceButtonStyle(selected: selected))
            .accessibilityLabel("\(board.title(q)): \(title)")
            .accessibilityAddTraits(selected ? .isSelected : [])
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
            DDSection("Levert · \(board.submitted.count)") {
                Text(board.submitted.isEmpty ? "Ingen ennå." : board.nameList(board.submitted))
                if !board.missing.isEmpty {
                    Text("Påmeldt, men ikke levert: \(board.nameList(board.missing))")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Innsats per kupong")
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddForestInk)
                HStack(spacing: 8) {
                    ForEach(board.rules.tips.stakeOptions, id: \.self) { n in
                        Button(n > 0 ? "\(n)" : "Æra") { save(stake: n, line: board.line) }
                            .buttonStyle(DDChoiceButtonStyle(selected: n == board.stake))
                            .accessibilityAddTraits(n == board.stake ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)
            HStack(spacing: 10) {
                Text("Linja")
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddForestInk)
                Spacer()
                Button {
                    save(stake: board.stake, line: board.line - board.rules.tips.lineStep)
                } label: { Image(systemName: "minus") }
                    .buttonStyle(DDStepperButtonStyle(kind: .minus, size: 44))
                    .disabled(fixed || !Tips.isValidLine(board.line - board.rules.tips.lineStep))
                    .accessibilityLabel("Senk linja")
                Text(Tips.formatSigned(board.line, decimals: 1))
                    .font(.ddNumberLarge)
                    .monospacedDigit()
                    .frame(minWidth: 56)
                Button {
                    save(stake: board.stake, line: board.line + board.rules.tips.lineStep)
                } label: { Image(systemName: "plus") }
                    .buttonStyle(DDStepperButtonStyle(kind: .plus, size: 44))
                    .disabled(fixed || !Tips.isValidLine(board.line + board.rules.tips.lineStep))
                    .accessibilityLabel("Hev linja")
            }
            .padding(.vertical, 4)
        } header: {
            DDHeader("Arrangør")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let error { Text(error).ddErrorStyle() }
                DDFooter(fixed ? "Står fast nå som noen har levert – de tippet på det som sto."
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
                DDSection("\(index + 1). \(board.title(q))") {
                    ForEach(board.groups(q)) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                if g.correct == true {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.ddLimeInk)
                                        .accessibilityLabel("Riktig")
                                }
                                Text(g.text)
                                    .font(.ddBodyEmphasis)
                                    .foregroundStyle(Color.ddForestInk)
                                Spacer()
                                DDChip("\(g.memberIDs.count) tips", tone: g.correct == true ? .lime : .earth, compact: true)
                                    .monospacedDigit()
                            }
                            Text(g.memberIDs.map { $0 == board.me ? "deg" : board.shortName($0) }.joined(separator: ", "))
                                .font(.ddCaption)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                        .padding(.vertical, 2)
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
            Section {
                HStack(spacing: 14) {
                    Text("👑")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tippekongen").ddEyebrow(color: .ddGold)
                        Text(board.nameList(board.result.winners))
                            .font(.ddTitle)
                        Text(board.kingText)
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddOnDark.opacity(0.8))
                    }
                }
                .foregroundStyle(Color.ddOnDark)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.ddHeroCard)
            }
            Section {
                ForEach(Array(board.result.rows.enumerated()), id: \.element.playerID) { i, row in
                    resultRow(row, showPlace: i == 0 || board.result.rows[i - 1].points != row.points)
                }
            } header: {
                DDHeader("Resultatliste")
            } footer: {
                DDFooter("Merkene er spørsmål 1–5 i rekkefølge. Ett poeng per riktig svar"
                         + (board.result.possible < TipsQuestion.allCases.count ? "; · er strøket og teller ikke for noen." : "."))
            }
            DDSection("Fasit") {
                ForEach(TipsQuestion.allCases) { q in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(board.title(q))
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                        Text(board.answerKeyText(q))
                            .font(.ddBodyEmphasis)
                            .foregroundStyle(Color.ddForestInk)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button(showAll ? "Skjul hva alle tippet" : "Vis hva alle tippet") { showAll.toggle() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.ddForestInk)
            }
            if showAll { TipsAllSections(board: board) }
        }
    }

    private func resultRow(_ row: TipsResult.Row, showPlace: Bool) -> some View {
        let id = UUID(uuidString: row.playerID)
        let isMe = id == board.me
        return HStack(spacing: 10) {
            Text(showPlace ? "\(board.place(of: row))." : "")
                .font(.ddMonoSmall).monospacedDigit().foregroundStyle(Color.ddInkSecondary)
                .frame(width: 26, alignment: .leading)
            Text(board.shortName(row.playerID) + (board.result.winners.contains(row.playerID) ? " 👑" : ""))
                .font(isMe ? .ddBodyEmphasis : .ddBody)
                .foregroundStyle(Color.ddForestInk)
            if isMe {
                DDPill("Deg", tone: .gold).fixedSize()
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(TipsQuestion.allCases) { q in
                    let v = row.correct[q] ?? nil
                    Text(v == nil ? "·" : (v! ? "✓" : "✗"))
                        .foregroundStyle(v == nil ? Color.ddInkSecondary : (v! ? Color.ddLimeInk : Color.ddRustText))
                        .frame(width: 14)
                }
            }
            .font(.dd(.mono, size: 13, weight: .semibold, relativeTo: .footnote))
            Text("\(row.points)").font(.ddNumber).monospacedDigit().frame(width: 28, alignment: .trailing)
        }
        .listRowBackground(ZStack {
            Color.ddCard
            if isMe { Color.ddYouRow }
        })
        .accessibilityElement(children: .combine)
    }
}
