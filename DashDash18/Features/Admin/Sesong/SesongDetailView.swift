import GolfgutuCore
import SwiftUI

/// Én sesong: sammendraget av reglene øverst, så «Endre reglene» og statusen.
struct SesongDetailView: View {
    let model: SesongAdminModel
    let seasonID: UUID

    var body: some View {
        if let season = model.season(id: seasonID) {
            SesongContentView(model: model, season: season)
                .navigationTitle(season.name)
                .ddNavigationChrome()
        } else {
            ContentUnavailableView("Turneringen finnes ikke lenger", systemImage: "trophy")
        }
    }
}

/// Innholdet til én sesong: sammendraget av reglene, «Endre reglene», status og handlingene.
/// Brukes av `SesongDetailView` og av «Turneringen» når den lander på den aktive sesongen,
/// som viser navnet på sesongen og legger egne seksjoner nederst (`bottom`).
struct SesongContentView<Bottom: View>: View {
    let model: SesongAdminModel
    let season: SeasonRow
    let showsName: Bool
    let bottom: Bottom
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dayTerm) private var dayTerm
    @State private var confirmsDeleteAll = false

    @State private var isBusy = false
    @State private var error: DataError?
    @State private var conflict: SeasonRow?
    @State private var confirmsFinish = false
    @State private var confirmsDelete = false

    init(model: SesongAdminModel, season: SeasonRow, showsName: Bool = false, @ViewBuilder bottom: () -> Bottom) {
        self.model = model
        self.season = season
        self.showsName = showsName
        self.bottom = bottom()
    }

    var body: some View {
        dialogs(list(season), season)
            .disabled(isBusy)
    }

    private func list(_ season: SeasonRow) -> some View {
        DDList {
            RulesetSummarySection(rules: season.rules)
            Section {
                NavigationLink {
                    RulesetEditorView(model: model, season: season)
                } label: {
                    Label(season.status == .finished ? "Se reglene" : "Endre reglene", systemImage: "slider.horizontal.3")
                }
            } footer: {
                if season.status == .active {
                    Text("Endrede regler gjelder også kvelder som er spilt.")
                } else if season.status == .finished {
                    Text("Turneringen er ferdig. Reglene kan ikke endres.")
                }
            }
            Section {
                if showsName {
                    LabeledContent("Turnering", value: season.name)
                }
                LabeledContent("Type", value: TournamentSetup.typeText(kind: .season, rules: season.rules))
                LabeledContent("Status", value: SeasonLifecycle.title(season.status))
                ForEach(SeasonLifecycle.actions(for: season.status).filter {
                    !(TournamentDeletionFeature.isEnabled && $0 == .delete)
                }, id: \.self) { action in
                    actionButton(action, season)
                }
            }
            // sql/038: hele turneringen kan slettes, også når den er spilt.
            if TournamentDeletionFeature.isEnabled {
                Section {
                    Button("Slett turneringen …", role: .destructive) { confirmsDeleteAll = true }
                } footer: {
                    Text("Sletter \(dayTerm.theMany), rundene og resultatene. Kan ikke angres.")
                }
            }
            if let error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
            bottom
        }
    }

    private func dialogs(_ view: some View, _ season: SeasonRow) -> some View {
        view
            .confirmationDialog("Avslutte turneringen som er i gang?", isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }),
                                titleVisibility: .visible, presenting: conflict) { other in
                Button("Avslutt «\(other.name)» og aktiver") {
                    conflict = nil
                    run { try await model.activate(season) }
                }
                Button("Avbryt", role: .cancel) { conflict = nil }
            } message: { other in
                Text("Klubben kan ha én serie i gang. «\(other.name)» blir ferdig.")
            }
            .confirmationDialog("Avslutte turneringen?", isPresented: $confirmsFinish, titleVisibility: .visible) {
                Button("Avslutt turneringen") { run { try await model.finish(season) } }
            } message: {
                Text("Turneringen blir ferdig, og reglene låses.")
            }
            .deleteTournamentAlert(isPresented: $confirmsDeleteAll, name: season.name) { typed in
                run {
                    _ = try await model.deleteTournament(season, confirmName: typed)
                    dismiss()
                }
            }
            .confirmationDialog("Slette turneringen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Slett", role: .destructive) {
                    run {
                        try await model.delete(season)
                        dismiss()
                    }
                }
            } message: {
                Text("Turneringen og reglene forsvinner. Det kan ikke angres.")
            }
    }

    @ViewBuilder
    private func actionButton(_ action: SeasonLifecycle.Action, _ season: SeasonRow) -> some View {
        switch action {
        case .activate:
            Button(season.status == .finished ? "Aktiver igjen" : "Aktiver turneringen") {
                if let other = SeasonLifecycle.activeConflict(activating: season, in: model.seasons) {
                    conflict = other
                } else {
                    run { try await model.activate(season) }
                }
            }
        case .finish:
            Button("Avslutt turneringen") { confirmsFinish = true }
        case .delete:
            Button("Slett turneringen", role: .destructive) { confirmsDelete = true }
        }
    }

    private func run(_ body: @escaping () async throws -> Void) {
        error = nil
        isBusy = true
        Task {
            do {
                try await body()
            } catch {
                self.error = DataError.from(error)
            }
            isBusy = false
        }
    }
}

extension SesongContentView where Bottom == EmptyView {
    init(model: SesongAdminModel, season: SeasonRow) {
        self.init(model: model, season: season) { EmptyView() }
    }
}
