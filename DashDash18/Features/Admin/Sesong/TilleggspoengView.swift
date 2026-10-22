import GolfgutuCore
import SwiftUI

/// «Tilleggspoeng» i en turnering (sql/072): poeng arrangøren gir for hånd, med en grunn. De legges
/// på totalen i tabellen, og grunnen står på spillerens profil i Tavla.
struct TilleggspoengView: View {
    @Environment(\.clubContext) private var context
    let season: SeasonRow

    var body: some View {
        if let context {
            TilleggspoengRoot(context: context, season: season)
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "plus.forwardslash.minus")
                .navigationTitle("Tilleggspoeng")
                .ddNavigationChrome()
        }
    }
}

private struct TilleggspoengRoot: View {
    @State private var model: TilleggspoengModel

    init(context: ClubContext, season: SeasonRow) {
        _model = State(initialValue: TilleggspoengModel(context: context, season: season))
    }

    var body: some View {
        TilleggspoengList(model: model)
    }
}

/// Lista over tilleggspoengene, med «Legg til» og sletting.
struct TilleggspoengList: View {
    let model: TilleggspoengModel
    @State private var adding: TilleggspoengDraft?
    @State private var pendingDelete: PointAdjustmentRow?
    @State private var error: DataError?

    var body: some View {
        content
            .navigationTitle("Tilleggspoeng")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Legg til", systemImage: "plus") { adding = TilleggspoengDraft() }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
            .sheet(isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
                NavigationStack {
                    TilleggspoengEditor(model: model, draft: adding ?? TilleggspoengDraft()) { adding = nil }
                }
            }
            .confirmationDialog("Slette tilleggspoenget?",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { row in
                Button("Slett", role: .destructive) { delete(row) }
            } message: { row in
                Text("\(model.name(row.memberID)) mister \(model.pointsText(row.points)) i tabellen.")
            }
    }

    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading where model.rows.isEmpty:
            ProgressView()
        case .failed(let error) where model.rows.isEmpty:
            ContentUnavailableView {
                Label("Fikk ikke hentet tilleggspoengene", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
            }
        default:
            list
        }
    }

    private var list: some View {
        DDList {
            if let error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
            Section {
                if model.rows.isEmpty {
                    Text("Ingen tilleggspoeng ennå.")
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(model.rows) { row in
                    line(row)
                        .swipeActions {
                            Button("Slett", systemImage: "trash", role: .destructive) { pendingDelete = row }
                        }
                }
                Button("Legg til tilleggspoeng", systemImage: "plus") { adding = TilleggspoengDraft() }
            } footer: {
                DDFooter("Poeng du gir for hånd, for eksempel fra en konkurranse utenfor appen. De legges på totalen i tabellen, og grunnen vises for spillerne.")
            }
        }
    }

    private func line(_ row: PointAdjustmentRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.name(row.memberID))
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text([row.reason, model.eventText(row.eventID)].compactMap { $0 }.joined(separator: " · "))
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            Text(model.pointsText(row.points))
                .font(.ddNumber)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func delete(_ row: PointAdjustmentRow) {
        error = nil
        Task {
            do {
                try await model.delete(row)
            } catch {
                self.error = DataError.from(error)
            }
        }
    }
}

/// Nytt tilleggspoeng: spiller, poeng, grunn og (valgfritt) kvelden.
struct TilleggspoengEditor: View {
    @Environment(\.dayTerm) private var dayTerm
    let model: TilleggspoengModel
    @State var draft: TilleggspoengDraft
    let done: () -> Void
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        DDForm {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }

            Section {
                Picker("Spiller", selection: $draft.memberID) {
                    Text("Velg").tag(UUID?.none)
                    ForEach(model.members) { member in
                        Text(member.displayName).tag(Optional(member.id))
                    }
                }
                Stepper(value: $draft.points, in: Tilleggspoeng.pointsRange, step: Tilleggspoeng.step) {
                    LabeledContent("Poeng", value: model.pointsText(draft.points))
                }
                TextField("Grunn", text: $draft.reason)
                    .textInputAutocapitalization(.sentences)
            } footer: {
                DDFooter("Grunnen vises for spillerne, for eksempel «CP knockout challenge». Minuspoeng trekkes fra.")
            }

            if !model.events.isEmpty {
                Section {
                    Picker(DayTerm.capitalized(dayTerm.one), selection: $draft.eventID) {
                        Text("Ingen").tag(UUID?.none)
                        ForEach(model.events) { event in
                            Text(EveningDates.dayMonthText(event.eventDate)).tag(Optional(event.id))
                        }
                    }
                } footer: {
                    DDFooter("Valgfritt. Vises ved siden av grunnen.")
                }
            }
        }
        .navigationTitle("Nytt tilleggspoeng")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .interactiveDismissDisabled(isBusy)
        .toolbar {
            DDCancelToolbarItem {
                Button("Avbryt", action: done)
            }
            DDConfirmToolbarItem {
                if isBusy {
                    ProgressView()
                } else {
                    Button("Lagre", action: save)
                        .disabled(draft.problem != nil)
                }
            }
        }
    }

    private func save() {
        error = nil
        isBusy = true
        Task {
            do {
                try await model.add(draft)
                done()
            } catch {
                self.error = DataError.from(error).message
            }
            isBusy = false
        }
    }
}

#if DEBUG
#Preview("Tilleggspoeng") {
    let club = UUID(), season = UUID()
    let members = ["Næsset", "Rostad", "Strypet", "JonasH"].map {
        ClubMemberRow(id: UUID(), clubID: club, userID: nil, displayName: $0, handicapIndex: nil, seedGroup: nil,
                      isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
    }
    let row = SeasonRow(id: season, clubID: club, name: "Golfgutu Invitational 2026", status: .active, rules: .golfgutu)
    let rows = zip(members, [1.0, 1, 0.5, 0.5]).map { member, points in
        PointAdjustmentRow(id: UUID(), clubID: club, seasonID: season, memberID: member.id, eventID: nil,
                           points: points, reason: "CP knockout challenge")
    }
    return NavigationStack {
        TilleggspoengList(model: TilleggspoengModel(preview: row, rows: rows, members: members))
    }
}
#endif
