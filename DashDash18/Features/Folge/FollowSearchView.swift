import Foundation
import Observation
import Supabase
import SwiftUI

/// Navnesøket øverst i «Følger» (`search_people`): minst tre tegn, og søket går først når du har
/// sluttet å skrive.
@Observable
final class FollowSearchModel {
    var text = ""
    var results: [PersonSearchRow] = []
    private(set) var searched: String?
    private(set) var isSearching = false
    private(set) var error: String?

    let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    /// Noe står i feltet: resultatene vises i stedet for resten av skjermen.
    var isActive: Bool { PeopleSearchQuery(text) != .empty }

    /// «Fant ingen med det navnet.»
    var showsNoMatch: Bool {
        searched != nil && results.isEmpty && !isSearching && error == nil && PeopleSearchQuery(text).hint == nil
    }

    func search() async {
        guard case .ready(let query) = PeopleSearchQuery(text) else {
            results = []
            searched = nil
            error = nil
            return
        }
        guard let client else { return }
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

/// Treffene i søket: portrett og navn (åpner profilen) og Følg / Venter / Følger.
struct FollowSearchResults: View {
    @Bindable var search: FollowSearchModel
    let client: SupabaseClient
    let userID: UUID

    var body: some View {
        if let hint = PeopleSearchQuery(search.text).hint {
            Section {
                Text(hint).font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
            } footer: {
                DDFooter("Du finner bare dem som er synlige i søket. E-post og handicap vises ikke.")
            }
        }
        if let error = search.error {
            Section { Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle() }
        }
        if search.showsNoMatch {
            Section {
                Text("Fant ingen med det navnet.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
            }
        }
        if search.isSearching && search.results.isEmpty {
            Section { ProgressView().frame(maxWidth: .infinity) }
        }
        if !search.results.isEmpty {
            Section {
                ForEach($search.results) { $row in
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
}
