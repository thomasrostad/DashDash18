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
        if !preview.openMembers.isEmpty {
            Section {
                ForEach(preview.openMembers) { member in
                    Button {
                        join(memberID: member.id)
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
            DDFooter("Arrangøren må godkjenne deg før du ser noe.")
        }
        Section {
            Button("Bruk en annen kode") {
                self.preview = nil
                error = nil
            }
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
        run {
            try await club.join(code: code, memberID: memberID, displayName: nil, handicapIndex: nil, userID: user.id)
        }
    }

    private func joinAsNew() {
        guard let name = ClubInput.normalizedName(newName) else {
            error = .invalidInput("Skriv inn navnet ditt (høyst 40 tegn).")
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
            try await club.join(code: code, memberID: nil, displayName: name, handicapIndex: handicap, userID: user.id)
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
