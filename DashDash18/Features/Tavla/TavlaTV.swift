import GolfgutuCore
import SwiftUI

/// TV-visning av Tavla (10.10.2026, fra analysen av andre golfapper: Golf Genius har en TV-modus for
/// klubbhuset). For skjermen i simulatorsenteret eller klubbhuset via AirPlay eller en iPad: store
/// tall, tabellen side for side, siste runde ved siden av, og alt oppdateres mens rundene føres.
nonisolated enum TavlaTV {
    /// Sidene tabellen deles i når den ikke får plass: [0..<8, 8..<16, …].
    static func pages(count: Int, perPage: Int) -> [Range<Int>] {
        guard count > 0, perPage > 0 else { return [] }
        return stride(from: 0, to: count, by: perPage).map { $0 ..< min($0 + perPage, count) }
    }

    /// Siste runde (nyeste kolonne) med de beste først: navn og poeng. Tom uten runder.
    static func latestRound(_ grid: RoundsGrid, limit: Int = 8) -> (title: String, isOngoing: Bool, lines: [(name: String, points: Double)])? {
        guard let n = grid.columns.indices.last else { return nil }
        let column = grid.columns[n]
        let lines = grid.rows.compactMap { row in row.points[n].map { (row.name, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : NorwegianSort.areInIncreasingOrder($0.0, $1.0) }
            .prefix(limit)
            .map { (name: $0.0, points: $0.1) }
        return (column.title, column.isOngoing, Array(lines))
    }

    /// Hvor lenge hver side står.
    static let pageSeconds: TimeInterval = 10
}

/// Fullskjerm for TV. Følger samme `TavlaModel` som Tavla, så nye scorer kommer inn av seg selv.
/// Liggende: tabellen og siste runde i to kolonner. Tabellen blar side for side av seg selv.
///
/// Størrelsene er faste og skaleres med skjermen (`scale`), ikke med Dynamic Type: TV-en leses på
/// avstand, og telefonens tekststørrelse gjelder ikke der.
struct TavlaTVView: View {
    private let model: TavlaModel?
    private let fixed: TavlaStandings?
    /// På den eksterne skjermen (AirPlay): ingen lukkeknapp, ingen kan trykke der.
    private let external: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: TavlaModel, external: Bool = false) {
        self.model = model
        fixed = nil
        self.external = external
    }

    #if DEBUG
    /// Skjermprøven `tavlatv`, uten nett.
    init(preview standings: TavlaStandings) {
        model = nil
        fixed = standings
        external = false
    }
    #endif

    private var standingsNow: TavlaStandings? { model?.standings ?? fixed }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.ddForestDeep.ignoresSafeArea()
                if let standings = standingsNow {
                    content(standings, size: geo.size)
                } else {
                    Text("Ingen turnering i gang")
                        .font(.ddTitle)
                        .foregroundStyle(Color.ddOnDark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !external {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.ddHeroSecondary)
                            .padding(12)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Lukk TV-visningen")
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // Skjermen skal ikke slukke mens Tavla står på veggen.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = TavlaExternalDisplay.shared.isConnected }
    }

    private func content(_ standings: TavlaStandings, size: CGSize) -> some View {
        let wide = size.width > size.height * 1.2
        let scale = min(max(size.width / (wide ? 1100 : 600), 0.8), 2.2)
        let rowHeight = 46 * scale
        let headerHeight = 110 * scale
        // Stående: siste runde står under tabellen og tar sin del av høyden.
        let latestHeight: CGFloat = wide ? 0 : min(size.height * 0.36, 360 * scale)
        let perPage = max(3, Int((size.height - headerHeight - latestHeight - 40 * scale) / rowHeight))
        let pages = TavlaTV.pages(count: standings.boardRows.count, perPage: perPage)
        let latest = TavlaTV.latestRound(standings.roundGrid)

        return VStack(alignment: .leading, spacing: 16 * scale) {
            header(standings, scale: scale)
            HStack(alignment: .top, spacing: 32 * scale) {
                TimelineView(.periodic(from: .now, by: TavlaTV.pageSeconds)) { context in
                    let page = pages.isEmpty ? 0
                        : Int(context.date.timeIntervalSinceReferenceDate / TavlaTV.pageSeconds) % pages.count
                    VStack(spacing: 0) {
                        if let range = pages.isEmpty ? nil : pages[page] {
                            ForEach(standings.boardRows[range]) { row in
                                tableRow(row, standings: standings, scale: scale, showsDetail: wide)
                                    .frame(height: rowHeight)
                            }
                        }
                        if pages.count > 1 {
                            HStack(spacing: 6 * scale) {
                                ForEach(pages.indices, id: \.self) { i in
                                    Circle().fill(Color.ddOnDark.opacity(i == page ? 0.9 : 0.25))
                                        .frame(width: 7 * scale, height: 7 * scale)
                                }
                            }
                            .padding(.top, 10 * scale)
                            .accessibilityLabel("Side \(page + 1) av \(pages.count)")
                        }
                    }
                    .animation(.easeInOut(duration: 0.6), value: page)
                }
                .frame(maxWidth: .infinity)
                if wide, let latest {
                    latestPanel(latest, scale: scale)
                        .frame(width: size.width * 0.32)
                }
            }
            if !wide, let latest {
                latestPanel((latest.title, latest.isOngoing, Array(latest.lines.prefix(5))), scale: scale)
            }
        }
        .padding(.horizontal, 40 * scale)
        .padding(.top, 28 * scale)
    }

    private func header(_ standings: TavlaStandings, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(standings.boardTitle)
                    .font(.dd(.sans, fixedSize: 34 * scale, weight: .semibold))
                Text(standings.progressText)
                    .font(.dd(.sans, fixedSize: 18 * scale))
                    .opacity(0.85)
            }
            Spacer()
            TVLiveBadge(scale: scale)
                .padding(.trailing, 16 * scale)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.dd(.sans, fixedSize: 30 * scale, weight: .light).monospacedDigit())
                    .opacity(0.8)
            }
        }
        .foregroundStyle(Color.ddOnDark)
        .padding(.leading, 28)
    }

    private func tableRow(_ row: TavlaStandings.Row, standings: TavlaStandings, scale: CGFloat,
                          showsDetail: Bool) -> some View {
        HStack(spacing: 18 * scale) {
            Text(standings.boardPlace(row))
                .font(.dd(.sans, fixedSize: 22 * scale, weight: .medium).monospacedDigit())
                .opacity(0.8)
                .frame(width: 44 * scale, alignment: .trailing)
            Text(row.name)
                .font(.dd(.sans, fixedSize: 26 * scale, weight: standings.isOnPodium(row) ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            if showsDetail {
                Text(standings.detail(row))
                    .font(.dd(.sans, fixedSize: 15 * scale))
                    .opacity(0.8)
                    .lineLimit(1)
            }
            Text(standings.points(row.total))
                .font(.dd(.sans, fixedSize: 28 * scale, weight: .semibold).monospacedDigit())
                .foregroundStyle(row.qualified && row.place == 1 ? Color.ddGold : Color.ddOnDark)
                .frame(minWidth: 70 * scale, alignment: .trailing)
        }
        .foregroundStyle(Color.ddOnDark)
        .accessibilityElement(children: .combine)
    }

    private func latestPanel(_ latest: (title: String, isOngoing: Bool, lines: [(name: String, points: Double)]),
                             scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            HStack(spacing: 8 * scale) {
                Text(latest.isOngoing ? "Pågår nå" : "Siste runde")
                    .font(.dd(.sans, fixedSize: 16 * scale, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(latest.isOngoing ? Color.ddGold : Color.ddHeroSecondary)
                if latest.isOngoing {
                    Circle().fill(Color.ddGold).frame(width: 8 * scale, height: 8 * scale)
                }
            }
            Text(latest.title)
                .font(.dd(.sans, fixedSize: 20 * scale))
                .foregroundStyle(Color.ddHeroSecondary)
            ForEach(Array(latest.lines.enumerated()), id: \.offset) { i, line in
                HStack {
                    Text("\(i + 1).").opacity(0.75).frame(width: 30 * scale, alignment: .trailing)
                    Text(line.name).lineLimit(1)
                    Spacer()
                    Text(RuleFormat.number(line.points)).font(.dd(.sans, fixedSize: 21 * scale, weight: .semibold)).monospacedDigit()
                }
                .font(.dd(.sans, fixedSize: 21 * scale))
                .foregroundStyle(Color.ddOnDark)
            }
        }
        .padding(20 * scale)
        .background(Color.ddOnDark.opacity(0.06), in: .rect(cornerRadius: 18 * scale))
    }
}

/// «Live»: tabellen på TV-en oppdateres mens rundene føres. Lime er fargen for live.
private struct TVLiveBadge: View {
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 8 * scale) {
            Circle()
                .fill(Color.ddLimeOnAccent)
                .frame(width: 9 * scale, height: 9 * scale)
            Text("Live")
                .font(.dd(.sans, fixedSize: 18 * scale, weight: .semibold))
                .foregroundStyle(Color.ddLimeOnAccent)
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 6 * scale)
        .background(Capsule().fill(Color.ddLime))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live")
    }
}
