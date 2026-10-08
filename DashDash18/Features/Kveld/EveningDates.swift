import Foundation

/// Datoer og klokkeslett for kveldene, alltid i Europe/Oslo. Databasen lagrer dato som
/// `YYYY-MM-DD` og klokkeslett som `HH:MM:SS` (lokal tid), og her regnes og vises de.
/// Ren logikk uten SwiftUI og nettverk, så den kan testes og brukes av widget-dataene.
nonisolated enum EveningDates {
    static let osloTimeZone = TimeZone(identifier: "Europe/Oslo")!

    /// Gregoriansk kalender i Oslo-tid.
    static let osloCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = osloTimeZone
        calendar.locale = Locale(identifier: "nb")
        return calendar
    }()

    /// Dagens dato i Oslo som `YYYY-MM-DD`, som PWA-ens `todayISO()`.
    static func today(now: Date = .now) -> String {
        dateString(from: now)
    }

    /// Et tidspunkt som dato i Oslo, `YYYY-MM-DD`.
    static func dateString(from date: Date) -> String {
        let parts = osloCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// `YYYY-MM-DD` som tidspunkt kl. 12 i Oslo (midt på dagen, så sommertid ikke flytter datoen).
    static func date(from string: String) -> Date? {
        guard let parts = components(of: string) else { return nil }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = 12
        guard let date = osloCalendar.date(from: components),
              dateString(from: date) == String(format: "%04d-%02d-%02d", parts.year, parts.month, parts.day)
        else { return nil }  // f.eks. 31. februar
        return date
    }

    /// Klokkeslett fra et tidspunkt, som Postgres `time`: `HH:MM:00`.
    static func timeString(from date: Date) -> String {
        let parts = osloCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// `HH:MM:SS` eller `HH:MM` som tidspunkt på en gitt dag (for tidsvelgeren).
    static func time(from string: String, on day: Date = .now) -> Date? {
        let parts = string.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return osloCalendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// `17:00:00` → `17:00`. Ugyldig eller tomt gir nil.
    static func timeText(_ string: String?) -> String? {
        guard let string, let date = time(from: string) else { return nil }
        let parts = osloCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// «torsdag 8. oktober». Året tas med når det er et annet enn `referenceYear`
    /// («torsdag 8. oktober 2027»). `capitalized` gir «Torsdag 8. oktober» (overskrift). Navnene står her, så teksten ikke avhenger av
    /// språkdataene på telefonen.
    static func longText(_ string: String, referenceYear: Int? = nil, capitalized: Bool = false) -> String {
        guard let parts = components(of: string), let date = date(from: string) else { return string }
        let weekday = osloCalendar.component(.weekday, from: date)  // 1 = søndag
        var text = "\(weekdays[weekday - 1]) \(parts.day). \(months[parts.month - 1])"
        if let referenceYear, referenceYear != parts.year {
            text += " \(parts.year)"
        }
        return capitalized ? text.prefix(1).uppercased() + text.dropFirst() : text
    }

    /// Antall kalenderdager fra `today` til `date` (begge `YYYY-MM-DD`). Negativt når
    /// datoen har vært. Regnes på datoene alene, så sommertid ikke gir 23- eller 25-timersdøgn.
    static func daysBetween(_ today: String, _ date: String) -> Int? {
        guard let a = dayNumber(today), let b = dayNumber(date) else { return nil }
        return b - a
    }

    /// «I dag», «I morgen», «Om 5 dager». Datoer som har vært gir «I dag» (som PWA-ens `max(d, 0)`).
    static func countdownText(days: Int) -> String {
        switch days {
        case ...0: "I dag"
        case 1: "I morgen"
        default: "Om \(days) dager"
        }
    }

    /// Året i en `YYYY-MM-DD`.
    static func year(of string: String) -> Int? {
        components(of: string)?.year
    }

    private static let weekdays = ["søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag"]
    private static let months = ["januar", "februar", "mars", "april", "mai", "juni",
                                 "juli", "august", "september", "oktober", "november", "desember"]

    private static func components(of string: String) -> (year: Int, month: Int, day: Int)? {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return (year, month, day)
    }

    /// Dagnummer i en fast UTC-kalender, så differansen er hele dager.
    private static func dayNumber(_ string: String) -> Int? {
        guard let parts = components(of: string) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let date = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) else {
            return nil
        }
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }
}

/// Norsk opplisting: «A», «A og B», «A, B og C».
nonisolated enum NorwegianList {
    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " og " + items[items.count - 1]
        }
    }
}
