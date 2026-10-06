import SwiftUI

/// Innlogging med engangskode på e-post. Apple og Google kommer i neste steg.
struct LoginView: View {
    @Environment(AuthModel.self) private var auth

    private enum Step {
        case email
        case code(email: String)
    }

    @State private var step: Step = .email
    @State private var emailText = ""
    @State private var codeText = ""
    @State private var isBusy = false
    @State private var error: LoginError?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .email:
                    emailSection
                case .code(let email):
                    codeSection(email: email)
                }
                if let error {
                    Section {
                        Label(error.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Logg inn")
            .disabled(isBusy)
            .onAppear { focused = true }
        }
    }

    private var emailSection: some View {
        Section {
            TextField("deg@epost.no", text: $emailText)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(sendCode)
            Button(action: sendCode) {
                busyLabel("Send kode")
            }
        } header: {
            Text("E-post")
        } footer: {
            Text("Vi sender en engangskode til e-posten din. Ingen passord å huske.")
        }
    }

    private func codeSection(email: String) -> some View {
        Section {
            TextField("Engangskode", text: $codeText)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focused)
                .onSubmit { verify(email: email) }
            Button { verify(email: email) } label: {
                busyLabel("Logg inn")
            }
            Button("Send ny kode") { resend(to: email) }
            Button("Bruk en annen e-post") {
                step = .email
                codeText = ""
                error = nil
            }
        } header: {
            Text("Kode")
        } footer: {
            Text("Sendt til \(email). Bli i appen og skriv inn koden her.")
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

    private func sendCode() {
        guard let email = LoginInput.normalizedEmail(emailText) else {
            error = .invalidEmail
            return
        }
        run {
            try await auth.sendCode(to: email)
            step = .code(email: email)
            codeText = ""
            focused = true
        }
    }

    private func resend(to email: String) {
        run { try await auth.sendCode(to: email) }
    }

    private func verify(email: String) {
        guard let code = LoginInput.normalizedCode(codeText) else {
            error = .invalidCode
            return
        }
        run { try await auth.verify(email: email, code: code) }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        isBusy = true
        Task {
            do {
                try await action()
            } catch {
                self.error = (error as? LoginError) ?? .unknown(error.localizedDescription)
            }
            isBusy = false
        }
    }
}
