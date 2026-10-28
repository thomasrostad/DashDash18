import AuthenticationServices
import Foundation
import GoogleSignIn
import Observation
import Supabase
import UIKit

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
    private let client: SupabaseClient
    /// Kjøres før utlogging, mens økten fortsatt finnes (push: fjern telefonen).
    @ObservationIgnored var willSignOut: (() async -> Void)?
    /// Kjøres når kontoen er slettet på serveren, før den lokale økten fjernes (rydd telefonen).
    @ObservationIgnored var didDeleteAccount: ((UUID) -> Void)?
    /// Site key for Turnstile når `CaptchaFeature` er på (fra appkonfigen), ellers `nil`.
    let captchaSiteKey: String?

    init(client: SupabaseClient, captchaSiteKey: String? = nil) {
        self.client = client
        auth = client.auth
        self.captchaSiteKey = CaptchaFeature.isEnabled(siteKey: captchaSiteKey) ? captchaSiteKey : nil
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

    /// Sender engangskoden. `captchaToken` er Turnstile-tokenet (`CaptchaFeature`); Supabase krever det
    /// når CAPTCHA er slått på i Auth. Et token kan bare brukes én gang.
    func sendCode(to email: String, captchaToken: String? = nil) async throws(LoginError) {
        do {
            try await auth.signInWithOTP(email: email, shouldCreateUser: true, captchaToken: captchaToken)
        } catch {
            throw Self.loginError(from: error)
        }
    }

    /// Uten `captchaToken`: Supabase sjekker ikke CAPTCHA på `/verify`, bare på `/otp`.
    func verify(email: String, code: String) async throws(LoginError) {
        do {
            try await auth.verifyOTP(email: email, token: code, type: .email)
        } catch {
            throw Self.loginError(from: error)
        }
    }

    /// Logg inn med Apple: ID-tokenet fra Apple byttes mot en Supabase-økt. Navnet Apple gir ved
    /// første innlogging (det står ikke i tokenet), blir profilnavnet når profilen ikke har et navn.
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents? = nil) async throws(LoginError) {
        let session: Session
        do {
            session = try await auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
            )
        } catch {
            throw Self.loginError(from: error)
        }
        if let name = AppleName.displayName(from: fullName) {
            await OwnProfileQueries.fillMissingName(client: client, userID: session.user.id, appleName: name)
        }
    }

    /// Logg inn med Google (B9, `GoogleLoginFeature`) med Googles egen pakke (GoogleSignIn, 28.10.2026):
    /// Google viser «Atten», ikke supabase.co. ID-tokenet byttes mot en Supabase-økt som med Apple, med
    /// nonce (Google får SHA-256, Supabase råverdien). iOS-klienten står i Info.plist (`GIDClientID`) og
    /// under «Client IDs» for Google i Supabase (test og prod).
    func signInWithGoogle() async throws(LoginError) {
        guard let presenter = GoogleLogin.presenter() else { throw .googleFailed }
        let rawNonce = AppleNonce.random()
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil,
                                                               nonce: AppleNonce.sha256(rawNonce))
        } catch {
            if GoogleLogin.isCancellation(error) { return }
            if error is URLError { throw .offline }
            throw .googleFailed
        }
        guard let idToken = result.user.idToken?.tokenString else { throw .googleFailed }
        do {
            try await auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken,
                                                      accessToken: result.user.accessToken.tokenString, nonce: rawNonce)
            )
        } catch {
            throw Self.loginError(from: error)
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

/// Google-innlogging med GoogleSignIn (B9).
nonisolated enum GoogleLogin {
    /// Skjermen Google-vinduet vises over: det øverste som står framme i vinduet som har fokus.
    @MainActor static func presenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        var top = (windows.first(where: \.isKeyWindow) ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Brukeren lukket vinduet: ikke en feil.
    static func isCancellation(_ error: any Error) -> Bool {
        let ns = error as NSError
        if ns.domain == kGIDSignInErrorDomain, ns.code == GIDSignInError.Code.canceled.rawValue { return true }
        return ns.domain == ASWebAuthenticationSessionError.errorDomain
            && ns.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue
    }
}
