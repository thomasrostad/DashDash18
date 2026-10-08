import GolfgutuCore
import SwiftUI

/// Designkatalogen: alle tokens og komponenter på én skjerm, for forhåndsvisning i Xcode.
struct DesignCatalogView: View {
    @State private var choice = 0
    @State private var segment = 0
    @State private var hole = 10

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.xxl) {
                golfee
                colors
                typography
                cards
                buttons
                chips
                holeCard
                holeTicks
                tavlaAndSocial
                NavigationLink("Listeprøve →") { DDListSample() }
                    .buttonStyle(.ddText)
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .ddScreenBackground()
        .navigationTitle("Designkatalog")
        .ddNavigationChrome()
    }

    /// Blandingen med konseptappen golfee: glass, grønn aktiv pille, gule nedtrekkspiller, svarte kort.
    private var golfee: some View {
        VStack(alignment: .leading, spacing: 12) {
            DDSectionLabel("Golfee-blanding")
            DDSegmentedControl([(0, "Hullet"), (1, "Scorekort"), (2, "Bayen")], selection: $segment)
            Menu {
                ForEach(1...18, id: \.self) { n in Button("Hull \(n)") { hole = n } }
            } label: {
                DDDropdownPill("Hull \(hole)")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Marco Simone · Ut").font(.ddBodyEmphasis)
                    Spacer()
                    DDPill("Live", tone: .gold)
                }
                DDStatRow(label: "Thomas", value: "19", secondary: "7", highlight: true)
                DDStatRow(label: "Kåre", value: "17", secondary: "7")
                DDStatRow(label: "Ola", value: "15", secondary: "6")
                DDStatRow(label: "Thomas og Kåre mot Ola og Per", value: "2 opp", highlight: true)
            }
            .ddCard(.stat)
            VStack(alignment: .leading, spacing: 6) {
                Text("Kort i glass over bakgrunnen").font(.ddBodyEmphasis)
                Text("Liquid Glass, stor radius, myk kant.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
            }
            .ddCard(.glass)
            Button("Lagre hull 7") {}.buttonStyle(.ddPrimary)
        }
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: 10) {
            DDSectionLabel("Farger")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(DDToken.allCases, id: \.self) { token in
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(token.color)
                            .frame(height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ddCardBorder))
                        Text(token.rawValue)
                            .font(.ddMonoSmall)
                            .foregroundStyle(Color.ddInkSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: 10) {
            DDSectionLabel("Typografi")
            VStack(alignment: .leading, spacing: 8) {
                Text("Atten").font(.ddDisplay).foregroundStyle(Color.ddForestInk)
                Text("Ingen runde på gang").font(.ddTitle).foregroundStyle(Color.ddForestInk)
                Text("Thomas").font(.ddName).foregroundStyle(Color.ddForestInk)
                Text("Brødtekst i Hanken Grotesk, som skalerer med Dynamic Type.").font(.ddBody)
                Text("Sekundærtekst under en rad").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                Text("Hull 7 av 18").ddEyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("7").font(.ddStrokes).foregroundStyle(Color.ddForestInk)
                    Text("168").font(.ddNumberLarge)
                    Text("3 brutto − 0 = 3 netto").font(.ddMonoSmall).foregroundStyle(Color.ddInkSecondary)
                }
            }
            .ddCard()
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: 10) {
            DDSectionLabel("Kort") {
                Button("Hele tavla →") {}.buttonStyle(.ddText)
            }
            Text("Vanlig kort med radius 16 og myk skygge.").ddCard()
            VStack(alignment: .leading, spacing: 6) {
                Text("Din score").ddEyebrow(color: Color.ddOnDark.opacity(0.55))
                Text("19").font(.ddDisplay)
                Text("poeng etter 7 hull").font(.ddCallout).foregroundStyle(Color.ddOnDark.opacity(0.72))
                DDDivider(onDark: true).padding(.vertical, 6)
                Button("Før poeng →") {}.buttonStyle(.dd(.secondary, compact: true, onDark: true))
            }
            .ddCard(.hero)
            VStack(spacing: 6) {
                Image(systemName: "flag").foregroundStyle(Color.ddRust)
                Text("Ingen runde på gang").font(.ddTitleSmall).foregroundStyle(Color.ddForestInk)
                Text("Arrangøren legger inn neste kveld.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
            }
            .frame(maxWidth: .infinity)
            .ddCard(.empty)
            DDInfoStripe(tone: .earth) {
                Text("**Du er markør i bås 1** · Kåre, Ola, Per og deg")
            }
            DDInfoStripe("Du ser på hull 5. Båsen er på hull 7.", tone: .sun)
            TextField("deg@epost.no", text: .constant("")).ddField()
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 10) {
            DDSectionLabel("Knapper")
            Button("Lagre hull 7") {}.buttonStyle(.ddPrimary)
            Button("Lagre hull 7 · 0 av 4 ført") {}.buttonStyle(.ddPrimary).disabled(true)
            Button("Send kode") {}.buttonStyle(.ddMoney)
            HStack {
                Button("Endre") {}.buttonStyle(.ddSecondary)
                Button("Meld inn") {}.buttonStyle(.ddGold)
                Button("Fjern") {}.buttonStyle(.ddDanger)
            }
            HStack {
                Button("‹ Forrige hull") {}.buttonStyle(.ddText)
                Button("Liten") {}.buttonStyle(.dd(.primary, compact: true))
            }
            Button("Ja, slett runden") {}.buttonStyle(.dd(.dangerFinal, fullWidth: true))
            HStack(spacing: 10) {
                Button("Kommer") { choice = 0 }.buttonStyle(DDChoiceButtonStyle(selected: choice == 0, tint: .lime))
                Button("Usikker") { choice = 1 }.buttonStyle(DDChoiceButtonStyle(selected: choice == 1, tint: .sun))
                Button("Kommer ikke") { choice = 2 }.buttonStyle(DDChoiceButtonStyle(selected: choice == 2, tint: .blush))
            }
        }
    }

    private var chips: some View {
        VStack(alignment: .leading, spacing: 10) {
            DDSectionLabel("Merker og piller")
            HStack(spacing: 6) {
                ForEach(ScoreName.allCases, id: \.self) { DDChip($0.label, tone: $0.tone, compact: true) }
            }
            HStack(spacing: 6) {
                DDPointsBadge(points: 1, name: .bogey)
                DDPointsBadge(points: 4, name: .eagle)
                DDPointsBadge(points: 2, name: .par)
                DDPointsBadge(points: 3, name: .birdie)
                DDPointsBadge(points: nil, name: nil)
            }
            HStack(spacing: 6) {
                DDPill("Åpent", tone: .lime)
                DDPill("Test", tone: .outlineRust)
                DDSidePrizeTag(kind: .longestDrive)
                DDSidePrizeTag(kind: .closestToPin)
            }
            HStack(spacing: 10) {
                DDAvatar(name: "Thomas Rostad")
                DDAvatar(name: "Kåre", size: 44)
                DDChip("Par? trykk tallet", tone: .earth, compact: true)
            }
        }
    }

    private var holeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DDSectionLabel("Hullkort")
            VStack(alignment: .leading, spacing: 0) {
                Text("Hull 7 av 18").ddEyebrow()
                Text("Par 3 · 155 m · indeks 17").font(.dd(.mono, size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Color.ddInkSecondary).padding(.top, 6)
                ForEach([("Thomas", false), ("Kåre", true)], id: \.0) { name, confirmed in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(.ddName).foregroundStyle(Color.ddForestInk)
                            Text("0 slag fått").font(.ddMonoSmall).foregroundStyle(Color.ddInkSecondary)
                            if confirmed { DDChip(ScoreName.par.label, tone: ScoreName.par.tone, compact: true) }
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            Button {} label: { Image(systemName: "minus") }
                                .buttonStyle(DDStepperButtonStyle(kind: .minus))
                            DDStrokeValue(value: "3", confirmed: confirmed)
                            Button {} label: { Image(systemName: "plus") }
                                .buttonStyle(DDStepperButtonStyle(kind: .plus))
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, confirmed ? 0 : 10)
                    .background(confirmed ? Color.clear : Color.ddYouRow, in: .rect(cornerRadius: 12))
                    .padding(.horizontal, confirmed ? 0 : -10)
                    .padding(.top, 10)
                }
            }
            .ddCard(.large)
        }
    }

    private var holeTicks: some View {
        VStack(alignment: .leading, spacing: 10) {
            DDSectionLabel("Hullprikker")
            HStack(spacing: 3) {
                ForEach(0..<18, id: \.self) { i in
                    DDHoleTick(
                        state: i < 6 ? .played : (i == 6 ? .partial : .upcoming),
                        isCurrent: i == 6,
                        marker: i == 3 ? .closestToPin : (i == 17 ? .longestDrive : .none),
                        isPending: i == 5,
                        isBayHole: i == 8
                    )
                }
            }
        }
    }
}

