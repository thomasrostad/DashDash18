import Foundation
import GolfgutuCore

/// Periodefilteret på statistikken.
nonisolated enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case all, thisYear, last12Months, last90Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alt"
        case .thisYear: "I år"
        case .last12Months: "Siste 12 mnd"
        case .last90Days: "Siste 90 dager"
        }
    }

    /// Første dag i perioden (`YYYY-MM-DD`), eller nil for alt.
    func from(today: Date, calendar: Calendar = StatsFormat.calendar) -> String? {
        let start: Date?
        switch self {
        case .all: return nil
        case .thisYear: start = calendar.date(from: calendar.dateComponents([.year], from: today))
        case .last12Months: start = calendar.date(byAdding: .month, value: -12, to: today)
        case .last90Days: start = calendar.date(byAdding: .day, value: -90, to: today)
        }
        return start.map { StatsFormat.day($0, calendar: calendar) }
    }
}

/// Tall og datoer i statistikken, på norsk.
nonisolated enum StatsFormat {
    static let locale = Locale(identifier: "nb_NO")

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
        c.locale = locale
        return c
    }()

    static func day(_ date: Date, calendar: Calendar = calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `YYYY-MM-DD` → dato (midt på dagen, så tidssonen ikke flytter den).
    static func date(_ day: String) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12))
    }

    /// «3. sep. 2026».
    static func shortDate(_ day: String) -> String {
        guard let d = date(day) else { return day }
        return d.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    /// Én desimal med komma: «4,2».
    static func decimal(_ x: Double, digits: Int = 1) -> String {
        x.formatted(.number.locale(locale).precision(.fractionLength(digits)).grouping(.never))
    }

    /// Mot par: «+5», «−2», «0». Med desimal for snitt: «+1,4».
    static func toPar(_ x: Double, digits: Int = 0) -> String {
        let text = decimal(abs(x), digits: digits)
        if (x * pow(10, Double(digits))).rounded() == 0 { return decimal(0, digits: digits) }
        return (x > 0 ? "+" : "−") + text
    }

    static func toPar(_ x: Int) -> String { toPar(Double(x)) }

    /// 0,456 → «46 %».
    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded())) %"
    }

    /// Handicapindeks: plusshandicap vises med «+» (WHS-skrivemåten), ellers vanlig tall.
    static func index(_ x: Double) -> String {
        x < 0 ? "+" + decimal(-x) : decimal(x)
    }

    /// «Bjaavann · 18 hull» / «Bjaavann · hull 10–18».
    static func layout(courseName: String?, layoutKey: String, holeCount: Int) -> String {
        let name = courseName ?? "Ukjent bane"
        if holeCount == 18 { return "\(name) · 18 hull" }
        return "\(name) · hull \(layoutKey.replacingOccurrences(of: "-", with: "–"))"
    }
}

nonisolated extension ScoreBucket {
    var label: String {
        switch self {
        case .eagleOrBetter: "Eagle+"
        case .birdie: "Birdie"
        case .par: "Par"
        case .bogey: "Bogey"
        case .doubleOrWorse: "Dobbel+"
        }
    }
}
