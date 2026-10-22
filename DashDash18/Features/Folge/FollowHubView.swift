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

/// «Følger»: én skjerm for å finne folk. Søkefeltet øverst, «Skann kode» og «Min kode», forespørslene,
/// folk du kjenner, og én lenke til lista over dem du følger og dine følgere (med personvern).
/// Åpnes fra Deg → Følger og fra kortet i «Følger» på Hjem.
struct FollowHubView: View {
    @State var model: FollowHubModel
    @State private var scanning = false
    @State private var showsCode = false
    @State private var showsLists = false
    @State private var report: FollowRow?
    @State private var confirmsBlock: FollowRow?
    @State private var moderationError: String?

    var body: some View {
        DDList {
            if model.search.isActive, let client = model.client {
                FollowSearchResults(search: model.search, client: client, userID: model.userID)
            } else {
                content
            }
        }
        .searchable(text: Bindable(model.search).text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Søk på navn")
        .autocorrectionDisabled()
        .task(id: model.search.text) { await model.search.search() }
        .overlay {
            if !model.search.isActive {
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
        }
        .navigationTitle("Følger")
        .ddNavigationChrome()
        .task { await model.load() }
        .task { await model.startRealtime() }
        .onDisappear { Task { await model.stopRealtime() } }
        .refreshable { await model.load() }
        .navigationDestination(isPresented: $showsCode) {
            if let client = model.client { FollowCodeView(client: client) }
        }
        .navigationDestination(isPresented: $showsLists) { FollowListsView(model: model) }
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
        // Lista bak lenken viser sine egne feil.
        .alert("Noe gikk galt", isPresented: Binding(
            get: { !showsLists && (model.errorMessage != nil || moderationError != nil) },
            set: { if !$0 { model.errorMessage = nil; moderationError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? moderationError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        Section {
            HStack(spacing: DDSpacing.s) {
                Button { scanning = true } label: {
                    Label("Skann kode", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                }
                Button { showsCode = true } label: {
                    Label("Min kode", systemImage: "qrcode").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.dd(.secondary, compact: true))
            .disabled(model.client == nil)
        } footer: {
            DDFooter("Skann koden til den du vil følge, eller vis din egen. Den som skanner koden din, følger deg med en gang.")
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
        if let client = model.client {
            Section {
                if model.state == .loaded, model.suggestions.isEmpty {
                    Text("Ingen flere å foreslå. Folk fra klubben og rundene dine dukker opp her.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach($model.suggestions) { $person in
                    FollowSuggestionRow(client: client, userID: model.userID, person: $person)
                }
            } header: {
                DDHeader("Folk du kjenner")
            } footer: {
                DDFooter("Fra klubben, rundene og turneringene dine. Godkjenner de nye følgere, står du som «Venter» til de har svart.")
            }
        }
        Section {
            Button { showsLists = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Du følger og følgere").font(.ddBody).foregroundStyle(Color.ddInk)
                        Text(model.lists.countsText)
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.ddCaption.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let client = model.client {
                NavigationLink {
                    FollowingFeedView(model: FollowingFeedModel(client: client, userID: model.userID),
                                      showsAddFriends: false)
                        .navigationTitle("Runder")
                        .ddNavigationChrome()
                } label: {
                    Label("Runder fra dem du følger", systemImage: "figure.golf").labelStyle(DDIconLabelStyle())
                }
            }
        } footer: {
            DDFooter("Under «Du følger og følgere» bestemmer du også om nye følgere må godkjennes, og om du kan finnes i søk.")
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

/// «Du følger og følgere»: begge listene (sveip for å slutte å følge eller fjerne), og personvernet.
struct FollowListsView: View {
    @Bindable var model: FollowHubModel

    var body: some View {
        DDList {
            Section {
                if model.lists.following.isEmpty, model.state == .loaded {
                    Text("Du følger ingen ennå.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(model.lists.following) { row in
                    FollowPersonLink(client: model.client, userID: model.userID, row: row,
                                     subtitle: row.status == .pending ? "Venter på svar" : nil)
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
                    FollowPersonLink(client: model.client, userID: model.userID, row: row)
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
        .navigationTitle("Du følger og følgere")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .refreshable { await model.load() }
        .alert("Noe gikk galt", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
