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

/// Terminlista for arrangøren: kveldene, sosialkomiteene og troppen å velge fra.
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

    private let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    private var client: SupabaseClient { context.client }
    private var clubID: UUID { context.clubID }

    func load() async {
        do {
            async let seasons: [SeasonSummary] = client.from("seasons")
                .select("id, name")
                .eq("club_id", value: clubID)
                .eq("status", value: SeasonStatus.active.rawValue)
                .limit(1)
                .execute().value
            async let eventRows: [EventRow] = client.from("events")
                .select("id, club_id, season_id, event_date, start_time, venue, note")
                .eq("club_id", value: clubID)
                .order("event_date")
                .execute().value
            async let committeeRows: [EventCommitteeRow] = client.from("event_committee")
                .select("event_id, member_id, club_id")
                .eq("club_id", value: clubID)
                .execute().value
            async let memberRows: [ClubMemberRow] = client.from("club_members")
                .select(KveldQueries.memberColumns)
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
        } catch {
            if case .loaded = state { return }  // behold det vi har ved en feilet oppfrisking
            state = .failed(DataError.from(error).message)
        }
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
                    .select("id, club_id, season_id, event_date, start_time, venue, note")
                    .execute().value
            } else {
                saved = try await client.from("events")
                    .insert(write)
                    .select("id, club_id, season_id, event_date, start_time, venue, note")
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
                .select("id, club_id, season_id, event_date, start_time, venue, note")
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
                .select("event_id, member_id, club_id")
                .execute().value
            guard inserted.count == rows.count else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    /// Bytter komiteen for en kveld: sletter dem som er tatt ut, legger til de nye.
    /// To kall, ikke én transaksjon (se sql/005_kveld.sql for en RPC som gjør det samlet).
    private func setCommittee(eventID: UUID, to wanted: Set<UUID>) async throws(DataError) {
        let current = Set(committees[eventID] ?? [])
        let removed = current.subtracting(wanted)
        let added = wanted.subtracting(current)
        do {
            if !removed.isEmpty {
                try await client.from("event_committee")
                    .delete()
                    .eq("event_id", value: eventID)
                    .in("member_id", values: removed.map(\.uuidString))
                    .execute()
            }
            if !added.isEmpty {
                let rows = added.map { EventCommitteeRow(eventID: eventID, memberID: $0, clubID: clubID) }
                let inserted: [EventCommitteeRow] = try await client.from("event_committee")
                    .insert(rows)
                    .select("event_id, member_id, club_id")
                    .execute().value
                guard inserted.count == rows.count else { throw DataError.notAllowed }
            }
        } catch {
            throw DataError.invalid("Kvelden er lagret, men ikke sosialkomiteen. \(DataError.from(error).message)")
        }
    }
}

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
