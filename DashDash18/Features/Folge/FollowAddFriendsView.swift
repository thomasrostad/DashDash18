import Supabase
import SwiftUI

/// «Legg til venner»: søk på navn, skann eller vis koden, og folk du kjenner fra klubben,
/// rundene og turneringene med Følg-knappen (sql/054). Åpnes fra «Følger» på Hjem og fra Deg → Følger.
struct FollowAddFriendsView: View {
    @State var model: FollowAddFriendsModel
    @State private var scanning = false

    var body: some View {
        DDList {
            Section {
                NavigationLink { FollowSearchView(client: model.client, userID: model.userID) } label: {
                    Label("Søk på navn", systemImage: "magnifyingglass").labelStyle(DDIconLabelStyle())
                }
                Button { scanning = true } label: {
                    Label("Skann QR-kode", systemImage: "qrcode.viewfinder").labelStyle(DDIconLabelStyle())
                }
                NavigationLink { FollowCodeView(client: model.client) } label: {
                    Label("Vis min kode og del lenken", systemImage: "qrcode").labelStyle(DDIconLabelStyle())
                }
            } footer: {
                DDFooter("Følger dere hverandre, er dere venner og ser de ferdige rundene til hverandre under «Følger» på Hjem.")
            }
            Section {
                if model.isLoaded, model.suggestions.isEmpty {
                    Text("Ingen flere å foreslå. Folk fra klubben og rundene dine dukker opp her.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach($model.suggestions) { $person in
                    FollowSuggestionRow(client: model.client, userID: model.userID, person: $person)
                }
            } header: {
                DDHeader("Folk du kjenner")
            } footer: {
                DDFooter("Fra klubben, rundene og turneringene dine. Godkjenner de nye følgere, står du som «Venter» til de har svart.")
            }
            Section {
                NavigationLink {
                    FollowHubView(model: FollowHubModel(client: model.client, userID: model.userID))
                } label: {
                    HStack {
                        Label("Forespørsler og dem du følger", systemImage: "person.2")
                            .labelStyle(DDIconLabelStyle())
                        Spacer()
                        if model.requests > 0 {
                            DDCountBadge(HomeBell.label(model.requests) ?? "")
                                .accessibilityLabel("\(model.requests) forespørsler")
                        }
                    }
                }
            }
        }
        .overlay { if !model.isLoaded { ProgressView() } }
        .navigationTitle("Legg til venner")
        .ddNavigationChrome()
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $scanning, onDismiss: { Task { await model.load() } }) {
            FollowScanSheet(client: model.client)
        }
    }
}

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
                FollowAddFriendsView(model: FollowAddFriendsModel(client: model.client, userID: model.userID))
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
