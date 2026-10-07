import AuthenticationServices
import SwiftUI

/// Innlogging med Apple eller engangskode på e-post. Google kommer i neste steg.
struct LoginView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @State private var appleNonce = ""

    private enum Step {
        case email
        case code(email: String)
    }

    @State private var step: Step = .email
    @State private var emailText = ""
    @State private var codeText = ""
    @State private var isBusy = false
    @State private var error: LoginError?
    /// Når siste kode ble sendt, for nedtellingen på «Send ny kode».
    @State private var lastSentAt: Date?
    /// «Ny kode er sendt» etter et nytt forsøk.
    @State private var info: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    LoginHero()
                        .padding(.vertical, 48)
                    VStack(alignment: .leading, spacing: DDSpacing.l) {
                        switch step {
                        case .email:
                            appleSection
                            emailSection
                        case .code(let email):
                            codeSection(email: email)
                        }
                        if let error {
                            Label(error.message, systemImage: "exclamationmark.triangle")
                                .font(.ddCallout)
                                .foregroundStyle(Color.ddError)
                        } else if let info {
                            Label(info, systemImage: "envelope")
                                .font(.ddCallout)
                                .foregroundStyle(Color.ddForestInk)
                        }
                    }
                    .padding(.horizontal, DDSpacing.xxl)
                    .padding(.top, DDSpacing.xxl)
                    .padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: DDRadius.sheet, topTrailingRadius: DDRadius.sheet)
                            .fill(Color.ddCard)
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.ddForestDeep.ignoresSafeArea())
            .navigationTitle("Logg inn")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .disabled(isBusy)
            .onAppear { focused = true }
        }
    }

    private var appleSection: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            Text("Logg inn")
                .font(.ddTitle)
                .foregroundStyle(Color.ddForestInk)
                .accessibilityAddTraits(.isHeader)
            SignInWithAppleButton(.signIn) { request in
                appleNonce = AppleNonce.random()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleNonce.sha256(appleNonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 56)
            .clipShape(.capsule)
            Text("Eller logg inn med en kode på e-post:")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .padding(.top, DDSpacing.s)
        }
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Text("E-post")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
            // Egen prompt med verbatim: ellers lenkefarger iOS e-postadressen i plassholderen.
            TextField("deg@epost.no", text: $emailText,
                      prompt: Text(verbatim: "deg@epost.no").foregroundStyle(Color.ddInkSecondary))
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("E-post")
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(sendCode)
                .ddField()
            Text("Vi sender en engangskode til e-posten din. Ingen passord å huske.")
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
            Button(action: sendCode) {
                busyLabel("Send kode")
            }
            .buttonStyle(.ddPrimary)
            .padding(.top, DDSpacing.s)
        }
    }

    private func codeSection(email: String) -> some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Text("Skriv inn koden")
                .font(.ddTitle)
                .foregroundStyle(Color.ddForestInk)
                .accessibilityAddTraits(.isHeader)
            Text("Sendt til \(email). Bli i appen og skriv inn koden her.")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
            Text("Kode")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .padding(.top, DDSpacing.s)
            TextField("Engangskode", text: $codeText)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focused)
                .onSubmit { verify(email: email) }
                .onChange(of: codeText) { old, new in
                    // Autofyll fra Mail/Meldinger eller innliming: logg inn uten å trykke.
                    if !isBusy, LoginInput.autoSubmittableCode(previous: old, current: new) != nil {
                        verify(email: email)
                    } else if error != nil, new != old {
                        error = nil
                    }
                }
                .font(.dd(.mono, size: 20, weight: .medium, relativeTo: .title3))
                .ddField()
            Button { verify(email: email) } label: {
                busyLabel("Logg inn")
            }
            .buttonStyle(.ddPrimary)
            .padding(.top, DDSpacing.s)
            ViewThatFits(in: .horizontal) {
                HStack {
                    resendButton(email: email)
                    Spacer()
                    otherEmailButton
                }
                // Store tekststørrelser: under hverandre i stedet for å klippe.
                VStack(alignment: .leading, spacing: DDSpacing.s) {
                    resendButton(email: email)
                    otherEmailButton
                }
            }
            .buttonStyle(.ddText)
        }
    }

    /// «Send ny kode», med nedtelling til Supabase tar imot en ny (ellers får du «for mange forsøk»).
    private func resendButton(email: String) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = LoginInput.secondsUntilResend(lastSent: lastSentAt, now: context.date)
            Button(wait > 0 ? "Ny kode om \(wait) s" : "Send ny kode") { resend(to: email) }
                .disabled(wait > 0)
                .monospacedDigit()
        }
    }

    private var otherEmailButton: some View {
        Button("Bruk en annen e-post") {
            step = .email
            codeText = ""
            error = nil
            info = nil
        }
    }

    private func busyLabel(_ title: String) -> some View {
        HStack(spacing: DDSpacing.s) {
            Text(title)
            if isBusy {
                ProgressView()
                    .tint(DDToken.buttonPrimaryText.color)
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
            lastSentAt = .now
            step = .code(email: email)
            codeText = ""
            focused = true
        }
    }

    private func resend(to email: String) {
        run {
            try await auth.sendCode(to: email)
            lastSentAt = .now
            codeText = ""
            info = "Ny kode er sendt. Bruk den nyeste."
            focused = true
        }
    }

    private func verify(email: String) {
        guard let code = LoginInput.normalizedCode(codeText) else {
            error = .invalidCode
            return
        }
        run { try await auth.verify(email: email, code: code) }
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                error = .appleFailed
                return
            }
            let nonce = appleNonce
            run { try await auth.signInWithApple(idToken: idToken, rawNonce: nonce) }
        case .failure(let failure):
            // Avbrutt av brukeren er ikke en feil.
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            error = .appleFailed
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        error = nil
        info = nil
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

/// Jakka, navnet og sesongen på grønn grunn, som innloggingen i PWA-en.
private struct LoginHero: View {
    var body: some View {
        VStack(spacing: DDSpacing.m) {
            DDJacketIcon()
                .stroke(Color.ddGold, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                .frame(width: 44, height: 52)
                .accessibilityHidden(true)
            Text("DashDash18")
                .font(.ddDisplay)
                .foregroundStyle(Color.ddOnDark)
            Text("GolfGutu Invitational")
                .ddEyebrow(color: Color.ddOnDark.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
