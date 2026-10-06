#if DEBUG
import GolfgutuCore
import SwiftUI

/// Skjermprøver med ekte views og oppdiktede data, for forhåndsvisning og skjermbilder.
/// Åpnes i simulatoren med `-DDDesignScreen hullkort` (eller `feiring`, `tavla`, `profil`, `sesong`,
/// `varsler`, `trad`).
struct DesignScreenSamples: View {
    enum Screen: String { case hullkort, feiring, tavla, tavlaferdig, profil, sesong, varsler, trad, liste }
    @State var screen: Screen = .hullkort

    var body: some View {
        switch screen {
        case .tavla, .tavlaferdig:
            NavigationStack {
                TavlaList(standings: TavlaSamples.standings(finished: screen == .tavlaferdig))
                    .navigationTitle("Tavla")
                    .ddNavigationChrome()
            }
            .tint(Color.ddForestInk)
        case .profil:
            NavigationStack {
                PlayerProfileView(standings: TavlaSamples.standings(), memberID: TavlaSamples.me)
            }
            .tint(Color.ddForestInk)
        case .sesong:
            NavigationStack {
                SeasonSummaryView(standings: TavlaSamples.standings(finished: true))
            }
            .tint(Color.ddForestInk)
        case .varsler:
            VarslerSampleScreen()
                .tint(Color.ddForestInk)
        case .trad:
            TradSampleScreen()
                .tint(Color.ddForestInk)
        case .liste:
            NavigationStack { DDListSample() }
                .tint(Color.ddForestInk)
        case .hullkort:
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DDInfoStripe(tone: .earth) {
                            Text("**Du er markør i bås 1** · Kåre, Ola, Per og deg")
                        }
                        HullprikkerView(dots: Self.dots) { _ in }
                        HullkortView(card: Self.card, isPending: false, isSaving: false, error: nil,
                                     onStep: { _, _ in }, onConfirm: { _ in }, onSave: {}, onGoTo: { _ in },
                                     onScorecard: { _ in })
                    }
                    .padding(.horizontal, DDSpacing.gutter)
                    .padding(.vertical, DDSpacing.l)
                }
                .navigationTitle("Runde 6")
                .navigationBarTitleDisplayMode(.inline)
                .ddNavigationChrome()
            }
        case .feiring:
            FeiringOverlay(celebration: Celebration(level: .eagle, eyebrow: "Hull 7 · par 4",
                                                    text: "To under par. Ikke for å bruse med fjæra, men det var pent.",
                                                    points: 4, place: 2, nextHole: 8)) {}
        }
    }

    static let ids = (0..<4).map { _ in UUID() }

    static let dots: [HoleDot] = (0..<18).map { i in
        HoleDot(index: i, number: i + 1, state: i < 6 ? .done : .upcoming, isCurrent: i == 6,
                isPending: false, isLongestDrive: i == 17, isClosestToPin: i == 3, isBayHole: false)
    }

    static let card = HoleCard(
        holeIndex: 6, title: "Hull 7 av 18", detail: "Par 3 · 155 m · indeks 17",
        isLongestDrive: false, isClosestToPin: true, header: "Båsen", strokesLabel: "Slag · brutto",
        rows: [
            .init(memberID: ids[0], name: "Thomas", isMe: true, editable: true, confirmed: false, saved: nil,
                  value: 3, strokesReceived: 0, calculation: nil, scoreName: nil, points: nil),
            .init(memberID: ids[1], name: "Kåre", isMe: false, editable: true, confirmed: true, saved: nil,
                  value: 4, strokesReceived: 1, calculation: "4 brutto − 1 = 3 netto", scoreName: .par, points: 2),
            .init(memberID: ids[2], name: "Ola", isMe: false, editable: true, confirmed: true, saved: nil,
                  value: 2, strokesReceived: 0, calculation: "2 brutto − 0 = 2 netto", scoreName: .birdie, points: 3),
            .init(memberID: ids[3], name: "Per", isMe: false, editable: true, confirmed: true, saved: nil,
                  value: 5, strokesReceived: 1, calculation: "5 brutto − 1 = 4 netto", scoreName: .bogey, points: 1),
        ],
        mustConfirm: true, showsParHint: true, outsideTruncation: nil,
        action: .save(title: "Lagre hull 7 · 3 av 4 ført", enabled: false, blocker: "Bekreft Thomas først."),
        viewerHint: nil
    )
}

#Preview("Hullkort") { DesignScreenSamples(screen: .hullkort) }
#Preview("Hullkort mørk") { DesignScreenSamples(screen: .hullkort).preferredColorScheme(.dark) }
#Preview("Feiring") { DesignScreenSamples(screen: .feiring) }
#endif