extension DesignCatalogView {
    /// Tavla (fliser, pall, rangering) og det sosiale (varsler, tråd).
    var tavlaAndSocial: some View {
        VStack(alignment: .leading, spacing: 12) {
            DDSectionLabel("Tavla")
            DDJacketHero(eyebrow: "Høst 2026 · mester", title: "Bjørn",
                         subtitle: "bærer den grønne jakka · 42 poeng")
            DDTileGrid([
                DDStatTile("Snitt / runde", value: "30"),
                DDStatTile("Beste runde", value: "36", highlight: true),
            ])
            VStack(spacing: 0) {
                DDRankRow(place: "1.", name: "Bjørn", detail: "+12 hull · 150 stableford") { DDRankValue("42") }
                DDDivider()
                DDRankRow(place: "2.", name: "Thomas", detail: "+4 hull · 138 stableford", isMe: true) {
                    DDRankValue("38")
                }
            }
            .ddCard(padding: DDSpacing.l)

            DDSectionLabel("Varsler og tråd")
            HStack(alignment: .top, spacing: 12) {
                DDIconTile(systemImage: "bird.fill")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ola birdie på hull 12").font(.ddBodyEmphasis)
                    HStack(spacing: 6) {
                        DDReactionChip(emoji: "🔥", count: 2, isMine: true)
                        DDReactionChip(emoji: "👍", count: 1)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("3 min").font(.ddMonoSmall).foregroundStyle(Color.ddInkSecondary)
                    DDUnreadDot()
                }
            }
            .ddCard()
            HStack(spacing: 10) {
                Image(systemName: "bell")
                    .foregroundStyle(Color.ddOnDark)
                    .overlay(alignment: .topTrailing) { DDCountBadge("3").fixedSize().offset(x: 10, y: -9) }
                    .padding(14)
                    .background(Circle().fill(Color.ddForest))
                Button {} label: { Image(systemName: "arrow.up") }
                    .buttonStyle(DDSendButtonStyle())
                    .accessibilityLabel("Send")
            }
            Text("Blir litt sen, starter dere uten meg?").ddBubble(mine: false)
            HStack {
                Spacer()
                Text("Vi venter ved båsen 👍").ddBubble(mine: true)
            }
        }
    }
}

