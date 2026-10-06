import SwiftUI

/// Svart statistikk-flis (golfee): etikett i mono versaler, stort lett tall, valgfri linje under.
/// Brukes i rutenett, f.eks. «Snitt / runde» og «Beste runde» på spillerprofilen.
struct DDStatTile: View {
    let label: String
    let value: String
    var detail: String?
    /// Tallet i gult (det som utheves).
    var highlight = false

    init(_ label: String, value: String, detail: String? = nil, highlight: Bool = false) {
        self.label = label
        self.value = value
        self.detail = detail
        self.highlight = highlight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .ddEyebrow(color: .ddStatSecondary)
                .lineLimit(2)
            Text(value)
                .font(.dd(.sans, size: 30, weight: .light, relativeTo: .title))
                .monospacedDigit()
                .foregroundStyle(highlight ? Color.ddYellow : Color.ddStatText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddStatSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ddCard(.stat, padding: DDSpacing.l)
        .accessibilityElement(children: .combine)
    }
}

/// Fliser i to kolonner, én kolonne ved store tekststørrelser. Flisene i en rad blir like høye.
struct DDTileGrid: View {
    let tiles: [DDStatTile]
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ tiles: [DDStatTile]) {
        self.tiles = tiles
    }

    var body: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        let rows = stride(from: 0, to: tiles.count, by: columns).map {
            Array(tiles[$0..<min($0 + columns, tiles.count)])
        }
        Grid(horizontalSpacing: DDSpacing.cardGap, verticalSpacing: DDSpacing.cardGap) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(rows[r].indices, id: \.self) { i in rows[r][i] }
                    if rows[r].count < columns {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

/// Grønt hero-kort med jakka i gull over (`.gg-green` med `ICON_JACKET2`): mester og jakkeracet.
struct DDJacketHero<Footer: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var footer: Footer

    init(eyebrow: String, title: String, subtitle: String? = nil, @ViewBuilder footer: () -> Footer) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 10) {
            DDJacketIcon()
                .stroke(Color.ddGold, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                .frame(width: 40, height: 48)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
            Text(eyebrow)
                .ddEyebrow(color: .ddGold)
                .multilineTextAlignment(.center)
            Text(title)
                .font(.dd(.sans, size: 40, weight: .light, relativeTo: .largeTitle))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddOnDark.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            footer
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DDSpacing.m)
        .ddCard(.hero)
    }
}

extension DDJacketHero where Footer == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Rad i en rangert liste (tabell, pall, resultat): plass, navn, detalj og tall.
/// `isMe` gir gul «DEG»-flate og merke, som `.gg-hullrad.deg` i PWA-en.
struct DDRankRow<Trailing: View>: View {
    let place: String
    let name: String
    var detail: String?
    var isMe = false
    @ViewBuilder var trailing: Trailing

    init(place: String, name: String, detail: String? = nil, isMe: Bool = false,
         @ViewBuilder trailing: () -> Trailing) {
        self.place = place
        self.name = name
        self.detail = detail
        self.isMe = isMe
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(place)
                .font(.ddMonoSmall)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .frame(minWidth: 26, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.ddName)
                        .foregroundStyle(Color.ddForestInk)
                    if isMe {
                        DDPill("Deg", tone: .gold)
                            .fixedSize()
                            .accessibilityLabel("deg")
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.ddCaption)
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isMe ? 10 : 0)
        .background {
            if isMe {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ddYouRow)
            }
        }
        .padding(.horizontal, isMe ? -10 : 0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension DDRankRow where Trailing == EmptyView {
    init(place: String, name: String, detail: String? = nil, isMe: Bool = false) {
        self.init(place: place, name: name, detail: detail, isMe: isMe) { EmptyView() }
    }
}

/// Tall til høyre i en rangert rad (`0` i tabellen, `12 p` på pallen).
struct DDRankValue: View {
    let text: String
    var emphasized = true

    init(_ text: String, emphasized: Bool = true) {
        self.text = text
        self.emphasized = emphasized
    }

    var body: some View {
        Text(text)
            .font(emphasized ? .ddNumber : .ddBody)
            .monospacedDigit()
            .foregroundStyle(Color.ddInk)
    }
}

#Preview("Fliser og rangering") {
    ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            DDJacketHero(eyebrow: "Sesongen 2026 · mester", title: "Bjørn",
                         subtitle: "42 poeng · 30 fra 7 dueller")
            DDTileGrid([
                DDStatTile("Snitt / runde", value: "30"),
                DDStatTile("Beste runde", value: "36", highlight: true),
                DDStatTile("Birdies", value: "7"),
            ])
            VStack(spacing: 0) {
                DDRankRow(place: "1.", name: "Bjørn", detail: "+12 hull · 150 stableford") { DDRankValue("42") }
                DDDivider()
                DDRankRow(place: "2.", name: "Thomas", detail: "+4 hull", isMe: true) { DDRankValue("38") }
            }
            .ddCard()
        }
        .padding(DDSpacing.gutter)
    }
    .ddScreenBackground()
}
