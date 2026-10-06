import Foundation

/// Hvordan et antall spillere deles i sider (`lagdeling`).
public struct TeamSplit: Hashable, Sendable {
    /// Antall lag. Alltid et partall, så alle har en motstander.
    public var sides: Int
    /// Lagstørrelsene. De som blir til overs fordeles én per lag fra første.
    public var sizes: [Int]
    public var matches: Int
}

/// Hva et antall spillere gir i en form (`oppsettForAntall`).
public enum FormSetup: Hashable, Sendable {
    /// Individuell form: dueller, og én trekant ved oddetall.
    case individual(duels: Int, triangle: Bool, text: String)
    /// Lagform som går opp. `uneven` når ikke alle lag er like store.
    case teams(TeamSplit, uneven: Bool, text: String)
    /// Går ikke opp. `reason` er teksten som vises.
    case impossible(reason: String)

    public var isOK: Bool {
        if case .impossible = self { return false }
        return true
    }

    /// Teksten som beskriver kvelden (`form`), f.eks. «4 dueller og én trekant».
    public var text: String? {
        switch self {
        case .individual(_, _, let text), .teams(_, _, let text): text
        case .impossible: nil
        }
    }

    /// Hvorfor det ikke går opp (`hvorfor`).
    public var reason: String? {
        if case .impossible(let reason) = self { return reason }
        return nil
    }

    public var isTriangle: Bool {
        if case .individual(_, true, _) = self { return true }
        return false
    }

    public var isUneven: Bool {
        if case .teams(_, true, _) = self { return true }
        return false
    }
}

/// En form som går opp med antallet (`formerSomPasser`).
public struct FormSuggestion: Hashable, Sendable {
    public var id: String
    public var name: String
    public var text: String
    public var uneven: Bool
    public var triangle: Bool
}

extension CompetitionForm {
    /// `SPILLERE_PER_BAAS` i Golfgutu-oppsettet.
    public static let golfgutuMaxPerBay = 4

    /// `erLagform`.
    public var isTeamForm: Bool { teamSize > 1 }

    /// `lagdeling`: et partall lag på `k` (eller `k + 1` der formen tåler skjeve lag), aldri større
    /// enn en bås. Flest mulig lag, så lagene ligger nærmest `k`. `nil` når det ikke går opp.
    public static func teamSplit(players: Int, teamSize k: Int, allowsUneven: Bool,
                                 maxPerBay: Int = golfgutuMaxPerBay) -> TeamSplit? {
        let maxSize = min(allowsUneven ? k + 1 : k, maxPerBay)
        if maxSize < k { return nil }
        var best: Int?
        var sides = 2
        while sides * k <= players {
            if players <= sides * maxSize { best = sides }
            sides += 2
        }
        guard let best else { return nil }
        let extra = players - best * k
        let sizes = (0..<best).map { k + ($0 < extra ? 1 : 0) }
        return TeamSplit(sides: best, sizes: sizes, matches: best / 2)
    }

    /// `oppsettForAntall`: går formen opp med dette antallet, og hvordan ser kvelden ut da?
    public static func setup(formID: String?, players: Int, maxPerBay: Int = golfgutuMaxPerBay) -> FormSetup {
        form(id: formID).setup(players: players, maxPerBay: maxPerBay)
    }

    /// `oppsettForAntall` for denne formen.
    public func setup(players: Int, maxPerBay: Int = CompetitionForm.golfgutuMaxPerBay) -> FormSetup {
        if players < 2 { return .impossible(reason: "Det må være minst to for å få en duell.") }

        if teamSize == 1 {
            let triangle = players % 2 == 1
            let duels = (players - (triangle ? 3 : 0)) / 2
            var parts: [String] = []
            if duels != 0 { parts.append("\(duels)" + (duels == 1 ? " duell" : " dueller")) }
            if triangle { parts.append("én trekant") }
            return .individual(duels: duels, triangle: triangle, text: parts.joined(separator: " og "))
        }

        guard let split = CompetitionForm.teamSplit(players: players, teamSize: teamSize,
                                                    allowsUneven: allowsUnevenTeams, maxPerBay: maxPerBay) else {
            return .impossible(reason: "\(players) mann går ikke opp i et likt antall lag på \(teamSize)"
                               + (allowsUnevenTeams ? "" : ", og denne formen tåler ikke skjeve lag") + ".")
        }
        let uneven = split.sizes.contains { $0 != teamSize }
        let text = "\(split.sides) lag (" + split.sizes.map(String.init).joined(separator: "+") + ") · "
            + "\(split.matches)" + (split.matches == 1 ? " match" : " matcher")
        return .teams(split, uneven: uneven, text: text)
    }

    /// `formerSomPasser`: de ferdige formene (støtte `full`) som går opp med antallet, i registerets rekkefølge.
    public static func suggestions(players: Int, forms: [CompetitionForm] = all,
                                   maxPerBay: Int = golfgutuMaxPerBay) -> [FormSuggestion] {
        forms.filter { $0.support == .full }.compactMap { f in
            let s = f.setup(players: players, maxPerBay: maxPerBay)
            guard let text = s.text else { return nil }
            return FormSuggestion(id: f.id, name: f.name, text: text, uneven: s.isUneven, triangle: s.isTriangle)
        }
    }
}

extension Round {
    /// `erLagform`.
    public var isTeamForm: Bool { form.isTeamForm }
}
