import GolfgutuCore
import SwiftUI

/// Tavla-fanen: sesongens tabell etter regelsettet, med spillerprofil og oppsummering.
struct TavlaView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            if CompetitionsFeature.isActive {
                // Fase 15: velger mellom jakkeracet og de andre konkurransene, og lista over dem.
                TavlaCompetitions(model: CompetitionsModel(context: context)) {
                    TavlaContent(model: TavlaModel(context: context))
                }
            } else {
                TavlaContent(model: TavlaModel(context: context))
            }
        } else {
            NoSeasonView()
        }
    }
}

private struct TavlaContent: View {
    @State var model: TavlaModel
    @State private var showsTV = false
    @State private var showsTVCode = false
    @State private var showsShare = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .task {
                await model.load()
                await model.follow()
            }
            .refreshable { await model.load() }
            .toolbar {
                if let standings = model.standings, standings.hasResults {
                    ToolbarItem(placement: .topBarTrailing) {
                        ResultShareButton(share: standings.share)
                            .tint(Color.ddForestInk)
                    }
                }
                // «Del tavla» (sql/056): lenken til Tavla i nettleseren for dem uten appen.
                if TavlaShareFeature.isEnabled, model.standings != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Del tavla", systemImage: "link") { showsShare = true }
                            .tint(Color.ddForestInk)
                    }
                }
                if model.standings != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Arrangøren kan også vise Tavla på en skjerm uten appen (TV-kode, sql/041).
                        if TVCodeFeature.isEnabled, model.clubContext.can(.tournaments) {
                            Menu {
                                Button("Vis på denne enheten", systemImage: "tv") { showsTV = true }
                                Button("TV-kode for en annen skjerm", systemImage: "qrcode") { showsTVCode = true }
                            } label: {
                                TVToolbarLabel()
                            }
                            .tint(Color.ddForestInk)
                        } else {
                            Button { showsTV = true } label: { TVToolbarLabel() }
                                .tint(Color.ddForestInk)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showsTV) { TavlaTVView(model: model) }
            .sheet(isPresented: $showsTVCode) {
                if let standings = model.standings {
                    NavigationStack {
                        TVCodeSheet(model: TVCodeModel(client: model.clubContext.client, seasonID: standings.seasonID,
                                                       competitionName: standings.seasonName))
                    }
                }
            }
            .sheet(isPresented: $showsShare) {
                if let standings = model.standings {
                    NavigationStack {
                        TavlaShareSheet(model: TavlaShareModel(client: model.clubContext.client, seasonID: standings.seasonID,
                                                               competitionName: standings.seasonName,
                                                               isOrganizer: model.clubContext.can(.tournaments)))
                    }
                }
            }
            // Tavla på en TV via AirPlay (V5): den ytre skjermen viser denne tabellen mens appen er åpen.
            .onAppear { TavlaExternalDisplay.shared.model = model }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter tabellen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet tabellen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if let standings = model.standings {
                TavlaList(standings: standings) { await model.load() }
            } else {
                // ScrollView, så «dra ned for å hente på nytt» virker også her.
                ScrollView {
                    NoSeasonView()
                        .ddCard(.empty)
                        .padding(.horizontal, DDSpacing.gutter)
                        .padding(.vertical, DDSpacing.l)
                }
            }
        }
    }
}

/// «TV» med AirPlay-ikonet i verktøylinja.
private struct TVToolbarLabel: View {
    var body: some View {
        Label("TV", systemImage: "airplayvideo")
            .labelStyle(.titleAndIcon)
            .accessibilityLabel("TV-visning")
    }
}

/// Hva Tavla viser under segmentet: tabellen, alle rundene eller turneringens tall.
enum TavlaSection: Hashable {
    case table, rounds, stats
}

/// Tavla for én turnering: segmentet «Tabell | Alle runder | Statistikk» og «Slik telles det» som ark (ⓘ).
struct TavlaList: View {
    let standings: TavlaStandings
    /// Hentes på nytt etter at en playoff er startet eller ført.
    var onChange: (() async -> Void)? = nil

    @State private var section: TavlaSection
    @State private var showsRules = false

    init(standings: TavlaStandings, onChange: (() async -> Void)? = nil, section: TavlaSection = .table) {
        self.standings = standings
        self.onChange = onChange
        _section = State(initialValue: section)
    }

