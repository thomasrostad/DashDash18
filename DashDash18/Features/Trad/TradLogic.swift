import Foundation

// Ren logikk for kveldens tråd: tekst, bildesti, bildemål, uleste og oppsummering.
// Ingen SwiftUI og ingen nettverk, så den testes isolert.

/// Teksten i en melding (`thread_messages_body_check`): trimmet, høyst 500 tegn, minst ett
/// tegn når det ikke er bilde.
nonisolated enum TradDraft {
    /// PWA: `MELDING_MAKS`. Samme grense som i databasen.
    static let maxLength = 500

    enum Check: Equatable, Sendable {
        /// Kan sendes, med den trimmede teksten.
        case ready(String)
        /// Ingenting å sende. Sier ikke fra (som PWA-en).
        case empty
        case tooLong

        var message: String? {
            switch self {
            case .tooLong: "Meldingen er for lang – maks \(TradDraft.maxLength) tegn."
            case .ready, .empty: nil
            }
        }
    }

    static func check(_ text: String, hasImage: Bool) -> Check {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && !hasImage { return .empty }
        // Postgres teller tegn som kodepunkter (`char_length`).
        if trimmed.unicodeScalars.count > maxLength { return .tooLong }
        return .ready(trimmed)
    }

    /// Teksten som står igjen når en sending feilet: den som ble sendt, og bak den det som
    /// ble skrevet i mellomtiden (PWA: `handleSendMelding`).
    static func restored(sent: String, typedSince: String) -> String {
        let since = typedSince.trimmingCharacters(in: .whitespacesAndNewlines)
        return since.isEmpty ? sent : sent + " " + typedSince
    }
}

/// Stien til et trådbilde i bøtta `thread`: `<member_id>/<message_id>.jpg`, små bokstaver
/// (`thread_messages_image_path_check` og `storage_path_member`).
nonisolated enum TradImagePath {
    static let bucket = "thread"

    static func make(memberID: UUID, messageID: UUID) -> String {
        "\(memberID.uuidString.lowercased())/\(messageID.uuidString.lowercased()).jpg"
    }
}

/// Hvordan et bilde gjøres klart før opplasting (PWA: `komprimerBilde`, `bildeMaal`).
nonisolated enum TradImageSpec {
    /// Lengste side i piksler.
    static let maxSide = 1600
    /// JPEG-kvalitet (PWA: 0,82).
    static let quality = 0.82
    /// Bøttas grense (`file_size_limit` 3 MB). Blir bildet større, prøves lavere kvalitet.
    static let maxBytes = 3 * 1024 * 1024
    /// Kvalitetene som prøves etter `quality` når bildet er for stort.
    static let fallbackQualities = [0.7, 0.6, 0.5, 0.4]

    /// `bildeMaal`: skaleres ned så lengste side er `maxSide`, aldri opp. `Math.round`.
    static func targetSize(width: Int, height: Int, maxSide: Int = maxSide) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (1, 1) }
        let scale = min(1, Double(maxSide) / Double(max(width, height)))
        func round(_ x: Double) -> Int { max(1, Int((x * scale + 0.5).rounded(.down))) }
        return (round(Double(width)), round(Double(height)))
    }
}

/// Uleste per tråd (PWA: `ulesteITraad`, `merkTraadLest`).
///
/// «Lest til» er tiden på andres nyeste melding, fra serveren. Egne meldinger teller aldri,
/// og en klokke på telefonen som går foran kan ikke skjule andres meldinger.
nonisolated enum TradUnread {
    static func count(_ messages: [ThreadMessageRow], viewer: UUID, lastSeen: Date?) -> Int {
        messages.filter { message in
            guard message.memberID != viewer else { return false }
            guard let lastSeen else { return true }
            return message.createdAt > lastSeen
        }.count
    }

    /// Ny «lest til» etter at tråden er vist, eller nil når den ikke skal flyttes.
    static func readMark(_ messages: [ThreadMessageRow], viewer: UUID, current: Date?) -> Date? {
        guard let newest = messages.filter({ $0.memberID != viewer }).map(\.createdAt).max() else { return nil }
        if let current, current >= newest { return nil }
        return newest
    }
}

