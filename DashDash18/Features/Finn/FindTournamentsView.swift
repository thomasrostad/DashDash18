import Observation
import Supabase
import SwiftUI

@Observable
final class FindTournamentsModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }

    private(set) var rows: [PublicCompetitionRow] = []
    private(set) var state: LoadState = .loading
    var query = ""
    /// Turneringer du har rapportert (sql/066). Serveren tar dem ut av lista; dette skjuler dem med
    /// en gang, før lista er hentet på nytt.
    private(set) var hidden = HiddenContent()
    let client: SupabaseClient?

    init(client: SupabaseClient) { self.client = client }

    #if DEBUG
    init(preview rows: [PublicCompetitionRow]) {
        client = nil
        self.rows = rows
        state = .loaded
    }
    #endif

    var visible: [PublicCompetitionRow] { FindTournaments.visible(rows, query: query, hidden: hidden.competitions) }

    /// Kan turneringen rapporteres her? (`PublicContentReportFeature`, sql/066.)
    var canReport: Bool { PublicContentReportFeature.isEnabled && client != nil }

    func load() async {
        guard let client else { return }
        do {
            rows = try await FindTournaments.load(client: client)
            state = .loaded
        } catch is CancellationError {
        } catch {
            if rows.isEmpty { state = .failed(DataError.from(error).message) }
        }
        if PublicContentReportFeature.isEnabled,
           let fresh = try? await ModerationService(client: client).hiddenContent() {
            hidden = HiddenContent(competitions: fresh.competitions)
        }
    }

    /// Rapporterer turneringen (`report_content('competition', …)`). Med `hide` skjules den for deg
    /// med en gang; fra turneringssiden skjules den først når arket er lukket (`hide(_:)`), så siden
    /// ikke forsvinner under takken.
    func report(_ row: PublicCompetitionRow, reason: ReportReason, note: String, hide: Bool = true) async throws {
        guard let client else { throw DataError.offline }
        _ = try await ModerationService(client: client)
            .report(kind: .competition, targetID: row.id, reason: reason, note: note)
        if hide { self.hide(row) }
    }

    func hide(_ row: PublicCompetitionRow) {
        hidden.insert(.competition, row.id)
    }
}

/// «Finn turneringer»: åpne turneringer du kan melde deg på, med søk. Trykk gir turneringen med
/// påmeldingskortet (samme som på turneringssiden).
struct FindTournamentsView: View {
    @State var model: FindTournamentsModel
    /// Turneringen som rapporteres fra lista.
    @State private var reporting: PublicCompetitionRow?

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
                                detail(row)
                            } label: {
                                FindTournamentRow(row: row)
                            }
                            .contextMenu { reportButton(row) }
                            .swipeActions(edge: .trailing) { reportButton(row) }
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
        .sheet(item: $reporting) { row in
            ReportSheet(target: FindTournaments.reportTarget(row)) { reason, note, _ in
                try await model.report(row, reason: reason, note: note)
            }
        }
    }

    private func detail(_ row: PublicCompetitionRow) -> FindTournamentDetail {
        let model = model
        var onReport: ((ReportReason, String) async throws -> Void)?
        if model.canReport {
            onReport = { reason, note in try await model.report(row, reason: reason, note: note, hide: false) }
        }
        return FindTournamentDetail(row: row, client: model.client, onReport: onReport,
                                    onReported: { model.hide(row) }, onChange: { await model.load() })
    }

    @ViewBuilder
    private func reportButton(_ row: PublicCompetitionRow) -> some View {
        if model.canReport {
            Button("Rapporter turneringen", systemImage: "flag") { reporting = row }
                .tint(Color.ddRust)
        }
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
    /// «Rapporter turneringen» (sql/066). nil når flagget er av.
    var onReport: ((ReportReason, String) async throws -> Void)?
    /// Etter at arket er lukket: turneringen skjules i lista.
    var onReported: () -> Void = {}
    let onChange: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isReporting = false
    @State private var reported = false

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
                    DDFooter(row.signupOpen ? "Når du er påmeldt, står turneringen under «Turneringer» i Spill. Når en runde du spiller i går, fører du den fra turneringen («Før runden»)."
                                            : "Påmeldingen er ikke åpen nå.")
                }
            }
        }
        .navigationTitle(row.name)
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .toolbar {
            if onReport != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Mer", systemImage: "ellipsis") {
                        Button("Rapporter turneringen", systemImage: "flag") { isReporting = true }
                    }
                }
            }
        }
        // Rapportert: turneringen er skjult i lista, så siden lukkes når arket er borte.
        .sheet(isPresented: $isReporting, onDismiss: {
            guard reported else { return }
            dismiss()
            onReported()
        }) {
            ReportSheet(target: FindTournaments.reportTarget(row)) { reason, note, _ in
                try await onReport?(reason, note)
                reported = true
            }
        }
    }
}
