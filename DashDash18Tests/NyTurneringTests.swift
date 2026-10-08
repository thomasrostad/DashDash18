import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Fase 18: «Ny turnering» med fire oppsett, «Alle turneringer» og Tavla for stableford-serie.
struct NyTurneringTests {
    private static let club = UUID()
    private static let oct2026 = Date(timeIntervalSince1970: 1_791_453_600) // 8. oktober 2026, 12:00 i Oslo

    private static var oslo: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Oslo")!
        return c
    }

    private static func date(_ month: Int) -> Date {
        oslo.date(from: DateComponents(year: 2026, month: month, day: 15, hour: 12))!
    }

    // MARK: Hvilke oppsett

    @Test func fireIKlubbTreUtenKlubb() {
        #expect(TournamentSetup.templates(inClub: true) == [.stablefordSeries, .matchSeries, .cup, .fun])
        #expect(TournamentSetup.templates(inClub: false) == [.stablefordSeries, .cup, .fun])
    }

    @Test func klubbEllerPrivatBareDerDetErEtValg() {
        #expect(TournamentSetup.showsOwnerChoice(.stablefordSeries, canCreateInClub: true, offersPrivate: true))
        #expect(!TournamentSetup.showsOwnerChoice(.matchSeries, canCreateInClub: true, offersPrivate: true))
        // Fra arrangørsiden er turneringen alltid klubbens, som «Ny sesong» før.
        #expect(!TournamentSetup.showsOwnerChoice(.cup, canCreateInClub: true, offersPrivate: false))
        // Ikke arrangør: bare privat, ingen valg.
        #expect(!TournamentSetup.showsOwnerChoice(.fun, canCreateInClub: false, offersPrivate: true))
    }

    // MARK: Hva som lages

    @Test func hvaSomLages() {
        #expect(TournamentSetup.target(.stablefordSeries, clubID: Self.club) == .season)
        #expect(TournamentSetup.target(.matchSeries, clubID: Self.club) == .season)
        #expect(TournamentSetup.target(.stablefordSeries, clubID: nil) == .competition(.league))
        #expect(TournamentSetup.target(.cup, clubID: Self.club) == .competition(.cup))
        #expect(TournamentSetup.target(.cup, clubID: nil) == .competition(.cup))
        #expect(TournamentSetup.target(.fun, clubID: nil) == .competition(.fun))
    }

    @Test func nySesongStarterBareNarIngenErIGang() {
        let ferdig = SeasonRow(id: UUID(), clubID: Self.club, name: "Vår", status: .finished, rules: .golfgutu)
        let aktiv = SeasonRow(id: UUID(), clubID: Self.club, name: "Høst", status: .active, rules: .golfgutu)
        #expect(TournamentSetup.activatesNewSeason(existing: []))
        #expect(TournamentSetup.activatesNewSeason(existing: [ferdig]))
        #expect(!TournamentSetup.activatesNewSeason(existing: [ferdig, aktiv]))
    }

    @Test func serieIKlubbenFarOppsettetsRegler() {
        let d = TournamentDraft(template: .stablefordSeries, clubID: Self.club, name: "Høst 2026", today: "2026-10-08")
        #expect(d.target == .season)
        #expect(d.rules == RulesetTemplate.stablefordSeries.rules)
        #expect(d.issues().isEmpty)
        let m = TournamentDraft(template: .matchSeries, clubID: Self.club, name: "Høst 2026", today: "2026-10-08")
        #expect(m.rules == .golfgutu)
    }

    @Test func privatStablefordSerieErEnLigaMedStablefordpoeng() throws {
        var d = TournamentDraft(template: .stablefordSeries, clubID: Self.club, name: "Høst 2026", today: "2026-10-08")
        d.clubID = nil
        #expect(d.target == .competition(.league))
        let c = d.competitionDraft
        #expect(c.kind == .league && c.clubID == nil && c.name == "Høst 2026")
        let rules = c.rules(main: nil)
        #expect(rules.competitionRules.league.scoring == .stableford)
        #expect(rules.competitionRules.league.participationPoints == 0)
        #expect(rules.competitionRules.league.bestRounds == 5)
        // Rundene spilles med stableford-seriens regler (ingen sidepremier eller seeding).
        var withoutCompetition = rules
        withoutCompetition.competition = nil
        #expect(withoutCompetition == RulesetTemplate.stablefordSeries.rules)
        #expect(RulesetSummary.badge(for: rules, kind: .league) == "Stableford-serie")
        let p = c.params(main: nil)
        #expect(p.p_kind == "league" && p.p_club_id == nil && p.p_starts_on == nil)
        // Liga krever kjøp som før.
        #expect(CompetitionPurchase.requiresPurchase(c.kind))
    }

    @Test func cupOgMorroFarOppsettetsRegler() {
        for (template, kind) in [(RulesetTemplate.cup, CompetitionKind.cup), (.fun, .fun)] {
            var d = TournamentDraft(template: template, clubID: Self.club, name: "Høstcupen", today: "2026-10-08")
            #expect(d.target == .competition(kind))
            #expect(d.competitionDraft.rules(main: nil) == template.rules)
            d.clubID = nil
            #expect(d.competitionDraft.rules(main: nil) == template.rules)
            #expect(d.competitionDraft.clubID == nil)
            #expect(d.issues().isEmpty)
        }
    }

    @Test func periodeBareForMorroIKlubben() {
        var d = TournamentDraft(template: .fun, clubID: Self.club, name: "Høstmorro", today: "2026-10-08")
        #expect(d.showsPeriod)
        d.competition.hasPeriod = true
        d.competition.endsOn = "2026-10-31"
        #expect(d.competitionDraft.params(main: nil).p_ends_on == "2026-10-31")
        d.clubID = nil
        #expect(!d.showsPeriod)
        #expect(d.competitionDraft.params(main: nil).p_ends_on == nil)
        #expect(!TournamentDraft(template: .cup, clubID: Self.club, name: "C", today: "2026-10-08").showsPeriod)
    }

    @Test func navnMangler() {
        var d = TournamentDraft(template: .stablefordSeries, clubID: Self.club, name: "  ", today: "2026-10-08")
        #expect(d.issues() == ["Gi turneringen et navn."])
        d.name = "Høst"
        d.rules.evenings = 0
        #expect(!d.issues().isEmpty)
    }

    // MARK: Navneforslag

    @Test func navneforslag() {
        let now = Self.oct2026, cal = Self.oslo
        #expect(TournamentSetup.suggestedName(.stablefordSeries, taken: [], now: now, calendar: cal) == "Høst 2026")
        #expect(TournamentSetup.suggestedName(.matchSeries, taken: [], now: now, calendar: cal) == "Høst 2026")
        #expect(TournamentSetup.suggestedName(.cup, taken: [], now: now, calendar: cal) == "Høstcupen")
        #expect(TournamentSetup.suggestedName(.fun, taken: [], now: now, calendar: cal) == "Høstmorro")
        #expect(TournamentSetup.suggestedName(.stablefordSeries, taken: [" høst 2026 "], now: now, calendar: cal)
                == "Høst 2026 2")
        #expect(TournamentSetup.suggestedName(.cup, taken: [], now: Self.date(5), calendar: cal) == "Vårcupen")
        #expect(TournamentSetup.suggestedName(.stablefordSeries, taken: [], now: Self.date(7), calendar: cal)
                == "Sommer 2026")
        #expect(TournamentSetup.suggestedName(.fun, taken: [], now: Self.date(1), calendar: cal) == "Vintermorro")
    }

    // MARK: Tekster

    @Test func typeSomUndertekst() {
        #expect(TournamentSetup.typeText(kind: .season, rules: RulesetTemplate.stablefordSeries.rules) == "Stableford-serie")
        #expect(TournamentSetup.typeText(kind: .season, rules: .golfgutu) == "Matchspill-serie")
        #expect(TournamentSetup.typeText(kind: .cup, rules: .golfgutu) == "Cup")
        #expect(TournamentSetup.typeText(kind: .fun, rules: .golfgutu) == "Morro")
        #expect(TournamentSetup.typeText(kind: .league, rules: .golfgutu) == "Liga")
    }

    @Test func reglerKortISteg2() {
        let s = TournamentDraft(template: .stablefordSeries, clubID: Self.club, name: "H", today: "2026-10-08")
        #expect(TournamentSetup.ruleLines(s) == ["Beste 5 av 7 kvelder teller", "Stablefordpoengene er tabellpoengene",
                                                 "Ingen sidepremier"])
        let m = TournamentDraft(template: .matchSeries, clubID: Self.club, name: "H", today: "2026-10-08")
        #expect(TournamentSetup.ruleLines(m)[1] == "Matcher hver kveld, seier gir 1 poeng")
        var l = s
        l.clubID = nil
        #expect(TournamentSetup.ruleLines(l).prefix(2) == ["Stablefordpoengene teller rett fram", "De 5 beste rundene teller"])
        let c = TournamentDraft(template: .cup, clubID: Self.club, name: "C", today: "2026-10-08")
        #expect(TournamentSetup.ruleLines(c).prefix(2) == ["Seeding: trekning", "Likt etter siste hull: sudden death"])
    }

    // MARK: Alle turneringer

    @Test func alleTurneringerIEnListeGruppertEtterStatus() {
        let other = UUID()
        let aktiv = SeasonRow(id: UUID(), clubID: Self.club, name: "Høst 2026", status: .active,
                              rules: RulesetTemplate.stablefordSeries.rules)
        let ferdig = SeasonRow(id: UUID(), clubID: Self.club, name: "Vår 2026", status: .finished, rules: .golfgutu)
        func comp(_ kind: CompetitionKind, _ name: String, _ status: SeasonStatus, club: UUID? = Self.club,
                  seasonID: UUID? = nil, ends: String? = nil) -> CompetitionRow {
            CompetitionRow(id: UUID(), kind: kind, name: name, clubID: club, ownerID: nil, seasonID: seasonID,
                           status: status, entry: .listed, rules: .golfgutu, startsOn: ends.map { _ in "2026-10-01" },
                           endsOn: ends, isMain: kind == .season, requiresPurchase: false, entitlementID: nil)
        }
        let speil = comp(.season, "Høst 2026", .active, seasonID: aktiv.id)
        let cup = comp(.cup, "Høstcupen", .planned)
        let morro = comp(.fun, "Oktobermorro", .active, ends: "2026-10-31")
        let privat = comp(.fun, "Gutta på tur", .active, club: nil)
        let annen = comp(.league, "Annen klubb", .active, club: other)
        let spill = comp(.game, "Skins", .active)
        let items = TournamentList.items(seasons: [aktiv, ferdig], competitions: [speil, cup, morro, privat, annen, spill],
                                         clubID: Self.club)
        // Sesongens speil, private, andre klubbers og spill er ikke med: hver turnering står én gang.
        #expect(items.map(\.name) == ["Høst 2026", "Vår 2026", "Høstcupen", "Oktobermorro"])
        let groups = TournamentList.grouped(items)
        #expect(groups.map(\.title) == ["Pågår", "Planlagt", "Ferdig"])
        #expect(groups[0].items.map(\.name) == ["Høst 2026", "Oktobermorro"])
        #expect(groups[0].items.map(\.subtitle) == ["Stableford-serie", "Morro · 1. okt – 31. okt"])
        #expect(groups[1].items.map(\.subtitle) == ["Cup"])
        #expect(groups[2].items.map(\.subtitle) == ["Matchspill-serie"])
    }

    // MARK: Kom i gang

    @Test func komIGangLenkerTilNyTurnering() {
        let input = GettingStarted.Input(hasActiveSeason: false, readyCourses: 1, activeMembers: 12, upcomingEvenings: 1)
        let step = GettingStarted.steps(input)[0]
        #expect(step.item.title == "Turneringen")
        #expect(step.detail == "Lag turneringen og velg hvordan dere spiller.")
        #expect(GettingStarted.opensNewTournament(step))
        var done = input
        done.hasActiveSeason = true
        #expect(!GettingStarted.opensNewTournament(GettingStarted.steps(done)[0]))
        #expect(!GettingStarted.opensNewTournament(GettingStarted.steps(input)[1]))
    }
}

/// Tavla for en stableford-serie: runder og stablefordpoeng, ikke dueller og hull.
@MainActor struct TavlaStablefordTests {
    @Test func tekstenePasserForStableford() throws {
        let standings = TavlaSamples.standings(stableford: true)
        #expect(standings.countsStableford)
        #expect(standings.roundColumns == "plass · stableford")
        let first = try #require(standings.rows.first)
        #expect(first.duel == 0 && first.matches == 0 && first.holes == 0)
        #expect(first.played == 6)
        #expect(standings.detail(first) == "6 kvelder · beste 5 teller")
        // Ingen sidepremier i oppsettet: alle poengene kommer fra rundene.
        #expect(first.side == 0)
        #expect(standings.basis(first) == "\(standings.points(first.roundPoints)) fra 6 runder")
    }

    @Test func matcherSomFor() throws {
        let standings = TavlaSamples.standings()
        #expect(!standings.countsStableford)
        #expect(standings.roundColumns == "plass · duell · stableford")
        let row = try #require(standings.rows.first)
        #expect(standings.detail(row).contains(" hull · "))
        #expect(standings.basis(row)?.contains("dueller") == true)
    }
}
