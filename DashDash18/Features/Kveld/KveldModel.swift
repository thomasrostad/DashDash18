import Foundation
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
    private(set) var committee: [String] = []
    private(set) var summary = SignupSummary(members: [], signups: [])
    private(set) var mySignup: SignupRow?
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
    var clubContext: ClubContext { context }

    /// Det «Legg i kalender» fyller inn for neste kveld.
    var calendarEntry: CalendarEntry? {
        event.flatMap {
            KveldCalendar.entry(for: $0, tournament: context.membership.club.name,
                                number: eveningNumber, committee: committee)
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
                .select("id, club_id, season_id, event_date, start_time, venue, note")
                .eq("club_id", value: clubID)
                .gte("event_date", value: today)
                .order("event_date")
                .execute().value
            async let memberRows: [ClubMemberRow] = client.from("club_members")
                .select(KveldQueries.memberColumns)
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

            guard let next = NextEvening.next(in: events, today: today, finished: finished) else {
                event = nil
                committee = []
                mySignup = nil
                eveningNumber = nil
                summary = SignupSummary(members: members, signups: [])
                state = .loaded
                WidgetSnapshotPublisher.publish(nextEvening: nil, today: today)
                return
            }

            async let committeeRows: [EventCommitteeRow] = client.from("event_committee")
                .select("event_id, member_id, club_id")
                .eq("event_id", value: next.id)
                .execute().value
            async let signupRows: [SignupRow] = client.from("signups")
                .select("event_id, member_id, club_id, status, comment")
                .eq("event_id", value: next.id)
                .execute().value

            async let number = fetchEveningNumber(of: next)

            let committeeIDs = Set(try await committeeRows.map(\.memberID))
            let signups = try await signupRows
            eveningNumber = await number

            if CompetitionsFeature.isActive {
                // Bare et merke: feiler hentingen, vises kvelden uten.
                funCompetitions = (try? await CompetitionQueries.funNames(client: client, event: next)) ?? []
            }
            event = next
            committee = members.filter { committeeIDs.contains($0.id) }.map(\.displayName)
            mySignup = signups.first { $0.memberID == memberID }
            summary = SignupSummary(members: members, signups: signups)
            state = .loaded
            WidgetSnapshotPublisher.publish(nextEvening: next, today: today)
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

    /// Svarer Kommer / Usikker / Kommer ikke. Kommentaren som står, beholdes.
    func answer(_ status: SignupStatus) async throws(DataError) {
        try await write(status: status, comment: mySignup?.comment)
    }

    /// Lagrer kommentaren med svaret som står.
    func saveComment(_ text: String) async throws(DataError) {
        guard let status = mySignup?.status else {
            throw .invalid("Svar først, så kan du skrive en kommentar.")
        }
        try await write(status: status, comment: text)
    }

    private func write(status: SignupStatus, comment raw: String?) async throws(DataError) {
        guard let event else { return }
        let comment = SignupInput.cleanComment(raw ?? "")
        guard SignupInput.needsWrite(current: mySignup, status: status, comment: comment) else { return }

        let before = mySignup?.status
        let row = SignupUpsert(eventID: event.id, memberID: memberID, clubID: clubID, status: status, comment: comment)
        do {
            let saved: [SignupRow] = try await client.from("signups")
                .upsert(row, onConflict: "event_id,member_id")
                .select("event_id, member_id, club_id, status, comment")
                .execute().value
            guard let mine = saved.first else { throw DataError.notAllowed }
            mySignup = mine
        } catch {
            throw DataError.from(error)
        }
        // Bare det som er nytt for de andre (`svarLinje`); en kommentar er ingen hendelse.
        if let news = SignupNews.event(member: memberID, from: before, to: status, eventDate: event.eventDate) {
            await activityLog.logQuietly(news, eventID: event.id)
        }
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
