import AuthenticationServices
import SwiftUI

/// «Innloggingsmåter» og «Konto» under Deg: hvilke måter kontoen kan logges inn med,
/// kobling av Apple (når det er slått på), og utlogging med bekreftelse.
struct DegAccountSection: View {
    let user: AuthUser
    @Environment(AuthModel.self) private var auth
    @State private var identities: [LinkedIdentity]?
    @State private var linkError: LinkIdentityError?
    @State private var isLinking = false
    @State private var appleNonce = ""

    var body: some View {
        Section {
            if let identities {
                ForEach(LoginMethods.rows(identities: identities)) { row in
                    LoginMethodRowView(row: row)
                    if case .notLinked(canLink: true) = row.status, row.method == .apple {
                        appleLinkButton
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } header: {
            DDHeader("Innloggingsmåter")
        } footer: {
            DDFooter("Samme konto uansett hvilken måte du bruker. Google kommer senere.")
        }
        .task { identities = await auth.identities() }
        .alert(
            "Kunne ikke koble til",
            isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } }),
            presenting: linkError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }

        DDSection("Konto") {
            LabeledContent("Logget inn som", value: user.email ?? "ukjent e-post")
            SignOutButton(loginHint: LoginMethods.signOutMessage(identities: identities ?? []))
                .foregroundStyle(Color.ddRustText)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var appleLinkButton: some View {
        SignInWithAppleButton(.continue) { request in
            appleNonce = AppleNonce.random()
            request.requestedScopes = [.email]
            request.nonce = AppleNonce.sha256(appleNonce)
        } onCompletion: { result in
            handleApple(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 44)
        .disabled(isLinking)
        .accessibilityLabel("Koble til Apple")
    }

    private func handleApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                linkError = .appleFailed
                return
            }
            let nonce = appleNonce
            isLinking = true
            Task {
                defer { isLinking = false }
                do throws(LinkIdentityError) {
                    try await auth.linkApple(idToken: idToken, rawNonce: nonce)
                    identities = await auth.identities()
                } catch {
                    linkError = error
                }
            }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code == .canceled { return }
            linkError = .appleFailed
        }
    }
}

/// Én innloggingsmåte: ikon, navn, e-posten bak (når den finnes) og status.
private struct LoginMethodRowView: View {
    let row: LoginMethodRow

    var body: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.method.title)
                    if case .linked(let detail?) = row.status {
                        Text(detail)
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } icon: {
                Image(systemName: row.method.systemImage)
            }
            .labelStyle(DDIconLabelStyle())
            Spacer(minLength: 8)
            switch row.status {
            case .linked:
                DDPill(row.trailingText, tone: .lime, systemImage: "checkmark")
                    .fixedSize()
            case .notLinked:
                Text(row.trailingText)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            case .comingSoon:
                DDPill(row.trailingText, tone: .earth)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
