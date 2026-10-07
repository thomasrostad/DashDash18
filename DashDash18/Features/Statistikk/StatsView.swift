import GolfgutuCore
import SwiftUI

/// Statistikk: oversikt, grafer, beste runder og lenker til historikken og banerekordene.
struct StatsView: View {
    @State var model: StatsModel
    var title = "Statistikk"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                switch model.state {
                case .loading where model.rounds.isEmpty:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                case .failed(let message):
                    ContentUnavailableView("Fikk ikke hentet statistikken", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                default:
                    content
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .ddScreenBackground()
        .navigationTitle(title)
        .ddNavigationChrome()
        .task { if model.rounds.isEmpty { await model.load() } }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        if model.rounds.isEmpty {
            StatsEmptyCard(text: "Statistikken fylles ut når du har spilt en runde. Snitt, rekorder og handicap regnes fra slagene du fører.")
        } else {
            StatsFilterBar(model: model)
            if model.isFilteredEmpty {
                StatsEmptyCard(text: "Ingen runder i dette utvalget.", resetAction: { model.resetFilter() })
            } else if !model.hasEnoughData {
                StatsEmptyCard(text: "Ingen fullførte runder i utvalget ennå. Snitt og grafer kommer når alle hull i en runde er ført.")
                links
            } else {
                overview
                trend
                distribution
                parTypes
                shots
                handicap
                best
                links
            }
        }
    }

    // MARK: Seksjoner

    private var overview: some View {
        let s = model.summary
        let holes = model.primaryHoleCount
        let avg = holes.flatMap { s.averages[$0] }
        var tiles = [
            DDStatTile("Runder", value: "\(s.rounds.count)", detail: "\(s.completeRounds.count) fullført"),
            DDStatTile("Snitt slag", value: avg.map { StatsFormat.decimal($0.gross) } ?? "—",
                       detail: holes.map { "\($0) hull" }, highlight: true),
            DDStatTile("Snitt mot par", value: avg.map { StatsFormat.toPar($0.toPar, digits: 1) } ?? "—"),
            DDStatTile("Snitt stableford", value: avg.map { StatsFormat.decimal($0.stableford) } ?? "—"),
        ]
        if let best = s.bestByStableford(1, holes: holes).first {
            tiles.append(DDStatTile("Beste runde", value: "\(best.stableford) p",
                                    detail: "\(best.gross) slag · \(StatsFormat.shortDate(best.date))"))
        }
        if let index = s.currentIndex {
            tiles.append(DDStatTile("Indeks (WHS)", value: StatsFormat.index(index), detail: "uoffisiell"))
        }
        return VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
            DDSectionLabel("Oversikt")
            DDTileGrid(tiles)
        }
    }

    @ViewBuilder
    private var trend: some View {
        let holes = model.primaryHoleCount
        let lines = model.summary.trend.filter { $0.holeCount == holes }
        if lines.count >= 2 {
            DDSectionLabel("Trend") { Text("mot par · \(holes ?? 18) hull").ddEyebrow() }
                .padding(.top, DDSpacing.m)
            StatsTrendChart(lines: lines, window: StatsModel.trendWindow)
                .ddCard()
        }
    }

