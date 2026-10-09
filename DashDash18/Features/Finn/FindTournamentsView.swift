import Observation
import Supabase
import SwiftUI

@Observable
final class FindTournamentsModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }

    private(set) var rows: [PublicCompetitionRow] = []
    private(set) var state: LoadState = .loading
    var query = ""
    let client: SupabaseClient?

    init(client: SupabaseClient) { self.client = client }

    #if DEBUG
    init(preview rows: [PublicCompetitionRow]) {
        client = nil
        self.rows = rows
        state = .loaded
    }
    #endif

    var visible: [PublicCompetitionRow] { FindTournaments.filter(rows, query: query) }

    func load() async {
        guard let client else { return }
        do {
            rows = try await FindTournaments.load(client: client)
            state = .loaded
        } catch is CancellationError {
        } catch {
            if rows.isEmpty { state = .failed(DataError.from(error).message) }
        }
    }
}

/// «Finn turneringer»: åpne turneringer du kan melde deg på, med søk. Trykk gir turneringen med
/// påmeldingskortet (samme som på turneringssiden).
struct FindTournamentsView: View {
    @State var model: FindTournamentsModel

    var body: some View {
        DDList {
            switch model.state {
            case .loading:
                ProgressView("Henter turneringene …")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DDSpacing.l)
            case .failed(let message):
                Section {
                    Label(message, systemImage: "wifi.exclamationmark").ddErrorStyle()
                    Button("Prøv igjen") { Task { await model.load() } }
                }
            case .loaded:
                if model.visible.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "Ingen åpne turneringer" : "Ingen treff",
                                           systemImage: "trophy",
                                           description: Text(model.query.isEmpty
                                                             ? "Når en klubb eller et simulatorsenter åpner en turnering for alle, står den her."
                                                             : "Prøv et annet navn, en klubb eller et sted."))
                } else {
                    Section {
                        ForEach(model.visible) { row in
                            NavigationLink {
                                FindTournamentDetail(row: row, client: model.client) { await model.load() }
                            } label: {
                                FindTournamentRow(row: row)
                            }
                        }
                    } footer: {
                        DDFooter("Turneringer som er åpne for alle. Du ser tabellen når du er påmeldt.")
                    }
                }
            }
        }
        .searchable(text: $model.query, prompt: "Navn, klubb eller sted")
        .navigationTitle("Finn turneringer")
        .ddNavigationChrome()
        .task { await model.load() }
        .refreshable { await model.load() }
    }
}

private struct FindTournamentRow: View {
    let row: PublicCompetitionRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.name)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Spacer(minLength: 8)
                DDPill(CompetitionText.kind(row.kind), tone: .lime)
            }
            let subtitle = FindTournaments.subtitle(row)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Text(FindTournaments.places(row))
                .font(.ddCaption)
                .foregroundStyle(row.signupOpen ? Color.ddForestInk : Color.ddInkSecondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Én åpen turnering: hva, hvor, når, plassene, og påmeldingen.
private struct FindTournamentDetail: View {
    let row: PublicCompetitionRow
    let client: SupabaseClient?
    let onChange: () async -> Void

    var body: some View {
        DDList {
            Section {
                LabeledContent("Type", value: CompetitionText.kind(row.kind))
                if let club = row.clubName { LabeledContent("Arrangør", value: club) }
                if let venue = row.venue, !venue.isEmpty { LabeledContent("Sted", value: venue) }
                if let period = FindTournaments.period(row) { LabeledContent("Når", value: period) }
                LabeledContent("Plasser", value: FindTournaments.places(row))
            }
            if let client {
                Section {
                    CompetitionSignupSection(model: CompetitionSignupModel(client: client, competitionID: row.id),
                                             competitionName: row.name, onChange: onChange)
                } footer: {
                    DDFooter(row.signupOpen ? "Når du er påmeldt, står turneringen under «Turneringer» i Spill."
                                            : "Påmeldingen er ikke åpen nå.")
                }
            }
        }
        .navigationTitle(row.name)
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
    }
}
