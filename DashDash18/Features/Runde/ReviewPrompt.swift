import Foundation

// Forespørselen om vurdering i App Store (A2 i docs/aso-plan.md). Spørres etter at en runde er
// levert og feiringen er lukket, aldri ved oppstart eller midt i føringen. Løs runde: «Avslutt
// runden» (`RundeModel.finish()`). Klubbrunde: når kortet ditt er ferdig ført (`RundeModel.saveCurrentHole()`).

/// Skal appen be om en vurdering nå? Ren logikk, så den kan testes uten telefonens lagre.
nonisolated struct ReviewPrompt: Equatable, Sendable {
    /// Antall leverte runder før det spørres.
    static let minimumRounds = 2

    var completedRounds: Int
    /// Versjonen det sist ble spurt i, eller `nil` når det aldri er spurt.
    var lastAskedVersion: String?
    var currentVersion: String
    /// Ikke på kortet med egen profil (gjest, eller bare eier av runden).
    var isGuest: Bool
    var isUITest: Bool

    /// Minst to leverte runder, høyst én gang per app-versjon, aldri for gjester eller i UI-tester.
    var shouldAsk: Bool {
        guard !isGuest, !isUITest, !currentVersion.isEmpty else { return false }
        return completedRounds >= Self.minimumRounds && lastAskedVersion != currentVersion
    }
}

/// Telleren og versjonen det sist ble spurt i, husket på telefonen (ikke per innlogging).
nonisolated struct ReviewPromptStore {
    static let roundsKey = "vurdering.leverteRunder"
    static let askedVersionKey = "vurdering.spurtVersjon"
    static let countedRoundsKey = "vurdering.telteRunder"
    /// Så mange runde-ID-er huskes, så samme runde ikke telles to ganger.
    static let rememberedRounds = 20
    /// Launch-argumentet UI-testene starter appen med.
    static let uiTestArgument = "-DDUITest"

    var defaults: UserDefaults = .standard
    var currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    var isUITest: Bool = ProcessInfo.processInfo.arguments.contains(uiTestArgument)

    var completedRounds: Int { defaults.integer(forKey: Self.roundsKey) }

    /// En runde er levert. Samme runde telles bare én gang (kortet kan bli ferdig igjen etter en retting).
    func roundFinished(_ roundID: UUID) {
        let counted = defaults.stringArray(forKey: Self.countedRoundsKey) ?? []
        guard !counted.contains(roundID.uuidString) else { return }
        defaults.set(Array((counted + [roundID.uuidString]).suffix(Self.rememberedRounds)), forKey: Self.countedRoundsKey)
        defaults.set(completedRounds + 1, forKey: Self.roundsKey)
    }

    func prompt(isGuest: Bool) -> ReviewPrompt {
        ReviewPrompt(completedRounds: completedRounds, lastAskedVersion: defaults.string(forKey: Self.askedVersionKey),
                     currentVersion: currentVersion, isGuest: isGuest, isUITest: isUITest)
    }

    /// Forespørselen er vist i denne versjonen.
    func markAsked() {
        defaults.set(currentVersion, forKey: Self.askedVersionKey)
    }
}
