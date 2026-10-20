import Foundation
import GolfgutuCore

/// Det Tavla viser rundt tabellen (V4): plass med delt plass, bevegelse siden forrige kveld, delt
/// ledelse og fremdriften. Ren, uten SwiftUI.
nonisolated extension TavlaStandings {
    /// Bevegelse siden tabellen før siste kveld.
    enum Movement: Equatable, Sendable {
        case up(Int)
        case down(Int)
        case same

        /// «▲1», «▼2», «–».
        var text: String {
            switch self {
            case .up(let n): "▲\(n)"
            case .down(let n): "▼\(n)"
            case .same: "–"
            }
        }

        /// «opp 1 plass», «ned 2 plasser», «samme plass» (VoiceOver).
        var spoken: String {
            switch self {
            case .up(let n): "opp \(n) \(n == 1 ? "plass" : "plasser")"
            case .down(let n): "ned \(n) \(n == 1 ? "plass" : "plasser")"
            case .same: "samme plass"
            }
        }
    }

    /// Plassen i tabellen: «1=» ved delt plass, «3» ellers, «–» før første kveld og uten nok kvelder.
    func boardPlace(_ row: Row) -> String {
        guard hasResults, row.qualified else { return "–" }
        let shared = boardRows.contains { $0.memberID != row.memberID && $0.qualified && $0.place == row.place }
        return shared ? "\(row.place)=" : "\(row.place)"
    }

    /// Linja under navnet i tabellen, kortere enn `detail` så den holder seg på én linje:
    /// «+26 hull · 215 stb». Kvelder står bare med når spilleren har stått over noen.
    func boardDetail(_ row: Row) -> String {
        guard !countsStableford else { return detail(row) }
        var text = "\(row.holes > 0 ? "+" : "")\(row.holes) hull · \(row.stableford) stb"
        if row.evenings < eveningsPlayed { text += " · \(rules.day.count(row.evenings))" }
        if row.playoffPending { text = "Playoff · " + text }
        if !row.qualified, let min = rules.table.minEvenings {
            text += " · minst \(rules.day.count(min)) for plass"
        }
        return text
    }

    /// Har tabellen en kolonne for bevegelse? Bare når tabellen før siste kveld kunne regnes.
    var showsMovement: Bool { hasResults && previousPlaces != nil }

    /// Bevegelsen for raden, nil når spilleren ikke hadde plass før (eller ikke har nå).
    func movement(_ row: Row) -> Movement? {
        guard showsMovement, row.qualified, let before = boardPreviousPlaces?[row.memberID] else { return nil }
        let change = before - row.place
        return change > 0 ? .up(change) : change < 0 ? .down(-change) : .same
    }

    /// De som står likt på flest poeng (minst to), i tabellens rekkefølge. Tom ellers.
    var tiedLeaders: [Row] {
        let ranked = boardRows.filter(\.qualified)
        guard hasResults, let top = ranked.first else { return [] }
        let tied = ranked.filter { $0.total == top.total }
        return tied.count > 1 ? tied : []
    }

    /// Hero-kortet ved delt ledelse: «Odd og Ola står likt på 6 poeng. Blir det likt etter kveld 7,
    /// avgjør playoff jakka.» Hva som avgjør, kommer fra regelsettet. Nil uten delt ledelse og når
    /// turneringen er ferdig.
    var leadTieText: String? {
        let leaders = tiedLeaders
        guard status != .finished, let first = leaders.first else { return nil }
        // Lagtabellen: «2 lag står likt …», for lagnavnene er alt lister.
        let names = isTeamBoard ? "\(leaders.count) lag" : RuleFormat.list(leaders.map(\.name))
        let lead = "\(names) står likt på \(points(first.total)) poeng."
        let prize = countsStableford ? "førsteplassen" : "jakka"
        let table = rules.table
        let remaining = eveningsPlayed < eveningsTotal
        let when = "Blir det likt etter \(rules.day.one) \(eveningsTotal)"
        if table.tieRule == .playoff {
            return lead + (remaining ? " \(when), avgjør playoff \(prize)." : " Playoff avgjør \(prize).")
        }
        if !table.tiebreaks.isEmpty {
            let order = RuleFormat.list(table.tiebreaks.map(RuleNames.inSentence), last: "så")
            return lead + (remaining ? " \(when), skiller \(order)." : " Det skilles på \(order).")
        }
        return lead + (remaining ? " \(when), deler de \(prize)." : " De deler \(prize).")
    }

    /// «Kveld 5 av 7 spilt», eller «0 av 7 kvelder spilt» før første kveld.
    var progressText: String {
        guard eveningsPlayed > 0 else { return "0 av \(rules.day.count(eveningsTotal)) spilt" }
        return "\(DayTerm.capitalized(rules.day.one)) \(eveningsPlayed) av \(eveningsTotal) spilt"
    }

    /// «Neste: onsdag 21. oktober», «Neste: i dag». Nil uten en neste kveld.
    func nextText(today: String = TavlaData.today()) -> String? {
        guard status != .finished, let date = nextEventDate else { return nil }
        if date == today { return "Neste: i dag" }
        guard let parsed = Self.dayFormat.date(from: date) else { return nil }
        return "Neste: " + parsed.formatted(.dateTime.weekday(.wide).day().month(.wide)
            .locale(Locale(identifier: "nb_NO")))
            .replacingOccurrences(of: ", ", with: " ")
    }

    private static var dayFormat: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Oslo")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
