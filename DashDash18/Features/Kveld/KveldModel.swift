import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Kveld-skjermen før runden: neste kveld, mitt svar og hvem som kommer.
@Observable
final class KveldModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var event: EventRow?
    /// Kvelden før `event` (i dag eller tidligere): kupongen med resultatet og tippekongen kan åpnes
    /// derfra også når neste kveld har tatt over (09.10.2026).
    private(set) var previousEvent: EventRow?
    private(set) var committee: [String] = []
    /// Mitt svar slik det ligger i databasen.
    private(set) var savedSignup: SignupRow?
    /// Svaret som venter i angre-vinduet.
    private(set) var pendingAnswer: PendingAnswer?
    /// Kvelden det ventende svaret gjelder.
    private var pendingEvent: EventRow?
    /// Feilen fra sist et svar ble sendt etter vinduet.
    var answerError: String?
    private var members: [ClubMemberRow] = []
    private var signups: [SignupRow] = []
    /// Tak, frister og gjester for kvelden (sql/045). nil uten 045: påmeldingen er som før.
    private(set) var settings: EveningSettingsRow?
    /// Gjestene på kvelden (sql/045).
    private(set) var guests: [EventGuestRow] = []
    /// Hvem som har sett kvelden. Bare for arrangøren (rettigheten tournaments), og bare med sql/045.
    private var seen: Set<UUID>?
    /// Kvelden «sett» er sendt for, så det ikke sendes ved hver oppfrisking.
    private var markedSeen: UUID?
    private let undoTimer = SignupUndoTimer()
    private(set) var today = EveningDates.today()
    /// Kveldens nummer i sesongen (plassen i terminlista), når det kan hentes.
    private(set) var eveningNumber: Int?
    /// Morroturneringene neste kveld hører til (fase 15). Tom når `CompetitionsFeature` er av.
    private(set) var funCompetitions: [String] = []
    /// Telles opp for hver henting, så kortene for tråd og tips kan hente på nytt samtidig.
    private(set) var loadCount = 0

    private let context: ClubContext
    private var isLoading = false
    private var reloadAgain = false

    init(context: ClubContext) {
        self.context = context
    }

    private var client: SupabaseClient { context.client }
    private var clubID: UUID { context.clubID }
    var memberID: UUID { context.memberID }
    var isOrganizer: Bool { context.isOrganizer }
    /// Kan endre påmeldingen og går forbi fristene (sql/045).
    var canManageSignups: Bool { context.can(.tournaments) }
    var clubContext: ClubContext { context }

    /// Det ventende svaret, bare når det gjelder kvelden som vises.
    private var visiblePending: PendingAnswer? {
        pendingAnswer.flatMap { $0.eventID == event?.id ? $0 : nil }
    }

    /// Mitt svar slik det vises: det som venter i angre-vinduet, ellers det lagrede.
    var mySignup: SignupRow? {
        SignupUndo.displayed(saved: savedSignup, pending: visiblePending, memberID: memberID, clubID: clubID)
    }

    /// Hvem som kommer, med mitt ventende svar lagt inn.
    var summary: SignupSummary {
        SignupSummary(members: members,
                      signups: SignupUndo.signups(signups, pending: visiblePending, memberID: memberID, clubID: clubID),
                      guests: guests, seen: seen)
    }

    /// «På venteliste (nr. 2)» når mitt «Kommer» står på ventelista.
    var waitlistText: String? {
        guard mySignup?.isWaitlisted == true else { return nil }
        return EveningSignupText.waitlist(place: summary.waitlistPlace(of: memberID))
    }

    /// Gjestene jeg har meldt på.
    var myGuests: [EventGuestRow] { guests.filter { $0.invitedBy == memberID } }

    /// «Kveld» eller «spilledag» (`DayTerm`), satt av skjermen fra miljøet.
    var dayTerm: DayTerm = .evening

    /// Det «Legg i kalender» fyller inn for neste kveld.
    var calendarEntry: CalendarEntry? {
        event.flatMap {
            KveldCalendar.entry(for: $0, tournament: context.membership.club.name,
                                number: eveningNumber, committee: committee, term: dayTerm)
        }
    }

    var daysUntil: Int? {
        event.flatMap { EveningDates.daysBetween(today, $0.eventDate) }
    }

    /// Henter kvelden. Kommer et nytt kall mens en henting pågår (realtime, retur fra
    /// bakgrunnen, dra ned), kjøres én til etterpå i stedet for to samtidig.
    func load() async {
        if isLoading { reloadAgain = true; return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadAgain = false
            await fetch()
        } while reloadAgain
        loadCount += 1
    }

    private func fetch() async {
        today = EveningDates.today()
        do {
            async let eventRows: [EventRow] = client.from("events")
                .select(EventRow.columns)
                .eq("club_id", value: clubID)
                .gte("event_date", value: today)
                .order("event_date")
                .execute().value
            async let pastRows: [EventRow] = client.from("events")
                .select(EventRow.columns)
                .eq("club_id", value: clubID)
                .lte("event_date", value: today)
                .order("event_date", ascending: false)
                .limit(2)
                .execute().value
            async let memberRows: [ClubMemberRow] = client.from("club_members")
                .select(ClubMemberRow.columns)
                .eq("club_id", value: clubID)
                .eq("status", value: MemberStatus.active.rawValue)
                .execute().value

            let events = try await eventRows
            let members = KveldQueries.sortedByName(try await memberRows)

            // Kvelden i dag er ferdig når alle rundene er låst. Kladder ser bare arrangøren.
            var finished: Set<UUID> = []
            let todays = events.filter { $0.eventDate == today }.map(\.id)
            if !todays.isEmpty {
                let rounds: [RoundStatusRow] = try await client.from("rounds")
                    .select("event_id, status")
                    .in("event_id", values: todays.map(\.uuidString))
                    .execute().value
                finished = NextEvening.finishedEventIDs(rounds: rounds.map { ($0.eventID, $0.status) })
            }

            let nextEvening = NextEvening.next(in: events, today: today, finished: finished)
            // Bare et tillegg: feiler hentingen, vises kvelden uten lenken.
            previousEvent = (try? await pastRows)?.first { $0.id != nextEvening?.id }
            guard let next = nextEvening else {
                event = nil
                committee = []
                savedSignup = nil
                eveningNumber = nil
                self.members = members
                self.signups = []
                settings = nil
                guests = []
                seen = nil
                state = .loaded
                WidgetSnapshotPublisher.publish(nextEvening: nil, today: today)
                return
            }

            async let committeeRows: [EventCommitteeRow] = client.from("event_committee")
                .select(EventCommitteeRow.columns)
                .eq("event_id", value: next.id)
                .execute().value
            async let signupRows = EveningSignupService.signups(client: client, eventIDs: [next.id])
            async let settingRows = EveningSignupService.settings(client: client, eventIDs: [next.id])
            async let guestRows = EveningSignupService.guests(client: client, eventIDs: [next.id])
            let manages = canManageSignups
            async let viewRows: [UUID: Set<UUID>]? = manages
                ? EveningSignupService.views(client: client, eventIDs: [next.id]) : nil

            async let number = fetchEveningNumber(of: next)

            let committeeIDs = Set(try await committeeRows.map(\.memberID))
            let signups = try await signupRows
            eveningNumber = await number
            let settingsByEvent = await settingRows
            let guestList = await guestRows
            let views = await viewRows

            if CompetitionsFeature.isActive {
                // Bare et merke: feiler hentingen, vises kvelden uten.
                funCompetitions = (try? await CompetitionQueries.funNames(client: client, event: next)) ?? []
            }
            event = next
            committee = members.filter { committeeIDs.contains($0.id) }.map(\.displayName)
            savedSignup = signups.first { $0.memberID == memberID }
            self.members = members
            self.signups = signups
            settings = settingsByEvent?[next.id]
            guests = guestList
            seen = settingsByEvent == nil ? nil : (views.map { $0[next.id] ?? [] })
            state = .loaded
            WidgetSnapshotPublisher.publish(nextEvening: next, today: today)
            if markedSeen != next.id {
                markedSeen = next.id
                await EveningSignupService.markSeen(client: client, eventID: next.id)
            }
        } catch {
            if case .loaded = state { return }  // behold det som vises ved en feilet oppfrisking
            state = .failed(DataError.from(error).message)
        }
    }

    /// Plassen i sesongens terminliste. Bare til kalenderen, så en feil gir nil og ikke en feilet skjerm.
    private func fetchEveningNumber(of event: EventRow) async -> Int? {
        guard let seasonID = event.seasonID else { return nil }
        let rows: [EventDateRow]? = try? await client.from("events")
            .select("event_date")
            .eq("season_id", value: seasonID)
            .execute().value
        return rows.flatMap { KveldCalendar.number(of: event.eventDate, in: $0.map(\.eventDate)) }
    }

    /// Svarer Kommer / Usikker / Kommer ikke. Svaret gjelder på skjermen med en gang og sendes når
    /// angre-vinduet er over (som PWA-en). Kommentaren som står, beholdes.
    func answer(_ status: SignupStatus) {
        guard let event, mySignup?.status != status else { return }
        answerError = nil
        // Fristen er ute: si det med en gang i stedet for etter angre-vinduet.
        if SignupDeadline.blocks(settings, current: savedSignup, new: status, now: .now, isOrganizer: canManageSignups) {
            answerError = EveningSignupText.deadlinePassed
            return
        }
        pendingEvent = event
        pendingAnswer = SignupUndo.begin(pendingAnswer, saved: savedSignup, eventID: event.id,
                                         status: status, comment: mySignup?.comment)
        undoTimer.schedule(after: SignupUndo.window) { await self.flush() }
    }

    /// «Angre»: tilbake til det som lå lagret. Ingenting er sendt.
    func undoAnswer() {
        undoTimer.cancel()
        pendingAnswer = nil
    }

    /// Sender svaret som venter nå (vinduet er over, eller appen legges bort).
    func flush() async {
        undoTimer.cancel()
        // Kvelden svaret ble gitt for, også om neste kveld har byttet i vinduet (midnatt, ferdig kveld).
        guard let pending = pendingAnswer, let event = pendingEvent, event.id == pending.eventID else { return }
        do throws(DataError) {
            try await write(event: event, status: pending.status, comment: pending.comment, saved: pending.saved)
            if pendingAnswer?.revision == pending.revision {
                pendingAnswer = nil
            } else {
                pendingAnswer?.saved = savedSignup
            }
        } catch {
            if pendingAnswer?.revision == pending.revision { pendingAnswer = nil }
            answerError = EveningSignupText.answerError(error)
        }
    }

    /// Lagrer kommentaren med svaret som står. Venter et svar, går det med nå.
    func saveComment(_ text: String) async throws(DataError) {
        guard let event, let status = mySignup?.status else {
            throw .invalid("Svar først, så kan du skrive en kommentar.")
        }
        let saved = pendingAnswer.map(\.saved) ?? savedSignup
        undoTimer.cancel()
        pendingAnswer = nil
        try await write(event: event, status: status, comment: text, saved: saved)
    }

    /// `saved` er raden på `event` som lå i databasen før svaret. Hendelsen til de andre regnes fra den.
    private func write(event: EventRow, status: SignupStatus, comment raw: String?, saved: SignupRow?) async throws(DataError) {
        let comment = SignupInput.cleanComment(raw ?? "")
        guard SignupInput.needsWrite(current: saved, status: status, comment: comment) else { return }

        // Fra ventelista er ingen «kommer» å melde av (serveren melder selv om opprykk).
        let before = saved.flatMap { $0.isWaitlisted ? nil : $0.status }
        // Tom kommentar tømmer den (`evening_signup`: null beholder).
        let result = try await EveningSignupService.answer(client: client, event: event, member: nil,
                                                           ownMemberID: memberID, status: status, comment: comment ?? "")
        if event.id == self.event?.id {
            savedSignup = SignupRow(eventID: event.id, memberID: memberID, clubID: clubID, status: status,
                                    comment: comment, waitlistedAt: result?.waitlisted == true ? .now : nil,
                                    late: result?.late ?? false)
        }
        // Bare det som er nytt for de andre (`svarLinje`); en kommentar er ingen hendelse, og et
        // «Kommer» som havnet på ventelista er ingen påmelding.
        if let news = SignupNews.event(member: memberID, from: before, to: status, eventDate: event.eventDate,
                                       waitlisted: result?.waitlisted ?? false) {
            await activityLog.logQuietly(news, eventID: event.id)
        }
        await load()
    }

    // MARK: Gjester

    /// Melder på en gjest (sql/045, når kvelden tillater det).
    func addGuest(_ raw: String) async throws(DataError) {
        guard let event else { throw .invalid("Ingen \(dayTerm.one) å melde på til.") }
        let name = try GuestInput.clean(raw).get()
        if SignupDeadline.blocksGuest(settings, adding: true, waitlisted: false, now: .now, isOrganizer: canManageSignups) {
            throw .invalid(EveningSignupText.deadlinePassed)
        }
        try await EveningSignupService.addGuest(client: client, eventID: event.id, name: name, invitedBy: nil)
        await load()
    }

    func removeGuest(_ guest: EventGuestRow) async throws(DataError) {
        if SignupDeadline.blocksGuest(settings, adding: false, waitlisted: guest.waitlistedAt != nil, now: .now,
                                      isOrganizer: canManageSignups) {
            throw .invalid(EveningSignupText.deadlinePassed)
        }
        try await EveningSignupService.removeGuest(client: client, guestID: guest.id)
        await load()
    }

    // MARK: Purring

    /// De aktive som ikke har svart, i visningsrekkefølgen. Purringen går til dem.
    var nudgeTargets: [SignupSummary.Entry] { Nudge.targets(summary) }

    /// Arrangøren purrer på dem som mangler svar. Gir teksten som skal vises etterpå.
    func nudge() async throws(DataError) -> String {
        guard context.isOrganizer else { throw .notAllowed }
        guard let event else { throw .invalid("Ingen kveld å purre på.") }
        let missing = nudgeTargets.map(\.memberID)
        try await activityLog.nudge(eventID: event.id, eventDate: event.eventDate, missing: missing)
        return Nudge.doneText(count: missing.count)
    }

    private var activityLog: ActivityLog { ActivityLog(client: client, clubID: clubID) }

    // MARK: Realtime

    /// Følger svar, kvelder og sosialkomité i klubben, som PWA-en, til oppgaven avbrytes
    /// (skjermen forsvinner). Det som kom mens appen var borte, hentes ved retur fra bakgrunnen.
    func followChanges() async {
        // Eget navn hver gang: kommer skjermen tilbake før den gamle kanalen er fjernet,
        // skal vi ikke få den igjen fra klienten.
        let channel = client.channel("kveld-\(clubID.uuidString.lowercased())-\(UUID().uuidString.prefix(8))")
        let streams = ["signups", "events", "event_committee"].map { table in
            channel.postgresChange(AnyAction.self, schema: "public", table: table, filter: .eq("club_id", value: clubID))
        }
        await withTaskGroup(of: Void.self) { group in
            for stream in streams {
                group.addTask {
                    for await _ in stream { await self.load() }
                }
            }
            group.addTask { try? await channel.subscribeWithError() }
        }
        // Avbrutt: fjernes utenfor den avbrutte oppgaven, så avmeldingen rekker å gå.
        let client = client
        Task { await client.removeChannel(channel) }
    }
}

/// Raden som sendes til `signups`. Kommentaren sendes som null når den er tom, så den tømmes.
nonisolated struct SignupUpsert: Encodable, Sendable {
    let eventID: UUID
    let memberID: UUID
    let clubID: UUID
    let status: SignupStatus
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case memberID = "member_id"
        case clubID = "club_id"
        case status
        case comment
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(memberID, forKey: .memberID)
        try container.encode(clubID, forKey: .clubID)
        try container.encode(status, forKey: .status)
        try container.encode(comment, forKey: .comment)
    }
}

/// Bare det Kveld trenger fra `rounds` for å se om kvelden er ferdig.
nonisolated struct RoundStatusRow: Decodable, Sendable {
    let eventID: UUID
    let status: NextEvening.RoundStatus

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case status
    }
}

/// Bare datoen fra `events`, for å nummerere kveldene i sesongen.
nonisolated struct EventDateRow: Decodable, Sendable {
    let eventDate: String

    enum CodingKeys: String, CodingKey {
        case eventDate = "event_date"
    }
}
