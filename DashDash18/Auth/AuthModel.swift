import AuthenticationServices
import Foundation
import Observation
import Supabase

struct AuthUser: Equatable, Sendable {
    let id: UUID
    let email: String?
}

enum AuthState: Equatable {
    /// Leser lagret økt fra nøkkelringen.
    case starting
    case signedOut
    case signedIn(AuthUser)
}

/// Innloggingstilstanden for hele appen. Lytter på Supabase og eier inn- og utlogging.
@Observable
final class AuthModel {
    private(set) var state: AuthState = .starting
    private let auth: AuthClient
    /// Kjøres før utlogging, mens økten fortsatt finnes (push: fjern telefonen).
    @ObservationIgnored var willSignOut: (() async -> Void)?
    /// Kjøres når kontoen er slettet på serveren, før den lokale økten fjernes (rydd telefonen).
    @ObservationIgnored var didDeleteAccount: ((UUID) -> Void)?

    init(client: SupabaseClient) {
        auth = client.auth
    }

    /// Følger økten så lenge appen lever. Første verdi er den lagrede økten (eller ingen).
    func observe() async {
        for await (_, session) in auth.authStateChanges {
            // En utløpt lagret økt fornyes automatisk. Vi regner deg som innlogget så lenge
            // det finnes en økt, så appen virker uten nett (offline-først). Stille fornying
            // (`tokenRefreshed`) gir samme bruker, og da rører vi ikke tilstanden, så ingen
            // skjerm tegnes på nytt midt i en runde.
            let next: AuthState = session.map { .signedIn(AuthUser(id: $0.user.id, email: $0.user.email)) } ?? .signedOut
            if next != state {
                state = next
            }
        }
    }

    func sendCode(to email: String) async throws(LoginError) {
        do {
            try await auth.signInWithOTP(email: email, shouldCreateUser: true)
        } catch {
            throw Self.loginError(from: error)
        }
    }

    func verify(email: String, code: String) async throws(LoginError) {
        do {
            try await auth.verifyOTP(email: email, token: code, type: .email)
        } catch {
            throw Self.loginError(from: error)
        }
    }

    /// Logg inn med Apple: ID-tokenet fra Apple byttes mot en Supabase-økt.
    func signInWithApple(idToken: String, rawNonce: String) async throws(LoginError) {
        do {
            try await auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
            )
        } catch {
            throw Self.loginError(from: error)
        }
    }

    /// Logg inn med Google (B9, `GoogleLoginFeature`): Supabase OAuth i et
    /// `ASWebAuthenticationSession`-vindu, som kommer tilbake til `GoogleLogin.redirectURL`.
    func signInWithGoogle() async throws(LoginError) {
        do {
            try await auth.signInWithOAuth(provider: .google, redirectTo: GoogleLogin.redirectURL) { session in
                // Delt Safari-økt: er du alt logget inn på Google, slipper du å skrive passordet.
                session.prefersEphemeralWebBrowserSession = false
            }
        } catch {
            if GoogleLogin.isCancellation(error) { return }
            if let authError = error as? AuthError {
                throw LoginError.from(errorCode: authError.errorCode.rawValue, fallback: authError.localizedDescription)
            }
            if error is URLError { throw .offline }
            throw .googleFailed
        }
    }

    /// Etter «Slett konto»: innloggingen finnes ikke lenger på serveren, så bare den lokale økten
    /// fjernes. Push er alt slettet av serveren (`delete_account_data`).
    func signOutAfterDeletion() async {
        if case .signedIn(let user) = state { didDeleteAccount?(user.id) }
        try? await auth.signOut(scope: .local)
        state = .signedOut
    }

    /// Innloggingsmåtene kontoen har. Hentes fra serveren, så en nylig koblet måte er med;
    /// uten nett brukes økten på telefonen.
    func identities() async -> [LinkedIdentity] {
        let fromServer = try? await auth.userIdentities()
        let identities = fromServer ?? auth.currentUser?.identities ?? []
        return identities.map {
            LinkedIdentity(provider: $0.provider, email: $0.identityData?["email"]?.stringValue)
        }
    }

    /// Kobler Apple til kontoen du er logget inn med (ID-token og nonce som ved innlogging).
    /// Krever manuell kobling i Supabase Auth (`AccountLinkingFeature`).
    func linkApple(idToken: String, rawNonce: String) async throws(LinkIdentityError) {
        do {
            try await auth.linkIdentityWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
            )
        } catch {
            if let authError = error as? AuthError {
                throw LinkIdentityError.from(errorCode: authError.errorCode.rawValue, fallback: authError.localizedDescription)
            }
            if error is URLError { throw .offline }
            throw .unknown(error.localizedDescription)
        }
    }

    /// Lokal utlogging, som i PWA-en: en global utlogging kunne henge.
    func signOut() async {
        await willSignOut?()
        try? await auth.signOut(scope: .local)
        state = .signedOut
    }

    private static func loginError(from error: any Error) -> LoginError {
        if let authError = error as? AuthError {
            return LoginError.from(errorCode: authError.errorCode.rawValue, fallback: authError.localizedDescription)
        }
        if error is URLError {
            return .offline
        }
        return .unknown(error.localizedDescription)
    }
}

/// Google-innlogging via Supabase OAuth (B9).
nonisolated enum GoogleLogin {
    /// Hit sender Supabase deg tilbake etter Google. Må stå i Supabase → Auth → URL Configuration →
    /// Redirect URLs. `ASWebAuthenticationSession` fanger adressen selv, så den trenger ikke å
    /// registreres som URL-skjema i appen.
    static let redirectURL = URL(string: "dashdash://login-callback")!

    /// Brukeren lukket vinduet: ikke en feil.
    static func isCancellation(_ error: any Error) -> Bool {
        if let web = error as? ASWebAuthenticationSessionError, web.code == .canceledLogin { return true }
        let ns = error as NSError
        return ns.domain == ASWebAuthenticationSessionError.errorDomain
            && ns.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    }
}
