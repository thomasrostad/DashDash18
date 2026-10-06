import Foundation

/// Hvilken kveld som står for tur, som PWA-ens `upcomingSchedule()` / `nextScheduleEntry()`:
/// første kveld med dato ≥ i dag (Oslo) som ikke er ferdig.
nonisolated enum NextEvening {
    /// Status på en runde, slik den leses fra `rounds.status`.
    enum RoundStatus: String, Decodable, Sendable {
        case draft, active, locked
    }

    /// Kvelder som er ferdige: de har runder, og alle er låst (`kveldErFerdig`).
    /// En kladd eller en runde som går holder kvelden åpen.
    static func finishedEventIDs(rounds: [(eventID: UUID, status: RoundStatus)]) -> Set<UUID> {
        let byEvent = Dictionary(grouping: rounds, by: \.eventID)
        return Set(byEvent.compactMap { id, rounds in
            rounds.allSatisfy { $0.status == .locked } ? id : nil
        })
    }

    static func next(in events: [EventRow], today: String, finished: Set<UUID> = []) -> EventRow? {
        events
            .filter { $0.eventDate >= today && !finished.contains($0.id) }
            .min { $0.eventDate < $1.eventDate }
    }
}

/// Hele troppen fordelt på svarene, som PWA-ens `svarOversikt`. «Ikke svart» er alle
/// aktive medlemmer uten en rad, også ledige navn som aldri har logget inn.
/// Svar fra noen som ikke er i troppen (arkivert eller ventende) tas ikke med.
nonisolated struct SignupSummary: Equatable, Sendable {
    struct Entry: Equatable, Identifiable, Sendable {
        let memberID: UUID
        let name: String
        let comment: String?
        var id: UUID { memberID }
    }

    var yes: [Entry] = []
    var maybe: [Entry] = []
    var no: [Entry] = []
    var notAnswered: [Entry] = []

    /// - Parameter members: troppen i den rekkefølgen den skal vises.
    init(members: [ClubMemberRow], signups: [SignupRow]) {
        let byMember = Dictionary(signups.map { ($0.memberID, $0) }, uniquingKeysWith: { first, _ in first })
        for member in members where member.status == .active {
            guard let signup = byMember[member.id] else {
                notAnswered.append(Entry(memberID: member.id, name: member.displayName, comment: nil))
                continue
            }
            let entry = Entry(memberID: member.id, name: member.displayName, comment: SignupInput.cleanComment(signup.comment ?? ""))
            switch signup.status {
            case .yes: yes.append(entry)
            case .maybe: maybe.append(entry)
            case .no: no.append(entry)
            }
        }
    }

    /// Gruppene i rekkefølgen de vises: Kommer, Usikker, Kommer ikke, så Ikke svart sist.
    var groups: [(title: String, entries: [Entry])] {
        [
            (SignupStatus.yes.title, yes),
            (SignupStatus.maybe.title, maybe),
            (SignupStatus.no.title, no),
            ("Ikke svart", notAnswered),
        ]
    }
}

/// Rydding av svaret før det sendes, som PWA-ens `svarPaaDato`.
nonisolated enum SignupInput {
    /// Maks lengde på kommentaren (`signups.comment`, `SVAR_KOMMENTAR_MAKS`).
    static let commentMax = 80

    /// Mellomrom slås sammen, trimmes og kappes til 80 tegn. Tom blir nil.
    /// Kappes på hele tegn, og slik at databasens `char_length` (kodepunkter) holder.
    static func cleanComment(_ raw: String) -> String? {
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        var result = ""
        var scalars = 0
        for character in collapsed {
            let count = character.unicodeScalars.count
            if scalars + count > commentMax { break }
            result.append(character)
            scalars += count
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Trenger svaret å skrives? Samme status og kommentar igjen gjør ingenting.
    static func needsWrite(current: SignupRow?, status: SignupStatus, comment: String?) -> Bool {
        guard let current else { return true }
        return current.status != status || cleanComment(current.comment ?? "") != comment
    }
}
