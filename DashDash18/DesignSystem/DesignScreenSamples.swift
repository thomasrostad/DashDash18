#if DEBUG
import GolfgutuCore
import SwiftUI

/// Skjermprøver med ekte views og oppdiktede data, for forhåndsvisning og skjermbilder.
/// Åpnes i simulatoren med `-DDDesignScreen hullkort` (eller `feiring`, `tavla`, `tavlaferdig`, `tavlastableford`, `profil`, `sesong`,
/// `varsler`, `trad`, `liste`, `hurtigstart`, `flerevalg`, `arrangor`, `arrangorstart`, `runder`, `kveldene`, `kvelden`, `baner`, `nybane`, `regler`, `reglerendre`, `nyturnering`, `nyturnering2`, `turneringer`,
/// `statoversikt`, `stathistorikk`, `statrekorder`, `stattom`, `statforing`,
/// og løse runder: `losspill`, `losny`, `losbane`, `losinviter`, `losblimed`, `losrunde`, `losresultat`,
/// og spill på runden: `spill`, `spillnytt`, `spillresultat`,
/// og åpent for alle (fase 17): `apenvalg`, `apenlogin`, `apendeg`, `apenslett`, `apenrapport`,
/// `apenrapporter`, `apenblokkerte`, `apenbetaling`, `apenregning`,
/// og konkurranser: `konktavla`, `konkliste`, `konkliga`, `konkcup`, `konkteller`, `konkkveld`, `konklast`, `konklastdeltaker`,
/// og Hjem (fase 19): `hjem`, `hjemmidt`, `hjembunn`, `hjemlos`, `hjemtom`, `hjemarrangor`, `hjembjelle`,
/// og slope.no (fase 20): `slopesok`, `slopebane`, `teevalg`, `losnytee`, `hurtigstarttee`, med hull (fase 20b)
/// `slopevelg` og `slopeklubb`).
struct DesignScreenSamples: View {
    enum Screen: String {
        case hullkort, feiring, tavla, tavlaferdig, profil, sesong, varsler, trad, liste, hurtigstart, arrangor, runder
        // «Flere valg» på Ny runde (fase 18).
        case flerevalg
        // Arrangørsiden: «Kom i gang» (fase 11).
        case arrangorstart
        // Kveldene og Kvelden (fase 11).
        case kveldene, kvelden
        // Arrangør: banene og sesong og regler (fase 11).
        case baner, nybane, regler, reglerendre
        // Turnering med fire oppsett (fase 18).
        case nyturnering, nyturnering2, turneringer, tavlastableford
        // Statistikk (fase 16).
        case statoversikt, stathistorikk, statrekorder, stattom, statforing
        // Løse runder med venner (fase 13).
        case losspill, losny, losbane, losinviter, losblimed, losrunde, losresultat
        // Spill på runden (fase 14).
        case spill, spillnytt, spillresultat
        // Åpent for alle (fase 17).
        case apenvalg, apenlogin, apendeg, apenslett, apenrapport, apenrapporter, apenblokkerte, apenbetaling, apenregning
        // Flere konkurranser (fase 15).
        case konktavla, konkliste, konkliga, konkcup, konkteller, konkkveld
        // Låst konkurranse: betalingsknappen for eieren, teksten for deltakerne (fase 17).
        case konklast, konklastdeltaker
        // Hjem-fanen med feeden (fase 19).
        case hjem, hjemmidt, hjembunn, hjemlos, hjemtom, hjemarrangor, hjembjelle
        // Baner og tees fra slope.no (fase 20).
        case slopesok, slopebane, teevalg, losnytee, hurtigstarttee
        // Hentede baner med hull valgt direkte (fase 20b).
        case slopevelg, slopeklubb
    }
    @State var screen: Screen = .hullkort

    var body: some View {
        switch screen {
        case .hurtigstart:
            let model = RundeAdminModel.sample()
            NavigationStack {
                RundeQuickStartView(model: model, draft: model.newDraft()!, onDone: { _ in })
            }
            .tint(Color.ddForestInk)
        case .flerevalg:
            FlereValgSample()
                .tint(Color.ddForestInk)
        case .arrangor, .arrangorstart:
            NavigationStack { AdminHubSample(screen == .arrangorstart ? .gettingStarted : .tonight) }
                .tint(Color.ddForestInk)
        case .runder:
            NavigationStack { RundeAdminSample() }
                .tint(Color.ddForestInk)
        case .kveldene:
            NavigationStack { KveldeneSample() }
                .tint(Color.ddForestInk)
        case .kvelden:
            NavigationStack { KveldenSample() }
                .tint(Color.ddForestInk)
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
        case .baner, .nybane:
            BanerSampleScreen(newCourse: screen == .nybane)
                .tint(Color.ddForestInk)
        case .regler, .reglerendre:
            SesongSampleScreen(screen: screen)
                .tint(Color.ddForestInk)
        case .nyturnering, .nyturnering2, .turneringer:
            TurneringSampleScreen(screen: screen)
        case .tavlastableford:
            NavigationStack {
                TavlaList(standings: TavlaSamples.standings(stableford: true))
                    .navigationTitle("Tavla")
                    .ddNavigationChrome()
            }
            .tint(Color.ddForestInk)
        case .statoversikt, .stattom:
            NavigationStack { StatsView(model: StatsSamples.model(empty: screen == .stattom)) }
                .tint(Color.ddForestInk)
        case .stathistorikk:
            NavigationStack { StatsHistoryView(model: StatsSamples.model()) }
                .tint(Color.ddForestInk)
        case .statrekorder:
            NavigationStack { StatsRecordsView(model: StatsSamples.model()) }
                .tint(Color.ddForestInk)
        case .statforing:
            StatsEntrySample()
                .tint(Color.ddForestInk)
        case .losspill, .losny, .losbane, .losinviter, .losblimed, .losrunde, .losresultat:
            SpillSampleScreen(screen: screen)
        case .slopesok, .slopebane, .teevalg, .losnytee, .hurtigstarttee, .slopevelg, .slopeklubb:
            SlopeNoSampleScreen(screen: screen)
        case .spill, .spillresultat:
            GamesSampleScreen(finished: screen == .spillresultat)
        case .apenvalg, .apenlogin, .apendeg, .apenslett, .apenrapport, .apenrapporter, .apenblokkerte, .apenbetaling, .apenregning:
            ApenSampleScreen(screen: screen)
        case .spillnytt:
            SpillNyttSampleScreen()
        case .konktavla, .konkliste, .konkliga, .konkcup, .konkteller, .konkkveld, .konklast, .konklastdeltaker:
            KonkurranseSampleScreen(screen: screen)
        case .hjem: HjemSampleScreen(variant: .full)
        case .hjemmidt: HjemSampleScreen(variant: .middle)
        case .hjembunn: HjemSampleScreen(variant: .bottom)
        case .hjemlos: HjemSampleScreen(variant: .loose)
        case .hjemtom: HjemSampleScreen(variant: .empty)
        case .hjemarrangor: HjemSampleScreen(variant: .organizer)
        case .hjembjelle: HjemSampleScreen(variant: .bell)
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
