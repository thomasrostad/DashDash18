/// Fanene i appen: Hjem · Spill · Tavla · Deg (fase 19, besluttet 08.10.2026). Hjem erstatter Kveld:
/// «Pågår nå» og «Neste kveld» står øverst, og Kveld-skjermen er ett trykk unna.
/// «Spill» (løse runder, fase 13) vises bare når `LooseRoundsFeature` er på.
nonisolated enum AppTab: String, CaseIterable, Identifiable {
    case hjem
    case spill
    case tavla
    case deg

    var id: Self { self }

    /// Fanene som vises, i rekkefølge.
    static func tabs(looseRounds: Bool = LooseRoundsFeature.isEnabled) -> [AppTab] {
        allCases.filter { $0 != .spill || looseRounds }
    }

    /// Knappen til Arrangørsiden i verktøylinja: bare på Hjem, og bare for arrangører.
    /// Raden i Deg står i tillegg. Knappen på «Neste kveld» går rett til neste steg (fase 21).
    func showsAdminButton(isOrganizer: Bool) -> Bool {
        self == .hjem && isOrganizer
    }

    var title: String {
        switch self {
        case .hjem: "Hjem"
        case .spill: "Spill"
        case .tavla: "Tavla"
        case .deg: "Deg"
        }
    }

    var systemImage: String {
        switch self {
        case .hjem: "house"
        case .spill: "figure.golf"
        case .tavla: "trophy"
        case .deg: "person.crop.circle"
        }
    }
}
