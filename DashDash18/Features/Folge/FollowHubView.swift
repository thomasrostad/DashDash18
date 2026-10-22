import Supabase
import SwiftUI

/// Raden under Deg som åpner «Følger». Vises bare når sql/054 finnes. Tallet er forespørslene.
struct DegFollowSection: View {
    let client: SupabaseClient
    let user: AuthUser
    @State private var available = FollowFeature.isAvailable
    @State private var requests = 0

    var body: some View {
        Group {
            if available {
                Section {
                    NavigationLink {
                        FollowHubView(model: FollowHubModel(client: client, userID: user.id))
                    } label: {
                        HStack {
                            Label("Følger", systemImage: "person.2")
                                .labelStyle(DDIconLabelStyle())
                            Spacer()
                            if requests > 0 {
                                DDCountBadge(HomeBell.label(requests) ?? "")
                                    .accessibilityLabel("\(requests) forespørsler")
                            }
                        }
                    }
                } footer: {
                    DDFooter("Følg andre spillere, se rundene deres og finn folk med navn eller QR-kode.")
                }
            }
        }
        .task {
            available = await FollowFeature.detect(client: client)
            guard available else { return }
            let rows = (try? await FollowService(client: client).myFollows()) ?? []
            requests = FollowLists(rows).requests.count
        }
    }
}

/// Deg → Følger: forespørsler øverst, så dem du følger og dem som følger deg, og innstillingene.
struct FollowHubView: View {
    @State var model: FollowHubModel
    @State private var scanning = false
    @State private var report: FollowRow?
    @State private var confirmsBlock: FollowRow?
    @State private var moderationError: String?

