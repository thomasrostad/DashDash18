import Foundation
import GolfgutuCore
import Supabase
import SwiftUI

/// Slette en hel turnering (`sql/038_slett_turnering.sql`, Thomas 09.10.2026).
nonisolated enum TournamentDeletionFeature {
    /// Av til 038 er kjørt. Med flagget av kan bare en planlagt sesong uten kvelder slettes, som før.
    static let isEnabled = false
}

/// Svaret fra `delete_tournament` og tekstene rundt.
nonisolated enum TournamentDeletion {
    struct Result: Decodable, Equatable, Sendable {
        let name: String
        let rounds: Int
        let events: Int
    }

    /// Navnet som er skrevet inn, er turneringens (store og små bokstaver og mellomrom i endene teller ikke,
    /// som i SQL-en).
    static func nameMatches(_ typed: String, name: String) -> Bool {
        let a = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !a.isEmpty && a == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Hva spørsmålet sier før sletting.
    static let warning = "Kveldene, rundene, resultatene, påmeldingene og veddemålene i turneringen slettes for godt. Runder som bare teller også her, blir stående. Skriv navnet for å bekrefte."

    /// «Høst 2026 er slettet, med 7 kvelder og 9 runder.»
    static func message(_ r: Result, term: DayTerm = .evening) -> String {
        var parts: [String] = []
        if r.events > 0 { parts.append(term.count(r.events)) }
        if r.rounds > 0 { parts.append(r.rounds == 1 ? "1 runde" : "\(r.rounds) runder") }
        return parts.isEmpty ? "\(r.name) er slettet." : "\(r.name) er slettet, med \(parts.joined(separator: " og "))."
    }

    static func delete(client: SupabaseClient, competitionID: UUID, confirmName: String) async throws -> Result {
        struct Params: Encodable { let p_competition_id: UUID; let p_confirm_name: String }
        return try await client.rpc("delete_tournament", params: Params(p_competition_id: competitionID,
                                                                         p_confirm_name: confirmName))
            .execute().value
    }

    /// Turneringsraden til en sesong (speilet siden 017).
    static func competitionID(client: SupabaseClient, seasonID: UUID) async throws -> UUID? {
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await client.from("competitions").select("id").eq("season_id", value: seasonID)
            .limit(1).execute().value
        return rows.first?.id
    }
}

extension View {
    /// «Slette <navn>?» med feltet for navnet. `perform` får det som er skrevet.
    func deleteTournamentAlert(isPresented: Binding<Bool>, name: String,
                               perform: @escaping (String) -> Void) -> some View {
        modifier(DeleteTournamentAlert(isPresented: isPresented, name: name, perform: perform))
    }
}

private struct DeleteTournamentAlert: ViewModifier {
    @Binding var isPresented: Bool
    let name: String
    let perform: (String) -> Void
    @State private var typed = ""

    func body(content: Content) -> some View {
        content.alert("Slette «\(name)»?", isPresented: $isPresented) {
            TextField(name, text: $typed)
                .autocorrectionDisabled()
            Button("Slett for godt", role: .destructive) {
                perform(typed)
                typed = ""
            }
            .disabled(!TournamentDeletion.nameMatches(typed, name: name))
            Button("Avbryt", role: .cancel) { typed = "" }
        } message: {
            Text(TournamentDeletion.warning)
        }
    }
}
