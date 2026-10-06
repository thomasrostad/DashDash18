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

    init(client: SupabaseClient) {
        auth = client.auth
    }

    /// Følger økten så lenge appen lever. Første verdi er den lagrede økten (eller ingen).
    func observe() async {
        for await (_, session) in auth.authStateChanges {
            // En utløpt lagret økt fornyes automatisk. Vi regner deg som innlogget så lenge
            // det finnes en økt, så appen virker uten nett (offline-først).
            if let session {
                state = .signedIn(AuthUser(id: session.user.id, email: session.user.email))
            } else {
                state = .signedOut
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

    /// Lokal utlogging, som i PWA-en: en global utlogging kunne henge.
    func signOut() async {
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