    var body: some View {
        DDList {
            Section {
                Text(model.lists.countsText)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                    .monospacedDigit()
                if let client = model.client {
                    NavigationLink {
                        FollowAddFriendsView(model: FollowAddFriendsModel(client: client, userID: model.userID))
                    } label: {
                        Label("Legg til venner", systemImage: "person.badge.plus").labelStyle(DDIconLabelStyle())
                    }
                    NavigationLink { FollowSearchView(client: client, userID: model.userID) } label: {
                        Label("Finn spillere", systemImage: "magnifyingglass").labelStyle(DDIconLabelStyle())
                    }
                    NavigationLink { FollowCodeView(client: client) } label: {
                        Label("Min kode", systemImage: "qrcode").labelStyle(DDIconLabelStyle())
                    }
                    NavigationLink {
                        FollowingFeedView(model: FollowingFeedModel(client: client, userID: model.userID),
                                          showsAddFriends: false)
                            .navigationTitle("Runder")
                            .ddNavigationChrome()
                    } label: {
                        Label("Runder fra dem du følger", systemImage: "figure.golf").labelStyle(DDIconLabelStyle())
                    }
                }
                Button { scanning = true } label: {
                    Label("Skann kode", systemImage: "qrcode.viewfinder").labelStyle(DDIconLabelStyle())
                }
            }
            if !model.lists.requests.isEmpty {
                Section {
                    ForEach(model.lists.requests) { row in requestRow(row) }
                } header: {
                    DDHeader("Forespørsler")
                } footer: {
                    DDFooter("Godtar du, ser de profilen din og de ferdige rundene dine.")
                }
            }
            Section {
                if model.lists.following.isEmpty, model.state == .loaded {
                    Text("Du følger ingen ennå.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(model.lists.following) { row in
                    personLink(row, subtitle: row.status == .pending ? "Venter på svar" : nil)
                        .swipeActions {
                            Button(row.status == .pending ? "Trekk" : "Slutt å følge", role: .destructive) {
                                Task { await model.unfollow(row.profileID) }
                            }
                        }
                }
            } header: {
                DDHeader("Du følger")
            }
            Section {
                if model.lists.followers.isEmpty, model.state == .loaded {
                    Text("Ingen følger deg ennå.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(model.lists.followers) { row in
                    personLink(row, subtitle: nil)
                        .swipeActions {
                            Button("Fjern", role: .destructive) { Task { await model.removeFollower(row.profileID) } }
                        }
                }
            } header: {
                DDHeader("Følger deg")
            } footer: {
                DDFooter("Sveip for å slutte å følge eller fjerne en følger. De får ikke beskjed.")
            }
            if let settings = model.settings {
                Section {
                    Toggle("Godkjenn nye følgere", isOn: Binding(
                        get: { settings.followApproval },
                        set: { on in Task { await model.setApproval(on) } }))
                        .tint(Color.ddForestInk)
                    Toggle("Kan finnes i søk", isOn: Binding(
                        get: { settings.searchable },
                        set: { on in Task { await model.setSearchable(on) } }))
                        .tint(Color.ddForestInk)
                } header: {
                    DDHeader("Personvern")
                } footer: {
                    DDFooter("Med godkjenning av kan alle som finner deg, følge deg med en gang. Skjult i søk finner andre deg bare via klubb, runde eller koden din.")
                }
            }
        }
        .overlay {
            if model.state == .loading { ProgressView() }
            if case .failed(let message) = model.state {
                ContentUnavailableView {
                    Label("Fikk ikke hentet følgingen", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Prøv igjen") { Task { await model.load() } }.buttonStyle(.dd(.primary))
                }
            }
        }
        .navigationTitle("Følger")
        .ddNavigationChrome()
        .task { await model.load() }
        .task { await model.startRealtime() }
        .onDisappear { Task { await model.stopRealtime() } }
        .refreshable { await model.load() }
        .sheet(isPresented: $scanning, onDismiss: { Task { await model.load() } }) {
            if let client = model.client { FollowScanSheet(client: client) }
        }
        .sheet(item: $report) { row in
            ReportSheet(target: ReportTarget(kind: .profile, targetID: row.profileID, memberID: nil,
                                             authorName: row.displayName)) { reason, note, _ in
                guard let client = model.client else { return }
                _ = try await ModerationService(client: client).report(kind: .profile, targetID: row.profileID,
                                                                       reason: reason, note: note)
            }
        }
        .confirmationDialog("Blokkere \(confirmsBlock?.displayName ?? "")?", isPresented: Binding(
            get: { confirmsBlock != nil }, set: { if !$0 { confirmsBlock = nil } }), titleVisibility: .visible) {
            Button("Blokker", role: .destructive) { if let row = confirmsBlock { block(row) } }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Følgingen fjernes begge veier, og dere finner ikke hverandre i søket.")
        }
        .alert("Noe gikk galt", isPresented: Binding(
            get: { model.errorMessage != nil || moderationError != nil },
            set: { if !$0 { model.errorMessage = nil; moderationError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? moderationError ?? "")
        }
    }

    private func requestRow(_ row: FollowRow) -> some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            FollowPersonLabel(client: model.client, name: row.displayName, avatarPath: row.avatarPath,
                              subtitle: "Vil følge deg")
            HStack(spacing: DDSpacing.s) {
                Button("Godta") { Task { await model.respond(to: row, accept: true) } }
                    .buttonStyle(.dd(.primary, compact: true))
                Button("Avslå") { Task { await model.respond(to: row, accept: false) } }
                    .buttonStyle(.dd(.secondary, compact: true))
                Spacer()
                Menu {
                    Button("Blokker", systemImage: "hand.raised") { confirmsBlock = row }
                    Button("Rapporter profil", systemImage: "flag") { report = row }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Mer for \(row.displayName)")
            }
            .disabled(model.working.contains(row.profileID))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func personLink(_ row: FollowRow, subtitle: String?) -> some View {
        if let client = model.client {
            NavigationLink {
                PersonProfileView(client: client, userID: model.userID, profileID: row.profileID,
                                  name: row.displayName, avatarPath: row.avatarPath)
            } label: {
                FollowPersonLabel(client: client, name: row.displayName, avatarPath: row.avatarPath, subtitle: subtitle)
            }
        } else {
            FollowPersonLabel(client: nil, name: row.displayName, avatarPath: row.avatarPath, subtitle: subtitle)
        }
    }

    private func block(_ row: FollowRow) {
        guard let client = model.client else { return }
        Task {
            do {
                _ = try await ModerationService(client: client).block(profileID: row.profileID)
                await model.load()
            } catch {
                moderationError = DataError.from(error).message
            }
        }
    }
}