    var body: some View {
        Group {
            switch section {
            case .table:
                TavlaTableSection(standings: standings, onChange: onChange)
            case .rounds:
                // Hva alle har slått, runde for runde, med scorekortet bak hver rute.
                RoundsLeaderboardView(grid: standings.roundGrid, game: standings.game, embedded: true)
            case .stats:
                TavlaStatsSection(standings: standings)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            DDSegmentedControl([(TavlaSection.table, "Tabell"), (.rounds, "Alle runder"), (.stats, "Statistikk")],
                               selection: $section)
                .accessibilityLabel("Vis")
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.s)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Slik telles det", systemImage: "info.circle") { showsRules = true }
                    .tint(Color.ddForestInk)
            }
        }
        .sheet(isPresented: $showsRules) {
            RulesExplanationSheet(rules: standings.rules)
        }
    }
}

/// Tabellen: fremdrift, delt ledelse, radene og det som hører til (playoff, lag mot lag, vedd).
private struct TavlaTableSection: View {
    let standings: TavlaStandings
    var onChange: (() async -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                if standings.status == .finished, standings.summary != nil {
                    NavigationLink {
                        SeasonSummaryView(standings: standings)
                    } label: {
                        FinishedSeasonCard()
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, DDSpacing.m)
                }

                // «Jakkeracet» er matchspill-seriens navn (PWA-en). En stableford-serie heter bare det den heter.
                DDSectionLabel(standings.countsStableford ? standings.seasonName : "Jakkeracet · \(standings.seasonName)")
                TavlaProgress(standings: standings)

                if let text = standings.leadTieText {
                    LeadTieCard(text: text, jacket: !standings.countsStableford)
                }

                if standings.isEmpty {
                    ContentUnavailableView("Ingen spillere ennå", systemImage: "person.3",
                                           description: Text("Troppen står her når arrangøren har lagt den inn."))
                        .ddCard(.empty)
                } else {
                    VStack(spacing: 0) {
                        TavlaColumnHeader(showsMovement: standings.showsMovement)
                        ForEach(standings.boardRows) { row in
                            DDDivider()
                            NavigationLink {
                                PlayerProfileView(standings: standings, memberID: row.memberID)
                            } label: {
                                TavlaRowView(row: row, standings: standings)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .ddCard(padding: DDSpacing.l)
                    if standings.hidesLastHoles {
                        DDInfoStripe(HiddenHoles.note + ".")
                    }
                    // Playoff om førsteplassen (sql/047).
                    PlayoffCard(standings: standings, onChange: onChange)
                    // Lag mot lag (sql/048): poengene til sidene over rundene.
                    if let table = standings.teamVsTeamTable {
                        TeamVsTeamTavlaCard(table: table)
                    }
                }
                BetsTavlaLink()
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
    }
}

/// «Kveld 5 av 7 spilt · Neste: onsdag 21. oktober» og en stripe med ett segment per kveld.
private struct TavlaProgress: View {
    let standings: TavlaStandings

    var body: some View {
        let total = standings.eveningsTotal
        VStack(alignment: .leading, spacing: 8) {
            Text([standings.progressText, standings.nextText()].compactMap(\.self).joined(separator: " · "))
                .font(.ddStatus)
                .foregroundStyle(Color.ddInkSecondary)
            if total > 0 {
                HStack(spacing: total > 20 ? 2 : 4) {
                    ForEach(0..<total, id: \.self) { i in
                        Capsule()
                            .fill(i < standings.eveningsPlayed ? Color.ddForestInk : Color.ddRule)
                            .frame(height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Hero-kortet ved delt ledelse: hvem som står likt, og hva som avgjør etter regelsettet.
private struct LeadTieCard: View {
    let text: String
    let jacket: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if jacket {
                    DDJacketIcon()
                        .stroke(Color.ddGold, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                        .frame(width: 26, height: 32)
                } else {
                    Image(systemName: "trophy")
                        .font(.title3)
                        .foregroundStyle(Color.ddGold)
                }
            }
            .accessibilityHidden(true)
            Text(text)
                .font(.ddBody)
                .foregroundStyle(Color.ddOnDark)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .ddCard(.hero)
        .accessibilityElement(children: .combine)
    }
}

/// Kolonneoverskriftene: # · SPILLER · (±) · POENG.
private struct TavlaColumnHeader: View {
    let showsMovement: Bool
    @ScaledMetric(relativeTo: .body) private var placeMetric: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var pointsMetric: CGFloat = 52
    @ScaledMetric(relativeTo: .footnote) private var movementMetric: CGFloat = 34
    // Faste kolonner vokser med teksten, men med tak, så navnet får plass i AX3 (ellers ble tabellen
    // bredere enn skjermen). Tallene i dem er låst til xxxL.
    private var placeWidth: CGFloat { min(placeMetric, 52) }
    private var pointsWidth: CGFloat { min(pointsMetric, 84) }
    private var movementWidth: CGFloat { min(movementMetric, 48) }

    var body: some View {
        HStack(spacing: 10) {
            Text("#").frame(width: placeWidth, alignment: .leading)
            Text("Spiller")
            Spacer(minLength: 8)
            if showsMovement {
                Text("±").frame(width: movementWidth, alignment: .center)
            }
            Text("Poeng").frame(width: pointsWidth, alignment: .trailing)
        }
        .ddEyebrow()
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }
}

/// «Slik telles det»: regelsettet i setninger, som ark fra ⓘ i verktøylinja.
struct RulesExplanationSheet: View {
    let rules: Ruleset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(RulesetExplanation.sentences(for: rules).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.ddBody)
                            .foregroundStyle(Color.ddInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .navigationTitle("Slik telles det")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") { dismiss() }
                        .tint(Color.ddForestInk)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// En rad i tabellen: plass (34 pt), spiller med linja under, bevegelse og poeng i fast kolonne.
struct TavlaRowView: View {
    let row: TavlaStandings.Row
    let standings: TavlaStandings
    @ScaledMetric(relativeTo: .body) private var placeMetric: CGFloat = 34
    @ScaledMetric(relativeTo: .title) private var pointsMetric: CGFloat = 52
    @ScaledMetric(relativeTo: .footnote) private var movementMetric: CGFloat = 34
    // Faste kolonner vokser med teksten, men med tak, så navnet får plass i AX3 (ellers ble tabellen
    // bredere enn skjermen). Tallene i dem er låst til xxxL.
    private var placeWidth: CGFloat { min(placeMetric, 52) }
    private var pointsWidth: CGFloat { min(pointsMetric, 84) }
    private var movementWidth: CGFloat { min(movementMetric, 48) }

    var body: some View {
        let movement = standings.movement(row)
        HStack(alignment: .center, spacing: 10) {
            Text(standings.boardPlace(row))
                .font(.ddBodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: placeWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.dd(.sans, size: 18, weight: .medium, relativeTo: .headline))
                        .foregroundStyle(Color.ddForestInk)
                    if row.isMe { DDYouBadge().fixedSize() }
                }
                Text(standings.boardDetail(row))
                    .font(.ddCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            if standings.showsMovement {
                Text(movement?.text ?? "")
                    .font(.ddStatus)
                    .monospacedDigit()
                    .foregroundStyle(color(movement))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(width: movementWidth, alignment: .center)
            }
            Text(standings.points(row.total))
                .font(.dd(.sans, size: 28, weight: .medium, relativeTo: .title))
                .monospacedDigit()
                .foregroundStyle(Color.ddInk)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(width: pointsWidth, alignment: .trailing)
        }
        .frame(minHeight: 60)
        .padding(.horizontal, row.isMe ? 10 : 0)
        .background {
            if row.isMe {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ddYouRow)
            }
        }
        .padding(.horizontal, row.isMe ? -10 : 0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(movement))
        .accessibilityHint("Åpner spillerprofilen")
    }

    private func color(_ movement: TavlaStandings.Movement?) -> Color {
        switch movement {
        case .up: Color.ddForestInk
        // Rust-tekst er for svak på din rad i mørk modus (DDContrastPairs).
        case .down: row.isMe ? Color.ddRustDark : Color.ddRustText
        default: Color.ddInkSecondary
        }
    }

    private func accessibilityText(_ movement: TavlaStandings.Movement?) -> String {
        let place = standings.boardPlace(row)
        var parts: [String] = []
        if place != "–" {
            parts.append(place.hasSuffix("=") ? "Delt \(row.place). plass" : "\(row.place). plass")
        }
        parts.append(row.isMe ? "\(row.name), deg" : row.name)
        parts.append("\(standings.points(row.total)) poeng")
        if let movement { parts.append(movement.spoken) }
        parts.append(standings.detail(row))
        return parts.joined(separator: ", ")
    }
}

/// Hero-kortet over tabellen når sesongen er ferdig: jakka og veien til oppsummeringen.
private struct FinishedSeasonCard: View {
    var body: some View {
        HStack(spacing: 14) {
            DDJacketIcon()
                .stroke(Color.ddGold, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                .frame(width: 30, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Turneringen er ferdig")
                    .font(.ddTitleSmall)
                Text("Se mesteren, pallen og turneringens tall.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddOnDark.opacity(0.8))
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .foregroundStyle(Color.ddGold)
                .accessibilityHidden(true)
        }
        .ddCard(.hero)
        .accessibilityElement(children: .combine)
    }
}


private struct NoSeasonView: View {
    @Environment(\.dayTerm) private var dayTerm
    var body: some View {
        ContentUnavailableView(
            "Ingen turnering i gang",
            systemImage: "trophy",
            description: Text("Tabellen fylles når arrangøren har startet turneringen og første \(dayTerm.one) er spilt.")
        )
    }
}

#Preview {
    NavigationStack {
        TavlaView()
    }
}
