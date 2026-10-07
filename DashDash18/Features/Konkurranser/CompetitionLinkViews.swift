import GolfgutuCore
import Observation
import Supabase
import SwiftUI

/// «Teller også i …» for en runde som settes opp: konkurransene du styrer der minst én av
/// spillerne er med, og hvilke som er valgt. Lagres med `set_round_competitions` (sql/022) etter
/// at runden er lagret eller startet.
@Observable
final class CompetitionLinkModel {
    private(set) var overview = CompetitionQueries.Overview()
    private(set) var members: [ClubMemberRow] = []
    /// Valgt av deg.
    var selected: Set<UUID> = []
    private(set) var isLoaded = false

    let access: CompetitionAccess
    private let client: SupabaseClient?

    init(client: SupabaseClient, access: CompetitionAccess) {
        self.client = client
        self.access = access
    }

    #if DEBUG
    init(preview overview: CompetitionQueries.Overview, members: [ClubMemberRow], access: CompetitionAccess,
         selected: Set<UUID>) {
        client = nil
        self.overview = overview
        self.members = members
        self.access = access
        self.selected = selected
        isLoaded = true
    }
    #endif

    /// Henter konkurransene, troppen i klubben (for å kjenne igjen profilene) og koblingene runden
    /// har fra før (en kladd som redigeres).
    func load(clubID: UUID?, roundID: UUID?) async {
        guard let client, CompetitionsFeature.isActive, !isLoaded else { return }
        do {
            overview = try await CompetitionQueries.overview(client: client)
            if let clubID {
                members = try await client.from("club_members").select(KveldQueries.memberColumns)
                    .eq("club_id", value: clubID).execute().value
            }
            if let roundID {
                let links = try await CompetitionQueries.links(client: client, roundID: roundID)
                selected = Set(links.filter { $0.source == .manual }.map(\.competitionID))
            }
            isLoaded = true
        } catch {
            // Uten konkurransene vises ikke valget; runden kan settes opp som før.
        }
    }

    func candidates(players: [CompetitionLinking.Player]) -> [CompetitionLinking.Candidate] {
        CompetitionLinking.candidates(competitions: overview.competitions, participants: overview.participants,
                                      members: members, access: access, players: players)
    }

    func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Lagrer valget for runden. Kastes ikke: gir en feilmelding, eller nil når det gikk.
    func save(roundID: UUID, players: [CompetitionLinking.Player]) async -> String? {
        guard let client, isLoaded else { return nil }
        let ids = CompetitionLinking.selection(selected, among: candidates(players: players))
        do {
            try await CompetitionQueries.setRoundCompetitions(client: client, roundID: roundID, ids: ids)
            return nil
        } catch {
            return "Runden ble ikke lagt i konkurransene. \(DataError.from(error).message)"
        }
    }
}

/// Seksjonen i oppsettet: én bryter per konkurranse runden kan telle i.
struct CountsAlsoInSection: View {
    @Bindable var model: CompetitionLinkModel
    let candidates: [CompetitionLinking.Candidate]

    var body: some View {
        if !candidates.isEmpty {
            Section {
                ForEach(candidates) { c in
                    Toggle(isOn: Binding(get: { model.selected.contains(c.id) }, set: { _ in model.toggle(c.id) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.competition.name)
                            Text("\(CompetitionText.kind(c.competition.kind)) · \(c.coverage)")
                                .font(.ddCaption)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                    }
                }
            } header: {
                DDHeader("Teller også i …")
            } footer: {
                DDFooter("Bare konkurranser du styrer, der noen av spillerne er med. De som ikke er med, telles ikke.")
            }
        }
    }
}

/// Velgeren øverst på Tavla når det finnes flere konkurranser enn jakkeracet.
struct CompetitionSwitcherBar: View {
    let competitions: [CompetitionRow]
    @Binding var selected: UUID?
    let mainID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(competitions) { c in
                    let isOn = (selected ?? mainID) == c.id
                    Button {
                        selected = c.id == mainID ? nil : c.id
                    } label: {
                        Label(c.name, systemImage: CompetitionListRow.icon(c.kind))
                            .font(.ddCallout.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(isOn ? Color.ddOnDark : Color.ddInk)
                            .background(isOn ? Color.ddForestInk : Color.ddCard, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }
}

/// Tavla med konkurransevelger (fase 15): jakkeracet som før, eller en annen konkurranse, og
/// veien til lista over konkurranser.
struct TavlaCompetitions<Main: View>: View {
    @State var model: CompetitionsModel
    @ViewBuilder let main: () -> Main

    @State private var selected: UUID?

    var body: some View {
        let switcher = model.switcher
        Group {
            if let id = selected, let c = model.all.first(where: { $0.id == id }), let client = model.client {
                CompetitionDetailView(model: CompetitionDetailModel(client: client, competition: c,
                                                                    participants: model.participants(c),
                                                                    access: model.access, main: model.main),
                                      list: model, embedded: true)
                    .id(id)
            } else {
                main()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if switcher.count > 1 || (switcher.count == 1 && switcher.first?.id != model.main?.id) {
                CompetitionSwitcherBar(competitions: switcher, selected: $selected, mainID: model.main?.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    CompetitionsListView(model: model)
                } label: {
                    Label("Konkurranser", systemImage: "trophy")
                }
                .tint(Color.ddOnDark)
            }
        }
        .task { await model.load() }
    }
}
