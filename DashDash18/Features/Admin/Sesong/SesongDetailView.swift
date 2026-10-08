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
            ContentUnavailableView("Sesongen finnes ikke lenger", systemImage: "list.number")
        }
    }
}

/// Innholdet til én sesong: sammendraget av reglene, «Endre reglene», status og handlingene.
/// Brukes av `SesongDetailView` og av «Sesong og regler» når den lander på den aktive sesongen,
/// som viser navnet på sesongen og legger egne seksjoner nederst (`bottom`).
struct SesongContentView<Bottom: View>: View {
    let model: SesongAdminModel
    let season: SeasonRow
    let showsName: Bool
    let bottom: Bottom
    @Environment(\.dismiss) private var dismiss

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
                    Text("Sesongen er i gang. Endrede regler gjelder hele sesongen, også kvelder som er spilt.")
                } else if season.status == .finished {
                    Text("Sesongen er ferdig. Reglene kan ikke endres.")
                }
            }
            Section {
                if showsName {
                    LabeledContent("Sesong", value: season.name)
                }
                LabeledContent("Status", value: SeasonLifecycle.title(season.status))
                ForEach(SeasonLifecycle.actions(for: season.status), id: \.self) { action in
                    actionButton(action, season)
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
            .confirmationDialog("Avslutte den aktive sesongen?", isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } }),
                                titleVisibility: .visible, presenting: conflict) { other in
                Button("Avslutt «\(other.name)» og aktiver") {
                    conflict = nil
                    run { try await model.activate(season, finishing: other) }
                }
                Button("Avbryt", role: .cancel) { conflict = nil }
            } message: { other in
                Text("Klubben kan ha én aktiv sesong. «\(other.name)» blir ferdig.")
            }
            .confirmationDialog("Avslutte sesongen?", isPresented: $confirmsFinish, titleVisibility: .visible) {
                Button("Avslutt sesongen") { run { try await model.finish(season) } }
            } message: {
                Text("Sesongen blir ferdig, og reglene låses.")
            }
            .confirmationDialog("Slette sesongen?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Slett", role: .destructive) {
                    run {
                        try await model.delete(season)
                        dismiss()
                    }
                }
            } message: {
                Text("Sesongen og reglene forsvinner. Det kan ikke angres.")
            }
    }

    @ViewBuilder
    private func actionButton(_ action: SeasonLifecycle.Action, _ season: SeasonRow) -> some View {
        switch action {
        case .activate:
            Button(season.status == .finished ? "Aktiver igjen" : "Aktiver sesongen") {
                if let other = SeasonLifecycle.activeConflict(activating: season, in: model.seasons) {
                    conflict = other
                } else {
                    run { try await model.activate(season, finishing: nil) }
                }
            }
        case .finish:
            Button("Avslutt sesongen") { confirmsFinish = true }
        case .delete:
            Button("Slett sesongen", role: .destructive) { confirmsDelete = true }
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
