import GolfgutuCore
import Testing

/// Bekrefter at appen er koblet til regelmotoren. Selve reglene testes i pakken.
struct GolfgutuCoreIntegrationTests {
    @Test func regelmotorenErTilgjengelig() {
        // brutto-test.js: hcp 18 gir ett slag per hull; 5 brutto på par 4 = netto par = 2 poeng.
        #expect(Scoring.points(par: 4, gross: 5, handicap: 18, strokeIndex: 1, holes: 18) == 2)
        #expect(JS.round(-2.5) == -2)
    }
}
