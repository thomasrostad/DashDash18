import GolfgutuCore
import SwiftUI

/// «Konkurranser»: alle du kan se, med påmelding og «Ny konkurranse». Åpnes fra Tavla.
struct CompetitionsListView: View {
    @Bindable var model: CompetitionsModel

    @State private var showsNew = false

    var body: some View {
        content
            .navigationTitle("Konkurranser")
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.canCreate {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Ny konkurranse", systemImage: "plus") { showsNew = true }
                    }
                }
            }
            .sheet(isPresented: $showsNew) {
                NavigationStack {
                    NewCompetitionView(model: model) { showsNew = false }
                }
            }
            .alert("Det gikk ikke", isPresented: Binding(get: { model.error != nil && !showsNew },
                                                         set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        let all = model.all
        if all.isEmpty {
            ScrollView {
                ContentUnavailableView {
                    Label("Ingen konkurranser ennå", systemImage: "trophy")
                } description: {
                    Text("Lag en liga, cup eller morroturnering, så teller rundene der i tillegg.")
                } actions: {
                    if model.canCreate {
                        Button("Ny konkurranse") { showsNew = true }
                            .buttonStyle(.dd(.primary))
                    }
                }
                .ddCard(.empty)
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
        } else {
            DDList {
                section("Pågår", all.filter { $0.status == .active })
                section("Planlagt", all.filter { $0.status == .planned })
                section("Ferdige", all.filter { $0.status == .finished })
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [CompetitionRow]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { c in
                    NavigationLink {
                        CompetitionDetailScreen(list: model, competition: c)
                    } label: {
                        CompetitionListRow(model: model, competition: c)
                    }
                }
            } header: {
                DDHeader(title)
            }
        }
    }
}

/// En konkurranse i lista: navn, type og eier, og påmeldingen din.
struct CompetitionListRow: View {
    let model: CompetitionsModel
    let competition: CompetitionRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: Self.icon(competition.kind))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ddForestInk)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(competition.name)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(CompetitionText.subtitle(competition, clubName: model.clubName(of: competition)))
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            if let pill {
                DDPill(pill.text, tone: pill.tone)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var pill: (text: String, tone: DDTone)? {
        switch model.signup(competition) {
        case .entered: return ("Påmeldt", .lime)
        case .open: return ("Åpen", .sun)
        case .closed, .notNeeded: return model.isAdmin(competition) && competition.kind != .season ? ("Arrangør", .earth) : nil
        }
    }

    static func icon(_ kind: CompetitionKind) -> String {
        switch kind {
        case .season: "trophy"
        case .league: "list.number"
        case .cup: "point.3.connected.trianglepath.dotted"
        case .fun: "party.popper"
        case .game: "die.face.5"
        }
    }
}

/// Påmeldingsknappen: «Meld meg på» når den er åpen, «Meld meg av» når du er med.
struct CompetitionSignupButton: View {
    let model: CompetitionsModel
    let competition: CompetitionRow

    @State private var confirmsLeave = false

    var body: some View {
        switch model.signup(competition) {
        case .open:
            Button("Meld meg på") { Task { await model.join(competition) } }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .disabled(model.busy != nil)
        case .entered:
            Button("Meld meg av") { confirmsLeave = true }
                .buttonStyle(.dd(.secondary, fullWidth: true))
                .disabled(model.busy != nil)
                .confirmationDialog("Meld deg av \(competition.name)?", isPresented: $confirmsLeave, titleVisibility: .visible) {
                    Button("Meld meg av", role: .destructive) { Task { await model.leave(competition) } }
                } message: {
                    Text(competition.kind == .cup
                         ? "Er cupen trukket, fører arrangøren walkover i kampen din."
                         : "Rundene du har spilt, står, men du forsvinner fra tabellen.")
                }
        case .closed, .notNeeded:
            EmptyView()
        }
    }
}
