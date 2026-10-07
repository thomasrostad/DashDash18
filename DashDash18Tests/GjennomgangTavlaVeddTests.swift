import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

/// Gjennomgangen av Tavla, deling, widgets og veddemål: tomtilstand før første kveld, kvelden
/// som er spilt i widgeten, filnavn på delingsbildet, ledige poeng før innsats og feilene fra RPC-ene.
struct GjennomgangTavlaVeddTests {
    typealias V = VeddTests
    typealias F = ForingFixture

    // MARK: Tavla før første kveld

    @MainActor static func standings(played: Bool) -> TavlaStandings {
        let season = SeasonRow(id: TavlaSamples.id(9002), clubID: TavlaSamples.club, name: "Sesong 2026",
                               status: .active, rules: .golfgutu)
        let rounds = played ? [TavlaSamples.round(1, date: "2026-05-14")] : []
        return TavlaStandings(TavlaInput(season: season, members: TavlaSamples.members, rounds: rounds),
                              me: TavlaSamples.me)
    }

    @MainActor @Test func foerFoersteKveldIngenPlasserDelingEllerToppTre() {
        let s = Self.standings(played: false)
        #expect(!s.isEmpty)
        #expect(!s.hasResults)
        #expect(s.rows.map { s.placeText($0) }.allSatisfy { $0 == "–" })
        #expect(WidgetSnapshot.topThree(s).isEmpty)
    }

    @MainActor @Test func etterFoersteKveldPlasserOgToppTre() {
        let s = Self.standings(played: true)
        #expect(s.hasResults)
        #expect(s.placeText(s.rows[0]) == "1.")
        #expect(WidgetSnapshot.topThree(s).map(\.place) == [1, 2, 3])
    }

    // MARK: Widgeten

    static func iso(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    static let evening = WidgetSnapshot.NextEvening(eventDate: "2026-10-08", dateText: "Torsdag 8. oktober",
                                                    timeText: "17:00", startsAt: iso("2026-10-08T15:00:00Z"),
                                                    venue: "Losby")

    @Test func kveldenVisesUtDagenOgForsvinnerVedMidnatt() {
        let snapshot = WidgetSnapshot(nextEvening: Self.evening)
        // Dagen før og selve kvelden, også etter start.
        #expect(snapshot.upcomingEvening(at: Self.iso("2026-10-07T12:00:00Z")) == Self.evening)
        #expect(snapshot.upcomingEvening(at: Self.iso("2026-10-08T21:30:00Z")) == Self.evening)
        #expect(!snapshot.eveningIsOver(at: Self.iso("2026-10-08T21:30:00Z")))
        // 00:30 i Oslo dagen etter (22:30 UTC): spilt.
        #expect(snapshot.upcomingEvening(at: Self.iso("2026-10-08T22:30:00Z")) == nil)
        #expect(snapshot.eveningIsOver(at: Self.iso("2026-10-08T22:30:00Z")))
        // Ingen kveld satt opp er ikke det samme som spilt.
        #expect(!WidgetSnapshot.empty.eveningIsOver(at: .now))
    }

    @Test func toppTreTomEtterInstallasjonBerOmAaAapneTavla() throws {
        #expect(WidgetSnapshot.empty.topThreeEmptyText == "Åpne Tavla i appen")
        var loaded = WidgetSnapshot.empty
        loaded.tavlaLoaded = true
        #expect(loaded.topThreeEmptyText == "Ingen tabell ennå")
        // Filer fra før feltet fantes, leses fortsatt.
        let old = Data(#"{"top":[],"updatedAt":"2026-10-07T10:00:00Z"}"#.utf8)
        let back = try WidgetSnapshotStore.decoder().decode(WidgetSnapshot.self, from: old)
        #expect(back.tavlaLoaded == nil)
    }

    // MARK: Delingsbildet

    @Test func filnavnetTaalerSkraastrek() {
        let share = ResultShare(eyebrow: "Kvelden", title: "Losby 1/2: Øst", subtitle: nil, lines: [])
        #expect(share.fileName == "Losby 1-2- Øst.png")
        #expect(ResultShare(eyebrow: "Kvelden", title: "  ", subtitle: nil, lines: []).fileName == "DashDash18.png")
    }

    // MARK: Veddemål: ledige poeng og tak før innsats

    @Test func ledigePoengOgTakVisesFoerInnsats() throws {
        #expect(BetTexts.stakeHint(available: 900, maxStake: 200, already: 0)
                == "Du har 900 ledige poeng · maks 200 per veddemål")
        #expect(BetTexts.stakeHint(available: 850, maxStake: 200, already: 150)
                == "Du har 850 ledige poeng · 50 til kan settes her (maks 200)")
        #expect(BetTexts.stakeHint(available: -20, maxStake: 200, already: 0)
                == "Du har 0 ledige poeng · maks 200 per veddemål")
        // Uten poengbank: bare taket.
        #expect(BetTexts.stakeHint(available: nil, maxStake: 200, already: 0) == "Maks 200 per veddemål")

        // Fra tavla: Anders har 150 på et åpent veddemål, start 1000.
        let bets = [V.bet(1, question: "Cato vinner runden", creator: V.cato)]
        let board = BetsBoard(V.input(bets: bets, stakes: [V.stake(11, 1, V.me, .no, 150)]), me: V.me, isOrganizer: false)
        let item = try #require(board.item(F.id(1)))
        #expect(board.available == 850)
        #expect(board.stakeHint(already: item.myPoints) == "Du har 850 ledige poeng · 50 til kan settes her (maks 200)")
    }

    // MARK: Veddemål: feilene fra RPC-ene

    @Test func feileneFraRpcEneOversettes() {
        #expect(BetErrors.text(sqlState: "22023", message: "Maks 200 poeng per veddemål. Du har 0 på det fra før.")
                == "Maks 200 poeng per veddemål.")
        #expect(BetErrors.text(sqlState: "55000", message: "Runden er låst")
                == "Runden er ferdig, så den kan ikke veddes på lenger.")
        #expect(BetErrors.text(sqlState: "22023", message: "Utfallet må være yes, no eller void")
                == "Velg JA, NEI eller annuller.")
        // Tilgangsfeilene fra RPC-ene står som de er, i stedet for «Du har ikke tilgang til dette.».
        #expect(BetErrors.text(sqlState: "42501", message: "Bare arrangøren avgjør veddemål")
                == "Bare arrangøren avgjør veddemål")
        #expect(BetErrors.text(sqlState: "42501", message: "Du er ikke aktivt medlem av klubben")
                == "Du er ikke aktivt medlem av klubben")
        // RLS-feil på engelsk og meldinger som alt er gode: den vanlige oversettingen.
        #expect(BetErrors.text(sqlState: "42501", message: "new row violates row-level security policy") == nil)
        #expect(BetErrors.text(sqlState: "22023", message: "Du har 120 ledige poeng") == nil)
        #expect(BetErrors.text(sqlState: "22023", message: "Maks 200 poeng per veddemål. Du har 150 på det fra før.") == nil)
    }
}
