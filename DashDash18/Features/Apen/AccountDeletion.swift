import Foundation
import Observation
import Supabase

// Sletting av konto i appen (App Store 5.1.1(v)). Serveren gjør jobben: Edge Function
// `delete-account` (supabase/functions/delete-account) med `delete_account_data` i sql/019.

/// Ren logikk: bekreftelsen, teksten og feilene.
nonisolated enum AccountDeletion {
    /// Ordet du skriver for å bekrefte. Samme som `CONFIRMATION_WORD` i Edge Function.
    static let confirmationWord = "SLETT"

    static func isConfirmed(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == confirmationWord
    }

    /// Hva som skjer, i den rekkefølgen det vises.
    static let consequences: [String] = [
        "Innloggingen din slettes. Du kan ikke logge inn på denne kontoen igjen.",
        "Navnet ditt byttes til «Slettet spiller» i klubber og runder. Scorene står, så tabellene til de andre ikke endres.",
        "Meldingene og bildene dine i tråden slettes, og det gjør også portrettet ditt.",
        "Telefonene dine slutter å få varsler, og blokkeringene dine slettes.",
        "Kjøp i appen refunderes ikke. Abonnement sier du opp i App Store.",
    ]

    /// Advarsel når du er eneste arrangør i en klubb.
    static func organizerWarning(clubs: [String]) -> String? {
        guard !clubs.isEmpty else { return nil }
        let names = ListFormatter.localizedString(byJoining: clubs)
        return "Du er arrangør i \(names). Har klubben ingen annen arrangør, tar det eldste medlemmet med innlogging over."
    }

    /// Advarsel når hull ikke er sendt ennå (de forsvinner med kontoen).
    static func pendingWarning(pending: Int) -> String? {
        guard pending > 0 else { return nil }
        return pending == 1 ? "1 hull er ikke sendt ennå og går tapt." : "\(pending) hull er ikke sendt ennå og går tapt."
    }
}

/// Svaret fra Edge Function (`DeletionResult` i logic.ts).
nonisolated struct AccountDeletionResponse: Decodable, Equatable, Sendable {
    let ok: Bool
    var removedFiles: Int?
    var failedAt: String?
    var error: String?
}

nonisolated enum AccountDeletionError: Error, Equatable {
    case notConfirmed
    case offline
    /// Stoppet underveis. Trygt å prøve igjen: hvert steg tåler å kjøres på nytt.
    case partial(step: String)
    case unknown(String)

    var message: String {
        switch self {
        case .notConfirmed: "Skriv \(AccountDeletion.confirmationWord) for å bekrefte."
        case .offline: "Ingen kontakt med serveren. Kontoen er ikke slettet. Prøv igjen når du har nett."
        case .partial(let step):
            "Slettingen stoppet underveis (\(Self.stepName(step))). Prøv igjen; det som er gjort, gjøres ikke dobbelt."
        case .unknown(let detail): "Kontoen ble ikke slettet: \(detail)"
        }
    }

    static func stepName(_ step: String) -> String {
        switch step {
        case "files": "bildene"
        case "anonymize": "navn og innhold"
        case "auth_user": "innloggingen"
        default: step
        }
    }

    static func from(_ response: AccountDeletionResponse) -> AccountDeletionError? {
        if response.ok { return nil }
        if let step = response.failedAt { return .partial(step: step) }
        return .unknown(response.error ?? "ukjent feil")
    }
}

/// Kaller `delete-account` og logger ut når kontoen er borte.
@Observable
final class AccountDeletionModel {
    private(set) var isDeleting = false
    var error: AccountDeletionError?
    private let client: SupabaseClient
    private let auth: AuthModel

    init(client: SupabaseClient, auth: AuthModel) {
        self.client = client
        self.auth = auth
    }

    func delete(typed: String) async {
        guard AccountDeletion.isConfirmed(typed) else { error = .notConfirmed; return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let response: AccountDeletionResponse = try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: ["confirm": AccountDeletion.confirmationWord])
            )
            if let failure = AccountDeletionError.from(response) {
                error = failure
                return
            }
            await auth.signOutAfterDeletion()
        } catch let FunctionsError.httpError(_, data) {
            let response = try? JSONDecoder().decode(AccountDeletionResponse.self, from: data)
            error = response.flatMap(AccountDeletionError.from) ?? .unknown("serveren sa nei")
        } catch is URLError {
            error = .offline
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
