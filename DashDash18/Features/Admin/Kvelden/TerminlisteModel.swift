import Foundation
import Observation
import Supabase

/// Det arrangøren fyller inn for en kveld.
struct EventDraft: Equatable {
    var id: UUID?
    var seasonID: UUID?
    var date: Date
    var hasTime: Bool
    var time: Date
    var venue: String
    var note: String
    var committee: Set<UUID>
}

/// Kveldene for arrangøren: terminlista med sosialkomiteene, påmeldingen per kveld og troppen
/// å velge fra. Brukes av «Kveldene» og «Kvelden».
@Observable
final class TerminlisteModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Bare det terminlista trenger av sesongen (regelsettet hentes ikke).
    struct SeasonSummary: Decodable, Equatable {
        let id: UUID
        let name: String
    }

    private(set) var state: LoadState = .loading
    private(set) var activeSeason: SeasonSummary?
    private(set) var events: [EventRow] = []
    /// Kveld → medlemmer i sosialkomiteen.
    private(set) var committees: [UUID: [UUID]] = [:]
    /// Aktive medlemmer, sortert på navn.
    private(set) var members: [ClubMemberRow] = []
    /// Kveld → svarene. Feiler hentingen, står kveldene uten påmelding.
    private(set) var signups: [UUID: [SignupRow]] = [:]

    private let context: ClubContext
    /// Turneringen kveldene hører til (fase 21). nil: hovedturneringen (den aktive).
    let tournamentID: UUID?

    init(context: ClubContext, tournamentID: UUID? = nil) {
        self.context = context
        self.tournamentID = tournamentID
    }

    private var client: SupabaseClient { context.client }
    private var clubID: UUID { context.clubID }

    func load() async {
        do {
            let seasonQuery = client.from("seasons")
                .select("id, name")
                .eq("club_id", value: clubID)
            // Den valgte turneringen, ellers hovedturneringen.
            async let seasons: [SeasonSummary] = (tournamentID.map { seasonQuery.eq("id", value: $0) }
                ?? seasonQuery.eq("status", value: SeasonStatus.active.rawValue))
                .limit(1)
                .execute().value
            async let eventRows: [EventRow] = client.from("events")
                .select(EventRow.columns)
                .eq("club_id", value: clubID)
                .order("event_date")
                .execute().value
            async let committeeRows: [EventCommitteeRow] = client.from("event_committee")
                .select(EventCommitteeRow.columns)
                .eq("club_id", value: clubID)
                .execute().value
            async let memberRows: [ClubMemberRow] = client.from("club_members")
                .select(ClubMemberRow.columns)
                .eq("club_id", value: clubID)
                .eq("status", value: MemberStatus.active.rawValue)
                .execute().value

            let season = try await seasons.first
            let allEvents = try await eventRows
            let committee = try await committeeRows
            let roster = try await memberRows

            activeSeason = season
            events = Terminliste.eveningsForSeason(allEvents, activeSeasonID: season?.id)
            committees = Dictionary(grouping: committee, by: \.eventID).mapValues { $0.map(\.memberID) }
            members = KveldQueries.sortedByName(roster)
            state = .loaded
            await loadSignups()
        } catch {
            if case .loaded = state { return }  // behold det vi har ved en feilet oppfrisking
            state = .failed(DataError.from(error).message)
        }
    }

    /// Svarene på sesongens kvelder. Bare et tillegg i lista, så en feil gir ingen feilet skjerm.
    private func loadSignups() async {
        guard !events.isEmpty else { signups = [:]; return }
        let rows: [SignupRow]? = try? await client.from("signups")
            .select(SignupRow.columns)
            .in("event_id", values: events.map(\.id.uuidString))
            .execute().value
        if let rows { signups = Dictionary(grouping: rows, by: \.eventID) }
    }

    /// Hele troppen fordelt på svarene for kvelden.
    func signupSummary(for eventID: UUID) -> SignupSummary {
        SignupSummary(members: members, signups: signups[eventID] ?? [])
    }

    /// Purrer på dem som ikke har svart på kvelden (samme purring som i Kveld). Gir teksten
    /// som skal vises etterpå.
    func nudge(_ event: EventRow) async throws(DataError) -> String {
        guard context.isOrganizer else { throw .notAllowed }
        let missing = Nudge.targets(signupSummary(for: event.id)).map(\.memberID)
        try await ActivityLog(client: client, clubID: clubID)
            .nudge(eventID: event.id, eventDate: event.eventDate, missing: missing)
        return Nudge.doneText(count: missing.count)
    }

    func memberName(_ id: UUID) -> String {
        members.first { $0.id == id }?.displayName ?? "Ukjent"
    }

    /// Komiteen for en kveld som navn, i troppens rekkefølge.
    func committeeNames(for eventID: UUID) -> [String] {
        let ids = Set(committees[eventID] ?? [])
        return members.filter { ids.contains($0.id) }.map(\.displayName)
    }

    func draft(for event: EventRow?) -> EventDraft {
        guard let event else {
            // Ny kveld: neste uke, samme sted og tid som sist.
            let last = events.last
            return EventDraft(
                id: nil, seasonID: activeSeason?.id,
                date: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now,
                hasTime: last?.startTime != nil,
                time: last?.startTime.flatMap { EveningDates.time(from: $0) }
                    ?? EveningDates.time(from: "17:00")!,
                venue: last?.venue ?? "", note: "", committee: []
            )
        }
        return EventDraft(
            id: event.id, seasonID: event.seasonID,
            date: EveningDates.date(from: event.eventDate) ?? .now,
            hasTime: event.startTime != nil,
            time: event.startTime.flatMap { EveningDates.time(from: $0) } ?? EveningDates.time(from: "17:00")!,
            venue: event.venue ?? "", note: event.note ?? "",
            committee: Set(committees[event.id] ?? [])
        )
    }

    /// Lagrer kvelden og komiteen. Feilmeldingen er ferdig norsk tekst.
    func save(_ draft: EventDraft) async throws(DataError) {
        let venue = try EventInput.text(draft.venue, max: EventInput.venueMax, field: "Sted").get()
        let note = try EventInput.text(draft.note, max: EventInput.noteMax, field: "Notatet").get()
        let date = EveningDates.dateString(from: draft.date)
        let write = EventWrite(
            clubID: clubID, seasonID: draft.seasonID, eventDate: date,
            startTime: draft.hasTime ? EveningDates.timeString(from: draft.time) : nil,
            venue: venue, note: note
        )

        let saved: [EventRow]
        do {
            if let id = draft.id {
                saved = try await client.from("events")
                    .update(write)
                    .eq("id", value: id)
                    .select(EventRow.columns)
                    .execute().value
            } else {
                saved = try await client.from("events")
                    .insert(write)
                    .select(EventRow.columns)
                    .execute().value
            }
        } catch {
            throw .invalid(Terminliste.saveErrorMessage(
                sqlState: (error as? PostgrestError)?.code, fallback: DataError.from(error), date: date))
        }
        guard let event = saved.first else { throw .notAllowed }  // RLS sa nei uten feilkode

        try await setCommittee(eventID: event.id, to: draft.committee)
        await load()
    }

    func delete(_ event: EventRow) async throws(DataError) {
        let deleted: [EventRow]
        do {
            deleted = try await client.from("events")
                .delete()
                .eq("id", value: event.id)
                .select(EventRow.columns)
                .execute().value
        } catch {
            throw .invalid(Terminliste.deleteErrorMessage(
                sqlState: (error as? PostgrestError)?.code, fallback: DataError.from(error)))
        }
        guard !deleted.isEmpty else { throw .notAllowed }
        await load()
    }

    /// Forslag til komité for kommende kveldene som mangler (lagres ikke).
    func proposeCommittees(perEvening: Int) -> [CommitteeDraw.Assignment] {
        CommitteeDraw.draw(
            evenings: events.map { CommitteeDraw.Evening(id: $0.id, date: $0.eventDate, committee: committees[$0.id] ?? []) },
            members: members.map(\.id),
            perEvening: perEvening,
            fillFrom: EveningDates.today()
        )
    }

    /// Lagrer en trekning. Én innsetting for alle kveldene, så den lykkes eller feiler samlet.
    func apply(_ plan: [CommitteeDraw.Assignment]) async throws(DataError) {
        let rows = plan.flatMap { assignment in
            assignment.added.map { EventCommitteeRow(eventID: assignment.eventID, memberID: $0, clubID: clubID) }
        }
        guard !rows.isEmpty else { return }
        do {
            let inserted: [EventCommitteeRow] = try await client.from("event_committee")
                .insert(rows)
                .select(EventCommitteeRow.columns)
                .execute().value
            guard inserted.count == rows.count else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    /// Bytter komiteen for en kveld i én transaksjon (RPC `set_event_committee`, sql/005,
    /// kjørt på test 06.10).
    private func setCommittee(eventID: UUID, to wanted: Set<UUID>) async throws(DataError) {
        struct Params: Encodable {
            let p_event_id: UUID
            let p_member_ids: [UUID]
        }
        guard Set(committees[eventID] ?? []) != wanted else { return }
        do {
            let saved: [UUID] = try await client
                .rpc("set_event_committee", params: Params(p_event_id: eventID, p_member_ids: wanted.sorted { $0.uuidString < $1.uuidString }))
                .execute()
                .value
            guard Set(saved) == wanted else { throw DataError.notAllowed }
        } catch {
            throw DataError.invalid("Datoen er lagret, men ikke sosialkomiteen. \(DataError.from(error).message)")
        }
    }
}

#if DEBUG
extension TerminlisteModel {
    /// Kveldene fra skjermprøvens rundemodell, med sosialkomité og påmelding (`kvelden`, `kveldene`).
    static func sample(from admin: RundeAdminModel) -> TerminlisteModel {
        let model = TerminlisteModel(context: admin.clubContext, tournamentID: admin.tournamentID)
        model.activeSeason = admin.tournament.map { SeasonSummary(id: $0.id, name: $0.name) }
        model.events = admin.events
        model.members = admin.members
        for (index, event) in admin.events.enumerated() {
            model.committees[event.id] = admin.members.dropFirst(index * 2).prefix(index == admin.events.count - 1 ? 0 : 2)
                .map(\.id)
        }
        if let selected = admin.selectedEventID {
            model.signups[selected] = admin.signups
        }
        if let next = admin.events.first(where: { $0.eventDate > EveningDates.today() }) {
            model.signups[next.id] = admin.members.prefix(5).map {
                SignupRow(eventID: next.id, memberID: $0.id, clubID: $0.clubID, status: .yes, comment: nil)
            }
        }
        model.state = .loaded
        return model
    }
}
#endif

/// Raden som skrives til `events`. Tomme felt sendes som null, så de også tømmes ved endring.
nonisolated struct EventWrite: Encodable, Sendable {
    let clubID: UUID
    let seasonID: UUID?
    let eventDate: String
    let startTime: String?
    let venue: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case clubID = "club_id"
        case seasonID = "season_id"
        case eventDate = "event_date"
        case startTime = "start_time"
        case venue
        case note
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clubID, forKey: .clubID)
        try container.encode(seasonID, forKey: .seasonID)
        try container.encode(eventDate, forKey: .eventDate)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(venue, forKey: .venue)
        try container.encode(note, forKey: .note)
    }
}
