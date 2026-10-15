#if DEBUG
import GolfgutuCore
import SwiftUI

/// Skjermprøver med ekte views og oppdiktede data, for forhåndsvisning og skjermbilder.
/// Åpnes i simulatoren med `-DDDesignScreen hullkort` (eller `feiring`, `tavla`, `tavlaferdig`, `tavlastableford`, `profil`, `sesong`,
/// `varsler`, `trad`, `liste`, `hurtigstart`, `flerevalg`, `tavlaregler`, `arrangor`, `arrangorstart`, `arrangorpagar`, `arrangorferdig`, `arrangorbunn`, `runder`, `kveldene`, `kvelden`, `kveldenbunn`, `baner`, `nybane`, `regler`, `reglerendre`, `nyturnering`, `nyturnering2`, `turneringer`,
/// `statoversikt`, `stathistorikk`, `statrekorder`, `stattom`, `statforing`,
/// og løse runder: `losspill`, `losny`, `losbane`, `losinviter`, `losblimed`, `losrunde`, `losresultat`,
/// og spill på runden: `spill`, `spillnytt`, `spillresultat`,
/// og åpent for alle (fase 17): `apenvalg`, `apenlogin`, `apendeg`, `apenslett`, `apenrapport`,
/// `apenrapporter`, `apenblokkerte`, `apenbetaling`, `apenregning`,
/// og konkurranser: `konktavla`, `konkliste`, `konkliga`, `konkcup`, `konkteller`, `konkkveld`, `konklast`, `konklastdeltaker`,
/// og Hjem (fase 19): `hjem`, `hjemmidt`, `hjembunn`, `hjemlos`, `hjemtom`, `hjemarrangor`, `hjembjelle`,
/// og slope.no (fase 20): `slopesok`, `slopebane`, `teevalg`, `losnytee`, `hurtigstarttee`, med hull (fase 20b)
/// `slopevelg` og `slopeklubb`), og turneringen som kjerne (fase 23): `turneringvelger`, `pamelding`,
/// `pameldingvente`, `pameldinginnstillinger`, `startliste`, `stab`, `mingruppe`, `oppdater`,
/// og invitasjon til klubb: `velkommen`, `blimedlenke`, `blimedbekreft`, `logininvitasjon`, `inviter`, `hjeminviter`,
/// og markørkonflikten (K6/6.3): `markorkonflikt`, `markorkonfliktark`, `arrangorkonflikt`.
struct DesignScreenSamples: View {
    enum Screen: String {
        case hullkort, feiring, tavla, tavlaferdig, profil, sesong, varsler, trad, liste, hurtigstart, arrangor, runder
        // «Flere valg» på Ny runde (fase 18).
        case flerevalg
        // Tavla med tabellreglene (steg 6): playoff om førsteplassen og minste antall kvelder.
        case tavlaregler
        // Arrangørsiden: «Kom i gang» (fase 11).
        case arrangorstart
        // Kveldene og Kvelden (fase 11).
        case kveldene, kvelden
        // Arrangørsiden som tidslinje (fase 21): runde pågår, kvelden ferdig, bunnen, Kvelden rullet ned.
        case arrangorpagar, arrangorferdig, arrangorbunn, kveldenbunn
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
        case hjem, hjemmidt, hjembunn, hjemlos, hjemtom, hjemarrangor, hjembjelle, hjemflere
        // Baner og tees fra slope.no (fase 20).
        case slopesok, slopebane, teevalg, losnytee, hurtigstarttee
        // Hentede baner med hull valgt direkte (fase 20b).
        case slopevelg, slopeklubb
        // Turneringen som kjerne (fase 23): velger, påmelding, stab, startliste og minste bygg.
        case turneringvelger, pamelding, pameldingvente, pameldinginnstillinger, startliste, stab, mingruppe, oppdater
        // Invitasjon til klubb: start uten kode, «Bli med» fra lenken, arrangørsiden og Hjem.
        case velkommen, blimedlenke, blimedbekreft, logininvitasjon, inviter, hjeminviter
        // Fase 25: finn åpne turneringer, og QR-koden til invitasjonen.
        case finn, inviterqr
        // Alle runder i turneringen (leaderboard).
        case allerunder, allerunderliga, tavlatv
        // Tavla-segmentet «Statistikk» og trendgrafen alene (V4, V10).
        case tavlastatistikk, stattrend
        // To markører førte ulikt (K6/6.3, sql/055): føringen, arket og «I kveld».
        case markorkonflikt, markorkonfliktark, arrangorkonflikt
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
        case .arrangor, .arrangorstart, .arrangorpagar, .arrangorkonflikt, .arrangorferdig, .arrangorbunn, .kveldene:
            NavigationStack { adminHub }
                .tint(Color.ddForestInk)
        case .runder:
            NavigationStack { RundeAdminSample() }
                .tint(Color.ddForestInk)
        case .kvelden, .kveldenbunn:
            NavigationStack { KveldenSample(scrolledDown: screen == .kveldenbunn) }
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
        case .tavlaregler:
            NavigationStack {
                TavlaList(standings: TavlaSamples.standings(rules: Self.tableRulesSample))
                    .navigationTitle("Tavla")
                    .ddNavigationChrome()
            }
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
        case .hjemflere: HjemSampleScreen(variant: .several)
        case .hjeminviter: HjemSampleScreen(variant: .invite)
        case .velkommen, .blimedlenke, .blimedbekreft, .logininvitasjon:
            ClubInviteSampleScreen(screen: screen)
        case .inviter:
            NavigationStack { AdminHubSample(.tonight, scroll: .top) }
                .tint(Color.ddForestInk)
        case .liste:
            NavigationStack { DDListSample() }
                .tint(Color.ddForestInk)
        case .hullkort:
            // Føringen som i skissen (4.2): Losby hull 7, par 3, nærmest pinnen, fire i båsen.
            NavigationStack { RundeView(model: SpillSamples.foeringModel()) }
                .tint(Color.ddForestInk)
        case .turneringvelger:
            NavigationStack { AdminHubSample(.tonight, scroll: .top, picker: TournamentCoreSamples.picker()) }
                .tint(Color.ddForestInk)
        case .markorkonflikt:
            NavigationStack { RundeView(model: MarkerConflictSamples.model()) }
                .tint(Color.ddForestInk)
        case .markorkonfliktark:
            MarkerConflictSheetSample()
        case .tavlastatistikk: TavlaStatsSample()
        case .stattrend: StatsTrendSample()
        case .tavlatv:
            TavlaTVView(preview: TavlaSamples.standings())
        case .allerunderliga:
            if case .league(let standings)? = KonkurranseSamples.league().content {
                NavigationStack { RoundsLeaderboardView(grid: standings.roundGrid, game: standings.game) }
                    .tint(Color.ddForestInk)
            }
        case .allerunder:
            NavigationStack { TavlaRoundsView(standings: TavlaSamples.standings()) }
                .tint(Color.ddForestInk)
        case .finn:
            NavigationStack { FindTournamentsView(model: FindTournamentsModel(preview: FindTournamentsSamples.rows)) }
                .tint(Color.ddForestInk)
        case .inviterqr:
            if let invite = ClubInvite(code: "02E5172C87") {
                NavigationStack { InviteShareSheet(clubName: "Golfgutu Invitational", invite: invite) }
                    .tint(Color.ddForestInk)
            }
        case .pamelding:
            SignupSampleScreen(state: .offered)
        case .pameldingvente:
            SignupSampleScreen(state: .waitlisted)
        case .pameldinginnstillinger:
            NavigationStack { SignupSettingsView(model: TournamentCoreSamples.settings(), loads: false) }
                .tint(Color.ddForestInk)
        case .startliste:
            NavigationStack { StartListView(model: TournamentCoreSamples.startList(), loads: false) }
                .tint(Color.ddForestInk)
        case .stab:
            NavigationStack { StaffView(model: TournamentCoreSamples.staff(), loads: false) }
                .tint(Color.ddForestInk)
        case .mingruppe:
            MyGroupSampleScreen()
        case .oppdater:
            UpdateRequiredView(current: 41, required: 57)
        case .feiring:
            // Samme kilde som i appen: «HULL n · PAR p» fra hullet som ble lagret (K2).
            FeiringOverlay(celebration: Celebration(level: .eagle, eyebrow: "HULL 5 · PAR 5",
                                                    text: "To under par. Ikke for å bruse med fjæra, men det var pent.",
                                                    points: 4, place: 2, nextHole: 6)) {}
        }
    }

    @ViewBuilder
    private var adminHub: some View {
        switch screen {
        case .arrangorstart: AdminHubSample(.gettingStarted)
        case .arrangorpagar: AdminHubSample(.liveEvening)
        case .arrangorkonflikt: AdminHubSample(.liveEvening, conflicts: true)
        case .arrangorferdig: AdminHubSample(.finished)
        case .arrangorbunn: AdminHubSample(.liveEvening, scroll: .bottom)
        case .kveldene: AdminHubSample(.liveEvening, scroll: .top)
        default: AdminHubSample(.tonight)
        }
    }

    static let ids = (0..<4).map { _ in UUID() }

    static let dots: [HoleDot] = (0..<18).map { i in
        HoleDot(index: i, number: i + 1, state: i < 6 ? .done : .upcoming, isCurrent: i == 6,
                isPending: false, isLongestDrive: i == 17, isClosestToPin: i == 3, isBayHole: false)
    }

    static let card = HoleCard(
        holeIndex: 6, number: 7, par: 3, meters: "155", strokeIndex: 17, holeCount: 18, title: "Hull 7 av 18", detail: "Par 3 · 155 m · indeks 17",
        isLongestDrive: false, isClosestToPin: true, header: "Båsen", strokesLabel: "Slag · brutto",
        rows: [
            .init(memberID: ids[0], name: "Thomas", isMe: true, editable: true, confirmed: false, saved: nil,
                  value: 3, strokesReceived: 0, calculation: "3 brutto − 0 = 3 netto", scoreName: .par, points: 2),
            .init(memberID: ids[1], name: "Kåre", isMe: false, editable: true, confirmed: true, saved: nil,
                  value: 4, strokesReceived: 1, calculation: "4 brutto − 1 = 3 netto", scoreName: .par, points: 2),
            .init(memberID: ids[2], name: "Ola", isMe: false, editable: true, confirmed: true, saved: nil,
                  value: 2, strokesReceived: 0, calculation: "2 brutto − 0 = 2 netto", scoreName: .birdie, points: 3),
            .init(memberID: ids[3], name: "Per", isMe: false, editable: true, confirmed: true, saved: nil,
                  value: 5, strokesReceived: 1, calculation: "5 brutto − 1 = 4 netto", scoreName: .bogey, points: 1),
        ],
        mustConfirm: true, outsideTruncation: nil,
        action: .save(title: "Lagre hull 7 og gå videre", enabled: true, status: "3 av 4 endret fra par"),
        viewerHint: nil
    )
}

#Preview("Hullkort") { DesignScreenSamples(screen: .hullkort) }
#Preview("Hullkort mørk") { DesignScreenSamples(screen: .hullkort).preferredColorScheme(.dark) }
#Preview("Feiring") { DesignScreenSamples(screen: .feiring) }

extension DesignScreenSamples {
    /// Golfgutu med playoff om førsteplassen, hele poeng og minst 4 kvelder for plass.
    static var tableRulesSample: Ruleset {
        var r = Ruleset.golfgutu
        r.table.tieRule = .playoff
        r.table.roundingStep = 1
        r.table.minEvenings = 4
        return r
    }
}
#endif
