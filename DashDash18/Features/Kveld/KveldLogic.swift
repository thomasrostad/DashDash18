import Foundation
import GolfgutuCore

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
///
/// sql/045: «Kommer» er `yes` uten venteliste, pluss bekreftede gjester. Ventelista (medlemmer og
/// gjester) står for seg, i rekkefølgen serveren rykker opp (tid, så id).
nonisolated struct SignupSummary: Equatable, Sendable {
    struct Entry: Equatable, Identifiable, Sendable {
        /// Medlemmet, eller den som meldte på gjesten.
        let memberID: UUID
        let name: String
        let comment: String?
        /// Satt for en gjest.
        var guestID: UUID? = nil
        /// «gjest av Anders».
        var invitedBy: String? = nil
        /// Plassen på ventelista (1 = først).
        var place: Int? = nil
        /// Bare for «Ikke svart» når arrangøren ser hvem som har sett kvelden (sql/045). nil: ukjent.
        var seen: Bool? = nil
        var id: UUID { guestID ?? memberID }
        var isGuest: Bool { guestID != nil }

        /// «gjest av Anders», «nr. 2 på ventelista».
        var detail: String? {
            var parts: [String] = []
            if let invitedBy { parts.append("gjest av \(invitedBy)") }
            if let place { parts.append("nr. \(place) på ventelista") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    /// Medlemmer som kommer (ikke ventelista).
    var yes: [Entry] = []
    /// Bekreftede gjester.
    var guests: [Entry] = []
    /// Ventelista, medlemmer og gjester sammen, i rekkefølge.
    var waitlist: [Entry] = []
    var maybe: [Entry] = []
    var no: [Entry] = []
    var notAnswered: [Entry] = []

    /// Alle som kommer: medlemmene og de bekreftede gjestene.
    var coming: Int { yes.count + guests.count }

    /// - Parameters:
    ///   - members: troppen i den rekkefølgen den skal vises.
    ///   - guests: gjestene på kvelden (sql/045).
    ///   - seen: medlemmene som har sett kvelden. nil: ikke kjent (ikke arrangør, eller uten sql/045).
    init(members: [ClubMemberRow], signups: [SignupRow], guests: [EventGuestRow] = [], seen: Set<UUID>? = nil) {
        let byMember = Dictionary(signups.map { ($0.memberID, $0) }, uniquingKeysWith: { first, _ in first })
        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        var waiting: [(at: Date, key: String, entry: Entry)] = []
        for member in members where member.status == .active {
            guard let signup = byMember[member.id] else {
                notAnswered.append(Entry(memberID: member.id, name: member.displayName, comment: nil,
                                         seen: seen.map { $0.contains(member.id) }))
                continue
            }
            let entry = Entry(memberID: member.id, name: member.displayName, comment: SignupInput.cleanComment(signup.comment ?? ""))
            switch signup.status {
            case .yes:
                if let at = signup.waitlistedAt {
                    waiting.append((at, member.id.uuidString.lowercased(), entry))
                } else {
                    yes.append(entry)
                }
            case .maybe: maybe.append(entry)
            case .no: no.append(entry)
            }
        }
        for guest in guests {
            let entry = Entry(memberID: guest.invitedBy, name: guest.name, comment: nil, guestID: guest.id,
                              invitedBy: names[guest.invitedBy] ?? "et medlem")
            if let at = guest.waitlistedAt {
                waiting.append((at, guest.id.uuidString.lowercased(), entry))
            } else {
                self.guests.append(entry)
            }
        }
        waitlist = waiting
            .sorted { ($0.at, $0.key) < ($1.at, $1.key) }
            .enumerated()
            .map { index, item in
                var entry = item.entry
                entry.place = index + 1
                return entry
            }
    }

    /// Plassen på ventelista for medlemmet (ikke gjestene).
    func waitlistPlace(of memberID: UUID) -> Int? {
        waitlist.first { $0.memberID == memberID && !$0.isGuest }?.place
    }

    /// De uten svar som har sett kvelden, og de som ikke har sett den. Tom når det ikke er kjent.
    var notAnsweredSeen: [Entry] { notAnswered.filter { $0.seen == true } }
    var notSeen: [Entry] { notAnswered.filter { $0.seen == false } }
    private var knowsSeen: Bool { notAnswered.contains { $0.seen != nil } }

    /// Gruppene i rekkefølgen de vises: Kommer (med gjestene), Venteliste, Usikker, Kommer ikke, så
    /// Ikke svart sist. Vet vi hvem som har sett kvelden, deles «Ikke svart» i «Ikke svart» og «Ikke sett».
    var groups: [(title: String, entries: [Entry])] {
        var out: [(title: String, entries: [Entry])] = [(SignupStatus.yes.title, yes + guests)]
        // Ventelista finnes bare med et tak (sql/045), så den står bare med når noen er på den.
        if !waitlist.isEmpty { out.append(("Venteliste", waitlist)) }
        out.append((SignupStatus.maybe.title, maybe))
        out.append((SignupStatus.no.title, no))
        if knowsSeen {
            out.append(("Ikke svart", notAnsweredSeen))
            out.append(("Ikke sett", notSeen))
        } else {
            out.append(("Ikke svart", notAnswered))
        }
        return out
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

/// Purringen fra arrangøren (`renderPurring` / `handlePurr`): bare til dem som ikke har svart.
nonisolated enum Nudge {
    /// Aktive i troppen uten svar, i visningsrekkefølgen.
    static func targets(_ summary: SignupSummary) -> [SignupSummary.Entry] { summary.notAnswered }

    /// Knappen vises for arrangøren når noen mangler svar.
    static func isOffered(isOrganizer: Bool, summary: SignupSummary) -> Bool {
        isOrganizer && !targets(summary).isEmpty
    }

    /// «den ene» eller «de 4».
    static func who(_ count: Int) -> String { count == 1 ? "den ene" : "de \(count)" }

    /// «Purr de 4 som ikke har svart …»
    static func buttonTitle(count: Int) -> String { "Purr \(who(count)) som ikke har svart …" }

    /// «Purre på de 2 som ikke har svart? Anders, Bjørn.»
    static func confirmMessage(names: [String]) -> String {
        "Purre på \(who(names.count)) som ikke har svart? " + names.joined(separator: ", ") + "."
    }

    static let confirmButton = "Send purring"

    /// «Purret på 4.»
    static func doneText(count: Int) -> String { "Purret på \(count)." }

    /// «2 av dem har ikke sett kvelden ennå.» nil når alle har sett den, eller det ikke er kjent.
    static func unseenText(unseen: Int, of count: Int) -> String? {
        guard unseen > 0 else { return nil }
        if unseen == count { return count == 1 ? "Har ikke sett kvelden ennå." : "Ingen av dem har sett kvelden ennå." }
        return "\(unseen) av dem har ikke sett kvelden ennå."
    }
}

/// Teksten på kortet «Kveldens tråd».
nonisolated enum KveldThreadStatus {
    /// «Ingen meldinger ennå», «1 melding», «5 meldinger · 2 uleste».
    static func subtitle(_ summary: TradSummary) -> String {
        guard summary.count > 0 else { return "Ingen meldinger ennå" }
        var text = summary.count == 1 ? "1 melding" : "\(summary.count) meldinger"
        if summary.unread > 0 { text += " · " + unreadText(summary.unread) }
        return text
    }

    /// Den siste meldingen: «Anders: Ses kl. 17».
    static func lastLine(_ summary: TradSummary) -> String? {
        summary.last.map { "\($0.author): \($0.preview)" }
    }

    /// Kort til knappen under spill: «2 uleste», ellers antall meldinger.
    static func short(_ summary: TradSummary) -> String {
        summary.unread > 0 ? unreadText(summary.unread) : "\(summary.count)"
    }

    static func unreadText(_ n: Int) -> String { n == 1 ? "1 ulest" : "\(n) uleste" }
}

/// Teksten på kortet «Tippekupongen»: åpen til fristen, låst, eller resultatet.
nonisolated enum KveldTipsStatus {
    /// - Parameters:
    ///   - deadlineText: fristen slik kupongen skriver den («torsdag 8. oktober kl. 17:00»).
    ///   - winners: tippekongen(e) som navneliste, tom til kvelden er ferdig.
    static func text(phase: TipsBoard.Phase, deadlineText: String, hasMyCoupon: Bool, submitted: Int,
                     winners: String, best: Int, possible: Int) -> String {
        switch phase {
        case .open:
            return (hasMyCoupon ? "Levert · åpen til " : "Åpen til ") + deadlineText
        case .locked:
            return submitted == 0 ? "Låst · ingen leverte" : "Låst · \(submitted) levert"
        case .finished:
            guard !winners.isEmpty else { return "Resultat: ingen leverte" }
            return "Resultat: \(winners) med \(best) av \(possible) riktige"
        }
    }

    static func text(_ board: TipsBoard) -> String {
        text(phase: board.phase, deadlineText: board.deadlineText, hasMyCoupon: board.myCoupon != nil,
             submitted: board.submitted.count, winners: board.nameList(board.result.winners),
             best: board.result.best, possible: board.result.possible)
    }

    /// Kort til knappen under spill.
    static func short(_ phase: TipsBoard.Phase) -> String {
        switch phase {
        case .open: "Åpen"
        case .locked: "Låst"
        case .finished: "Resultat"
        }
    }
}

// MARK: - Angre svaret

/// Svaret som venter i angre-vinduet (`handleSvar` / `angre()` i PWA-en). Det gjelder på skjermen
/// med en gang, men sendes først når vinduet er over, så arrangøren ikke får push for et feiltrykk.
nonisolated struct PendingAnswer: Equatable, Sendable {
    let eventID: UUID
    /// Raden som lå lagret da vinduet åpnet. «Angre» går tilbake hit, og hendelsen til de andre
    /// regnes fra hit, også når man ombestemmer seg flere ganger i vinduet.
    var saved: SignupRow?
    var status: SignupStatus
    var comment: String?
    /// Telles opp for hver endring, så et svar som ble sendt ikke sletter et nyere.
    var revision: Int
}

nonisolated enum SignupUndo {
    /// Lengden på angre-vinduet (`ANGRE_MS` = 8000).
    static let window: Duration = .seconds(8)

    /// Nytt svar i vinduet. Står det et svar og venter, beholdes det lagrede fra før.
    static func begin(_ pending: PendingAnswer?, saved: SignupRow?, eventID: UUID,
                      status: SignupStatus, comment: String?) -> PendingAnswer {
        if var pending, pending.eventID == eventID {
            pending.status = status
            pending.comment = comment
            pending.revision += 1
            return pending
        }
        return PendingAnswer(eventID: eventID, saved: saved, status: status, comment: comment, revision: 0)
    }

    /// Mitt svar slik det vises: det som venter, ellers det lagrede.
    static func displayed(saved: SignupRow?, pending: PendingAnswer?, memberID: UUID, clubID: UUID) -> SignupRow? {
        guard let pending else { return saved }
        // Står du på ventelista og svarer «Kommer» igjen, står du der fortsatt.
        let waiting = pending.status == .yes && saved?.status == .yes ? saved?.waitlistedAt : nil
        return SignupRow(eventID: pending.eventID, memberID: memberID, clubID: clubID,
                         status: pending.status, comment: pending.comment, waitlistedAt: waiting)
    }

    /// Kveldens svar med mitt ventende svar lagt inn, til oversikten over hvem som kommer.
    static func signups(_ signups: [SignupRow], pending: PendingAnswer?, memberID: UUID, clubID: UUID) -> [SignupRow] {
        guard pending != nil,
              let mine = displayed(saved: signups.first { $0.memberID == memberID }, pending: pending,
                                   memberID: memberID, clubID: clubID) else { return signups }
        return signups.filter { $0.memberID != memberID } + [mine]
    }

    /// «Svaret ditt: Kommer».
    static func text(_ status: SignupStatus) -> String { "Svaret ditt: \(status.title)" }
}

/// Venter ut angre-vinduet og kjører så `action`. Et nytt `schedule` eller `cancel` stopper ventingen.
/// Når vinduet er over, slippes oppgaven før `action` kjører: et `cancel` fra `action` (eller et
/// nytt svar mens det sendes) avbryter da ikke sendingen som pågår.
final class SignupUndoTimer {
    private var task: Task<Void, Never>?

    func schedule(after window: Duration, _ action: @escaping () async -> Void) {
        task?.cancel()
        // Sterk referanse til `action`: svaret skal ut selv om skjermen forsvinner i vinduet.
        task = Task {
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            self.task = nil
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