    private var distribution: some View {
        VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
            DDSectionLabel("Fordeling") { Text("\(model.summary.distribution.total) hull · brutto").ddEyebrow() }
                .padding(.top, DDSpacing.m)
            StatsDistributionChart(distribution: model.summary.distribution)
                .ddCard()
        }
    }

    private var parTypes: some View {
        VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
            DDSectionLabel("Per par-type").padding(.top, DDSpacing.m)
            DDTileGrid(model.summary.parTypes.map { p in
                DDStatTile("Par \(p.par)", value: StatsFormat.decimal(p.averageGross),
                           detail: "\(StatsFormat.toPar(p.averageToPar, digits: 2)) · \(p.holes) hull")
            })
        }
    }

    @ViewBuilder
    private var shots: some View {
        let s = model.summary.shots
        DDSectionLabel("Fairway, green og putter").padding(.top, DDSpacing.m)
        if s.hasAny {
            DDTileGrid([
                DDStatTile("Fairway", value: s.fairwayShare.map(StatsFormat.percent) ?? "—",
                           detail: s.fairwayHoles > 0 ? "\(s.fairwayLeft) venstre · \(s.fairwayRight) høyre" : nil),
                DDStatTile("Green i regulering", value: s.girShare.map(StatsFormat.percent) ?? "—",
                           detail: s.girHoles > 0 ? "\(s.girHit) av \(s.girHoles) hull" : nil),
                DDStatTile("Putter / runde", value: s.puttsPerRound.map { StatsFormat.decimal($0) } ?? "—",
                           detail: s.puttsPerHole.map { "\(StatsFormat.decimal($0, digits: 2)) per hull" }),
                DDStatTile("Sand save", value: s.sandSaveShare.map(StatsFormat.percent) ?? "—",
                           detail: s.bunkerVisits > 0 ? "\(s.bunkerVisits) bunkerhull" : nil),
                DDStatTile("Straffeslag", value: "\(s.penaltyTotal)",
                           detail: s.penaltyHoles > 0 ? "på \(s.penaltyHoles) førte hull" : nil),
            ])
        } else {
            Text("Før fairway, green og putter under hullet mens du spiller. Slå det på under Deg.")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ddCard(.empty)
        }
    }

    @ViewBuilder
    private var handicap: some View {
        let revisions = model.summary.handicap
        if !revisions.isEmpty {
            DDSectionLabel("Handicaputvikling") { Text("WHS · uoffisiell").ddEyebrow() }
                .padding(.top, DDSpacing.m)
            VStack(alignment: .leading, spacing: DDSpacing.m) {
                if revisions.filter({ $0.index != nil }).count >= 2 {
                    StatsHandicapChart(revisions: revisions)
                } else {
                    Text("Indeksen kommer etter tre runder med course rating og slope.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if let last = revisions.last {
                    LabeledContent("Siste score differential", value: StatsFormat.decimal(last.differential))
                        .font(.ddCallout)
                }
                DDFooter("Regnet etter WHS: beste 8 av de siste 20 differentialene, netto dobbel bogey per hull, "
                         + "myk og hard grense. Bare 18-hullsrunder der alle hull er ført og banen har CR og slope.")
            }
            .ddCard()
        }
    }

    @ViewBuilder
    private var best: some View {
        let rounds = model.summary.bestByStableford(3, holes: model.primaryHoleCount)
        if !rounds.isEmpty {
            DDSectionLabel("Beste runder") { Text("stableford").ddEyebrow() }
                .padding(.top, DDSpacing.m)
            VStack(spacing: 0) {
                ForEach(Array(rounds.enumerated()), id: \.element.id) { i, line in
                    DDRankRow(place: "\(i + 1).", name: line.courseName ?? "Ukjent bane",
                              detail: "\(StatsFormat.shortDate(line.date)) · \(line.gross) slag (\(StatsFormat.toPar(line.toPar)))") {
                        DDRankValue("\(line.stableford) p")
                    }
                    if i < rounds.count - 1 { DDDivider() }
                }
            }
            .ddCard(padding: DDSpacing.l)
        }
    }

    private var links: some View {
        VStack(spacing: 0) {
            NavigationLink { StatsHistoryView(model: model) } label: {
                StatsLinkRow(title: "Alle runder", detail: "\(model.summary.rounds.count)", systemImage: "list.bullet")
            }
            DDDivider()
            NavigationLink { StatsRecordsView(model: model) } label: {
                StatsLinkRow(title: "Banerekorder", detail: "\(model.summary.courseRecords.count)", systemImage: "trophy")
            }
        }
        .buttonStyle(.plain)
        .ddCard(padding: DDSpacing.l)
        .padding(.top, DDSpacing.m)
    }
}

/// Filtrene i én rad: klubb/løs, bane og periode.
struct StatsFilterBar: View {
    @Bindable var model: StatsModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.hasBothKinds {
                    Menu {
                        Picker("Runder", selection: $model.kind) {
                            Text("Alle runder").tag(StatsRound.Kind?.none)
                            Text("Klubbrunder").tag(StatsRound.Kind?.some(.club))
                            Text("Løse runder").tag(StatsRound.Kind?.some(.loose))
                        }
                    } label: {
                        chip(model.kind == nil ? "Alle runder" : model.kind == .club ? "Klubbrunder" : "Løse runder",
                             active: model.kind != nil)
                    }
                }
                if model.courses.count > 1 {
                    Menu {
                        Picker("Bane", selection: $model.courseID) {
                            Text("Alle baner").tag(String?.none)
                            ForEach(model.courses, id: \.id) { c in Text(c.name).tag(String?.some(c.id)) }
                        }
                    } label: {
                        chip(model.courses.first { $0.id == model.courseID }?.name ?? "Alle baner",
                             active: model.courseID != nil)
                    }
                }
                Menu {
                    Picker("Periode", selection: $model.period) {
                        ForEach(StatsPeriod.allCases) { p in Text(p.title).tag(p) }
                    }
                } label: {
                    chip(model.period.title, active: model.period != .all)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter")
    }

    private func chip(_ text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.down").imageScale(.small).accessibilityHidden(true)
        }
        .font(.ddChip)
        .foregroundStyle(active ? DDTone.sun.foreground : Color.ddForestInk)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(active ? DDTone.sun.background : Color.ddCard))
        .overlay(Capsule().strokeBorder(Color.ddCardBorder, lineWidth: active ? 0 : 1))
    }
}

struct StatsEmptyCard: View {
    let text: String
    var resetAction: (() -> Void)?

    var body: some View {
        VStack(spacing: DDSpacing.m) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title2)
                .foregroundStyle(Color.ddInkSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .multilineTextAlignment(.center)
            if let resetAction {
                Button("Vis alt", action: resetAction)
                    .buttonStyle(.dd(.secondary, compact: true))
            }
        }
        .frame(maxWidth: .infinity)
        .ddCard(.empty)
    }
}

private struct StatsLinkRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
                .labelStyle(DDIconLabelStyle())
                .font(.ddBody)
                .foregroundStyle(Color.ddInk)
            Spacer()
            Text(detail).font(.ddCallout).monospacedDigit().foregroundStyle(Color.ddInkSecondary)
            Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(Color.ddInkSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
