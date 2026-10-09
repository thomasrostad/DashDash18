/// Fanene i appen: Hjem · Spill · Tavla · Deg (fase 19, besluttet 08.10.2026). Hjem erstatter Kveld:
/// «Pågår nå» og «Neste kveld» står øverst, og Kveld-skjermen er ett trykk unna.
/// «Spill» (løse runder, fase 13) vises bare når `LooseRoundsFeature` er på. «Arrangør» vises bare
/// for arrangører i klubben (09.10.2026, Thomas: arrangørsiden var for gjemt bak et ikon på Hjem).
nonisolated enum AppTab: String, CaseIterable, Identifiable {
    case hjem
    case spill
    case tavla
    case arrangor
    case deg

    var id: Self { self }

    /// Fanene som vises, i rekkefølge.
    static func tabs(looseRounds: Bool = LooseRoundsFeature.isEnabled, isOrganizer: Bool = false) -> [AppTab] {
        allCases.filter { ($0 != .spill || looseRounds) && ($0 != .arrangor || isOrganizer) }
    }

    var title: String {
        switch self {
        case .hjem: "Hjem"
        case .spill: "Spill"
        case .tavla: "Tavla"
        case .arrangor: "Arrangør"
        case .deg: "Deg"
        }
    }

    var systemImage: String {
        switch self {
        case .hjem: "house"
        case .spill: "figure.golf"
        case .tavla: "trophy"
        case .arrangor: "slider.horizontal.3"
        case .deg: "person.crop.circle"
        }
    }
}
