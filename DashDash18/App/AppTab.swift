/// Fanene i appen. Penger er utenfor v1 (ROADMAP B10), så Deg tar den plassen.
/// «Spill» (løse runder, fase 13) vises bare når `LooseRoundsFeature` er på.
nonisolated enum AppTab: String, CaseIterable, Identifiable {
    case kveld
    case spill
    case tavla
    case deg

    var id: Self { self }

    /// Fanene som vises, i rekkefølge. Uten løse runder er det de samme som før fase 13.
    static func tabs(looseRounds: Bool = LooseRoundsFeature.isEnabled) -> [AppTab] {
        allCases.filter { $0 != .spill || looseRounds }
    }

    /// Knappen til Arrangørsiden i verktøylinja: bare i Kveld, og bare for arrangører.
    /// Raden i Deg står i tillegg.
    func showsAdminButton(isOrganizer: Bool) -> Bool {
        self == .kveld && isOrganizer
    }

    var title: String {
        switch self {
        case .kveld: "Kveld"
        case .spill: "Spill"
        case .tavla: "Tavla"
        case .deg: "Deg"
        }
    }

    var systemImage: String {
        switch self {
        case .kveld: "flag"
        case .spill: "figure.golf"
        case .tavla: "trophy"
        case .deg: "person.crop.circle"
        }
    }
}
