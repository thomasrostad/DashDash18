import Foundation
import Testing
@testable import DashDash18

/// Forespørselen om vurdering (A2 i docs/aso-plan.md): etter minst to leverte runder, høyst én
/// gang per app-versjon, aldri for gjester eller i UI-tester.
struct VurderingTests {
    private func prompt(rounds: Int, asked: String? = nil, current: String = "1.0.1",
                        isGuest: Bool = false, isUITest: Bool = false) -> ReviewPrompt {
        ReviewPrompt(completedRounds: rounds, lastAskedVersion: asked, currentVersion: current,
                     isGuest: isGuest, isUITest: isUITest)
    }

    @Test func underToRunderSporIkke() {
        #expect(!prompt(rounds: 0).shouldAsk)
        #expect(!prompt(rounds: 1).shouldAsk)
    }

    @Test func toRunderSporer() {
        #expect(prompt(rounds: 2).shouldAsk)
        #expect(prompt(rounds: 7).shouldAsk)
    }

    @Test func sammeVersjonSporIkkeIgjen() {
        #expect(!prompt(rounds: 5, asked: "1.0.1", current: "1.0.1").shouldAsk)
    }

    @Test func nyVersjonSporIgjen() {
        #expect(prompt(rounds: 5, asked: "1.0.1", current: "1.1").shouldAsk)
    }

    @Test func gjestSporIkke() {
        #expect(!prompt(rounds: 5, isGuest: true).shouldAsk)
    }

    @Test func uiTestSporIkke() {
        #expect(!prompt(rounds: 5, isUITest: true).shouldAsk)
    }

    @Test func tomVersjonSporIkke() {
        #expect(!prompt(rounds: 5, current: "").shouldAsk)
    }

    // MARK: Lagringen

    private func store() -> ReviewPromptStore {
        ReviewPromptStore(defaults: UserDefaults(suiteName: "test.vurdering.\(UUID().uuidString)")!,
                          currentVersion: "1.0.1", isUITest: false)
    }

    @Test func andreLeverteRundeSporer() {
        let store = store()
        store.roundFinished()
        #expect(!store.prompt(isGuest: false).shouldAsk)
        store.roundFinished()
        #expect(store.completedRounds == 2)
        #expect(store.prompt(isGuest: false).shouldAsk)
    }

    @Test func sporsIkkeIgjenEtterAtDetErSpurt() {
        let store = store()
        store.roundFinished()
        store.roundFinished()
        store.markAsked()
        store.roundFinished()
        #expect(!store.prompt(isGuest: false).shouldAsk)
    }
}
