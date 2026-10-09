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
    /// Avvis spør først, som på spillersiden.
    @State private var rejecting: ClubMemberRow?

    var body: some View {
        let sections = model.sections
        DDList {
            TroppInviteSection(club: model.context.membership.club)
            if !sections.pending.isEmpty {
                Section {
                    ForEach(sections.pending) { row in
                        memberLink(row)
                            .swipeActions(edge: .leading) {
                                Button("Godkjenn") { run(.approve, row) }.tint(.green)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Avvis", role: .destructive) { rejecting = row }
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
        .confirmationDialog(
            rejecting.map { "Avvise \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { rejecting != nil }, set: { if !$0 { rejecting = nil } }),
            titleVisibility: .visible,
            presenting: rejecting
        ) { row in
            Button("Avvis", role: .destructive) { run(.reject, row) }
            Button("Avbryt", role: .cancel) {}
        } message: { _ in
            Text("Raden arkiveres og innloggingen frigjøres, så personen kan prøve igjen med riktig navn.")
        }
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

/// Invitasjonskoden øverst i troppen: den nye spillere trenger for å bli med eller ta et ledig navn.
private struct TroppInviteSection: View {
    let club: Membership.ClubInfo

    var body: some View {
        if let code = club.joinCode, let text = TroppInvite.shareText(clubName: club.name, code: code) {
            Section {
                LabeledContent("Invitasjonskode") {
                    Text(code)
                        .font(.dd(.mono, size: 15, weight: .medium, relativeTo: .body))
                        .tracking(1)
                        .foregroundStyle(Color.ddForestInk)
                        .textSelection(.enabled)
                }
                ShareLink("Del invitasjonen", item: text)
                    .fontWeight(.medium)
            } header: {
                DDHeader("Invitasjon")
            } footer: {
                DDFooter("Invitasjonen har både lenke og kode. Med appen trykker de på lenken; ellers skriver de koden. Du godkjenner nye her.")
            }
        }
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
