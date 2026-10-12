import Supabase
import SwiftUI

/// «Finn spillere» (`search_people`): minst tre tegn, og søket går først når du har sluttet å skrive.
struct FollowSearchView: View {
    let client: SupabaseClient
    let userID: UUID
    @State private var text = ""
    @State private var results: [PersonSearchRow] = []
    @State private var searched: String?
    @State private var isSearching = false
    @State private var error: String?

    var body: some View {
        DDList {
            if let hint = PeopleSearchQuery(text).hint {
                Section {
                    Text(hint).font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                } footer: {
                    DDFooter("Du finner bare dem som er synlige i søket. E-post og handicap vises ikke.")
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle() }
            }
            if searched != nil, results.isEmpty, !isSearching, error == nil, PeopleSearchQuery(text).hint == nil {
                Section {
                    Text("Fant ingen med det navnet.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                }
            }
            if !results.isEmpty {
                Section {
                    ForEach($results) { $row in
                        HStack(spacing: DDSpacing.s) {
                            NavigationLink {
                                PersonProfileView(client: client, userID: userID, profileID: row.id,
                                                  name: row.displayName, avatarPath: row.avatarPath)
                            } label: {
                                FollowPersonLabel(client: client, name: row.displayName, avatarPath: row.avatarPath,
                                                  subtitle: row.subtitle)
                            }
                            FollowStatusButton(client: client, profileID: row.id, name: row.displayName,
                                               status: $row.myStatus, source: .search)
                                .fixedSize()
                        }
                    }
                }
            }
        }
        .overlay { if isSearching && results.isEmpty { ProgressView() } }
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Navn")
        .autocorrectionDisabled()
        .navigationTitle("Finn spillere")
        .ddNavigationChrome()
        .task(id: text) { await search() }
    }

    private func search() async {
        guard case .ready(let query) = PeopleSearchQuery(text) else {
            results = []
            searched = nil
            error = nil
            return
        }
        // Venter til du har sluttet å skrive (60 søk i timen).
        try? await Task.sleep(for: PeopleSearchQuery.debounce)
        guard !Task.isCancelled, query != searched else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let rows = try await FollowService(client: client).search(query)
            guard !Task.isCancelled else { return }
            results = rows
            searched = query
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = FollowService.message(error)
        }
    }
}
