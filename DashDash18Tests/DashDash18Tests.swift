import Testing
@testable import DashDash18

struct AppTabTests {
    @Test func fanerIRekkefolge() {
        #expect(AppTab.allCases.map(\.title) == ["Kveld", "Tavla", "Deg"])
    }

    @Test func hverFaneHarIkon() {
        #expect(AppTab.allCases.allSatisfy { !$0.systemImage.isEmpty })
    }
}
