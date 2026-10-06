import GolfgutuCore
import SwiftUI

/// Designkatalogen: alle tokens og komponenter på én skjerm, for forhåndsvisning i Xcode.
struct DesignCatalogView: View {
    @State private var choice = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.xxl) {
                colors
                typography
                cards
                buttons
                chips
                holeCard
                holeTicks
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .ddScreenBackground()
        .navigationTitle("Designkatalog")
        .ddNavigationChrome()
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
                Text("GolfGutu").font(.ddDisplay).foregroundStyle(Color.ddForestInk)
                Text("Ingen runde på gang").font(.ddTitle).foregroundStyle(Color.ddForestInk)
                Text("Thomas").font(.ddName).foregroundStyle(Color.ddForestInk)
                Text("Brødtekst i Hanken Grotesk, som skalerer med Dynamic Type.").font(.ddBody)
                Text("Sekundærtekst under en rad").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                Text("Hull 7 av 18").ddEyebrow()
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text("7").font(.ddHoleNumber).foregroundStyle(Color.ddForestInk)
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
                Text("19").font(.ddHeroNumber)
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
                ForEach(ScoreName.allCases, id: \.self) { DDScoreBadge(name: $0, compact: true) }
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
                DDLivePill(text: "Runden pågår")
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
                            if confirmed { DDScoreBadge(name: .par, compact: true) }
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
