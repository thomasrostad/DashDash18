import GolfgutuCore
import SwiftUI

/// Troppen: arrangørens oversikt over spillerne i klubben.
struct TroppAdminView: View {
    @Environment(\.clubContext) private var context
    @State private var model: TroppModel?

    var body: some View {
        Group {
            if let model {
                TroppListView(model: model)
            } else {
                ContentUnavailableView("Ingen klubb", systemImage: "person.3", description: Text("Velg en klubb først."))
            }
        }
        .navigationTitle("Troppen")
        .ddNavigationChrome()
        .task(id: context?.clubID) {
            guard let context else { return }
            let model = TroppModel(context: context)
            self.model = model
            await model.load()
        }
    }
}

private struct TroppListView: View {
    @Bindable var model: TroppModel
    @State private var isAdding = false

    var body: some View {
        let sections = model.sections
        DDList {
            if !sections.pending.isEmpty {
                Section {
                    ForEach(sections.pending) { row in
                        memberLink(row)
                            .swipeActions(edge: .leading) {
                                Button("Godkjenn") { run(.approve, row) }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Avvis", role: .destructive) { run(.reject, row) }
                            }
                    }
                } header: {
                    DDHeader("Venter på godkjenning")
                } footer: {
                    DDFooter("Sveip mot høyre for å godkjenne, mot venstre for å avvise.")
                }
            }
            Section {
                ForEach(sections.active) { row in memberLink(row) }
            } header: {
                DDHeader("Aktive (\(sections.active.count))")
            } footer: {
                DDFooter("Navn uten innlogging kan tas av spilleren med invitasjonskoden.")
            }
            if !sections.archived.isEmpty {
                DDSection("Arkivert") {
                    ForEach(sections.archived) { row in memberLink(row) }
                }
            }
        }
        .overlay {
            if model.isLoading && !model.hasLoaded { ProgressView() }
        }
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: {
                    Label("Legg til navn", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            TroppAddView(model: model)
        }
        .troppErrorAlert(model: model, isActive: !isAdding)
    }

    private func memberLink(_ row: ClubMemberRow) -> some View {
        NavigationLink {
            TroppMemberView(model: model, memberID: row.id)
        } label: {
            TroppRowLabel(row: row, isMe: row.id == model.context.memberID, groups: model.seedGroups)
        }
        .disabled(model.isBusy(row.id))
    }

    private func run(_ action: TroppAction, _ row: ClubMemberRow) {
        Task { await model.perform(action, on: row.id) }
    }
}

private struct TroppRowLabel: View {
    let row: ClubMemberRow
    let isMe: Bool
    let groups: [SeedingGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.displayName)
                if isMe { Text("(deg)").foregroundStyle(Color.ddInkSecondary) }
            }
            let details = TroppDisplay.details(for: row, groups: groups)
            if !details.isEmpty {
                Text(details)
                    .font(.dd(.sans, size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
    }
}

extension View {
    /// Viser feilen fra troppen som et varsel. `isActive` er false når et ark ligger
    /// over og viser feilen selv, så ikke to varsler kjemper om samme feil.
    func troppErrorAlert(model: TroppModel, isActive: Bool = true) -> some View {
        alert(
            "Noe gikk galt",
            isPresented: Binding(get: { isActive && model.error != nil }, set: { if !$0 { model.error = nil } }),
            presenting: model.error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}
