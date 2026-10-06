import SwiftUI

struct CreateClubView: View {
    let user: AuthUser
    @Environment(ClubModel.self) private var club

    @State private var clubName = ""
    @State private var displayName = ""
    @State private var handicapText = ""
    @State private var isBusy = false
    @State private var error: ClubError?

    var body: some View {
        DDForm {
            DDSection("Klubben") {
                TextField("Navn på klubben", text: $clubName)
                    .textInputAutocapitalization(.words)
            }
            Section {
                TextField("Ditt navn", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                TextField("Handicapindeks (valgfritt)", text: $handicapText)
                    .keyboardType(.numbersAndPunctuation)
            } header: {
                DDHeader("Deg")
            } footer: {
                DDFooter("Navnet er det de andre ser i troppen. Plusshandicap skrives med «+».")
            }
            if let error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
            Section {
                Button(action: create) {
                    HStack {
                        Text("Lag klubben")
                        if isBusy {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
            }
        }
        .navigationTitle("Ny klubb")
        .ddNavigationChrome()
        .disabled(isBusy)
    }

    private func create() {
        guard let name = ClubInput.normalizedName(clubName, maxLength: 60) else {
            error = .invalidInput("Skriv inn et navn på klubben.")
            return
        }
        guard let me = ClubInput.normalizedName(displayName) else {
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
        error = nil
        isBusy = true
        Task {
            do {
                try await club.createClub(name: name, displayName: me, handicapIndex: handicap, userID: user.id)
            } catch {
                self.error = (error as? ClubError) ?? .unknown(error.localizedDescription)
            }
            isBusy = false
        }
    }
}
