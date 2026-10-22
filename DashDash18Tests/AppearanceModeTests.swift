import SwiftUI
import Testing
@testable import DashDash18

struct AppearanceModeTests {
    @Test func systemFolgerTelefonenLysOgMorkTvinger() {
        #expect(AppearanceMode.system.colorScheme == nil)
        #expect(AppearanceMode.light.colorScheme == .light)
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }

    @Test func rekkefolgenOgNorskeNavn() {
        #expect(AppearanceMode.allCases.map(\.label) == ["System", "Lys", "Mørk"])
    }

    @Test func lagretVerdiGirModus() {
        #expect(AppearanceMode(stored: "dark") == .dark)
        #expect(AppearanceMode(stored: "light") == .light)
        #expect(AppearanceMode(stored: "system") == .system)
    }

    @Test func ukjentEllerTomVerdiGirSystem() {
        #expect(AppearanceMode(stored: "") == .system)
        #expect(AppearanceMode(stored: "sepia") == .system)
    }
}
