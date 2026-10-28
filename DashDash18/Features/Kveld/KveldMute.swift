import GolfgutuCore
import Supabase
import SwiftUI

/// «Demp denne kvelden» (sql/046): ingen push om kvelden for deg, utenom «Melding til alle».
/// Kveld-skjermen henter valget med `load` og viser bryteren bare når det finnes: ikke når 046
/// mangler (`PushEventMuteStore.isMuted` gir nil).
struct EveningMuteToggle: View {
    @Environment(\.dayTerm) private var dayTerm
    let client: SupabaseClient
    let eventID: UUID
    @Binding var isMuted: Bool?
    @State private var isSaving = false
    @State private var error: String?

    /// Valget for kvelden. nil når 046 mangler eller lesingen feilet.
    static func load(client: SupabaseClient, eventID: UUID) async -> Bool? {
        try? await PushEventMuteStore(client: client).isMuted(eventID: eventID)
    }

    var body: some View {
        if let muted = isMuted {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(get: { muted }, set: { on in Task { await set(on) } })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PushEventMuteText.title(term: dayTerm))
                        Text(PushEventMuteText.subtitle(term: dayTerm))
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
                .disabled(isSaving)
                if let error {
                    Text(error)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddRustText)
                }
            }
            .ddCard()
        }
    }

    private func set(_ on: Bool) async {
        let before = isMuted
        isMuted = on
        isSaving = true
        defer { isSaving = false }
        do {
            isMuted = try await PushEventMuteStore(client: client).setMuted(eventID: eventID, on: on)
            error = nil
        } catch {
            isMuted = before
            self.error = "Klarte ikke å lagre: \(error.message)"
        }
    }
}
