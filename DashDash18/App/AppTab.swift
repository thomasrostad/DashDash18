/// Fanene i appen. Penger er utenfor v1 (ROADMAP B10), så Deg tar den plassen.
nonisolated enum AppTab: String, CaseIterable, Identifiable {
    case kveld
    case tavla
    case deg

    var id: Self { self }

    var title: String {
        switch self {
        case .kveld: "Kveld"
        case .tavla: "Tavla"
        case .deg: "Deg"
        }
    }

    var systemImage: String {
        switch self {
        case .kveld: "flag"
        case .tavla: "trophy"
        case .deg: "person.crop.circle"
        }
    }
}
