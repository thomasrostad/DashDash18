import Foundation
import GolfgutuCore

/// Det som legges i kalenderen for én kveld. Ren verdi uten EventKit, så den kan testes.
nonisolated struct CalendarEntry: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    /// Uten klokkeslett legges kvelden inn som heldagshendelse.
    var isAllDay: Bool
    var location: String?
    var notes: String?
    /// Varsel før start (negativt antall sekunder), eller nil.
    var alarmOffset: TimeInterval?
    var timeZone: TimeZone
}

/// Bygger kalenderhendelsen fra kvelden. Tidene regnes i Europe/Oslo, så sommer- og vintertid
/// blir riktig uansett hvilken tidssone telefonen står i.
nonisolated enum KveldCalendar {
    /// Hvor lenge en kveld varer i kalenderen når modellen ikke har sluttid. Bare et
    /// kalenderforslag (brukeren kan endre det i arket), ikke en regelverdi.
    static let defaultDuration: TimeInterval = 4 * 60 * 60

    /// Varsel to timer før start, så det rekker å pakke bagen.
    static let alarmOffset: TimeInterval = -2 * 60 * 60

    /// `tournament` er turneringens (klubbens) navn, `number` kveldens nummer i sesongen.
    static func entry(for event: EventRow, tournament: String, number: Int?,
                      committee: [String] = [], term: DayTerm = .evening) -> CalendarEntry? {
        guard let day = EveningDates.date(from: event.eventDate) else { return nil }
        let calendar = EveningDates.osloCalendar

        let start: Date
        let end: Date
        let isAllDay: Bool
        if let time = event.startTime, let timed = EveningDates.time(from: time, on: day) {
            start = timed
            end = timed.addingTimeInterval(defaultDuration)
            isAllDay = false
        } else {
            start = calendar.startOfDay(for: day)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            isAllDay = true
        }

        return CalendarEntry(
            title: title(tournament: tournament, number: number, term: term),
            start: start,
            end: end,
            isAllDay: isAllDay,
            location: clean(event.venue),
            notes: notes(event: event, committee: committee),
            alarmOffset: isAllDay ? nil : alarmOffset,
            timeZone: EveningDates.osloTimeZone
        )
    }

    /// «GolfGutu Invitational – kveld 5». Uten nummer: «GolfGutu Invitational – kveld».
    static func title(tournament: String, number: Int?, term: DayTerm = .evening) -> String {
        let name = tournament.trimmingCharacters(in: .whitespacesAndNewlines)
        let evening = number.map { "\(term.one) \($0)" } ?? term.one
        return name.isEmpty ? evening.prefix(1).uppercased() + evening.dropFirst() : "\(name) – \(evening)"
    }

    /// Kveldens nummer i sesongen: plassen i terminlista (sortert på dato), fra 1.
    static func number(of date: String, in seasonDates: [String]) -> Int? {
        let dates = Array(Set(seasonDates)).sorted()
        return dates.firstIndex(of: date).map { $0 + 1 }
    }

    private static func notes(event: EventRow, committee: [String]) -> String? {
        var lines: [String] = []
        if !committee.isEmpty {
            lines.append("Sosialkomité: \(NorwegianList.join(committee))")
        }
        if let note = clean(event.note) {
            lines.append(note)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n\n")
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
