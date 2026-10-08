import Testing
@testable import DashDash18

struct AppTabTests {
    @Test func fanerIRekkefolge() {
        #expect(AppTab.tabs(looseRounds: false).map(\.title) == ["Hjem", "Tavla", "Deg"])
    }

    /// Fase 13: «Spill» kommer etter Hjem når løse runder er på, ellers er fanene som før.
    @Test func spillfanenBareMedLoseRunder() {
        #expect(AppTab.tabs(looseRounds: true).map(\.title) == ["Hjem", "Spill", "Tavla", "Deg"])
        #expect(AppTab.tabs() == AppTab.tabs(looseRounds: LooseRoundsFeature.isEnabled))
        #expect(!LooseRoundsFeature.isEnabled || FoundationFeature.isEnabled)
    }

    @Test func hverFaneHarIkon() {
        #expect(AppTab.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
