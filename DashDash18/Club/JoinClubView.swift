import SwiftUI

/// Bli med i en klubb: kode → velg ditt navn i troppen, eller be om å bli med som ny.
struct JoinClubView: View {
    let user: AuthUser
    @Environment(ClubModel.self) private var club

    @State private var codeText = ""
    @State private var preview: ClubPreview?
    @State private var code = ""
    @State private var newName = ""
    @State private var handicapText = ""
    @State private var isBusy = false
    @State private var error: ClubError?
    /// Navnet som venter på «Ja, det er meg».
    @State private var claiming: ClubPreview.OpenMember?

    var body: some View {
        DDForm {
            if let preview {
                previewSections(preview)
            } else {
                codeSection
            }
            if let error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
        }
        .navigationTitle(preview?.name ?? "Bli med")
        .ddNavigationChrome()
        .disabled(isBusy)
        // Et feiltrykk kobler deg til en annens navn, og bare arrangøren kan løse det opp.
        .confirmationDialog(
            claiming.map { "Er du \($0.displayName)?" } ?? "",
            isPresented: Binding(get: { claiming != nil }, set: { if !$0 { claiming = nil } }),
            titleVisibility: .visible,
            presenting: claiming
        ) { member in
            Button("Ja, jeg er \(member.displayName)") { join(memberID: member.id) }
            Button("Avbryt", role: .cancel) {}
        } message: { _ in
            Text("Du blir koblet til navnet og er med med én gang. Velger du feil, må arrangøren frigjøre det.")
        }
    }

    private var codeSection: some View {
        Section {
            TextField("Invitasjonskode", text: $codeText)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.dd(.mono, size: 14, relativeTo: .body))
                .onSubmit(lookUp)
            Button(action: lookUp) {
                busyLabel("Finn klubben")
            }
        } footer: {
            DDFooter("Koden får du av arrangøren, f.eks. «A1B2C3D4E5».")
        }
    }

    @ViewBuilder
    private func previewSections(_ preview: ClubPreview) -> some View {
        if preview.myStatus == .archived {
            Section {
                Label("Du er arkivert i \(preview.name). Be arrangøren gjenopprette deg i troppen.", systemImage: "archivebox")
            } footer: {
                loggedInFooter
            }
        } else {
            joinSections(preview)
        }
        Section {
            Button("Bruk en annen kode") {
                self.preview = nil
                error = nil
            }
        }
    }

    @ViewBuilder
    private func joinSections(_ preview: ClubPreview) -> some View {
        if !preview.openMembers.isEmpty {
            Section {
                ForEach(preview.sortedOpenMembers) { member in
                    Button {
                        claiming = member
                    } label: {
                        Label(member.displayName, systemImage: "person")
                    }
                }
            } header: {
                DDHeader("Er du en av disse?")
            } footer: {
                DDFooter("Trykk på navnet ditt. Da er du med med én gang.")
            }
        }
        Section {
            TextField("Ditt navn", text: $newName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            TextField("Handicapindeks (valgfritt)", text: $handicapText)
                .keyboardType(.numbersAndPunctuation)
            Button { joinAsNew() } label: {
                busyLabel("Be om å bli med")
            }
        } header: {
            DDHeader(preview.openMembers.isEmpty ? "Bli med som ny" : "Står du ikke på lista?")
        } footer: {
            VStack(alignment: .leading, spacing: DDSpacing.s) {
                DDFooter("Arrangøren må godkjenne deg før du ser noe.")
                loggedInFooter
            }
        }
    }

    /// Navnet ditt henger på innloggingen. Står det som tatt, er det ofte en annen e-post.
    @ViewBuilder
    private var loggedInFooter: some View {
        if let email = user.email {
            DDFooter("Logget inn som \(email). Står navnet ditt ikke som ledig, har du kanskje brukt en annen e-post før.")
        }
    }

    private func busyLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            if isBusy {
                Spacer()
                ProgressView()
            }
        }
    }

    private func lookUp() {
        guard let normalized = ClubInput.normalizedJoinCode(codeText) else {
            error = .invalidInput("Koden er 6–16 bokstaver og tall.")
            return
        }
        run {
            preview = try await club.preview(code: normalized)
            code = normalized
        }
    }

    private func join(memberID: UUID) {
        let code = code
        error = nil
        isBusy = true
        Task {
            do {
                try await club.join(code: code, memberID: memberID, displayName: nil, handicapIndex: nil, userID: user.id)
            } catch {
                let failure = (error as? ClubError) ?? .unknown(error.localizedDescription)
                self.error = failure
                // Noen rakk det først: vis lista slik den er nå.
                if failure == .nameTaken, let fresh = try? await club.preview(code: code) {
                    preview = fresh
                }
            }
            isBusy = false
        }
    }

    private func joinAsNew() {
        guard let name = ClubInput.normalizedName(newName) else {
            error = .invalidInput("Skriv inn navnet ditt (høyst 40 tegn).")
            return
        }
        if let conflict = ClubInput.openNameConflict(name, openMembers: preview?.openMembers ?? []) {
            error = conflict
            return
        }
        let handicap: Double?
        switch ClubInput.handicapIndex(handicapText) {
        case .success(let value): handicap = value
        case .failure(let failure):
            error = failure
            return
        }
        run {
            do {
                try await club.join(code: code, memberID: nil, displayName: name, handicapIndex: handicap, userID: user.id)
            } catch ClubError.duplicateName {
                throw ClubInput.nameTakenByOtherLogin(name)
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        isBusy = true
        Task {
            do {
                try await action()
            } catch {
                self.error = (error as? ClubError) ?? .unknown(error.localizedDescription)
            }
            isBusy = false
        }
    }
}
