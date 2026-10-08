import Foundation

/// 1b-oppsummeringen øverst på Hjem: bare når noe har skjedd siden du sist så Hjem.
/// «Siden sist · søndag» · «Du klatret til 3. plass i Jakkeracet, og Anders slo eagle.» · tre tall.
nonisolated enum HomeSummaryBuilder {
    /// Høyst to ting i setningen.
    static let maxParts = 2

    static func summary(_ drafts: [HomeFeedDraft], context: HomeFeedContext) -> HomeSummary? {
        let input = context.input
        guard let lastSeen = input.lastSeen else { return nil }
        let fresh = drafts.filter { $0.date > lastSeen && !$0.isOwn }
        guard !fresh.isEmpty else { return nil }

        // Nye runder: låst siden sist, i klubbene (aktiviteten) og i rundene appen har hentet.
        var rounds = Set(input.activity.filter { $0.kind == "round_locked" && $0.createdAt > lastSeen }
            .compactMap(\.roundID))
        for s in input.rounds where (s.round.lockedAt ?? .distantPast) > lastSeen { rounds.insert(s.round.id) }
        let feats = fresh.filter { if case .feat = $0.kind { true } else { false } }
        let places = fresh.reduce(0) { sum, d in
            if case .table(let t) = d.kind { return sum + (t.myMove ?? 0) }
            return sum
        }

        return HomeSummary(
            eyebrow: "Siden sist · " + dayText(lastSeen, now: input.now),
            sentence: sentence(fresh, rounds: rounds.count),
            stats: [
                .init(value: "\(rounds.count)", label: rounds.count == 1 ? "ny runde" : "nye runder"),
                .init(value: "\(feats.count)", label: feats.count == 1 ? "bragd" : "bragder"),
                .init(value: HomeFeedText.signed(places), label: abs(places) == 1 ? "plass" : "plasser"),
            ])
    }

    /// Det viktigste først: plassbyttet ditt (størst først), så en bragd, så runden din.
    static func sentence(_ fresh: [HomeFeedDraft], rounds: Int) -> String {
        let ranked = fresh.filter { $0.phrase != nil }
            .enumerated()
            .sorted { a, b in a.element.weight != b.element.weight ? a.element.weight > b.element.weight : a.offset < b.offset }
            .map(\.element)
        // Én ting per slag (plassbytte, bragd, runde): resten står i tallene.
        var parts: [String] = []
        var kinds: Set<String> = []
        for d in ranked where parts.count < maxParts {
            guard let phrase = d.phrase else { continue }
            let kind = switch d.kind {
            case .table: "table"
            case .feat: "feat"
            case .myRound: "round"
            case .line: "line"
            }
            guard kinds.insert(kind).inserted else { continue }
            parts.append(phrase)
        }
        if parts.isEmpty {
            parts.append(rounds > 0 ? (rounds == 1 ? "1 ny runde er ferdig" : "\(rounds) nye runder er ferdige")
                         : (fresh.count == 1 ? "1 ny hendelse" : "\(fresh.count) nye hendelser"))
        }
        let text = parts.joined(separator: ", og ")
        return text.prefix(1).uppercased() + text.dropFirst() + "."
    }

    /// «i dag», «i går», ukedagen den siste uka, ellers datoen («3. okt.»).
    static func dayText(_ date: Date, now: Date) -> String {
        let day = EveningDates.dateString(from: date)
        switch EveningDates.daysBetween(day, EveningDates.dateString(from: now)) ?? 7 {
        case ...0: return "i dag"
        case 1: return "i går"
        case 2...6: return String(EveningDates.longText(day).split(separator: " ").first ?? "")
        default: return ActivityFeed.relativeTime(date, now: now)
        }
    }
}