/// Liste og skjema med designsystemet, for å se rader, overskrifter og felt.
struct DDListSample: View {
    @State private var name = "Thomas"
    @State private var on = true

    var body: some View {
        DDList {
            Section {
                // Hero-rad i en liste (Tippekupongen, Tippekongen): radens egen bakgrunn vinner over DDList.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tippekupongen").ddEyebrow(color: .ddGold)
                    Text("Torsdag 8. oktober").font(.ddTitle)
                }
                .foregroundStyle(Color.ddOnDark)
                .padding(.vertical, 8)
                .listRowBackground(Color.ddHeroCard)
            }
            Section {
                TextField("Ditt navn", text: $name)
                Toggle("Seedet", isOn: $on)
                LabeledContent("Handicap", value: "12,4")
                NavigationLink("Kåre") { Text("Kåre") }
            } header: {
                DDHeader("Troppen")
            } footer: {
                DDFooter("Navnet er det de andre ser i troppen.")
            }
            Section {
                Button("Lagre") {}
                Label("Klarte ikke å lagre. Prøv igjen.", systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
        }
        .navigationTitle("Listeprøve")
        .ddNavigationChrome()
    }
}

#Preview("Lys") {
    NavigationStack { DesignCatalogView() }
}

#Preview("Mørk") {
    NavigationStack { DesignCatalogView() }
        .preferredColorScheme(.dark)
}

#Preview("Stor tekst") {
    NavigationStack { DesignCatalogView() }
        .dynamicTypeSize(.accessibility2)
}
