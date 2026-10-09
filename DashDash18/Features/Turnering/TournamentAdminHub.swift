import Observation
import Supabase
import SwiftUI

/// Klubbens turneringer til velgeren øverst på arrangørsiden (fase 23).
@Observable
final class TournamentPickerModel {
    private(set) var rows: [CompetitionRow] = []
    private(set) var options: [TournamentOption] = []
    private(set) var isLoaded = false

    private let client: SupabaseClient?
    private let clubID: UUID

    init(client: SupabaseClient, clubID: UUID) {
        self.client = client
        self.clubID = clubID
    }

    #if DEBUG
    init(preview rows: [CompetitionRow], clubID: UUID) {
        client = nil
        self.clubID = clubID
        self.rows = rows
        options = TournamentPicker.options(rows, clubID: clubID)
        isLoaded = true
    }
    #endif

    /// En feil gir ingen velger: arrangørsiden er som før (hovedturneringen).
    func load() async {
        guard let client else { return }
        if let rows = try? await TournamentCoreQueries.clubCompetitions(client: client, clubID: clubID) {
            self.rows = rows
            options = TournamentPicker.options(rows, clubID: clubID)
        }
        isLoaded = true
    }

    func row(_ id: UUID?) -> CompetitionRow? {
        id.flatMap { id in rows.first { $0.id == id } }
    }
}

/// Velgeren og turneringens påmelding og stab, slik arrangørsiden viser dem.
struct TournamentHeader {
    let options: [TournamentOption]
    let selectedID: UUID?
    let competition: CompetitionRow?
    let context: ClubContext
    let select: (TournamentOption) -> Void
}

/// Velgeren øverst: vises bare når klubben har mer enn én turnering som ikke er ferdig.
struct TournamentPickerSection: View {
    let header: TournamentHeader

    private var selected: TournamentOption? {
        header.options.first { $0.id == header.selectedID }
    }

    var body: some View {
        if TournamentPicker.showsPicker(header.options) {
            Section {
                Menu {
                    ForEach(header.options) { option in
                        Button {
                            header.select(option)
                        } label: {
                            if option.id == selected?.id {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                            Text(option.subtitle)
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected?.name ?? "Kveldene")
                                .font(.ddBodyEmphasis)
                                .foregroundStyle(Color.ddInk)
                            Text(selected?.subtitle ?? "Kvelder uten turnering. Velg en turnering.")
                                .font(.ddCaption)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.ddForestInk)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .accessibilityLabel("Turnering: \(selected?.name ?? "ingen valgt")")
                .accessibilityHint("Bytter turneringen arrangørsiden viser")
            } header: {
                DDHeader("Turnering")
            } footer: {
                DDFooter("\(header.options.count) turneringer i klubben. Arrangørsiden viser den du velger.")
            }
        }
    }
}

/// «Påmelding» og «Stab» for den valgte turneringen (i Oppsett, eller øverst for en turnering uten
/// kvelder). Påmelding vises ikke når hele troppen er med.
struct TournamentSetupRows: View {
    let competition: CompetitionRow
    let context: ClubContext

    var body: some View {
        if competition.entry != .club {
            NavigationLink {
                SignupSettingsView(model: SignupSettingsModel(client: context.client, competition: competition))
            } label: {
                AdminHubRow("Påmelding", "Åpen eller stengt, tak, venteliste og påmeldingsvindu.",
                            systemImage: "person.crop.circle.badge.plus")
            }
        }
        NavigationLink {
            StaffView(model: StaffModel(client: context.client, competition: competition, me: context.user.id))
        } label: {
            AdminHubRow("Stab", "Flere arrangører og funksjonærer som fører for gruppene sine.",
                        systemImage: "person.2.badge.gearshape")
        }
    }
}

/// Arrangørsiden for en turnering uten kvelder (liga, cup, morro): velgeren, tabellen og
/// påmeldte, påmeldingen og staben. Spilledager per turnering kommer i trinn 3 (sql/033).
struct CompetitionAdminPanel: View {
    let header: TournamentHeader
    @State private var showsNewTournament = false

    var body: some View {
        DDList {
            TournamentPickerSection(header: header)
            if let invite = TroppInvite.invite(header.context.membership.club.joinCode) {
                Section {
                    InvitePlayersRow(clubName: header.context.membership.club.name, invite: invite)
                }
            }
            if let competition = header.competition {
                Section {
                    NavigationLink {
                        CompetitionDetailScreen(list: CompetitionsModel(context: header.context), competition: competition)
                    } label: {
                        AdminHubRow("Tabell og påmeldte", CompetitionText.subtitle(competition, clubName: nil),
                                    systemImage: "trophy")
                    }
                    TournamentSetupRows(competition: competition, context: header.context)
                } header: {
                    DDHeader(competition.name)
                } footer: {
                    DDFooter("Egne spilledager for denne turneringen kommer i neste steg. Til da legges runder i turneringen med «Teller også i …» når runden settes opp.")
                }
            }
        }
        .navigationTitle("Arrangørsiden")
        .ddNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ny turnering", systemImage: "plus") { showsNewTournament = true }
            }
        }
        .newTournamentSheet(isPresented: $showsNewTournament, seasons: SesongAdminModel(context: header.context),
                            competitions: CompetitionsModel(context: header.context))
    }
}
