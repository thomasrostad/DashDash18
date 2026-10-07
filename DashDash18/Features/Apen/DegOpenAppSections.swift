import Supabase
import SwiftUI

/// Nederst under Deg (med og uten klubb): personvern og vilkår, blokkerte og «Slett konto».
/// Med flaggene av (og lenkene ikke publisert) vises ingenting, så Deg er som før.
struct DegOpenAppSections: View {
    let client: SupabaseClient?
    let user: AuthUser
    @Environment(ClubModel.self) private var club: ClubModel?
    @State private var showsDeletion = false

    var body: some View {
        if ModerationFeature.isEnabled, let client {
            Section {
                NavigationLink { BlockedUsersView(service: ModerationService(client: client)) } label: {
                    Label("Blokkerte", systemImage: "hand.raised")
                        .labelStyle(DDIconLabelStyle())
                }
            } footer: {
                DDFooter("De du har blokkert, ser du ikke i tråden, og de kan ikke legge deg til i runder.")
            }
        }
        if LegalLinks.isVisible {
            Section {
                LegalLinksRow()
                LabeledContent("Kontakt", value: LegalLinks.contactEmail)
            } header: {
                DDHeader("Personvern og vilkår")
            } footer: {
                DDFooter("Ingen reklame og ingen sporing. Dataene ligger hos Supabase i EU.")
            }
        }
        if AccountDeletionFeature.isEnabled, let client {
            Section {
                Button("Slett konto …", role: .destructive) { showsDeletion = true }
                    .foregroundStyle(Color.ddRustText)
            } footer: {
                DDFooter("Sletter innloggingen din og det du har lagt ut. Scorene står som «Slettet spiller».")
            }
            .sheet(isPresented: $showsDeletion) {
                AccountDeletionSheet(client: client, user: user, organizerClubs: organizerClubs)
            }
        }
    }
}

extension DegOpenAppSections {
    private var organizerClubs: [String] {
        (club?.memberships ?? []).filter { $0.isOrganizer && $0.status == .active }.map(\.club.name)
    }
}

/// «Slett konto»: hva som skjer, og bekreftelse med ordet SLETT.
struct AccountDeletionSheet: View {
    let client: SupabaseClient?
    let user: AuthUser
    /// Klubbene der du er arrangør (advarsel). Tom uten klubb.
    var organizerClubs: [String] = []
    @Environment(AuthModel.self) private var auth
    @Environment(OutboxStatus.self) private var outbox: OutboxStatus?
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var model: AccountDeletionModel?

    var body: some View {
        NavigationStack {
            DDList {
                Section {
                    VStack(alignment: .leading, spacing: DDSpacing.s) {
                        Text("Slette kontoen?")
                            .font(.ddTitle)
                            .foregroundStyle(Color.ddInk)
                            .accessibilityAddTraits(.isHeader)
                        Text(user.email.map { "Kontoen \($0) slettes for godt. Det kan ikke angres." }
                             ?? "Kontoen slettes for godt. Det kan ikke angres.")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    .padding(.vertical, DDSpacing.xs)
                }
                Section {
                    ForEach(AccountDeletion.consequences, id: \.self) { line in
                        Label(line, systemImage: "circle.fill")
                            .labelStyle(BulletLabelStyle())
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInk)
                    }
                } header: {
                    DDHeader("Dette skjer")
                }
                if let warning = AccountDeletion.organizerWarning(clubs: organizerClubs) {
                    Section { Label(warning, systemImage: "person.badge.key").ddWarningStyle() }
                }
                if let warning = AccountDeletion.pendingWarning(pending: outbox?.pendingCount ?? 0) {
                    Section { Label(warning, systemImage: "tray.and.arrow.up").ddWarningStyle() }
                }
                Section {
                    TextField("Skriv \(AccountDeletion.confirmationWord)", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Bekreft ved å skrive \(AccountDeletion.confirmationWord)")
                        .ddField()
                    Button {
                        Task { await model?.delete(typed: typed) }
                    } label: {
                        HStack(spacing: DDSpacing.s) {
                            Text("Slett kontoen for godt")
                            if model?.isDeleting == true { ProgressView() }
                        }
                    }
                    .buttonStyle(.dd(.dangerFinal, fullWidth: true))
                    .disabled(!AccountDeletion.isConfirmed(typed) || model?.isDeleting == true || client == nil)
                    if let error = model?.error {
                        Label(error.message, systemImage: "exclamationmark.triangle").ddErrorStyle()
                    }
                } header: {
                    DDHeader("Bekreft")
                } footer: {
                    DDFooter("Skriv \(AccountDeletion.confirmationWord) med store bokstaver for å slette.")
                }
            }
            .navigationTitle("Slett konto")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                        .tint(Color.ddOnDark)
                }
            }
            .task {
                if model == nil, let client { model = AccountDeletionModel(client: client, auth: auth) }
            }
        }
        .tint(Color.ddForestInk)
    }
}

/// Punktliste med en liten prikk.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            configuration.icon
                .font(.system(size: 6))
                .foregroundStyle(Color.ddRustText)
                .accessibilityHidden(true)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// «Blokkerte»: hvem du har blokkert, og opphev.
struct BlockedUsersView: View {
    let service: ModerationService?
    @State private var blocked: [BlockedUser]?
    @State private var error: String?

    init(service: ModerationService?, preview: [BlockedUser]? = nil) {
        self.service = service
        _blocked = State(initialValue: preview)
    }

    var body: some View {
        DDList {
            if let blocked, blocked.isEmpty {
                Section {
                    Text("Du har ikke blokkert noen.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            if let blocked, !blocked.isEmpty {
                Section {
                    ForEach(blocked) { person in
                        HStack {
                            DDAvatar(name: person.displayName, size: 30, image: nil)
                            Text(person.displayName)
                            Spacer()
                            Button("Opphev") { unblock(person) }
                                .buttonStyle(.dd(.text, compact: true))
                        }
                    }
                } footer: {
                    DDFooter("Den du blokkerer, får ikke vite det. Opphever du, ser du meldingene deres igjen.")
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle() }
            }
        }
        .overlay { if blocked == nil { ProgressView() } }
        .navigationTitle("Blokkerte")
        .ddNavigationChrome()
        .task { await load() }
    }

    private func load() async {
        guard let service else { return }
        do { blocked = try await service.myBlocks() } catch { self.error = DataError.from(error).message; blocked = blocked ?? [] }
    }

    private func unblock(_ person: BlockedUser) {
        guard let service else { blocked?.removeAll { $0.id == person.id }; return }
        Task {
            do {
                try await service.unblock(person.blockedID)
                blocked?.removeAll { $0.id == person.id }
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
