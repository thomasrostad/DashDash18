import Foundation

/// Hva appen viser etter innlogging. Med `OpenAppFeature` av er det det samme som før:
/// klubbvalg, venting eller klubbappen.
nonisolated enum AppHome: Equatable, Sendable {
    case loading
    /// Velg «Spill med venner» eller «Bli med i/lag en klubb» (bare med OpenAppFeature).
    case chooser
    /// Dagens klubbvalg: bli med i eller lag en klubb.
    case clubOnboarding
    /// Uten klubb: Spill og Deg.
    case friends
    case pending(Membership)
    case club(Membership)
    case failed(ClubError)
}

/// Valget i onboardingen, lagret per innlogging på telefonen.
nonisolated enum AppHomeChoice: String, Sendable {
    case friends
    case club
}

nonisolated enum OpenAppGate {
    /// Hvor du havner. En aktiv klubb vinner alltid: da får du klubbappen (med Spill-fanen).
    /// Venter du på godkjenning og har valgt venner, kan du spille mens du venter.
    static func home(club: ClubState, choice: AppHomeChoice?, openApp: Bool = OpenAppFeature.isEnabled) -> AppHome {
        switch club {
        case .loading: return .loading
        case .failed(let error): return .failed(error)
        case .active(let membership): return .club(membership)
        case .pending(let membership):
            return openApp && choice == .friends ? .friends : .pending(membership)
        case .noClub:
            guard openApp else { return .clubOnboarding }
            switch choice {
            case .friends: return .friends
            case .club: return .clubOnboarding
            case nil: return .chooser
            }
        }
    }
}

/// Valget lagres per innlogging, så en annen konto på samme telefon får spørsmålet selv.
nonisolated struct AppHomeChoiceStore {
    var defaults: UserDefaults = .standard

    private func key(_ userID: UUID) -> String { "apenValg.\(userID.uuidString.lowercased())" }

    func load(userID: UUID) -> AppHomeChoice? {
        defaults.string(forKey: key(userID)).flatMap(AppHomeChoice.init(rawValue:))
    }

    func save(_ choice: AppHomeChoice?, userID: UUID) {
        if let choice { defaults.set(choice.rawValue, forKey: key(userID)) } else { defaults.removeObject(forKey: key(userID)) }
    }
}

nonisolated extension AppTab {
    /// Fanene uten klubb: Spill og Deg. Kveld og Tavla hører til klubben. Konkurranser (fase 15)
    /// legges inn her når den fanen finnes.
    static func tabsWithoutClub() -> [AppTab] {
        [.spill, .deg]
    }
}
