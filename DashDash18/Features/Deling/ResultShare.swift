import Foundation
import GolfgutuCore

/// Det som deles fra Tavla eller kvelden: overskrift og linjene i den rekkefølgen og med de
/// plassene appen allerede viser. Ingenting regnes på nytt her. Ren, uten SwiftUI og nettverk.
nonisolated struct ResultShare: Equatable, Hashable, Sendable {
    /// Én linje: plass (nil når appen ikke viser plass, f.eks. hull for hull), navn og verdi.
    struct Line: Equatable, Hashable, Sendable {
        let place: Int?
        let name: String
        /// Ferdig formatert, som i appen: «12,5 p», «24 p», «2 opp», «Delt».
        let value: String
        let isMe: Bool
    }

    /// «Jakkeracet» eller «Kvelden».
    let eyebrow: String
    /// Sesongnavnet eller banen.
    let title: String
    /// «3 av 7 kvelder spilt», «Torsdag 8. oktober · resultat».
    let subtitle: String?
    let lines: [Line]

    /// «Jakkeracet · Sesong 2026»: tittelen i delingsarket og første linje i teksten.
    var heading: String { "\(eyebrow) · \(title)" }

    /// Filnavnet på bildet: tittelen uten tegn som ikke tåles i et filnavn («Sesong 2026.png»).
    var fileName: String {
        let cleaned = title.map { "/\\:".contains($0) ? "-" : $0 }
        let name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return (name.isEmpty ? "Atten" : name) + ".png"
    }

    /// Tekstversjonen, som fallback når mottakeren ikke tar bilder.
    var text: String { Self.text(self) }

    /// Overskrift, undertittel, tom linje og én linje per plass: «1. Anders – 12 p».
    /// Uten plass står bare navnet først.
    static func text(_ share: ResultShare) -> String {
        var out = [share.heading]
        if let subtitle = share.subtitle, !subtitle.isEmpty { out.append(subtitle) }
        if !share.lines.isEmpty {
            out.append("")
            out += share.lines.map(line)
        }
        return out.joined(separator: "\n")
    }

    static func line(_ line: Line) -> String {
        let place = line.place.map { "\($0). " } ?? ""
        return "\(place)\(line.name) – \(line.value)"
    }
}

// MARK: - Tavla

nonisolated extension ResultShare {
    /// Linjene fra tabellens rader, i tabellens rekkefølge og med tabellens plass.
    static func lines(from rows: [TavlaStandings.Row], points: (Double) -> String) -> [Line] {
        rows.map { Line(place: $0.place, name: $0.name, value: "\(points($0.total)) p", isMe: $0.isMe) }
    }
}

nonisolated extension TavlaStandings {
    /// Sesongtabellen til deling.
    var share: ResultShare {
        return ResultShare(eyebrow: "Jakkeracet", title: seasonName,
                           subtitle: "\(eveningsPlayed) av \(rules.day.count(eveningsTotal)) spilt",
                           lines: ResultShare.lines(from: rows, points: points))
    }
}

// MARK: - Kvelden

nonisolated extension ResultShare {
    /// Linjene fra «Bayen nå», i samme rekkefølge og med samme plass (ingen plass hull for hull).
    /// Står raden i en hullmatch, deles stillingen; ellers poengsummen.
    static func lines(from rows: [BayenRow]) -> [Line] {
        rows.map { row in
            Line(place: row.place, name: row.name, value: row.match != nil ? row.value : "\(row.total) p",
                 isMe: row.isMe)
        }
    }
}

nonisolated extension RoundGame {
    /// Kveldens stilling (eller resultat når runden er låst) til deling. En løs runde (uten klubb)
    /// heter «Runden».
    func share(viewer: Viewer) -> ResultShare {
        let state = snapshot.round.status == .locked ? "Resultat" : "Stilling nå"
        let date = snapshot.eventDate.map { EveningDates.longText($0, capitalized: true) }
        let eyebrow = snapshot.isLoose ? "Runden" : DayTerm.capitalized(snapshot.rules.day.the)
        return ResultShare(eyebrow: eyebrow, title: snapshot.course?.name ?? eyebrow,
                           subtitle: [date, state].compactMap { $0 }.joined(separator: " · "),
                           lines: ResultShare.lines(from: bayenNaa(viewer: viewer)))
    }
}