/// Kort om én tråd, for kortet på Kveld: antall, uleste og de siste meldingene.
nonisolated struct TradSummary: Equatable, Sendable {
    struct Line: Equatable, Sendable, Identifiable {
        let id: UUID
        let memberID: UUID
        let author: String
        /// Teksten, eller «📷 Bilde» når meldingen bare er et bilde.
        let preview: String
        let createdAt: Date
    }

    let count: Int
    let unread: Int
    /// De siste meldingene, eldste først (PWA-kortet viser tre).
    let recent: [Line]

    var last: Line? { recent.last }

    /// PWA-kortet viser de tre siste.
    static let recentLimit = 3
    static let imageOnlyText = "📷 Bilde"

    static func make(messages: [ThreadMessageRow], names: [UUID: String], viewer: UUID, lastSeen: Date?,
                     recentLimit: Int = recentLimit) -> TradSummary {
        let sorted = TradOrder.sorted(messages)
        let recent = sorted.suffix(recentLimit).map { m in
            Line(id: m.id, memberID: m.memberID, author: names[m.memberID] ?? "Ukjent",
                 preview: preview(m), createdAt: m.createdAt)
        }
        return TradSummary(count: sorted.count,
                           unread: TradUnread.count(sorted, viewer: viewer, lastSeen: lastSeen),
                           recent: recent)
    }

    static func preview(_ message: ThreadMessageRow) -> String {
        let text = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, message.imagePath != nil { return imageOnlyText }
        return text
    }
}

/// Rekkefølgen i tråden: eldste øverst, nyeste nederst. Lik tid: id, så rekkefølgen er fast.
nonisolated enum TradOrder {
    static func sorted(_ messages: [ThreadMessageRow]) -> [ThreadMessageRow] {
        messages.sorted {
            $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString
        }
    }
}

/// Hvem kan slette: egen melding, eller arrangøren alle (`thread_messages_delete`).
nonisolated enum TradPermissions {
    static func canDelete(_ message: ThreadMessageRow, viewer: UUID, isOrganizer: Bool) -> Bool {
        isOrganizer || message.memberID == viewer
    }
}

/// Signerte lenker til bildene (PWA: `sikreBildelenker`). En time fra serveren; brukes i 55
/// minutter og fornyes når det er under ti igjen. En sti som feilet, prøves ikke igjen før
/// tråden hentes på nytt.
nonisolated struct TradSignedURLCache: Sendable {
    static let lifetimeSeconds = 3600
    static let usableFor: TimeInterval = 55 * 60
    static let renewWhenLeft: TimeInterval = 10 * 60

    struct Entry: Equatable, Sendable {
        let url: URL
        let usableUntil: Date
    }

    private(set) var entries: [String: Entry] = [:]
    private(set) var failed: Set<String> = []

    /// Stiene som trenger ny lenke, uten dubletter, i rekkefølgen de kom.
    func pathsToSign(_ paths: [String], now: Date) -> [String] {
        var seen: Set<String> = []
        return paths.filter { path in
            guard seen.insert(path).inserted, !failed.contains(path) else { return false }
            guard let entry = entries[path] else { return true }
            return entry.usableUntil.timeIntervalSince(now) < Self.renewWhenLeft
        }
    }

    /// Lagrer svaret. Stier som ble bedt om uten å få lenke, merkes som feilet.
    mutating func store(signed: [String: URL], requested: [String], now: Date) {
        for path in requested {
            if let url = signed[path] {
                entries[path] = Entry(url: url, usableUntil: now.addingTimeInterval(Self.usableFor))
                failed.remove(path)
            } else {
                failed.insert(path)
            }
        }
    }

    mutating func markFailed(_ paths: [String]) {
        failed.formUnion(paths)
    }

    mutating func forget(_ path: String) {
        entries[path] = nil
        failed.remove(path)
    }

    /// Ny henting av tråden: prøv de feilede igjen.
    mutating func retryFailed() {
        failed.removeAll()
    }

    func url(for path: String, now: Date) -> URL? {
        guard let entry = entries[path], entry.usableUntil > now else { return nil }
        return entry.url
    }
}

/// Tiden under en melding: «17:05» i dag, «i går 17:05», ellers «8. okt. 17:05».
nonisolated enum TradTimeLabel {
    static func text(for date: Date, now: Date, calendar: Calendar = osloCalendar) -> String {
        let time = format(date, "HH:mm", calendar)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "i går " + time
        }
        return format(date, "d. MMM", calendar) + " " + time
    }

    static var osloCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "nb")
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo") ?? .current
        return calendar
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
