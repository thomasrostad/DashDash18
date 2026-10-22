import Supabase
import SwiftUI

/// Én du kjenner: portrett og navn (åpner profilen) og Følg / Venter / Følger.
struct FollowSuggestionRow: View {
    let client: SupabaseClient
    let userID: UUID
    @Binding var person: FollowSuggestion

    var body: some View {
        HStack(spacing: DDSpacing.s) {
            NavigationLink {
                PersonProfileView(client: client, userID: userID, profileID: person.profileID,
                                  name: person.name, avatarPath: person.avatarPath, source: .suggestion)
            } label: {
                FollowPersonLabel(client: client, name: person.name, avatarPath: person.avatarPath,
                                  subtitle: person.subtitle)
            }
            FollowStatusButton(client: client, profileID: person.profileID, name: person.name,
                               status: $person.status, source: .suggestion)
                .fixedSize()
        }
    }
}

/// Kortet øverst i «Følger» på Hjem: «Legg til venner» med noen du kjenner og en vei videre til
/// søk og QR-kode. Uten forslag står bare knappen.
struct FollowAddFriendsCard: View {
    let model: FollowAddFriendsModel
    /// Ingen runder i feeden ennå: kortet forklarer hva «Følger» er.
    let feedIsEmpty: Bool
    @State private var preview: [FollowSuggestion] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Legg til venner").font(.ddBodyEmphasis).foregroundStyle(Color.ddInk)
                Text(feedIsEmpty
                     ? "Følg vennene dine, så kommer de ferdige rundene deres her."
                     : "Finn flere å følge med navn eller QR-kode.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if !preview.isEmpty {
                VStack(spacing: 0) {
                    ForEach($preview) { $person in
                        FollowSuggestionRow(client: model.client, userID: model.userID, person: $person)
                            .padding(.vertical, 6)
                        if person.id != preview.last?.id { DDDivider() }
                    }
                }
            }
            NavigationLink {
                FollowHubView(model: FollowHubModel(client: model.client, userID: model.userID))
            } label: {
                Label(preview.isEmpty ? "Legg til venner" : "Søk, skann kode eller se flere",
                      systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dd(feedIsEmpty ? .primary : .secondary, compact: true))
            .accessibilityHint("Søk på navn, skann en QR-kode eller følg folk du kjenner.")
        }
        .ddCard(feedIsEmpty ? .empty : .standard)
        .onChange(of: model.suggestions, initial: true) { _, people in
            preview = FollowSuggestions.preview(people)
        }
    }
}
