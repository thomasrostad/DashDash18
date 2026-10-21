import AuthenticationServices
import UIKit

// Fersk Apple-innlogging rett før «Slett konto» (App Review 5.1.1(v) og 4.8). Koden
// (`authorizationCode`) går til `delete-account`, som bytter den mot et token hos Apple og
// trekker det tilbake. Ingen Apple-token lagres, verken på telefonen eller på serveren.

/// Ren logikk: når det trengs, og hva svaret fra Apple betyr.
nonisolated enum AppleReauthorization {
    enum Outcome: Equatable, Sendable {
        /// Fersk kode som sendes med slettingen.
        case code(String)
        /// Brukeren lukket Apple-arket: ingenting slettes.
        case cancelled
        /// Apple ga ingen kode (feil, ingen Apple-ID på telefonen). Kontoen slettes likevel.
        case unavailable
    }

    /// Bare kontoer med Apple-innlogging (også koblet til senere) blir bedt om Apple.
    static func isNeeded(identities: [LinkedIdentity]) -> Bool {
        identities.contains { $0.provider.lowercased() == "apple" }
    }

    static func outcome(authorizationCode: Data?) -> Outcome {
        guard let authorizationCode, let code = String(data: authorizationCode, encoding: .utf8),
              !code.isEmpty
        else { return .unavailable }
        return .code(code)
    }

    static func outcome(error: any Error) -> Outcome {
        if let error = error as? ASAuthorizationError, error.code == .canceled { return .cancelled }
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain, ns.code == ASAuthorizationError.Code.canceled.rawValue {
            return .cancelled
        }
        return .unavailable
    }
}

/// Viser Apple-arket og venter på svaret. Én forespørsel per objekt.
final class AppleAuthorizationCodeRequest: NSObject {
    private var continuation: CheckedContinuation<AppleReauthorization.Outcome, Never>?
    private var controller: ASAuthorizationController?

    func run() async -> AppleReauthorization.Outcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            // Ingen navn eller e-post: vi trenger bare koden.
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ outcome: AppleReauthorization.Outcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
        controller = nil
    }
}

extension AppleAuthorizationCodeRequest: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        finish(AppleReauthorization.outcome(authorizationCode: credential?.authorizationCode))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        finish(AppleReauthorization.outcome(error: error))
    }
}

extension AppleAuthorizationCodeRequest: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        if let window = windows.first(where: \.isKeyWindow) ?? windows.first { return window }
        // Slett konto-arket vises, så en scene finnes alltid her.
        guard let scene = scenes.first else { preconditionFailure("Ingen vindusscene for Apple-arket") }
        return ASPresentationAnchor(windowScene: scene)
    }
}
