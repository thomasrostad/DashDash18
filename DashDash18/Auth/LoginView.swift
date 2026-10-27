import AuthenticationServices
import SwiftUI

/// Innlogging med Apple, Google (bak `GoogleLoginFeature`) eller engangskode på e-post.
/// Med `CaptchaFeature` på kommer en Turnstile-sjekk (`CaptchaSheet`) før hver kode sendes.
struct LoginView: View {
    /// Google-knappen (skjermprøven viser den selv om flagget er av).
    var showsGoogle = GoogleLoginFeature.isEnabled
    /// Lenkene til vilkår og personvern.
    var showsLegal = LegalLinks.isVisible
    /// Åpnet fra en klubbinvitasjon (`dashdash://klubb/KODE`): si at den er tatt vare på.
    var hasClubInvite = false
    /// Åpnet fra en turneringslenke (`dashdash18.com/konkurranse/KODE`, sql/060).
    var hasCompetitionInvite = false
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
    /// Turnstile-sjekken før koden sendes (`CaptchaFeature`).
    @State private var captcha: CaptchaRequest?

    private struct CaptchaRequest: Identifiable {
        let id = UUID()
        let siteKey: String
        let email: String
        let isResend: Bool
    }
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Logoen tar plassen som blir til overs, så kortet ligger nede som et ark.
                        // Små skjermer (SE): mindre merke, så Apple-knappen synes uten å rulle.
                        LoginHero(markSize: proxy.size.height < 700 ? 80 : 112)
                            .frame(maxHeight: .infinity)
                            // Følger innholdet når store tekststørrelser gjør at det ruller.
                            .background(Color.ddForestDeep)
                        VStack(alignment: .leading, spacing: 14) {
                            if hasClubInvite {
                                DDInfoStripe(tone: .earth) {
                                    Label("Invitasjonen er tatt vare på. Logg inn, så går du rett videre til klubben.",
                                          systemImage: "envelope.open")
                                }
                            } else if hasCompetitionInvite {
                                DDInfoStripe(tone: .earth) {
                                    Label("Logg inn for å ta plassen din i turneringen. Lenken er tatt vare på.",
                                          systemImage: "trophy")
                                }
                            }
                            switch step {
                            case .email:
                                appleSection
                                orDivider
                                emailSection
                            case .code(let email):
                                codeSection(email: email)
                                if showsLegal {
                                    LegalLinksRow()
                                        .padding(.top, DDSpacing.s)
                                }
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
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Arket får høyden det trenger; heroen krymper (ellers kuttes tekst i arket).
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            UnevenRoundedRectangle(topLeadingRadius: DDRadius.sheet, topTrailingRadius: DDRadius.sheet)
                                .fill(Color.ddCard)
                                .ignoresSafeArea(edges: .bottom)
                                // Skoggrønt bak de runde hjørnene, også når innholdet ruller.
                                .background(alignment: .top) {
                                    Color.ddForestDeep.frame(height: DDRadius.sheet)
                                }
                        )
                    }
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            // Skoggrønt bak logoen og kortets farge nederst (bak kortet), så arket går helt ned
            // under hjemindikatoren. I stedet for `ddNavigationChrome`: den la `ddBackground` bak
            // alt og ga en mørk stripe nederst.
            .containerBackground(for: .navigation) {
                VStack(spacing: 0) {
                    Color.ddForestDeep
                    Color.ddCard.frame(height: 300)
                }
            }
            // Ingen navigasjonslinje: «Atten» i heroen er overskriften.
            .toolbar(.hidden, for: .navigationBar)
            .disabled(isBusy)
            .sheet(item: $captcha) { request in
                CaptchaSheet(siteKey: request.siteKey) { token in
                    captcha = nil
                    deliverCode(to: request.email, isResend: request.isResend, captchaToken: token)
                }
            }
            // Ingen fokus i e-postfeltet ved oppstart: tastaturet skal ikke dekke Apple-knappen.
            // Kodesteget får fokus selv (sendCode).
        }
    }

    private var appleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SignInWithAppleButton(.signIn) { request in
                appleNonce = AppleNonce.random()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleNonce.sha256(appleNonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            // Stilen settes bare når knappen lages: ny knapp når modusen byttes.
            .id(colorScheme)
            .frame(height: 56)
            .clipShape(.capsule)
            if showsGoogle {
                GoogleSignInButton { run { try await auth.signInWithGoogle() } }
            }
        }
    }

    /// Tynn linje, «ELLER», tynn linje mellom knappene og e-posten.
    private var orDivider: some View {
        HStack(spacing: DDSpacing.m) {
            Rectangle().fill(Color.ddHairline).frame(height: 1)
            Text("Eller").ddEyebrow()
                .fixedSize()
            Rectangle().fill(Color.ddHairline).frame(height: 1)
        }
        .accessibilityHidden(true)
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
            Button(action: sendCode) {
                busyLabel("Send engangskode")
            }
            .buttonStyle(.ddPrimary)
            .padding(.top, DDSpacing.s)
            if showsLegal {
                legalLine
                    .padding(.top, DDSpacing.xs)
            }
        }
    }

    /// «Ingen passord. Ved å fortsette godtar du vilkårene og personvernerklæringen.» Uten begge
    /// lenkene: lenkeraden som før.
    @ViewBuilder
    private var legalLine: some View {
        if let terms = LegalLinks.terms, let privacy = LegalLinks.privacy,
           let text = try? AttributedString(markdown: "Ingen passord. Ved å fortsette godtar du "
               + "[vilkårene](\(terms.absoluteString)) og [personvernerklæringen](\(privacy.absoluteString)).") {
            Text(text)
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
                .tint(Color.ddForestInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else {
            LegalLinksRow()
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
            // Koden havner ofte i søppelpost eller «Kampanjer» første gang.
            Label("Finner du ikke e-posten? Sjekk søppelpost, eller «Kampanjer» hvis du bruker Gmail.",
                  systemImage: "envelope.badge")
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
        requestCode(to: email, isResend: false)
    }

    private func resend(to email: String) {
        requestCode(to: email, isResend: true)
    }

    /// Med `CaptchaFeature` på: først Turnstile-sjekken, så koden. Ellers rett på.
    private func requestCode(to email: String, isResend: Bool) {
        if let siteKey = auth.captchaSiteKey {
            error = nil
            info = nil
            captcha = CaptchaRequest(siteKey: siteKey, email: email, isResend: isResend)
        } else {
            deliverCode(to: email, isResend: isResend, captchaToken: nil)
        }
    }

    private func deliverCode(to email: String, isResend: Bool, captchaToken: String?) {
        run {
            try await auth.sendCode(to: email, captchaToken: captchaToken)
            lastSentAt = .now
            codeText = ""
            if isResend {
                info = "Ny kode er sendt. Bruk den nyeste."
            } else {
                step = .code(email: email)
            }
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
            let fullName = credential.fullName
            run { try await auth.signInWithApple(idToken: idToken, rawNonce: nonce, fullName: fullName) }
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

/// Attens merke, appnavnet og hva appen er for, på grønn grunn (`docs/design/innlogging/SPEC.md`).
private struct LoginHero: View {
    var markSize: CGFloat = 112

    var body: some View {
        VStack(spacing: 18) {
            AttenMark()
                .frame(width: markSize, height: markSize)
            Text("Atten")
                .font(.ddBrandDisplay)
                .tracking(-0.5)
                .foregroundStyle(Color.ddOnDark)
                .padding(.top, DDSpacing.s)
                .accessibilityAddTraits(.isHeader)
            Text("Turnering, liga og scorekort for golfgjengen.")
                .font(.ddBody)
                .foregroundStyle(Color.ddHeroSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
        .padding(.horizontal, 32)
        .padding(.bottom, DDSpacing.xxl)
    }
}

/// «Fortsett med Google» i samme form som Apple-knappen. Googles retningslinjer: hvit flate,
/// tydelig navn. Ingen logo-fil (ingen nye ressurser); teksten er nok.
private struct GoogleSignInButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("G")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .accessibilityHidden(true)
                Text("Fortsett med Google")
                    .font(.system(size: 19, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color(white: 0.12))
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().strokeBorder(Color(white: 0.75), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fortsett med Google")
    }
}
